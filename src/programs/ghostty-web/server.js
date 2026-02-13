#!/usr/bin/env node
// Ghostty Web Terminal Server
// Konductor Integration - Single-port HTTP/HTTPS + WebSocket PTY Server
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
    port: { type: 'string', default: '10000' },
    host: { type: 'string', default: '0.0.0.0' },
    'working-directory': { type: 'string', default: '/workspace' },
    'max-sessions': { type: 'string', default: '10' },
    'idle-timeout': { type: 'string', default: '1800' },
    shell: { type: 'string' },
    // SSL options (matches ttyd pattern)
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
  // NixOS: use system bash wrapper (symlink to nix store)
  const nixSystemBash = '/run/current-system/sw/bin/bash';
  if (existsSync(nixSystemBash)) {
    return nixSystemBash;
  }
  // Non-NixOS: use SHELL env or /bin/bash
  return process.env.SHELL || '/bin/bash';
}

const CONFIG = {
  port: parseInt(args.port, 10),
  host: args.host,
  workingDirectory: args['working-directory'],
  maxSessions: parseInt(args['max-sessions'], 10),
  idleTimeout: parseInt(args['idle-timeout'], 10) * 1000, // Convert to ms
  shell: args.shell || getDefaultShell(),
  // SSL configuration
  ssl: args.ssl,
  sslCert: args['ssl-cert'],
  sslKey: args['ssl-key'],
  // Reverse proxy base path (e.g., /terminal)
  basePath: args['base-path'].replace(/\/$/, ''), // Remove trailing slash
  // WebSocket origin checking
  checkOrigin: args['check-origin'],
  // Allow client input
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
};

// =============================================================================
// STATIC FILE PATHS (injected by Nix)
// =============================================================================

const STATIC_DIR = process.env.GHOSTTY_WEB_STATIC || join(import.meta.dirname, 'static');
const WASM_PATH = process.env.GHOSTTY_WEB_WASM || join(STATIC_DIR, 'ghostty-vt.wasm');

// Resolve absolute path for comparison (handles symlinks in /nix/store)
const STATIC_DIR_RESOLVED = resolve(STATIC_DIR);

// =============================================================================
// PATH TRAVERSAL PROTECTION
// =============================================================================
// Validates that requested path resolves within STATIC_DIR.
// Prevents directory traversal attacks (../, encoded variants, symlink escapes).

function resolveSafePath(requestedPath) {
  // Normalize to handle encoded characters and redundant separators
  const normalized = normalize(requestedPath);

  // Join with static dir and resolve to absolute path
  const resolved = resolve(STATIC_DIR, '.' + normalized);

  // Verify resolved path is within STATIC_DIR (prefix check)
  // The '/' suffix check prevents /static-evil matching /static
  if (!resolved.startsWith(STATIC_DIR_RESOLVED + '/') && resolved !== STATIC_DIR_RESOLVED) {
    return null; // Traversal attempt
  }

  return resolved;
}

// =============================================================================
// SESSION MANAGEMENT
// =============================================================================

const sessions = new Map();

function getShell() {
  // Prefer login shell for full environment (completions, readline, etc.)
  // Order: --shell flag > $SHELL > /bin/bash
  return CONFIG.shell;
}

function getShellArgs() {
  // Use login shell (-l) to source /etc/profile, ~/.profile, ~/.bashrc, etc.
  // This ensures full environment with completions, aliases, and proper readline
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
      LANG: process.env.LANG || 'C.UTF-8',
      // Ensure HOME is set for login shell initialization
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
      console.log(`[ghostty-web] Session idle timeout, closing`);
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
    res.writeHead(200, { 'Content-Type': contentType });
    res.end(content);
  } catch (err) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found');
  }
}

// Strip basePath from pathname if configured
function stripBasePath(pathname) {
  if (CONFIG.basePath && pathname.startsWith(CONFIG.basePath)) {
    const stripped = pathname.slice(CONFIG.basePath.length);
    return stripped || '/';
  }
  return pathname;
}

// Request handler (shared between HTTP and HTTPS)
function handleRequest(req, res) {
  const protocol = CONFIG.ssl ? 'https' : 'http';
  const url = new URL(req.url, `${protocol}://${req.headers.host}`);
  let pathname = url.pathname;

  // Strip basePath for routing
  pathname = stripBasePath(pathname);

  // Health check endpoint (always accessible, ignores basePath)
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

  // WASM file
  if (pathname === '/ghostty-vt.wasm') {
    serveFile(WASM_PATH, res);
    return;
  }

  // Static files - validate path is within STATIC_DIR
  const resolvedPath = resolveSafePath(pathname === '/' ? '/index.html' : pathname);

  if (resolvedPath === null) {
    // Path traversal attempt detected
    console.warn(`[ghostty-web] Path traversal blocked: ${pathname}`);
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    res.end('Forbidden');
    return;
  }

  serveFile(resolvedPath, res);
}

// Create HTTP or HTTPS server based on SSL config
let httpServer;
if (CONFIG.ssl) {
  if (!CONFIG.sslCert || !CONFIG.sslKey) {
    console.error('[ghostty-web] SSL enabled but --ssl-cert and --ssl-key not provided');
    process.exit(1);
  }
  if (!existsSync(CONFIG.sslCert)) {
    console.error(`[ghostty-web] SSL certificate not found: ${CONFIG.sslCert}`);
    process.exit(1);
  }
  if (!existsSync(CONFIG.sslKey)) {
    console.error(`[ghostty-web] SSL key not found: ${CONFIG.sslKey}`);
    process.exit(1);
  }

  const sslOptions = {
    cert: readFileSync(CONFIG.sslCert),
    key: readFileSync(CONFIG.sslKey),
  };
  httpServer = createHttpsServer(sslOptions, handleRequest);
  console.log('[ghostty-web] SSL enabled');
} else {
  httpServer = createHttpServer(handleRequest);
}

// =============================================================================
// WEBSOCKET SERVER
// =============================================================================

// WebSocket path (with basePath if configured)
const wsPath = CONFIG.basePath ? `${CONFIG.basePath}/ws` : '/ws';

const wss = new WebSocketServer({
  server: httpServer,
  path: wsPath,
  // Origin verification callback
  verifyClient: CONFIG.checkOrigin ? ({ origin, req }) => {
    // Allow requests without origin header (non-browser clients)
    if (!origin) return true;

    // Parse origin and request host
    const requestHost = req.headers.host;
    try {
      const originUrl = new URL(origin);
      const originHost = originUrl.host;

      // Allow if origin host matches request host
      if (originHost === requestHost) return true;

      console.warn(`[ghostty-web] Origin check failed: ${origin} vs ${requestHost}`);
      return false;
    } catch (e) {
      console.warn(`[ghostty-web] Invalid origin header: ${origin}`);
      return false;
    }
  } : undefined,
});

wss.on('connection', (ws, req) => {
  // Check max sessions
  if (sessions.size >= CONFIG.maxSessions) {
    console.log(`[ghostty-web] Max sessions (${CONFIG.maxSessions}) reached, rejecting connection`);
    ws.close(1013, 'Max sessions reached');
    return;
  }

  // Parse dimensions from query string
  const url = new URL(req.url, `http://${req.headers.host}`);
  const cols = parseInt(url.searchParams.get('cols')) || 80;
  const rows = parseInt(url.searchParams.get('rows')) || 24;

  const mode = CONFIG.writable ? 'rw' : 'ro';
  console.log(`[ghostty-web] New connection: ${cols}x${rows} [${mode}] (${sessions.size + 1}/${CONFIG.maxSessions})`);

  // Create PTY session
  let ptyProcess;
  try {
    ptyProcess = createPtySession(cols, rows);
  } catch (err) {
    console.error(`[ghostty-web] Failed to spawn PTY:`, err.message);
    ws.close(1011, 'PTY spawn failed');
    return;
  }

  // Store session
  const session = { pty: ptyProcess, idleTimer: null };
  sessions.set(ws, session);
  resetIdleTimer(ws);

  // PTY -> WebSocket
  ptyProcess.onData((data) => {
    if (ws.readyState === ws.OPEN) {
      ws.send(data);
    }
  });

  // PTY exit
  ptyProcess.onExit(({ exitCode, signal }) => {
    console.log(`[ghostty-web] PTY exited: code=${exitCode}, signal=${signal}`);
    if (ws.readyState === ws.OPEN) {
      ws.close(1000, 'PTY exited');
    }
    sessions.delete(ws);
  });

  // WebSocket -> PTY
  ws.on('message', (data) => {
    resetIdleTimer(ws);
    const message = data.toString('utf8');

    // Resize commands allowed in readonly mode
    if (message.startsWith('{')) {
      try {
        const msg = JSON.parse(message);
        if (msg.type === 'resize' && typeof msg.cols === 'number' && typeof msg.rows === 'number') {
          ptyProcess.resize(msg.cols, msg.rows);
          return;
        }
      } catch (e) {
        // Not valid JSON, treat as input
      }
    }

    // Readonly mode: ignore input
    if (!CONFIG.writable) {
      return;
    }

    ptyProcess.write(message);
  });

  // WebSocket close
  ws.on('close', () => {
    console.log(`[ghostty-web] Connection closed (${sessions.size - 1}/${CONFIG.maxSessions})`);
    cleanupSession(ws);
  });

  // WebSocket error
  ws.on('error', (err) => {
    console.error(`[ghostty-web] WebSocket error:`, err.message);
    cleanupSession(ws);
  });
});

// =============================================================================
// LIFECYCLE
// =============================================================================

function shutdown(signal) {
  console.log(`\n[ghostty-web] Received ${signal}, shutting down...`);

  // Close all sessions
  for (const ws of sessions.keys()) {
    cleanupSession(ws);
    ws.close(1001, 'Server shutting down');
  }

  // Close servers
  wss.close(() => {
    httpServer.close(() => {
      console.log('[ghostty-web] Shutdown complete');
      process.exit(0);
    });
  });

  // Force exit after 5 seconds
  setTimeout(() => {
    console.error('[ghostty-web] Forced shutdown');
    process.exit(1);
  }, 5000);
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

// Start server
httpServer.listen(CONFIG.port, CONFIG.host, () => {
  const protocol = CONFIG.ssl ? 'https' : 'http';
  const wsProtocol = CONFIG.ssl ? 'wss' : 'ws';
  const baseUrl = CONFIG.basePath || '';

  console.log(`[ghostty-web] Server listening on ${protocol}://${CONFIG.host}:${CONFIG.port}${baseUrl}`);
  console.log(`[ghostty-web] WebSocket endpoint: ${wsProtocol}://${CONFIG.host}:${CONFIG.port}${baseUrl}/ws`);
  console.log(`[ghostty-web] Health check: ${protocol}://${CONFIG.host}:${CONFIG.port}/health`);
  console.log(`[ghostty-web] Shell: ${CONFIG.shell}`);
  console.log(`[ghostty-web] Working directory: ${CONFIG.workingDirectory}`);
  console.log(`[ghostty-web] Max sessions: ${CONFIG.maxSessions}`);
  console.log(`[ghostty-web] Idle timeout: ${CONFIG.idleTimeout / 1000}s`);
  if (CONFIG.basePath) {
    console.log(`[ghostty-web] Base path: ${CONFIG.basePath}`);
  }
  if (CONFIG.checkOrigin) {
    console.log(`[ghostty-web] Origin checking: enabled`);
  }
  console.log(`[ghostty-web] Mode: ${CONFIG.writable ? 'writable' : 'readonly'}`);
});
