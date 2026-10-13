#!/usr/bin/env python3
"""Assemble one. (src/) into dist/index.html, dist/artifact.html and a self-contained Cloudflare Worker (dist/worker.js).
Usage: python3 scripts/build.py   (no dependencies beyond the Python standard library)

Original: Assemble one. V8 into dist/index.html and a self-contained Cloudflare Worker (dist/worker.js)."""
import base64, hashlib, io, json, pathlib

root = pathlib.Path(__file__).resolve().parent.parent
src = root / 'src'
dist = root / 'dist'; dist.mkdir(exist_ok=True)
css = (src / 'style.css').read_text(encoding='utf-8')
js = (src / 'app.js').read_text(encoding='utf-8')

html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="default">
<meta name="apple-mobile-web-app-title" content="one.">
<meta name="theme-color" content="#F6F6F2" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#101312" media="(prefers-color-scheme: dark)">
<meta name="robots" content="noindex,nofollow">
<meta name="description" content="one. V8 — an iOS-feel interactive prototype. Today, Calendar, Tasks, Alarms and AI in one calm system.">
<title>one.</title>
<link rel="manifest" href="/manifest.webmanifest">
<link rel="icon" href="/icon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<style>{css}</style>
</head>
<body>
<aside class="side"><b>one.</b><p>V8 prototype. Open this page on your iPhone and use “Add to Home Screen” for the full-screen feel.</p><p>Swipe from the left edge (or tap ☰) for every view. Swipe tasks · long-press anything · drag dashed tasks in Calendar · pull sheets down by the handle.</p></aside>
<div class="app" id="app">
<header class="navbar" id="navbar"></header>
<main class="main" id="main" tabindex="-1"></main>
<div class="dock" id="dock"></div>
<nav class="tabbar" id="tabbar" aria-label="Main"></nav>
<div id="drawer-root"></div><div id="sheet-root"></div><div id="menu-root"></div><div id="ring-root"></div><div id="toast-root" aria-live="polite"></div>
</div>
<script>{js}</script>
</body>
</html>
"""
(dist / 'index.html').write_text(html, encoding='utf-8')

# icons
svg = '<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 192 192"><rect width="192" height="192" rx="42" fill="#257050"/><text x="96" y="118" text-anchor="middle" fill="#fff" font-family="-apple-system,system-ui,sans-serif" font-size="66" font-weight="800" letter-spacing="-4">one.</text></svg>'
png_bytes = (src / 'apple-touch-icon.png').read_bytes(); png_b64 = base64.b64encode(png_bytes).decode()
(dist / 'apple-touch-icon.png').write_bytes(png_bytes)

manifest = json.dumps({"name": "one. — your day, connected", "short_name": "one.", "start_url": "/", "scope": "/", "display": "standalone",
    "background_color": "#F6F6F2", "theme_color": "#F6F6F2", "icons": [{"src": "/icon.svg", "sizes": "any", "type": "image/svg+xml"}, {"src": "/apple-touch-icon.png", "sizes": "180x180", "type": "image/png"}]})

script_hash = base64.b64encode(hashlib.sha256(js.encode()).digest()).decode()
csp = ("default-src 'none'; script-src 'sha256-" + script_hash + "'; style-src 'unsafe-inline'; img-src 'self' data:; "
       "manifest-src 'self'; connect-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'")
health = json.dumps({"app": "one", "build": "v8", "kind": "interactive-prototype", "liveAI": False, "liveAlarms": False})

worker = f"""// one. V8 — static Cloudflare Worker. Sample data only; the page makes no network calls.
const HTML={json.dumps(html)};
const ICON={json.dumps(svg)};
const PNG={json.dumps(png_b64)};
const MANIFEST={json.dumps(manifest)};
const HEALTH={json.dumps(health)};
const BASE={{'X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','X-Robots-Tag':'noindex, nofollow','Permissions-Policy':'camera=(), geolocation=(), microphone=(self)','Content-Security-Policy':{json.dumps(csp)},'Cache-Control':'no-store'}};
function png(){{const b=atob(PNG),u=new Uint8Array(b.length);for(let i=0;i<b.length;i++)u[i]=b.charCodeAt(i);return u}}
export default {{async fetch(req){{const p=new URL(req.url).pathname,h=new Headers(BASE);
 if(p==='/'||p==='/index.html'){{h.set('Content-Type','text/html; charset=utf-8');return new Response(HTML,{{headers:h}})}}
 if(p==='/icon.svg'||p==='/favicon.ico'){{h.set('Content-Type','image/svg+xml');return new Response(ICON,{{headers:h}})}}
 if(p==='/apple-touch-icon.png'||p==='/apple-touch-icon-precomposed.png'){{h.set('Content-Type','image/png');return new Response(png(),{{headers:h}})}}
 if(p==='/manifest.webmanifest'){{h.set('Content-Type','application/manifest+json');return new Response(MANIFEST,{{headers:h}})}}
 if(p==='/health'){{h.set('Content-Type','application/json');return new Response(HEALTH,{{headers:h}})}}
 h.set('Content-Type','text/plain');return new Response('Not found',{{status:404,headers:h}})}}}};
"""
(dist / 'worker.js').write_text(worker, encoding='utf-8')
(dist / 'wrangler.toml').write_text('name = "one-calm-v8"\nmain = "worker.js"\ncompatibility_date = "2026-10-01"\nworkers_dev = true\n', encoding='utf-8')
print('built', len(html), 'bytes html;', len(worker), 'bytes worker')

# claude.ai artifact variant (host supplies doctype/head/body)
body = html.split('<body>',1)[1].rsplit('</body>',1)[0]
art = f"<title>one. V8</title>\n<style>{css}</style>\n{body}"
(dist / 'artifact.html').write_text(art, encoding='utf-8')
print('artifact', len(art))
