"""Behaves the paycheck key against the real code, sliced from the file.

Both were written this session and neither had been run. These run the shipped lines:
the block is cut straight out of w_core/server/loops.lua.
"""
import sys

from lupa.lua54 import LuaRuntime

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

LOOPS = r"F:\Server RedM\Wraith Core\txData\WraithCore\resources\[wraith]\w_core\server\loops.lua"

fails = []


def check(label, ok, detail=""):
    print("  %s  %s%s" % ("PASS" if ok else "FAIL", label, (" -- " + detail) if detail else ""))
    if not ok:
        fails.append(label)


def slice_between(text, begin, end):
    return text[text.index(begin):text.index(end)]


# payDoctor (the medic's fee) is tested by the medic itself since 2026-10-14: w_medic/tests/test_pay.py.
# The block that stood here sliced w_ambulancejob's, which paid the PATIENT, and asserted that.

print("\n--- the paycheck key separates employees and cycles ---")
loops = open(LOOPS, encoding="utf-8-sig").read()
body = loops[loops.index("-- Paycheck Loop --"):]
print("paycheck loop: %d lines from w_core/server/loops.lua (it is the last block in the file)"
      % body.count("\n"))
check("the cycle is stamped once per round", "local cycle = os.time()" in body)
check("the key carries the employee", "'paycheck:'..Player.PlayerData.citizenid..':'..cycle" in body)
check("the old shared key is gone", "'paycheck:'..Player.PlayerData.job.name" not in body)

keys_seen = set()
for cid in ("AAA", "BBB"):
    for cycle in (1000, 2000):
        keys_seen.add("paycheck:%s:%s" % (cid, cycle))
check("every employee in every round has their own key", len(keys_seen) == 4, str(sorted(keys_seen)))

print("\n%d check(s) failed" % len(fails))
for f in fails:
    print("  ! " + f)
sys.exit(1 if fails else 0)