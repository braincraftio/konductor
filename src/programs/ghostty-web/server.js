#!/usr/bin/env node
// Ghostty Web Terminal Server
// Konductor Integration - Single-port HTTP + WebSocket PTY Server

import { createServer } from 'node:http';
import { readFileSync, existsSync } from 'node:fs';
import { join, extname } from 'node:path';
import { homedir } from 'node:os';
import { WebSocketServer } from 'ws';
import pty from 'node-pty';
import { parseArgs } from 'node:util';

// =============================================================================
// CONFIGURATION
// =============================================================================

const { values: args } = parseArgs({
  options: {
    port: { type: 'string', default: '7681' },
    host: { type: 'string', default: '0.0.0.0' },
    'working-directory': { type: 'string', default: '/workspace' },
    'max-sessions': { type: 'string', default: '10' },
    'idle-timeout': { type: 'string', default: '1800' },
    shell: { type: 'string' },
  },
});

// Detect if shell is a minimal Nix bash (lacks readline/completions)
function getDefaultShell() {
  const envShell = process.env.SHELL || '';
  // Nix store bash is minimal - prefer system bash for full features
  // (readline, programmable completion, bind, etc.)
  if (envShell.includes('/nix/store/') && envShell.includes('bash')) {
    return '/bin/bash';
  }
  return envShell || '/bin/bash';
}

const CONFIG = {
  port: parseInt(args.port, 10),
  host: args.host,
  workingDirectory: args['working-directory'],
  maxSessions: parseInt(args['max-sessions'], 10),
  idleTimeout: parseInt(args['idle-timeout'], 10) * 1000, // Convert to ms
  shell: args.shell || getDefaultShell(),
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

const httpServer = createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const pathname = url.pathname;

  // Health check endpoint
  if (pathname === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      status: 'ok',
      sessions: sessions.size,
      maxSessions: CONFIG.maxSessions,
      uptime: process.uptime(),
    }));
    return;
  }

  // WASM file
  if (pathname === '/ghostty-vt.wasm') {
    serveFile(WASM_PATH, res);
    return;
  }

  // Static files
  if (pathname === '/' || pathname === '/index.html') {
    serveFile(join(STATIC_DIR, 'index.html'), res);
    return;
  }

  // Other static assets
  const safePath = pathname.replace(/\.\./g, '');
  serveFile(join(STATIC_DIR, safePath), res);
});

// =============================================================================
// WEBSOCKET SERVER
// =============================================================================

const wss = new WebSocketServer({ server: httpServer, path: '/ws' });

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

  console.log(`[ghostty-web] New connection: ${cols}x${rows} (${sessions.size + 1}/${CONFIG.maxSessions})`);

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

    // Check for JSON control message
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

    // Regular input
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
  console.log(`[ghostty-web] Server listening on http://${CONFIG.host}:${CONFIG.port}`);
  console.log(`[ghostty-web] WebSocket endpoint: ws://${CONFIG.host}:${CONFIG.port}/ws`);
  console.log(`[ghostty-web] Health check: http://${CONFIG.host}:${CONFIG.port}/health`);
  console.log(`[ghostty-web] Shell: ${CONFIG.shell}`);
  console.log(`[ghostty-web] Working directory: ${CONFIG.workingDirectory}`);
  console.log(`[ghostty-web] Max sessions: ${CONFIG.maxSessions}`);
  console.log(`[ghostty-web] Idle timeout: ${CONFIG.idleTimeout / 1000}s`);
});
