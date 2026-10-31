"""Run actual command/event files in Lua 5.4; no database, network or live server."""
from pathlib import Path
import unittest
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

SERVER = r'''
COMMANDS={}; EVENTS={}; GRANTS={}; TRACE={}; GUARD='started'; ACCEPT=true; ACL={tp=true,tpm=true}
WCore={Functions={},Config={Server={Permissions={'admin'}}}}
WConfig={Server={Permissions={'admin'}}}; WShared={Locations={home={x=5,y=6,z=7,w=8}}}
Lang={t=function(_,key) return key end}
exports={w_lib={addAce=function()end},w_guard={
 AllowMove=function(_,src,seconds) GRANTS[#GRANTS+1]={kind='move',source=src,seconds=seconds}; TRACE[#TRACE+1]='move';return ACCEPT end,
 AllowFlag=function(_,src,flag,seconds) GRANTS[#GRANTS+1]={kind=flag,source=src,seconds=seconds};TRACE[#TRACE+1]=flag;return ACCEPT end}}
function GetResourceState()return GUARD end
function GetPlayerName(src)return src==7 and 'Admin' or src==8 and 'Target' or nil end
function GetPlayerPed(src)return src==8 and 88 or 0 end
function GetEntityCoords()return {x=11,y=12,z=13}end
function RegisterCommand(name,fn,restricted) COMMANDS[name]={fn=fn,restricted=restricted} end
function CreateThread()end
function TriggerClientEvent(name,src,...) EVENTS[#EVENTS+1]={name=name,source=src};TRACE[#TRACE+1]='event' end
function IsPlayerAceAllowed(src,node)return ACL[node:match('^command%.(.+)$')]==true end
function RUN(name,src,args)
 local command=COMMANDS[name]
 if command.restricted and not IsPlayerAceAllowed(src,'command.'..name) then return false end
 command.fn(src,args or {},name);return true
end
w={citizen={parse=function(value)return value=='#8' and 'server' or 'location' end,
 requireOnline=function(value)return value=='#8' and {source=8,online=true} or nil,'not_found' end,
 resolve=function()end,reasonText=function()return 'not_found'end,label=function()return 'Target'end}}
function print()end
'''

CLIENT = r'''
EVENTS={}; HANDLERS={}; MOVES={}; NOTICES={}; NOW=0; STEP=100; FADE_BLOCK=false; LOAD=false; GROUND=true
FROZEN=false; ORIGINAL_FROZEN=false; FADE_INS=0; PROBES=0; CACHED_PED=1; VEHICLE=0; WAYPOINT=true
cache={ped=1}; WCore={Functions={Notify=function(key,kind)NOTICES[#NOTICES+1]={key=key,kind=kind}end}}
Lang={t=function(_,key)return key end}
function RegisterNetEvent(name,fn)EVENTS[name]=fn end
function AddEventHandler(name,fn)HANDLERS[name]=fn end
function GetCurrentResourceName()return 'w_core'end
function GetGameTimer()return NOW end
function GetEntityCoords()return {x=10,y=20,z=30}end
function DoesEntityExist(entity)return entity==1 or entity==2 or entity==3 end
function GetVehiclePedIsIn()return VEHICLE end
function IsEntityPositionFrozen()return ORIGINAL_FROZEN end
function FreezeEntityPosition(_,flag)FROZEN=flag end
function GetWaypointCoords()return {x=100,y=200}end
function IsWaypointActive()return WAYPOINT end
function DoScreenFadeOut()end
function IsScreenFadedOut()return not FADE_BLOCK end
function DoScreenFadeIn()FADE_INS=FADE_INS+1 end
function RequestCollisionAtCoord()end
function SetEntityCoords(ped,x,y,z)MOVES[#MOVES+1]={ped=ped,x=x,y=y,z=z,at=NOW}end
function GetGroundZAndNormalFor_3dCoord()
 if GROUND_ERROR then error('native lookup failed')end
 if LATE_GROUND then NOW=45000 end
 return GROUND,GROUND_NAN and 0/0 or 42
end
Citizen={InvokeNative=function(hash)
 if hash==0x387AD749E3B69B70 then PROBES=PROBES+1 end
 if hash==0xCF45DF50C7775F2A then return LOAD end
end}
function Wait()
 NOW=NOW+STEP
 if CANCEL and NOW>=CANCEL then CANCEL=nil;HANDLERS.onResourceStop('w_core')end
 if SWAP_PED then cache.ped=2;SWAP_PED=false end
 if WRAP then NOW=-1;WRAP=false end
end
function RUN()EVENTS['WCore:Command:GoToMarker']()end
'''


class TrustedTeleportCommands(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(SERVER)
        source = (ROOT / 'server/commands.lua').read_text(encoding='utf-8')
        # Existing Cfx compound assignment, unchanged by this patch; portable Lua uses its equivalent.
        self.assertEqual(source.count('extraPerms.n += 1'), 1)
        self.lua.execute(source.replace('extraPerms.n += 1', 'extraPerms.n = extraPerms.n + 1'))

    def test_all_three_direct_destinations_get_only_short_move_before_event(self):
        for expression in ["{'#8'}", "{'home'}", "{'1','2','3'}"]:
            with self.subTest(destination=expression):
                self.lua.execute(f"GRANTS={{}};TRACE={{}};EVENTS={{}};RUN('tp',7,{expression})")
                self.assertEqual(self.lua.eval('#GRANTS'), 1)
                self.assertEqual(self.lua.eval('GRANTS[1].kind'), 'move')
                self.assertEqual(self.lua.eval('GRANTS[1].seconds'), 10)
                self.assertEqual(self.lua.eval('TRACE[1]'), 'move')
                self.assertEqual(self.lua.eval('TRACE[2]'), 'event')

    def test_waypoint_gets_bounded_move_and_fly_only(self):
        self.lua.execute("RUN('tpm',7,{})")
        self.assertEqual(self.lua.eval('#GRANTS'), 2)
        self.assertEqual(self.lua.eval('GRANTS[1].kind'), 'move')
        self.assertEqual(self.lua.eval('GRANTS[2].kind'), 'fly')
        self.assertEqual(self.lua.eval('GRANTS[1].seconds'), 50)
        self.assertEqual(self.lua.eval('GRANTS[2].seconds'), 50)
        self.assertEqual(self.lua.eval('TRACE[3]'), 'event')

    def test_denied_or_revoked_command_never_creates_a_guard_permit(self):
        self.lua.execute("ACL.tp=false;ACL.tpm=false;RUN('tp',7,{'home'});RUN('tpm',7,{})")
        self.assertEqual(self.lua.eval('#GRANTS'), 0)
        self.assertEqual(self.lua.eval('#EVENTS'), 0)
        self.assertTrue(self.lua.eval('COMMANDS.tp.restricted'))
        self.assertTrue(self.lua.eval('COMMANDS.tpm.restricted'))

    def test_invalid_destination_never_creates_a_guard_permit(self):
        self.lua.execute("RUN('tp',7,{'missing'});RUN('tp',7,{'0','2','3'})")
        self.assertEqual(self.lua.eval('#GRANTS'), 0)

    def test_missing_guard_keeps_the_existing_authorized_command_usable(self):
        self.lua.execute("GUARD='stopped';RUN('tp',7,{'home'})")
        self.assertEqual(self.lua.eval('#GRANTS'), 0)
        self.assertEqual(self.lua.eval('EVENTS[1].name'), 'WCore:Command:TeleportToCoords')

    def test_guard_refusal_prevents_the_movement_instead_of_issuing_a_false_safe_action(self):
        self.lua.execute("ACCEPT=false;RUN('tp',7,{'home'})")
        self.assertEqual(self.lua.eval('EVENTS[1].name'), 'WCore:Notify')


class BoundedWaypointClient(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(CLIENT)
        self.lua.execute((ROOT / 'client/events.lua').read_text(encoding='utf-8'))

    def run_client(self, setup=''):
        self.lua.execute(setup + ';RUN()')

    def assert_restored(self, expect_position=True):
        self.assertFalse(self.lua.eval('FROZEN'))
        self.assertEqual(self.lua.eval('FADE_INS'), 1)
        self.assertEqual(self.lua.eval('NOTICES[#NOTICES].kind'), 'error')
        if expect_position:
            self.assertEqual(self.lua.eval('MOVES[#MOVES].x'), 10)
            self.assertEqual(self.lua.eval('MOVES[#MOVES].y'), 20)
            self.assertEqual(self.lua.eval('MOVES[#MOVES].z'), 30)

    def test_normal_ground_finishes_once_without_duplicate_final_coordinate_write(self):
        self.run_client()
        self.assertEqual(self.lua.eval('#MOVES'), 2)
        self.assertEqual(self.lua.eval('MOVES[2].z'), 42)
        self.assertEqual(self.lua.eval('NOTICES[1].kind'), 'success')
        self.assertFalse(self.lua.eval('FROZEN'))

    def test_stuck_fade_aborts_in_three_seconds_without_moving(self):
        self.run_client('FADE_BLOCK=true')
        self.assertEqual(self.lua.eval('NOW'), 3000)
        self.assertEqual(self.lua.eval('#MOVES'), 0)
        self.assert_restored(False)

    def test_overall_deadline_restores_once_and_never_continues_toward_destination(self):
        self.run_client('GROUND=false;LOAD=true;STEP=1500')
        self.assertEqual(self.lua.eval('NOW'), 45000)
        self.assert_restored()
        self.assertTrue(self.lua.eval('(function() for i=1,#MOVES-1 do if MOVES[i].at>=45000 then return false end end return true end)()'))

    def test_no_ground_restores_original_position_and_reports_only_failure(self):
        self.run_client('GROUND=false')
        self.assert_restored()
        self.assertEqual(self.lua.eval('#NOTICES'), 1)

    def test_numeric_native_false_is_not_a_ground_hit(self):
        self.run_client('GROUND=0')
        self.assert_restored()

    def test_invalid_native_ground_height_never_reaches_entity_coordinates(self):
        self.run_client('GROUND_NAN=true')
        self.assert_restored()
        self.assertTrue(self.lua.eval('(function() for _,m in ipairs(MOVES)do if m.z~=m.z then return false end end return true end)()'))

    def test_ground_result_after_deadline_cannot_issue_a_final_destination_write(self):
        self.run_client('LATE_GROUND=true')
        self.assert_restored()
        self.assertTrue(self.lua.eval('(function() for _,m in ipairs(MOVES)do if m.z==42 then return false end end return true end)()'))

    def test_native_lookup_failure_restores_screen_position_and_freeze_state(self):
        self.run_client('GROUND_ERROR=true')
        self.assert_restored()

    def test_source_ped_change_never_moves_the_new_ped_or_restores_a_stale_destination(self):
        self.run_client('SWAP_PED=true')
        self.assertEqual(self.lua.eval('#MOVES'), 1)
        self.assertEqual(self.lua.eval('MOVES[1].ped'), 1)
        self.assert_restored(False)

    def test_clock_wrap_aborts_instead_of_extending_the_workflow(self):
        self.run_client('WRAP=true')
        self.assert_restored()

    def test_preexisting_freeze_is_preserved(self):
        self.run_client('ORIGINAL_FROZEN=true')
        self.assertTrue(self.lua.eval('FROZEN'))

    def test_resource_stop_cancels_before_late_movement_and_restores_screen(self):
        self.run_client('CANCEL=100')
        self.assertFalse(self.lua.eval('FROZEN'))
        self.assertEqual(self.lua.eval('FADE_INS'), 1)
        self.assertEqual(self.lua.eval('#MOVES'), 2)
        self.assertEqual(self.lua.eval('MOVES[2].x'), 10)
        self.assertEqual(self.lua.eval('#NOTICES'), 0)


if __name__ == '__main__':
    unittest.main()
