from contextlib import closing
import importlib.util
from pathlib import Path
import sqlite3
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[2] / 'tool'))
from import_sabda_development import convert

class DevelopmentImportTest(unittest.TestCase):
    def test_utf8_offsets_sources_reference_validation_and_skipped_record(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            html = '<h2>Istilah [sumber contoh]</h2><p>Kasih α dan שלום.</p><script>hidden</script><a href="lid:1">Mat 1:1; 1:2</a><a href="lid:3">Mat 1:99</a>'
            raw = html.encode('utf-8')
            (root / 'arti_000.txt').write_bytes(raw)
            (root / 'index.txt').write_text(f'0@0@{len(raw)}@Kasih\n0@{len(raw)+1}@10@Rusak\n', encoding='utf-8')
            bible = root / 'bible.sqlite'
            with closing(sqlite3.connect(bible)) as db:
                db.executescript("CREATE TABLE books(book_number,short_name,long_name); INSERT INTO books VALUES(470,'Mat','Matius'); CREATE TABLE verses(book_number,chapter,verse); INSERT INTO verses VALUES(470,1,1),(470,1,2);")
            output = root / 'dictionary.sqlite'
            report = convert(root, output, bible)
            self.assertEqual(report['entries'], 1)
            self.assertEqual(report['excluded'][0]['term'], 'Rusak')
            self.assertEqual(report['references'], 2)
            self.assertIn('Matius 1:99', report['invalid_verse_references'])
            with closing(sqlite3.connect(output)) as db:
                row = db.execute('SELECT definition,source,refs FROM entries').fetchone()
                self.assertIn('α dan שלום', row[0])
                self.assertNotIn('hidden', row[0])
                self.assertIn('sumber contoh', row[1])
                self.assertEqual(row[2], '["Matius 1:1", "Matius 1:2"]')
