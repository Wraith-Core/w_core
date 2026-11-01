"""Run server/player.lua's actual Save in Lua 5.4: a character created this session gets its
players.id after its first save lands; no database, network or live server."""
from pathlib import Path
import unittest
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

STUBS = r'''
WCore={Players={},Player={},Functions={},Config={Debug=false}}
INSERTS={}; LOOKUPS={}; UPDATES=0
json={encode=function()return '{}' end}
function GetPlayerPed()return 1 end
function GetEntityCoords()return {x=0,y=0,z=0} end
function GetGameTimer()return 0 end
function GetResourceState()return 'missing' end
MySQL={insert=function(sql,params,cb) INSERTS[#INSERTS+1]=cb end,
 scalar=function(sql,params,cb) LOOKUPS[#LOOKUPS+1]={sql=sql,cid=params[1],cb=cb} end}
function PLAYER(citizenid,id)
 local self={PlayerData={citizenid=citizenid,id=id},Functions={}}
 function self.Functions.SetPlayerData(key,val) self.PlayerData[key]=val; UPDATES=UPDATES+1 end
 return self
end
'''


def section(src, start, end):
    i = src.index(start)
    return src[i:src.index(end, i)]


class NewCharacterRowId(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.g = self.lua.globals()
        self.lua.execute(STUBS)
        src = (ROOT / 'server/player.lua').read_text(encoding='utf-8-sig')
        self.lua.execute(section(src, 'local savesInFlight = {}', 'function WCore.Player.SaveOffline('))

    def put(self, src, citizenid, row_id=None):
        p = self.g.PLAYER(citizenid, row_id)
        self.g.WCore.Players[src] = p
        return p

    def land_insert(self, n=1):
        self.g.INSERTS[n]()

    def test_new_character_gets_its_row_id_through_the_setter(self):
        p = self.put(1, '1001')
        self.g.WCore.Player.Save(1)
        self.land_insert()
        self.assertEqual(len(self.g.LOOKUPS), 1)
        look = self.g.LOOKUPS[1]
        self.assertEqual(look.cid, '1001')
        self.assertIn('WHERE citizenid = ?', look.sql)
        look.cb(42)
        self.assertEqual(p.PlayerData.id, 42)
        self.assertEqual(self.g.UPDATES, 1)
        # once it has the id, later saves read nothing
        self.g.WCore.Player.Save(1)
        self.land_insert(2)
        self.assertEqual(len(self.g.LOOKUPS), 1)

    def test_loaded_character_reads_nothing(self):
        p = self.put(1, '1002', 7)
        self.g.WCore.Player.Save(1)
        self.land_insert()
        self.assertEqual(len(self.g.LOOKUPS), 0)
        self.assertEqual(p.PlayerData.id, 7)

    def test_logged_out_before_the_lookup_returns(self):
        p = self.put(1, '1003')
        self.g.WCore.Player.Save(1)
        self.land_insert()
        self.g.WCore.Players[1] = None
        self.g.LOOKUPS[1].cb(43)
        self.assertIsNone(p.PlayerData.id)
        self.assertEqual(self.g.UPDATES, 0)

    def test_another_character_on_the_same_source_is_not_given_the_id(self):
        old = self.put(1, '1004')
        self.g.WCore.Player.Save(1)
        self.land_insert()
        new = self.put(1, '1005')
        self.g.LOOKUPS[1].cb(44)
        self.assertIsNone(old.PlayerData.id)
        self.assertIsNone(new.PlayerData.id)
        self.assertEqual(self.g.UPDATES, 0)

    def test_number_changed_meanwhile_is_not_given_the_id(self):
        p = self.put(1, '1006')
        self.g.WCore.Player.Save(1)
        self.land_insert()
        p.PlayerData.citizenid = '2006'
        self.g.LOOKUPS[1].cb(45)
        self.assertIsNone(p.PlayerData.id)

    def test_no_row_found_tries_again_on_the_next_save(self):
        p = self.put(1, '1007')
        self.g.WCore.Player.Save(1)
        self.land_insert()
        self.g.LOOKUPS[1].cb(None)
        self.assertIsNone(p.PlayerData.id)
        self.g.WCore.Player.Save(1)
        self.land_insert(2)
        self.assertEqual(len(self.g.LOOKUPS), 2)
        self.g.LOOKUPS[2].cb(46)
        self.assertEqual(p.PlayerData.id, 46)


if __name__ == '__main__':
    unittest.main()
