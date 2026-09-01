// Vercel entrypoint — routes /api/* to the correct handler in api/
import { createServer } from 'http';
import { readFileSync, existsSync } from 'fs';
import { join, extname } from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __dirname = dirname(fileURLToPath(import.meta.url));

const MIME = {
  '.html': 'text/html', '.css': 'text/css', '.js': 'application/javascript',
  '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon', '.apk': 'application/vnd.android.package-archive',
};

const server = createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  let pathname = url.pathname;

  // API routing
  if (pathname.startsWith('/api/')) {
    const handlerName = pathname.replace('/api/', '').split('/')[0] || 'health';
    const handlerPath = join(__dirname, 'api', handlerName + '.js');
    try {
      const mod = await import(handlerPath);
      const handler = mod.default || mod;
      await handler(req, res);
    } catch (e) {
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: false, error: { code: 'NOT_FOUND', message: 'Endpoint not found' } }));
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
