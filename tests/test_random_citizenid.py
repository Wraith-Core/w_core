"""Owner 2026-11-06: a new character gets a random 4-digit id, never a special one (they are sold)."""
from pathlib import Path
import unittest
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def section(s, a, b):
    return s[s.index(a):s.index(b, s.index(a))]


class RandomCitizenId(unittest.TestCase):
    def setUp(self):
        self.l = LuaRuntime(unpack_returned_tuples=True)
        self.g = self.l.globals()
        src = (ROOT / 'server/citizen.lua').read_text(encoding='utf-8-sig')
        block = section(src, 'function C.IsSpecialNumber(', 'function C.Resolve(')
        self.l.execute(
            'WCore={Citizen={}};TAKEN={};BUSY={};'
            'function Wait()end;'
            'local C=WCore.Citizen;local busy=BUSY;'
            'function C.SaveBlocked()return false end;'
            "local function idOf(n)return ('%d'):format(math.floor(tonumber(n) or 0))end;"
            'local function used(id)return TAKEN[id]==true end;'
            + block)
        self.C = self.g.WCore.Citizen

    def special(self, s):
        return bool(self.C.IsSpecialNumber(s))

    def test_special_numbers(self):
        for s in ['1111', '7777', '1234', '9876', '3456', '1221', '1001', '3443', '1122', '1212',
                  '1000', '2000', '4500', '7700', '1112', '7779', '1777', '5550', '1711', '12321']:
            self.assertTrue(self.special(s), s)

    def test_plain_numbers(self):
        for s in ['4827', '1593', '6081', '2749', '9315', '1024', '3871']:
            self.assertFalse(self.special(s), s)

    def test_next_is_random_four_digits_and_never_special(self):
        seen = set()
        for _ in range(300):
            cid = self.C.Next()
            self.assertRegex(cid, r'^[1-9]\d{3}$')
            self.assertFalse(self.special(cid), cid)
            seen.add(cid)
        self.assertGreater(len(seen), 250)  # random, not one number again and again

    def test_next_skips_taken_numbers(self):
        taken = {str(n) for n in range(1000, 10000) if n % 3 != 0}
        for s in taken:
            self.g.TAKEN[s] = True
        for _ in range(200):
            cid = self.C.Next()
            self.assertNotIn(cid, taken)
            self.assertEqual(int(cid) % 3, 0)

    def test_moves_to_five_digits_when_four_are_full(self):
        for n in range(1000, 10000):
            self.g.TAKEN[str(n)] = True
        cid = self.C.Next()
        self.assertRegex(cid, r'^[1-9]\d{4}$')
        self.assertFalse(self.special(cid))

    def test_how_many_plain_four_digit_numbers(self):
        plain = [n for n in range(1000, 10000) if not self.special(str(n))]
        self.assertGreater(len(plain), 6000)


if __name__ == '__main__':
    unittest.main()
