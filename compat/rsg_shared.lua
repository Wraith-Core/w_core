-- Wraith core event mirrors and raw shared tables. Public dialect exports are owned by w_lib.

-- RSG-Core exposes the definition tables as plain fields (RSGCore.Shared.Items[name]). They
-- must be RAW fields, not a metatable lookup: the core object leaves this VM through
-- GetCoreObject() as a msgpack copy, and the packer only walks real keys. This file is the last
-- script on both sides, so every shared/*.lua (weapons.lua, vehicles.lua included) has run.
WShared.Items    = WItems
WShared.Weapons  = WWeapons
WShared.Jobs     = WJobs
WShared.Gangs    = WGangs
WShared.Horses   = WHorses
WShared.Vehicles = WVehicles
WShared.Keybinds = WKeybinds

-- The foreign GetCoreObject export is owned by w_lib/core/compat/shared.lua.

-- RSG name for the player list
WCore.Functions.GetRSGPlayers = WCore.Functions.GetWPlayers

-- Mirror one event name onto another in the same VM. `mirroring` stops the pair from
-- re-triggering each other forever when both directions are registered.
local mirroring = {}

function WCore.Compat_Mirror(from, to, net)
    if net then RegisterNetEvent(from) end

    AddEventHandler(from, function(...)
        if mirroring[to] then return end
        mirroring[from] = true
        TriggerEvent(to, ...)
        mirroring[from] = nil
    end)
end

-- Both directions: a resource may fire either name and every listener still hears it.
function WCore.Compat_MirrorBoth(wName, rsgName, net)
    WCore.Compat_Mirror(wName, rsgName, net)
    WCore.Compat_Mirror(rsgName, wName, net)
end
