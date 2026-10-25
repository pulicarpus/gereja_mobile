from contextlib import closing
from pathlib import Path
import sqlite3
import unittest

ROOT = Path(__file__).resolve().parents[2]


class BibleTranslationsTest(unittest.TestCase):
    def test_both_versions_have_same_book_ids_and_chapters_but_distinct_text(self):
        catalogs = []
        openings = []
        for filename in ('TB.SQLite3', 'TJL.SQLite3'):
            with self.subTest(version=filename), closing(sqlite3.connect(str(ROOT / 'assets' / filename))) as db:
                self.assertEqual(db.execute('PRAGMA quick_check').fetchone()[0], 'ok')
                books = db.execute('SELECT book_number, long_name, short_name FROM books ORDER BY book_number').fetchall()
                self.assertEqual(len(books), 66)
                chapters = db.execute('SELECT DISTINCT book_number, chapter FROM verses ORDER BY book_number, chapter').fetchall()
                self.assertEqual(len(chapters), 1189)
                self.assertGreater(db.execute('SELECT COUNT(*) FROM verses').fetchone()[0], 31000)
                catalogs.append(([book[0] for book in books], chapters))
                openings.append(db.execute('SELECT text FROM verses WHERE book_number=10 AND chapter=1 AND verse=1').fetchone()[0])
                columns = {row[1] for row in db.execute('PRAGMA table_info(stories)')}
                order = 'verse, order_if_several' if 'order_if_several' in columns else 'verse'
                db.execute(f'SELECT * FROM stories WHERE book_number=? AND chapter=? ORDER BY {order}', (10, 1)).fetchall()
        self.assertEqual(catalogs[0], catalogs[1])
        self.assertNotEqual(openings[0], openings[1])
        self.assertIn('mula pertama', openings[1])


if __name__ == '__main__':
    unittest.main()
