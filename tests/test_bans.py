"""w_core server/bans.lua (2026-10-22): the server's one ban store, on the real Lua against a real MariaDB.

Needs the local XAMPP MariaDB on 127.0.0.1:3306 (root, no password); the database w_core_bans_test is made again
for every test. Run from the resource folder:  py -3 -I -m unittest discover -s tests -p "test_bans.py"
"""
import os
import time
import unittest

import lupa
import pymysql

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = 'w_core_bans_test'


def connect(db=None):
    return pymysql.connect(host='127.0.0.1', port=3306, user='root', password='', database=db,
                           charset='utf8mb4', autocommit=True, cursorclass=pymysql.cursors.DictCursor)


class Store(unittest.TestCase):
    def setUp(self):
        c = connect()
        with c.cursor() as cur:
            cur.execute(f'DROP DATABASE IF EXISTS {DB}')
            cur.execute(f'CREATE DATABASE {DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci')
        c.close()
        self.db = connect(DB)
        self.dropped = []
        self.online = {}  # src -> identifiers
        L = self.L = lupa.LuaRuntime(unpack_returned_tuples=True)

        def params(p):
            return [p[i] for i in range(1, len(p) + 1)] if p is not None else []

        def run(sql, p):
            with self.db.cursor() as cur:
                cur.execute(sql.replace('?', '%s'), params(p))
                return cur

        def query(sql, p=None):
            with self.db.cursor() as cur:
                cur.execute(sql.replace('?', '%s'), params(p))
                rows = cur.fetchall() or []
            return L.table_from([L.table_from(r) for r in rows])

        def insert(sql, p=None):
            return run(sql, p).lastrowid

        def update(sql, p=None):
            return run(sql, p).rowcount

        def scalar(sql, p=None):
            with self.db.cursor() as cur:
                cur.execute(sql.replace('?', '%s'), params(p))
                row = cur.fetchone()
            return list(row.values())[0] if row else None

        g = L.globals()
        g.py_query, g.py_insert, g.py_update, g.py_scalar = query, insert, update, scalar
        g.py_drop = lambda src, msg: self.dropped.append((src, msg))
        g.py_ids = lambda src: L.table_from(self.online.get(src, []))
        g.py_players = lambda: L.table_from([str(s) for s in self.online])
        L.execute(r'''
            MySQL = {
              query = { await = function(s, p) return py_query(s, p) end },
              insert = { await = function(s, p) return py_insert(s, p) end },
              update = setmetatable({ await = function(s, p) return py_update(s, p) end },
                                    { __call = function(_, s, p) return py_update(s, p) end }),
              scalar = { await = function(s, p) return py_scalar(s, p) end },
            }
            function CreateThread(fn) fn() end
            function TriggerEvent() end
            function DropPlayer(src, msg) py_drop(src, msg) end
            function GetPlayerIdentifiers(src) return py_ids(src) end
            function GetPlayers() return py_players() end
            Lang = { t = function(_, key, v) return key .. ':' .. tostring(v and v.reason) end }
        ''')
        with open(os.path.join(ROOT, 'server', 'bans.lua'), encoding='utf-8') as fh:
            L.execute(fh.read())

    def tearDown(self):
        self.db.close()

    def ev(self, code):
        return self.L.eval(code)

    def add(self, fields):
        out = self.ev('WBans.add({ %s })' % fields)
        return out[0] if isinstance(out, tuple) else out

    def test_a_license_ban_keeps_the_license_out(self):
        bid = self.add("license = 'license:aaa', reason = 'cheat', minutes = 0, bannedBy = 'Admin'")
        self.assertIsNotNone(bid)
        self.assertEqual(self.ev("WBans.check({ license = 'license:aaa' }).reason"), 'cheat')
        self.assertIsNone(self.ev("WBans.check({ license = 'license:bbb' })"))

    def test_a_bare_discord_id_matches_its_prefixed_ban(self):
        self.add("discord = '123456', reason = 'toxic'")
        self.assertEqual(self.ev("WBans.check({ discord = 'discord:123456' }).reason"), 'toxic')
        self.assertEqual(self.ev("WBans.check({ discord = '123456', license = 'license:zzz' }).reason"), 'toxic')

    def test_an_expired_ban_is_closed_and_kept(self):
        bid = self.add("license = 'license:aaa', reason = 'short', minutes = 5")
        with self.db.cursor() as cur:
            cur.execute('UPDATE bans SET expire = %s WHERE id = %s', (int(time.time()) - 10, bid))
        self.assertIsNone(self.ev("WBans.check({ license = 'license:aaa' })"))
        with self.db.cursor() as cur:
            cur.execute('SELECT active FROM bans WHERE id = %s', (bid,))
            self.assertEqual(cur.fetchone()['active'], 0)

    def test_lifting_keeps_the_history(self):
        bid = self.add("license = 'license:aaa', reason = 'x'")
        self.assertTrue(self.ev(f"WBans.lift({bid}, 'Boss')"))
        self.assertIsNone(self.ev("WBans.check({ license = 'license:aaa' })"))
        self.assertEqual(self.ev(f"select(2, WBans.lift({bid}, 'Boss'))"), 'not_found')
        hist = self.ev("WBans.history({ license = 'license:aaa' })")
        self.assertEqual(len(hist), 1)
        self.assertEqual(hist[1]['unbanned_by'], 'Boss')
        self.assertEqual(self.ev('WBans.count()'), 0)

    def test_edit_changes_reason_and_length(self):
        bid = self.add("license = 'license:aaa', reason = 'old', minutes = 60")
        self.assertTrue(self.ev(f"WBans.edit({bid}, 'new', 0)"))
        row = self.ev("WBans.check({ license = 'license:aaa' })")
        self.assertEqual(row['reason'], 'new')
        self.assertEqual(row['expire'], 2147483647)

    def test_the_list_holds_only_bans_in_force(self):
        self.add("license = 'license:a1', reason = 'a'")
        b2 = self.add("license = 'license:a2', reason = 'b'")
        self.ev(f"WBans.lift({b2}, 'x')")
        rows = self.ev('WBans.list()')
        self.assertEqual([rows[i]['license'] for i in range(1, len(rows) + 1)], ['license:a1'])
        self.assertEqual(self.ev('WBans.count()'), 1)

    def test_a_connected_player_is_dropped(self):
        self.online[7] = ['license:aaa', 'discord:999', 'steam:110000100000001']
        self.online[8] = ['license:other']
        self.add("discord = '999', reason = 'raid'")
        self.assertEqual([d[0] for d in self.dropped], [7])

    def test_no_identifier_no_ban(self):
        self.assertEqual(self.ev("select(2, WBans.add({ reason = 'x' }))"), 'no_identifier')


if __name__ == '__main__':
    unittest.main()
