#!/usr/bin/env node
// Restty Web Terminal Server
// Konductor Integration - Single-port HTTP/HTTPS + WebSocket PTY Server
//
// Protocol differences from ghostty-web:
// - Client sends JSON: {"type":"input","data":"..."} instead of raw strings
// - Server sends raw binary PTY output (ArrayBuffer) for efficiency
// - Server sends JSON control messages: status, error, exit
// - WebSocket endpoint: /pty (restty convention) instead of /ws
//
// Features:
// - SSL/TLS support for encrypted connections
// - basePath support for reverse proxy deployment
// - Origin checking for WebSocket security
// - Path traversal protection
// - Idle timeout and max session limits

import { createServer as createHttpServer } from 'node:http';
import { createServer as createHttpsServer } from 'node:https';
import { readFileSync, existsSync } from 'node:fs';
import { join, extname, normalize, resolve } from 'node:path';
import { homedir } from 'node:os';
import { WebSocketServer } from 'ws';
import pty from 'node-pty';
import { parseArgs } from 'node:util';

// =============================================================================
// CONFIGURATION
// =============================================================================

const { values: args } = parseArgs({
  options: {
    port: { type: 'string', default: '7685' },
    host: { type: 'string', default: '0.0.0.0' },
    'working-directory': { type: 'string', default: '/workspace' },
    'max-sessions': { type: 'string', default: '10' },
    'idle-timeout': { type: 'string', default: '1800' },
    shell: { type: 'string' },
    // SSL options (matches ghostty-web/ttyd pattern)
    ssl: { type: 'boolean', default: false },
    'ssl-cert': { type: 'string' },
    'ssl-key': { type: 'string' },
    // Reverse proxy support
    'base-path': { type: 'string', default: '' },
    // WebSocket security
    'check-origin': { type: 'boolean', default: false },
    // Allow client input (readonly by default)
    writable: { type: 'boolean', default: false },
  },
});

// Detect shell - NixOS doesn't have /bin/bash
function getDefaultShell() {
  const nixSystemBash = '/run/current-system/sw/bin/bash';
  if (existsSync(nixSystemBash)) {
    return nixSystemBash;
  }
  return process.env.SHELL || '/bin/bash';
}

const CONFIG = {
  port: parseInt(args.port, 10),
  host: args.host,
  workingDirectory: args['working-directory'],
  maxSessions: parseInt(args['max-sessions'], 10),
  idleTimeout: parseInt(args['idle-timeout'], 10) * 1000,
  shell: args.shell || getDefaultShell(),
  ssl: args.ssl,
  sslCert: args['ssl-cert'],
  sslKey: args['ssl-key'],
  basePath: args['base-path'].replace(/\/$/, ''),
  checkOrigin: args['check-origin'],
  writable: args.writable,
};

// =============================================================================
// MIME TYPES
// =============================================================================

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

// =============================================================================
// STATIC FILE PATHS (injected by Nix)
// =============================================================================

const STATIC_DIR = process.env.RESTTY_WEB_STATIC || join(import.meta.dirname, 'static');
const STATIC_DIR_RESOLVED = resolve(STATIC_DIR);

// =============================================================================
// PATH TRAVERSAL PROTECTION
// =============================================================================

function resolveSafePath(requestedPath) {
  const normalized = normalize(requestedPath);
  const resolved = resolve(STATIC_DIR, '.' + normalized);
  if (!resolved.startsWith(STATIC_DIR_RESOLVED + '/') && resolved !== STATIC_DIR_RESOLVED) {
    return null;
  }
  return resolved;
}

// =============================================================================
// SESSION MANAGEMENT
// =============================================================================

const sessions = new Map();

function getShell() {
  return CONFIG.shell;
}

function getShellArgs() {
  return ['-l'];
}

function createPtySession(cols, rows) {
  const shell = getShell();
  const cwd = existsSync(CONFIG.workingDirectory) ? CONFIG.workingDirectory : homedir();

  const ptyProcess = pty.spawn(shell, getShellArgs(), {
    name: 'xterm-256color',
    cols: cols || 80,
    rows: rows || 24,
    cwd: cwd,
    env: {
      ...process.env,
      TERM: 'xterm-256color',
      COLORTERM: 'truecolor',
      // restty uses libghostty-vt WASM core — TERM_PROGRAM='ghostty' activates
      // ghostty-specific shell integrations which restty supports natively
      TERM_PROGRAM: 'ghostty',
      TERM_PROGRAM_VERSION: '1.0',
      LANG: process.env.LANG || 'C.UTF-8',
      HOME: process.env.HOME || homedir(),
    },
  });

  return ptyProcess;
}

function cleanupSession(ws) {
  const session = sessions.get(ws);
  if (session) {
    if (session.idleTimer) clearTimeout(session.idleTimer);
    try {
      session.pty.kill();
    } catch (e) {
      // PTY may already be dead
    }
    sessions.delete(ws);
  }
}

function resetIdleTimer(ws) {
  const session = sessions.get(ws);
  if (session && CONFIG.idleTimeout > 0) {
    if (session.idleTimer) clearTimeout(session.idleTimer);
    session.idleTimer = setTimeout(() => {
      console.log(`[restty-web] Session idle timeout, closing`);
      ws.close(1000, 'Idle timeout');
    }, CONFIG.idleTimeout);
  }
}

// =============================================================================
// HTTP SERVER
// =============================================================================

function serveFile(filePath, res) {
  try {
    const content = readFileSync(filePath);
    const ext = extname(filePath);
    const contentType = MIME_TYPES[ext] || 'application/octet-stream';
    res.writeHead(200, {
      'Content-Type': contentType,
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp',
    });
    res.end(content);
  } catch (err) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found');
  }
}

function stripBasePath(pathname) {
  if (CONFIG.basePath && pathname.startsWith(CONFIG.basePath)) {
    const stripped = pathname.slice(CONFIG.basePath.length);
    return stripped || '/';
  }
  return pathname;
}

function handleRequest(req, res) {
  const protocol = CONFIG.ssl ? 'https' : 'http';
  const url = new URL(req.url, `${protocol}://${req.headers.host}`);
  let pathname = url.pathname;

  pathname = stripBasePath(pathname);

  // Health check endpoint
  if (pathname === '/health' || url.pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      sessions: sessions.size,
      maxSessions: CONFIG.maxSessions,
      uptime: process.uptime(),
      ssl: CONFIG.ssl,
      basePath: CONFIG.basePath || '/',
    }));
    return;
  }

  // Static files
  const resolvedPath = resolveSafePath(pathname === '/' ? '/index.html' : pathname);

  if (resolvedPath === null) {
    console.warn(`[restty-web] Path traversal blocked: ${pathname}`);
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    res.end('Forbidden');
    return;
  }

  serveFile(resolvedPath, res);
}

// Create HTTP or HTTPS server
let httpServer;
if (CONFIG.ssl) {
  if (!CONFIG.sslCert || !CONFIG.sslKey) {
    console.error('[restty-web] SSL enabled but --ssl-cert and --ssl-key not provided');
    process.exit(1);
  }
  if (!existsSync(CONFIG.sslCert)) {
    console.error(`[restty-web] SSL certificate not found: ${CONFIG.sslCert}`);
    process.exit(1);
  }
  if (!existsSync(CONFIG.sslKey)) {
    console.error(`[restty-web] SSL key not found: ${CONFIG.sslKey}`);
    process.exit(1);
  }

  const sslOptions = {
    cert: readFileSync(CONFIG.sslCert),
    key: readFileSync(CONFIG.sslKey),
  };
  httpServer = createHttpsServer(sslOptions, handleRequest);
  console.log('[restty-web] SSL enabled');
} else {
  httpServer = createHttpServer(handleRequest);
}

// =============================================================================
// WEBSOCKET SERVER
// =============================================================================

const wsPath = CONFIG.basePath ? `${CONFIG.basePath}/pty` : '/pty';

const wss = new WebSocketServer({
  server: httpServer,
  path: wsPath,
  verifyClient: CONFIG.checkOrigin
    ? ({ origin, req }) => {
        if (!origin) return true;
        const requestHost = req.headers.host;
        try {
          const originUrl = new URL(origin);
          if (originUrl.host === requestHost) return true;
          console.warn(`[restty-web] Origin check failed: ${origin} vs ${requestHost}`);
          return false;
        } catch (e) {
          console.warn(`[restty-web] Invalid origin header: ${origin}`);
          return false;
        }
      }
    : undefined,
});

wss.on('connection', (ws, req) => {
  if (sessions.size >= CONFIG.maxSessions) {
    console.log(`[restty-web] Max sessions (${CONFIG.maxSessions}) reached, rejecting`);
    ws.send(JSON.stringify({ type: 'error', message: 'Max sessions reached' }));
    ws.close(1013, 'Max sessions reached');
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host}`);
  const cols = parseInt(url.searchParams.get('cols')) || 80;
  const rows = parseInt(url.searchParams.get('rows')) || 24;

  const mode = CONFIG.writable ? 'rw' : 'ro';
  console.log(
    `[restty-web] New connection: ${cols}x${rows} [${mode}] (${sessions.size + 1}/${CONFIG.maxSessions})`
  );

  let ptyProcess;
  try {
    ptyProcess = createPtySession(cols, rows);
  } catch (err) {
    console.error(`[restty-web] Failed to spawn PTY:`, err.message);
    ws.send(
      JSON.stringify({ type: 'error', message: 'Failed to spawn shell', errors: [err.message] })
    );
    ws.close(1011, 'PTY spawn failed');
    return;
  }

  const session = { pty: ptyProcess, idleTimer: null };
  sessions.set(ws, session);
  resetIdleTimer(ws);

  // Send status message (restty protocol)
  try {
    ws.send(JSON.stringify({ type: 'status', shell: getShell() }));
  } catch (e) {
    // ignore
  }

  // PTY -> WebSocket (send as binary for restty efficiency)
  ptyProcess.onData((data) => {
    if (ws.readyState === ws.OPEN) {
      ws.send(Buffer.from(data, 'utf8'));
    }
  });

  // PTY exit
  ptyProcess.onExit(({ exitCode, signal }) => {
    console.log(`[restty-web] PTY exited: code=${exitCode}, signal=${signal}`);
    if (ws.readyState === ws.OPEN) {
      try {
        ws.send(JSON.stringify({ type: 'exit', code: exitCode }));
      } catch (e) {
        // ignore
      }
      ws.close(1000, 'PTY exited');
    }
    sessions.delete(ws);
  });

  // WebSocket -> PTY (restty protocol: JSON messages)
  ws.on('message', (data) => {
    resetIdleTimer(ws);
    const message = data.toString('utf8');

    if (message.startsWith('{')) {
      try {
        const msg = JSON.parse(message);

        // Resize: always allowed (even in readonly mode)
        if (msg.type === 'resize' && typeof msg.cols === 'number' && typeof msg.rows === 'number') {
          ptyProcess.resize(msg.cols, msg.rows);
          return;
        }

        // Input: only in writable mode
        if (msg.type === 'input' && typeof msg.data === 'string') {
          if (!CONFIG.writable) {
            return;
          }
          ptyProcess.write(msg.data);
          return;
        }
      } catch (e) {
        // Not valid JSON, treat as raw input below
      }
    }

    // Raw string input (fallback) — only in writable mode
    if (!CONFIG.writable) {
      return;
    }
    ptyProcess.write(message);
  });

  ws.on('close', () => {
    console.log(`[restty-web] Connection closed (${sessions.size - 1}/${CONFIG.maxSessions})`);
    cleanupSession(ws);
  });

  ws.on('error', (err) => {
    console.error(`[restty-web] WebSocket error:`, err.message);
    cleanupSession(ws);
  });
});

// =============================================================================
// LIFECYCLE
// =============================================================================

function shutdown(signal) {
  console.log(`\n[restty-web] Received ${signal}, shutting down...`);

  for (const ws of sessions.keys()) {
    cleanupSession(ws);
    ws.close(1001, 'Server shutting down');
  }

  wss.close(() => {
    httpServer.close(() => {
      console.log('[restty-web] Shutdown complete');
      process.exit(0);
    });
  });

  setTimeout(() => {
    console.error('[restty-web] Forced shutdown');
    process.exit(1);
  }, 5000);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

httpServer.listen(CONFIG.port, CONFIG.host, () => {
  const protocol = CONFIG.ssl ? 'https' : 'http';
  const wsProtocol = CONFIG.ssl ? 'wss' : 'ws';
  const baseUrl = CONFIG.basePath || '';

  console.log(`[restty-web] Server listening on ${protocol}://${CONFIG.host}:${CONFIG.port}${baseUrl}`);
  console.log(`[restty-web] WebSocket endpoint: ${wsProtocol}://${CONFIG.host}:${CONFIG.port}${baseUrl}/pty`);
  console.log(`[restty-web] Health check: ${protocol}://${CONFIG.host}:${CONFIG.port}/health`);
  console.log(`[restty-web] Shell: ${CONFIG.shell}`);
  console.log(`[restty-web] Working directory: ${CONFIG.workingDirectory}`);
  console.log(`[restty-web] Max sessions: ${CONFIG.maxSessions}`);
  console.log(`[restty-web] Idle timeout: ${CONFIG.idleTimeout / 1000}s`);
  if (CONFIG.basePath) {
    console.log(`[restty-web] Base path: ${CONFIG.basePath}`);
  }
  if (CONFIG.checkOrigin) {
    console.log(`[restty-web] Origin checking: enabled`);
  }
  console.log(`[restty-web] Mode: ${CONFIG.writable ? 'writable' : 'readonly'}`);
});
