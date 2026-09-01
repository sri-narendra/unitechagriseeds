import { createServer } from 'http';
import { readFileSync } from 'fs';
import { join, extname } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css',
  '.js': 'application/javascript',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.apk': 'application/vnd.android.package-archive',
};

// Load all API handlers
const healthHandler = (await import('./api/health.js')).default;
const createDealerHandler = (await import('./api/create-dealer.js')).default;
const resetPwHandler = (await import('./api/reset-dealer-password.js')).default;
const bootstrapHandler = (await import('./api/bootstrap-admin.js')).default;

const API_ROUTES = {
  '/api/health': healthHandler,
  '/api/create-dealer': createDealerHandler,
  '/api/reset-dealer-password': resetPwHandler,
  '/api/bootstrap-admin': bootstrapHandler,
};

const server = createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  let pathname = url.pathname;

  // API routing
  const apiHandler = API_ROUTES[pathname];
  if (apiHandler) {
    try { await apiHandler(req, res); }
    catch (e) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: { code: 'INTERNAL', message: 'Server error' } }));
    }
    return;
  }

  // Static files from public/
  if (pathname === '/') pathname = '/index.html';
  const filePath = join(__dirname, 'public', pathname);
  try {
    const content = readFileSync(filePath);
    const ext = extname(filePath).toLowerCase();
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(content);
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not Found');
  }
});

server.listen(3000);
