"""Build an offline dictionary from JSON definitions with explicit attribution."""
import argparse
import json
import os
from pathlib import Path
import sqlite3
import tempfile

def build_dictionary(source, output):
    entries = json.loads(Path(source).read_text(encoding='utf-8'))
    if not isinstance(entries, list) or not entries:
        raise ValueError('Expected a nonempty list of entries')
    rows = []
    for entry in entries:
        values = [entry.get(key) for key in ('term', 'definition', 'source')]
        if any(not isinstance(value, str) or not value.strip() for value in values):
            raise ValueError('Every entry requires term, definition and source')
        refs = entry.get('references', [])
        if not isinstance(refs, list) or any(not isinstance(ref, str) or not ref.strip() for ref in refs):
            raise ValueError('References must be a list of nonempty strings')
        term, definition, attribution = [value.strip() for value in values]
        rows.append((term, term.lower(), definition, attribution, json.dumps(refs, ensure_ascii=False)))
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=output.parent, suffix='.sqlite')
    os.close(fd)
    try:
        with sqlite3.connect(temporary) as db:
            db.execute('CREATE TABLE entries (id INTEGER PRIMARY KEY, term TEXT NOT NULL, search_term TEXT NOT NULL, definition TEXT NOT NULL, source TEXT NOT NULL, refs TEXT NOT NULL)')
            db.execute('CREATE INDEX entry_search ON entries(search_term)')
            db.executemany('INSERT INTO entries(term,search_term,definition,source,refs) VALUES (?,?,?,?,?)', rows)
            db.execute('PRAGMA user_version=1')
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    return len(rows)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source')
    parser.add_argument('output')
    args = parser.parse_args()
    print(f'Imported {build_dictionary(args.source, args.output)} entries')
