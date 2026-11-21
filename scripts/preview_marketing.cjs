// Read-only loopback preview. Run: node scripts/preview_marketing.cjs --port 4178
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const args = process.argv.slice(2);
if (args.length !== 2 || args[0] !== '--port' || !/^\d+$/.test(args[1])) throw Error('Usage: node scripts/preview_marketing.cjs --port <1024-65535>');
const port = Number(args[1]);
if (port < 1024 || port > 65535) throw Error('Port outside 1024-65535');
const root = path.resolve(__dirname, '../public');
const types = {'.html':'text/html; charset=utf-8','.css':'text/css','.js':'text/javascript','.svg':'image/svg+xml','.png':'image/png','.webp':'image/webp','.json':'application/json','.apk':'application/vnd.android.package-archive'};
const server = http.createServer((request, response) => {
  if (!['GET','HEAD'].includes(request.method)) { response.writeHead(405); return response.end(); }
  try {
    const pathname = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
    let file = path.resolve(root, '.' + pathname);
    if (!file.startsWith(root + path.sep) && file !== root) { response.writeHead(403); return response.end(); }
    if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
    if (!fs.existsSync(file) || !fs.statSync(file).isFile()) { response.writeHead(404); return response.end('Not found'); }
    response.writeHead(200, {'Content-Type':types[path.extname(file)] || 'application/octet-stream','Cache-Control':'no-store'});
    if (request.method === 'HEAD') return response.end();
    const stream = fs.createReadStream(file); stream.on('error', () => response.destroy()); stream.pipe(response);
  } catch { response.writeHead(400); response.end('Invalid request'); }
});
server.on('error', error => { console.error(error.message); process.exitCode = 1; });
server.listen(port, '127.0.0.1', () => console.log(`Pokpok marketing preview: http://127.0.0.1:${port}`));
