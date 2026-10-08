from contextlib import closing
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('dictionary_import', Path(__file__).parents[2] / 'tool/import_dictionary.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class DictionaryImportTest(unittest.TestCase):
    def test_roundtrip_and_failed_import_preserves_previous_database(self):
        with tempfile.TemporaryDirectory() as folder:
            source, output = Path(folder) / 'input.json', Path(folder) / 'output.sqlite'
            entries = [{'term': 'Kasih', 'definition': 'Peduli kepada sesama.', 'source': 'Contoh', 'references': ['Matius 22:39']}]
            source.write_text(json.dumps(entries), encoding='utf-8')
            self.assertEqual(module.build_dictionary(source, output), 1)
            with closing(sqlite3.connect(output)) as db:
                row = db.execute('SELECT term,source,refs FROM entries').fetchone()
                self.assertEqual(row, ('Kasih', 'Contoh', '["Matius 22:39"]'))
            original = output.read_bytes()
            source.write_text('[{"term":"Tanpa sumber"}]', encoding='utf-8')
            with self.assertRaises(ValueError):
                module.build_dictionary(source, output)
            self.assertEqual(output.read_bytes(), original)
