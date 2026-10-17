import pathlib, re, sys
here = pathlib.Path(__file__).parent
out = pathlib.Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
css = (here / 'common.css').read_text()
js = (here / 'dataset.js').read_text() + (here / 'common.js').read_text()
for page in sorted(here.glob('*.page.html')):
    body = page.read_text()
    title = re.search(r'<!--TITLE:(.*?)-->', body).group(1)
    body = re.sub(r'<!--TITLE:.*?-->\n', '', body)
    body = body.replace('<!--DOCK-->', '<script>document.write(dock())</script>')
    body = body.replace('<!--SHEET-->', '<script>document.getElementById("phone").insertAdjacentHTML("beforeend", sheetHTML())</script>')
    html = f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>{title}</title>
<!-- Design prototype for the Today app. Fictional data from tests/fixtures/today-dataset.json, fixed clock, no network. Generated; edit the sources in docs/research/prototypes/src/. -->
<style>{css}</style>
<script>{js}</script></head>
<body>
{body}
</body></html>
'''
    (out / page.name.replace('.page.html', '.html')).write_text(html)
    print('wrote', page.name)
