"""Loopback HTTP facade with exact routes, bearer auth and same-origin mutations."""
import base64
import hashlib
import hmac
from http.server import BaseHTTPRequestHandler, HTTPServer
import ipaddress
import json
import secrets
import socket

from .adapter import sha


PAGE = '''<!doctype html><meta charset="utf-8"><title>Today native gallery</title>
<h1>Today native gallery</h1><p>Native captures. Open a scene on the owned device to interact.</p>
<main></main><script>
const token = location.hash.slice(1); history.replaceState(null, '', '/');
const headers = {Authorization: 'Bearer ' + token, 'Content-Type': 'application/json'};
const main = document.querySelector('main'); let busy = false; let urls = [];
async function refresh() {
 if (busy) return; busy = true;
 try {
  const response = await fetch('/api/state', {headers});
  if (!response.ok) throw Error('Authentication or state request failed');
  const state = await response.json(); const content = document.createDocumentFragment(); const nextUrls = [];
  for (const entry of state.entries) {
   const section = document.createElement('section'); const title = document.createElement('h2');
   title.textContent = entry.scene + ' / ' + entry.scenario + ' — ' + entry.status; section.append(title);
   for (const action of ['capture', 'open']) {
    const button = document.createElement('button'); button.textContent = action;
    button.onclick = async () => { button.disabled = true;
     try { const r = await fetch('/api/' + action, {method:'POST', headers,
      body: JSON.stringify({scene: entry.scene, scenario: entry.scenario})});
      if (!r.ok) alert(await r.text()); } finally { button.disabled = false; refresh(); }
    }; section.append(button);
   }
   const info = document.createElement('pre'); info.textContent = JSON.stringify(entry, null, 2); section.append(info);
   if (entry.last_good) {
    const r = await fetch(entry.last_good.image, {headers});
    if (r.ok) { const img = document.createElement('img'); img.alt = entry.scene + ' native capture';
     img.style.maxWidth = '420px'; img.src = URL.createObjectURL(await r.blob()); nextUrls.push(img.src); section.append(img); }
   } content.append(section);
  }
  main.replaceChildren(content); urls.forEach(url => URL.revokeObjectURL(url)); urls = nextUrls;
 } catch (error) { main.textContent = error.message; } finally { busy = false; }
}
refresh(); setInterval(refresh, 1500);
</script>'''


class GalleryServer(HTTPServer):
    """Single executor: HTTP capture and watch never run native commands in parallel."""
    allow_reuse_address = False

    def __init__(self, gallery, *, host='127.0.0.1', port=0, token=None, watch=True):
        if host != '127.0.0.1':
            raise ValueError('Gallery must bind IPv4 loopback only')
        self.gallery, self.watch = gallery, watch
        self.token = token or secrets.token_urlsafe(32)
        if len(self.token) < 32 or not self.token.isascii() or any(c.isspace() for c in self.token):
            raise ValueError('Strong ASCII token required')
        super().__init__((host, port), Handler)
        self.origin = f'http://127.0.0.1:{self.server_port}'
        self.authority = f'127.0.0.1:{self.server_port}'

    @property
    def url(self):
        return self.origin + '/#' + self.token

    def service_actions(self):
        if self.gallery.native.cancel.is_set():
            raise KeyboardInterrupt
        if self.watch:
            self.gallery.tick()

    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(3)
        return connection, address


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # Never log bearer credentials or attacker-controlled request lines.

    def reply(self, status, body=b'', content_type='application/json'):
        if not isinstance(body, bytes):
            body = json.dumps(body).encode()
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('Content-Security-Policy',
                         "default-src 'none'; script-src 'sha256-" +
                         base64.b64encode(hashlib.sha256(
                             PAGE.split('<script>')[1].split('</script>')[0].encode()).digest()).decode() +
                         "'; connect-src 'self'; img-src blob:; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
        self.send_header('Connection', 'close')
        self.end_headers()
        self.close_connection = True
        self.wfile.write(body)

    def guard(self, *, mutation=False, authenticated=True):
        def single(name):
            values = self.headers.get_all(name, [])
            return values[0] if len(values) == 1 else None
        origin = single('Origin')
        if (not ipaddress.ip_address(self.client_address[0]).is_loopback or
                single('Host') != self.server.authority or
                (self.headers.get_all('Origin') and origin != self.server.origin) or
                (mutation and origin != self.server.origin) or
                self.headers.get('Sec-Fetch-Site') not in (None, 'same-origin', 'none')):
            self.reply(403, {'error': 'Loopback same-origin request required'})
            return False
        auth = single('Authorization') or ''
        if authenticated and not hmac.compare_digest(auth.encode(), ('Bearer ' + self.server.token).encode()):
            self.reply(401, {'error': 'Bearer token required'})
            return False
        return True

    def do_GET(self):
        if not self.guard(authenticated=self.path != '/'):
            return
        if self.path == '/':
            self.reply(200, PAGE.encode(), 'text/html; charset=utf-8')
        elif self.path == '/api/state':
            self.reply(200, self.server.gallery.state())
        elif self.path.startswith('/images/') and self.path[8:] in self.server.gallery.images:
            path, digest = self.server.gallery.images[self.path[8:]]
            if path.is_symlink() or not path.is_file():
                self.reply(409, {'error': 'Capture missing'})
                return
            data = path.read_bytes()
            if sha(data) != digest:
                self.reply(409, {'error': 'Capture changed after indexing'})
                return
            self.reply(200, data, 'image/png')
        else:
            self.reply(404, {'error': 'Unknown read route'})

    def do_POST(self):
        if not self.guard(mutation=True):
            return
        if self.path not in ('/api/capture', '/api/open'):
            self.reply(404, {'error': 'Unknown mutation route'})
            return
        try:
            lengths = self.headers.get_all('Content-Length', [])
            if (self.headers.get('Transfer-Encoding') or len(lengths) != 1 or
                    self.headers.get('Content-Type') != 'application/json'):
                raise ValueError('Only bounded JSON bodies accepted')
            length = int(lengths[0])
            if not 0 < length <= 1024:
                raise ValueError('Invalid body size')
            def unique(pairs):
                result = {}
                for key, value in pairs:
                    if key in result:
                        raise ValueError('Duplicate JSON key')
                    result[key] = value
                return result
            body = json.loads(self.rfile.read(length), object_pairs_hook=unique)
            if not isinstance(body, dict) or set(body) != {'scene', 'scenario'}:
                raise ValueError('Only scene/scenario accepted')
            self.server.gallery.manifest.scene(body['scene'], body['scenario'])
        except (ValueError, TypeError, UnicodeError, socket.timeout):
            self.reply(400, {'error': 'Invalid allowlisted scene request'})
            return
        try:
            if self.path == '/api/capture':
                result = self.server.gallery.capture(body['scene'], body['scenario'])
                self.reply(502 if result['error'] else 200, result)
            else:
                self.server.gallery.open(body['scene'], body['scenario'])
                self.reply(200, {'opened': True})
        except Exception:
            self.reply(502, {'error': 'Native action failed; inspect retained native log'})

    def do_OPTIONS(self):
        self.reply(403, {'error': 'CORS is disabled'})
