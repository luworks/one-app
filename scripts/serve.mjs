// Local preview without wrangler: node scripts/serve.mjs  →  http://localhost:8787
import http from 'node:http';
import { pathToFileURL } from 'node:url';
import fs from 'node:fs';
const p = new URL('../dist/worker.js', import.meta.url);
const tmp = new URL('../dist/.worker.mjs', import.meta.url);
fs.copyFileSync(p, tmp);
const { default: worker } = await import(tmp.href + '?' + Date.now());
const port = process.env.PORT || 8787;
http.createServer(async (req, res) => {
  const r = await worker.fetch(new Request('http://localhost' + req.url));
  res.writeHead(r.status, Object.fromEntries(r.headers));
  res.end(Buffer.from(await r.arrayBuffer()));
}).listen(port, () => console.log('one. preview on http://localhost:' + port));
