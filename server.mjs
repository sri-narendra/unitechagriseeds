import http from 'http';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = 3000;

// Simple static file server that also handles API routes
const server = http.createServer(async (req, res) => {
  let urlPath = new URL(req.url, `http://localhost:${PORT}`).pathname;
  
  // Route rewrites from vercel.json
  const rewrites = {
    '/': '/public/index.html',
    '/about': '/public/about.html',
    '/about.html': '/public/about.html',
    '/products': '/public/products.html',
    '/products.html': '/public/products.html',
    '/contact': '/public/contact.html',
    '/contact.html': '/public/contact.html'
  };
  
  // Apply rewrites
  if (rewrites[urlPath]) {
    urlPath = rewrites[urlPath];
  }
  
  // API routes
  if (urlPath.startsWith('/api/')) {
    await handleApi(req, res, urlPath);
    return;
  }
  
  // Serve static files
  let filePath = path.join(__dirname, urlPath);
  
  // Default to index.html for directory roots
  if (urlPath.endsWith('/')) {
    filePath = path.join(filePath, 'index.html');
  }
  
  try {
    const content = fs.readFileSync(filePath);
    const ext = path.extname(filePath).toLowerCase();
    const mimeTypes = {
      '.html': 'text/html',
      '.css': 'text/css',
      '.js': 'application/javascript',
      '.json': 'application/json',
      '.png': 'image/png',
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.gif': 'image/gif',
      '.svg': 'image/svg+xml',
      '.ico': 'image/x-icon'
    };
    res.writeHead(200, { 
      'Content-Type': mimeTypes[ext] || 'application/octet-stream',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'DENY',
      'Referrer-Policy': 'strict-origin-when-cross-origin'
    });
    res.end(content);
  } catch (err) {
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('NOT_FOUND');
  }
});

async function handleApi(req, res, urlPath) {
  // Set security headers
  const headers = {
    'Content-Type': 'application/json',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'strict-origin-when-cross-origin'
  };
  
  // Handle health endpoint
  if (urlPath === '/api/health') {
    res.writeHead(200, headers);
    res.end(JSON.stringify({ ok: true, data: { uptime: process.uptime() } }));
    return;
  }
  
  res.writeHead(404, headers);
  res.end(JSON.stringify({ ok: false, error: { code: 'NOT_FOUND', message: 'Endpoint not found' } }));
}

server.listen(PORT, () => {
  console.log(`\n🚀 Local server running at http://localhost:${PORT}`);
  console.log(`   Serving: public/, dealer/, admin/ + /api/health\n`);
});
