"""Execute the staged generation lease and actual mutation-entry wrappers in isolated Lua."""
from pathlib import Path
import unittest
from lupa.lua54 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
def section(s,a,b):return s[s.index(a):s.index(b,s.index(a))]
class GenerationLease(unittest.TestCase):
 def setUp(self):
  self.l=LuaRuntime(unpack_returned_tuples=True);self.g=self.l.globals();self.l.execute('''
WCore={Citizen={}};EXPORTS={};SQL_CALLS=0;MUTATIONS=0;ROW=1;CALLER='w_pets'
function exports(n,f)EXPORTS[n]=f end
function GetInvokingResource()return CALLER end
function print()end
MySQL={single={await=function(sql,p)SQL_CALLS=SQL_CALLS+1;if DB_WAIT then coroutine.yield('lookup')end;if DB_ERROR then error('offline')end;if ROW==nil then return nil end;return {id=ROW}end},scalar={await=function()return 0 end}}
local C=WCore.Citizen;local ready=true;local busy={}
function C.Normalize(v)if type(v)=='string'and v~=''then return v elseif type(v)=='number'and v>0 and v%1==0 then return tostring(v)end end
function C.IsNumeric(v)return v:match('^%d+$')~=nil end
function C.IsBusy(id)return busy[id]==true end
function C.RowPurged(id)return PURGED==id end
function C.RowMoved(id,cid)return MOVED==id end
function SET_BUSY(id,value)busy[id]=value end
local function clip(s)return s end
local function reassign()MUTATIONS=MUTATIONS+1;if MUTATION_WAIT then coroutine.yield('mutation')end;return true end
local function purge()MUTATIONS=MUTATIONS+1;return true end
local function transfer()MUTATIONS=MUTATIONS+1;return true end
local function oldIdsInOrder()SCANNED=true;return {'AAA00001'}end
local function used()return false end
local function idOf(n)return tostring(n)end
local function textColumns()return {}end
local function sweep()if PLAN_WAIT then coroutine.yield('plan')end;return {}end
local function ledgerNotReady()return false end
local function migrateRun()MUTATIONS=MUTATIONS+1;return 1 end
local function forgetSchema()end
function GetPlayers()return {}end
''')
  # The functions below use private busy/ready, so inject into the same lexical scope.
  pre='local C=WCore.Citizen;local ready=true;local busy={};function C.IsBusy(id)return busy[id]==true end;function SET_BUSY(id,value)busy[id]=value end;local function clip(s)return s end;local function reassign()MUTATIONS=MUTATIONS+1;if MUTATION_WAIT then coroutine.yield()end;return true end;local function purge()MUTATIONS=MUTATIONS+1;return true end;local function transfer()MUTATIONS=MUTATIONS+1;return true end;local function oldIdsInOrder()SCANNED=true;return {"AAA00001"}end;local function idOf(n)return tostring(n)end;local function used()return false end;local function textColumns()return {}end;local function sweep()if PLAN_WAIT then coroutine.yield()end;return {}end;local function ledgerNotReady()return false end;local function migrateRun()MUTATIONS=MUTATIONS+1;return 1 end;local function forgetSchema()end;'
  src=(ROOT/'server/citizen.lua').read_text(encoding='utf-8-sig')
  blocks=section(src,'function C.Reassign(', '-- ── deleting a character:')+section(src,'function C.Purge(', '-- ── handing a number')+section(src,'function C.TransferNumber(', '-- ── the one-time migration:')+section(src,'function C.Migrate(', "RegisterCommand('wcore_citizenid'")
  self.l.execute(pre+blocks);self.l.execute((ROOT/'server/generation.lua').read_text(encoding='utf-8'))
 def runlua(self,s):return self.l.execute(s)
 def test_yielding_callback_blocks_all_identity_mutations(self):
  self.runlua("CO=coroutine.create(function()return EXPORTS.WithCitizenGeneration('1',1,function()INSIDE_BUSY=WCore.Citizen.IsBusy('1');coroutine.yield();return true,'done'end)end);assert(coroutine.resume(CO));A,RA=WCore.Citizen.Purge('1');B,RB=WCore.Citizen.Reassign('1','2');C,RC=WCore.Citizen.Reassign('2','1');D,RD=WCore.Citizen.TransferNumber('1','2');E,RE=WCore.Citizen.TransferNumber('2','1');WCore.Citizen.Migrate('run')")
  for k in ['A','B','C','D','E']:self.assertFalse(self.g[k])
  for k in ['RA','RB','RC','RD','RE']:self.assertEqual(self.g[k],'busy')
  self.assertFalse(self.g.INSIDE_BUSY);self.assertEqual(self.g.MUTATIONS,0);self.assertIsNone(self.g.SCANNED)
  self.runlua("assert(coroutine.resume(CO));A=WCore.Citizen.Purge('1')");self.assertTrue(self.g.A);self.assertFalse(self.g.WCore.Citizen.HasGenerationLease('1'))
 def test_lease_precedes_the_first_database_yield(self):
  self.runlua("DB_WAIT=true;CO=coroutine.create(function()return EXPORTS.WithCitizenGeneration('1',1,function()return true end)end);assert(coroutine.resume(CO));A,WHY=WCore.Citizen.Purge('1')")
  self.assertFalse(self.g.A);self.assertEqual(self.g.WHY,'busy');self.assertTrue(self.g.WCore.Citizen.HasGenerationLease('1'));self.runlua('assert(coroutine.resume(CO))');self.assertFalse(self.g.WCore.Citizen.HasGenerationLease('1'))
 def test_already_running_mutation_refuses_lease_without_query(self):
  self.runlua("SET_BUSY('1',true);A,WHY=EXPORTS.WithCitizenGeneration('1',1,function()error('must not enter')end)")
  self.assertFalse(self.g.A);self.assertEqual(self.g.WHY,'generation_busy');self.assertEqual(self.g.SQL_CALLS,0)
 def test_mismatched_missing_and_retired_generation_never_enters(self):
  for change in ['ROW=2','ROW=nil','PURGED=1','MOVED=1']:
   self.setUp();self.runlua(change+";A,WHY=EXPORTS.WithCitizenGeneration('1',1,function()ENTERED=true end)")
   self.assertFalse(self.g.A);self.assertEqual(self.g.WHY,'generation_changed');self.assertIsNone(self.g.ENTERED);self.assertFalse(self.g.WCore.Citizen.HasGenerationLease('1'))
 def test_lookup_error_and_callback_error_always_release(self):
  self.runlua("DB_ERROR=true;A,WHY=EXPORTS.WithCitizenGeneration('1',1,function()end)");self.assertEqual(self.g.WHY,'generation_unavailable');self.assertFalse(self.g.WCore.Citizen.HasGenerationLease('1'))
  self.runlua("DB_ERROR=false;A,WHY=EXPORTS.WithCitizenGeneration('1',1,function()error('failure')end)");self.assertEqual(self.g.WHY,'generation_callback_failed');self.assertFalse(self.g.WCore.Citizen.HasGenerationLease('1'))
 def test_callback_tuple_preserves_leading_nil_and_false(self):
  self.assertEqual(self.g.EXPORTS.WithCitizenGeneration('1',1,self.l.eval("function()return nil,'receipt',42,false end")),(None,'receipt',42,False))
  self.assertFalse(self.g.WCore.Citizen.HasGenerationLease('1'))
 def test_multiple_and_nested_leases_release_counts_correctly(self):
  self.runlua("function start()return coroutine.create(function()return EXPORTS.WithCitizenGeneration('1',1,function()coroutine.yield();return true end)end)end;A=start();B=start();assert(coroutine.resume(A));assert(coroutine.resume(B));assert(coroutine.resume(A))")
  self.assertTrue(self.g.WCore.Citizen.HasGenerationLease('1'));self.runlua('assert(coroutine.resume(B))');self.assertFalse(self.g.WCore.Citizen.HasGenerationLease('1'))
  self.runlua("OK=EXPORTS.WithCitizenGeneration('1',1,function()return EXPORTS.WithCitizenGeneration('1',1,function()return 'nested'end)end)");self.assertEqual(self.g.OK,'nested');self.assertFalse(self.g.WCore.Citizen.HasGenerationLease('1'))
 def test_allowlist_and_bad_generation_values_fail_before_query(self):
  self.runlua("CALLER='untrusted';A,WHY=EXPORTS.WithCitizenGeneration('1',1,function()end)");self.assertEqual(self.g.WHY,'forbidden')
  self.g.CALLER='w_pets'
  for n in [0,-1,1.5,float('nan'),float('inf')]:self.assertEqual(self.g.EXPORTS.WithCitizenGeneration('1',n,self.l.eval('function()end')),(False,'invalid_generation'))
  self.assertEqual(self.g.SQL_CALLS,0)
 def test_callable_cross_resource_reference_is_supported(self):
  self.runlua("REF=setmetatable({},{__call=function()return true,'reference'end});A,B=EXPORTS.WithCitizenGeneration('1',1,REF)");self.assertTrue(self.g.A);self.assertEqual(self.g.B,'reference')
 def test_migration_rechecks_a_lease_started_during_its_plan(self):
  self.runlua("PLAN_WAIT=true;M=coroutine.create(function()WCore.Citizen.Migrate('run')end);assert(coroutine.resume(M));L=coroutine.create(function()return EXPORTS.WithCitizenGeneration('AAA00001',1,function()coroutine.yield()end)end);assert(coroutine.resume(L));assert(coroutine.resume(M))")
  self.assertEqual(self.g.MUTATIONS,0);self.assertTrue(self.g.WCore.Citizen.HasGenerationLease('AAA00001'));self.runlua('assert(coroutine.resume(L))')
if __name__=='__main__':unittest.main()
