import { createServer } from 'http';
import { readFileSync } from 'fs';
import { join, extname } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { createRequire } from 'module';

const __dirname = dirname(fileURLToPath(import.meta.url));
const require = createRequire(import.meta.url);

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

// Wrap raw http.ServerResponse to provide Express-like .status().json() methods
function wrapRes(res) {
  const wrapped = Object.create(res);
  wrapped.status = function (code) {
    res.statusCode = code;
    return wrapped;
  };
  wrapped.json = function (data) {
    const body = JSON.stringify(data);
    if (!res.headersSent) {
      res.setHeader('Content-Type', 'application/json');
      res.end(body);
    }
    return wrapped;
  };
  wrapped.setHeader = function (name, value) {
    if (!res.headersSent) res.setHeader(name, value);
    return wrapped;
  };
  return wrapped;
}

const healthHandler = require('./api/health.js');
const createDealerHandler = require('./api/create-dealer.js');
const resetPwHandler = require('./api/reset-dealer-password.js');
const bootstrapHandler = require('./api/bootstrap-admin.js');

const API_ROUTES = {
  '/api/health': healthHandler,
  '/api/create-dealer': createDealerHandler,
  '/api/reset-dealer-password': resetPwHandler,
  '/api/bootstrap-admin': bootstrapHandler,
};

const server = createServer(async (req, res) => {
  const wrappedRes = wrapRes(res);
  const url = new URL(req.url, 'http://localhost');
  let pathname = url.pathname;

  // API routing
  const apiHandler = API_ROUTES[pathname];
  if (apiHandler) {
    try {
      // Parse JSON body for POST requests (handle both fresh and pre-consumed streams)
      if (req.method === 'POST' && !req.body) {
        const chunks = [];
        for await (const chunk of req) chunks.push(chunk);
        const raw = Buffer.concat(chunks).toString();
        try { req.body = JSON.parse(raw); } catch { req.body = raw || {}; }
      } else if (req.method === 'POST' && typeof req.body === 'string') {
        try { req.body = JSON.parse(req.body); } catch {}
      }
      await apiHandler(req, wrappedRes);
    } catch (e) {
      if (!res.headersSent) {
        wrappedRes.status(500).json({ ok: false, error: { code: 'INTERNAL', message: String(e.message || e) } });
      }
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
