"""Convert an extracted SABDA APK dictionary to an external development database."""
import argparse
from collections import Counter
from contextlib import closing
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sqlite3
from import_dictionary import build_dictionary

class DefinitionParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts, self.links, self.headings = [], [], []
        self.anchor = None
        self.heading = None
        self.hidden = 0
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in ('script', 'style'):
            self.hidden += 1
        if tag in ('p', 'div', 'br', 'li', 'h1', 'h2', 'h3', 'tr'):
            self.parts.append('\n')
        if tag in ('td', 'th'):
            self.parts.append(' | ')
        if tag == 'a' and attrs.get('href', '').startswith('lid:'):
            self.anchor = []
        if tag == 'h2':
            self.heading = []
    def handle_endtag(self, tag):
        if tag in ('script', 'style'):
            self.hidden = max(0, self.hidden - 1)
        if tag == 'a' and self.anchor is not None:
            self.links.append(''.join(self.anchor).strip())
            self.anchor = None
        if tag == 'h2' and self.heading is not None:
            self.headings.append(''.join(self.heading).strip())
            self.heading = None
        if tag in ('p', 'div', 'li', 'h1', 'h2', 'h3', 'tr'):
            self.parts.append('\n')
    def handle_data(self, data):
        if self.hidden:
            return
        self.parts.append(data)
        if self.anchor is not None:
            self.anchor.append(data)
        if self.heading is not None:
            self.heading.append(data)
    def text(self):
        lines = [re.sub(r'\s+', ' ', line).strip() for line in ''.join(self.parts).splitlines()]
        return '\n\n'.join(line for line in lines if line and line != 'Ke atas')

def verse_references(labels, books):
    refs, rejected = [], []
    for label in labels:
        book = None
        for part in label.replace('\u2013', '-').split(';'):
            part = part.strip().rstrip('.')
            match = re.fullmatch(r'(.+?)\s+(\d+):([\d, -]+)', part)
            if match:
                name, chapter, verses = match.groups()
                book = books.get(re.sub(r'\s+', '', name).lower().rstrip('.'))
            else:
                match = re.fullmatch(r'(\d+):([\d, -]+)', part)
                if not match or not book:
                    if part: rejected.append(part)
                    continue
                chapter, verses = match.groups()
            if not book:
                rejected.append(part)
                continue
            ref = f'{book} {chapter}:{verses.replace(" ", "")}'
            if ref not in refs: refs.append(ref)
    return refs, rejected

def convert(root, output, bible):
    root, output = Path(root), Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    books, book_ids, valid_verses = {}, {}, {}
    with closing(sqlite3.connect(f'file:{Path(bible).resolve().as_posix()}?mode=ro', uri=True)) as db:
        for book_id, short, name in db.execute('SELECT book_number,short_name,long_name FROM books'):
            book_ids[name] = book_id
            for alias in (short, name): books[re.sub(r'\s+', '', alias).lower()] = name
        for book_id, chapter, verse in db.execute('SELECT book_number,chapter,verse FROM verses'):
            valid_verses.setdefault((book_id, chapter), set()).add(verse)
    for alias, name in {'mazm':'Mazmur', '1tim':'1 Timotius', '2tim':'2 Timotius', '1pet':'1 Petrus', '2pet':'2 Petrus', 'kid':'Kidung Agung'}.items():
        if name in books.values(): books[alias] = name
    files, entries, excluded, unresolved = {}, [], [], Counter()
    invalid_verses = Counter()
    for number, line in enumerate((root / 'index.txt').read_text(encoding='utf-8').splitlines(), 1):
        file, offset, length, term = line.split('@', 3)
        filename = f'arti_{int(file):03}.txt'
        if filename not in files: files[filename] = (root / filename).read_bytes()
        offset, length = int(offset), int(length)
        raw = files[filename][offset:offset + length]
        if offset < 0 or length <= 0 or len(raw) != length:
            excluded.append({'line': number, 'term': term, 'reason': 'Offset or length outside definition file'})
            continue
        try:
            html = raw.decode('utf-8')
        except UnicodeDecodeError:
            excluded.append({'line': number, 'term': term, 'reason': 'Invalid UTF-8'})
            continue
        parser = DefinitionParser()
        parser.feed(html)
        text = parser.text()
        if not text:
            excluded.append({'line': number, 'term': term, 'reason': 'Empty definition'})
            continue
        refs, rejected = verse_references(parser.links, books)
        unresolved.update(rejected)
        valid_refs = []
        for ref in refs:
            match = re.fullmatch(r'(.+?) (\d+):([\d,-]+)', ref)
            if not match:
                invalid_verses[ref] += 1
                continue
            name, chapter, verse_text = match.groups()
            requested = set()
            for part in verse_text.split(','):
                bounds = part.split('-')
                if len(bounds) > 2 or not all(bounds):
                    requested.add(-1)
                    break
                start, end = int(bounds[0]), int(bounds[-1])
                if start < 1 or end < start or end > 200:
                    requested.add(-1)
                    break
                requested.update(range(start, end + 1))
            if requested and requested <= valid_verses.get((book_ids[name], int(chapter)), set()):
                valid_refs.append(ref)
            else:
                invalid_verses[ref] += 1
        refs = valid_refs
        sources = list(dict.fromkeys(label for heading in parser.headings for label in re.findall(r'\[([^]]+)\]', heading)))
        source = 'SABDA — Kamus Alkitab 2.0.1 (org.sabda.kamus); salinan APK untuk uji pengembangan'
        if sources: source += '; sumber bagian: ' + ', '.join(sources)
        entries.append({'term': term, 'definition': text, 'source': source, 'references': refs, 'headings': parser.headings})
    intermediate = output.with_suffix('.development.json')
    intermediate.write_text(json.dumps(entries, ensure_ascii=False), encoding='utf-8')
    try:
        count = build_dictionary(intermediate, output)
    finally:
        intermediate.unlink(missing_ok=True)
    report = {'entries': count, 'excluded': excluded, 'references': sum(len(e['references']) for e in entries), 'unresolved_reference_labels': dict(unresolved.most_common()), 'invalid_verse_references': dict(invalid_verses.most_common()), 'format': 'Plain text preserving section headings; internal term/Strong links remain text'}
    output.with_suffix('.report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    return report

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dictdata')
    parser.add_argument('output')
    parser.add_argument('--bible', required=True)
    args = parser.parse_args()
    report = convert(args.dictdata, args.output, args.bible)
    print(json.dumps({k: v for k, v in report.items() if k not in ('unresolved_reference_labels', 'invalid_verse_references')}, ensure_ascii=False, indent=2))
