"""Exercise the actual population thread with Lua 5.4 and native-call spies."""
from pathlib import Path
import unittest
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class Population(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            WConfig={Population={Enabled=true,AmbientHumans=0.65,ScenarioHumans=0.65}}
            LocalPlayer={state={isLoggedIn=true}}
            calls={}; waits={}; survival='missing'
            Citizen={InvokeNative=function(hash,value)
                calls[#calls+1]={hash=hash,value=value,kind=math.type(value)}
            end}
            function GetResourceState() return survival end
            function CreateThread(fn) worker=coroutine.create(fn) end
            function Wait(ms) waits[#waits+1]=ms; coroutine.yield() end
            function step() local ok,err=coroutine.resume(worker); assert(ok,err) end
        ''')
        self.lua.execute((ROOT / 'client/population.lua').read_text(encoding='utf-8'))
        self.g = self.lua.globals()

    def test_human_density_only_runs_every_frame(self):
        self.g.step()
        self.assertEqual(len(self.g.calls), 2)
        expected = [0xBA0980B5C0A11924, 0x28CB6391ACEDD9DB]
        for index, hash_value in enumerate(expected, 1):
            signed_hash = hash_value if hash_value < 2**63 else hash_value - 2**64
            self.assertEqual(self.g.calls[index].hash, signed_hash)
            self.assertAlmostEqual(self.g.calls[index].value, 0.65)
            self.assertEqual(self.g.calls[index].kind, 'float')
        self.assertEqual(self.g.waits[1], 0)
        self.g.step()
        self.assertEqual(len(self.g.calls), 4)

    def test_stops_during_character_selection_and_logout(self):
        self.g.LocalPlayer.state.isLoggedIn = False
        self.g.step()
        self.assertEqual(len(self.g.calls), 0)
        self.assertEqual(self.g.waits[1], 500)

    def test_toggle_and_missing_configuration_leave_world_to_engine(self):
        self.g.WConfig.Population.Enabled = False
        self.g.step()
        self.assertEqual(len(self.g.calls), 0)
        self.g.WConfig.Population = None
        self.g.step()
        self.assertEqual(len(self.g.calls), 0)

    def test_survival_owns_its_population_when_running(self):
        self.g.survival = 'started'
        self.g.step()
        self.assertEqual(len(self.g.calls), 0)
        self.g.survival = 'missing'
        self.g.step()
        self.assertEqual(len(self.g.calls), 2)

    def test_invalid_values_and_limits_are_safe_floats(self):
        for value, expected in [(-1, 0.0), (8, 1.0), (0, 0.0), (1, 1.0),
                                (float('nan'), 1.0), (float('inf'), 1.0),
                                (None, 1.0), ('0.5', 1.0), (True, 1.0)]:
            with self.subTest(value=value):
                self.g.WConfig.Population.AmbientHumans = value
                self.g.calls = self.lua.table()
                self.g.step()
                self.assertEqual(self.g.calls[1].value, expected)
                self.assertEqual(self.g.calls[1].kind, 'float')


if __name__ == '__main__':
    unittest.main()
