"""Compact checks of the affected rendered pages; no statistical recalculation."""
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit, unquote
import json
import re

EXERCISE = Path(__file__).resolve().parents[1]
ROOT = EXERCISE.parents[1]
SITE = ROOT / '_site'
PREFIX = Path('Take-home_Ex/Take-home_Ex02')
PAGES = [SITE / PREFIX / name for name in (
    'Take-home_Ex02.html', 'technical-report.html', 'executive-summary.html')]
PAGES += [SITE / 'index.html', SITE / 'take-home.html']

class Page(HTMLParser):
    def __init__(self):
        super().__init__()
        self.refs = []
        self.slides = 0
        self.images = 0
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        for key in ('src', 'href', 'data-src'):
            if a.get(key):
                self.refs.append(a[key])
        if tag == 'img':
            self.images += 1
        if tag == 'section' and ('slide' in a.get('class', '').split() or a.get('id') == 'title-slide'):
            self.slides += 1

results = []
for path in PAGES:
    assert path.is_file(), f'Missing rendered page: {path}'
    text = path.read_text(encoding='utf-8')
    page = Page()
    page.feed(text)
    broken = []
    for ref in page.refs:
        url = urlsplit(ref)
        if url.scheme or url.netloc or not url.path:
            continue
        target = (SITE / unquote(url.path.lstrip('/'))) if url.path.startswith('/') else path.parent / unquote(url.path)
        if not target.exists():
            broken.append(ref)
    assert not broken, f'{path.name}: missing local references {broken}'
    if path.name == 'executive-summary.html':
        assert page.slides == 9, f'Expected cover + 8 slides, found {page.slides}'
    assert not re.search(r'Preparation checkpoint|Analysis has not started|Statistical findings are not available', text, re.I), path
    results.append(dict(page=str(path.relative_to(SITE)), references=len(page.refs), images=page.images, slides=page.slides))

report = (EXERCISE / 'technical-report.qmd').read_text(encoding='utf-8')
word_counts = {}
for name, prose in re.findall(r'<!-- commentary:([^:]+):start -->(.*?)<!-- commentary:\1:end -->', report, re.S):
    count = len(re.findall(r"\b[\w]+(?:[’'–-][\w]+)*\b", prose))
    limit = 250 if name.startswith('category-') else 200
    assert count <= limit, f'{name}: {count} words exceeds {limit}'
    word_counts[name] = count
assert len(word_counts) >= 8, 'Expected descriptive, LMSA and EHSA commentary checks'

published_exercise = SITE / PREFIX
for path in published_exercise.rglob('*'):
    if path.is_file():
        relative = path.relative_to(published_exercise)
        assert not set(relative.parts) & {'data', '_workflow', 'R', 'tests'}, f'Private/workflow resource copied into site: {path}'
        assert path.suffix.lower() not in {'.rds', '.geojson', '.gpkg', '.shp'}, path

evidence = dict(status='PASS', pages=results, commentary_words=word_counts,
                body_slides=8, restricted_inputs_in_site=False)
(EXERCISE / '_workflow' / 'pages-validation.json').write_text(json.dumps(evidence, indent=2), encoding='utf-8')
print(json.dumps(evidence, indent=2))
