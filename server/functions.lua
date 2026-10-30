WCore.Functions = {}
WCore.Player_Buckets = {}
WCore.Entity_Buckets = {}
WCore.UsableItems = {}

-- Getters
-- Get your player first and then trigger a function on them
-- ex: local player = WCore.Functions.GetPlayer(source)
-- ex: local example = player.Functions.functionname(parameter)

function WCore.Functions.GetCoords(entity)
    local coords = GetEntityCoords(entity, false)
    local heading = GetEntityHeading(entity)
    return vector4(coords.x, coords.y, coords.z, heading)
end

function WCore.Functions.GetIdentifier(source, idtype)
    local identifiers = GetPlayerIdentifiers(source)
    for _, identifier in pairs(identifiers) do
        if identifier:match('^([^:]+):') == idtype then
            return identifier
        end
    end
    return nil
end

function WCore.Functions.GetSource(identifier)
    for src, _ in pairs(WCore.Players) do
        local idens = GetPlayerIdentifiers(src)
        for _, id in pairs(idens) do
            if identifier == id then
                return src
            end
        end
    end
    return 0
end

function WCore.Functions.GetPlayer(source)
    if type(source) == 'number' then
        return WCore.Players[source]
    else
        return WCore.Players[WCore.Functions.GetSource(source)]
    end
end

function WCore.Functions.GetPlayerByCitizenId(citizenid)
    for src in pairs(WCore.Players) do
        if WCore.Players[src].PlayerData.citizenid == citizenid then
            return WCore.Players[src]
        end
    end
    return nil
end

function WCore.Functions.GetOfflinePlayerByCitizenId(citizenid)
    return WCore.Player.GetOfflinePlayer(citizenid)
end

function WCore.Functions.GetPlayers()
    local sources = {}
    for k in pairs(WCore.Players) do
        sources[#sources+1] = k
    end
    return sources
end

-- Will return an array of W Player class instances
-- unlike the GetPlayers() wrapper which only returns IDs
function WCore.Functions.GetWPlayers()
    return WCore.Players
end

--- Gets a list of all on duty players of a specified job and the number
function WCore.Functions.GetPlayersOnDuty(job)
    local players = {}
    local count = 0
    for src, Player in pairs(WCore.Players) do
        if Player.PlayerData.job.name == job then
            if Player.PlayerData.job.onduty then
                players[#players + 1] = src
                count += 1
            end
        end
    end
    return players, count
end

-- Returns only the amount of players on duty for the specified job
function WCore.Functions.GetDutyCount(job)
    local count = 0
    for _, Player in pairs(WCore.Players) do
        if Player.PlayerData.job.name == job then
            if Player.PlayerData.job.onduty then
                count += 1
            end
        end
    end
    return count
end

-- Routing buckets (Only touch if you know what you are doing)

-- Returns the objects related to buckets, first returned value is the player buckets, second one is entity buckets
function WCore.Functions.GetBucketObjects()
    return WCore.Player_Buckets, WCore.Entity_Buckets
end

-- Will set the provided player id / source into the provided bucket id
function WCore.Functions.SetPlayerBucket(source --[[ int ]], bucket --[[ int ]])
    if source and bucket then
        local plicense = WCore.Functions.GetIdentifier(source, 'license')
        SetPlayerRoutingBucket(source, bucket)
        WCore.Player_Buckets[plicense] = {id = source, bucket = bucket}
        return true
    else
        return false
    end
end

-- Will set any entity into the provided bucket, for example peds / vehicles / props / etc.
function WCore.Functions.SetEntityBucket(entity --[[ int ]], bucket --[[ int ]])
    if entity and bucket then
        SetEntityRoutingBucket(entity, bucket)
        WCore.Entity_Buckets[entity] = {id = entity, bucket = bucket}
        return true
    else
        return false
    end
end

-- Will return an array of all the player ids inside the current bucket
function WCore.Functions.GetPlayersInBucket(bucket --[[ int ]])
    local curr_bucket_pool = {}
    if WCore.Player_Buckets and next(WCore.Player_Buckets) then
        for _, v in pairs(WCore.Player_Buckets) do
            if v.bucket == bucket then
                curr_bucket_pool[#curr_bucket_pool + 1] = v.id
            end
        end
        return curr_bucket_pool
    else
        return false
    end
end

-- Will return an array of all the entities inside the current bucket (not for player entities, use GetPlayersInBucket for that)
function WCore.Functions.GetEntitiesInBucket(bucket --[[ int ]])
    local curr_bucket_pool = {}
    if WCore.Entity_Buckets and next(WCore.Entity_Buckets) then
        for _, v in pairs(WCore.Entity_Buckets) do
            if v.bucket == bucket then
                curr_bucket_pool[#curr_bucket_pool + 1] = v.id
            end
        end
        return curr_bucket_pool
    else
        return false
    end
end

-- Server side wagon creation (wagons, carriages, boats)
-- the CreateVehicle RPC still uses the client for creation so the player must be near
function WCore.Functions.SpawnVehicle(source, model, coords, warp)
    local ped = GetPlayerPed(source)
    model = type(model) == 'string' and joaat(model) or model
    if not coords then coords = GetEntityCoords(ped) end
    local heading = coords.w or GetEntityHeading(ped)
    local veh = CreateVehicle(model, coords.x, coords.y, coords.z, heading, true, true)
    while not DoesEntityExist(veh) do Wait(0) end
    if warp then
        while GetVehiclePedIsIn(ped) ~= veh do
            Wait(0)
            TaskWarpPedIntoVehicle(ped, veh, -1)
        end
    end
    while NetworkGetEntityOwner(veh) ~= source do Wait(0) end
    return veh
end

-- Callback Functions --
-- Both directions ride on w.callback (the library wire, '__w_cb_<name>'). The WCore signatures
-- are unchanged: a server callback is still written as cb(source, callback, ...) and answers by
-- calling `callback(...)`; the adapter turns that into the return values w.callback expects.

---Run a (source, cb, ...) style handler and yield until it answers.
---@param handler function
---@param source number
---@param ... any
---@return ...
local function awaitHandler(handler, source, ...)
    local p = promise.new()
    local answered = false
    local function answer(...)
        if answered then return end
        answered = true
        p:resolve(table.pack(...))
    end
    local ok, err = pcall(handler, source, answer, ...)
    if not ok then
        answer()
        error(err, 0)
    end
    local result = Citizen.Await(p)
    return table.unpack(result, 1, result.n)
end

-- Client Callback (asks a player); the answer goes to cb
function WCore.Functions.TriggerClientCallback(name, source, cb, ...)
    if w and w.callback and w.callback.triggerClient then
        return w.callback.triggerClient(name, source, cb or function() end, ...)
    end
    TriggerClientEvent('WCore:Client:TriggerCallback', source, name, ...)
end

-- Server Callback (answers the clients)
-- ★ 2026-10-15: the handler registered with w_lib reads WCore.ServerCallbacks[name] on every call, so
--   a resource that restarts (w_medic) only needs its function swapped. Registering the name again
--   made w_lib print "Callback already registered" for each of its callbacks on every restart. The
--   name is registered once; it is registered again only after w_lib dropped it, which w_lib does
--   when the resource it recorded for the name (GetInvokingResource() at registration -- the same
--   value here, w_lib's register runs in this call) stops: that rule is mirrored below.
local callbackOwner = {}   -- [name] = what w_lib recorded as the registering resource (false = none)
function WCore.Functions.CreateCallback(name, cb)
    WCore.ServerCallbacks[name] = cb
    if callbackOwner[name] ~= nil then return end
    callbackOwner[name] = GetInvokingResource() or false
    w.callback.register(name, function(source, ...)
        return awaitHandler(WCore.ServerCallbacks[name], source, ...)
    end)
end

AddEventHandler('onResourceStop', function(resource)
    for name, owner in pairs(callbackOwner) do
        if owner == resource and name:match('^[^:]*') ~= 'w_lib' then callbackOwner[name] = nil end
    end
end)

-- Runs a server callback locally (same VM), the way the old net adapter did
function WCore.Functions.TriggerCallback(name, source, cb, ...)
    if not WCore.ServerCallbacks[name] then return end
    WCore.ServerCallbacks[name](source, cb, ...)
end

-- Items

function WCore.Functions.CreateUseableItem(item, data)
    WCore.UsableItems[item] = data
end

function WCore.Functions.CanUseItem(item)
    return WCore.UsableItems[item]
end

-- Runs the usable-item callback registered with CreateUseableItem. w_inventory resolves the
-- same callback through CanUseItem when a bag slot is used, so nothing here goes back
-- through the inventory (its UseItem export has a different signature).
function WCore.Functions.UseItem(source, item)
    local itemName = type(item) == 'table' and item.name or item
    local usable = WCore.UsableItems[itemName]
    if not usable then return end

    local callback = type(usable) == 'table' and (usable.cb or usable.callback or usable.func) or usable
    if type(callback) ~= 'function' and not (type(callback) == 'table' and rawget(callback, '__cfx_functionReference')) then return end

    callback(source, item)
end

-- Kick Player

function WCore.Functions.Kick(source, reason, setKickReason, deferrals)
    reason = '\n' .. Lang:t(reason or '') .. '\n' .. Lang:t('info.kick_discord', { discord = WCore.Config.Server.Discord })
    if setKickReason then
        setKickReason(reason)
    end
    CreateThread(function()
        if deferrals then
            deferrals.update(reason)
            Wait(2500)
        end
        if source then
            DropPlayer(source, reason)
        end
        for _ = 0, 4 do
            while true do
                if source then
                    if GetPlayerPing(source) >= 0 then
                        break
                    end
                    Wait(100)
                    CreateThread(function()
                        DropPlayer(source, reason)
                    end)
                end
            end
            Wait(5000)
        end
    end)
end

-- Check if player is whitelisted, kept like this for backwards compatibility or future plans

function WCore.Functions.IsWhitelisted(source)
    if not WCore.Config.Server.Whitelist then return true end
    if WCore.Functions.HasPermission(source, WCore.Config.Server.WhitelistPermission) then return true end
    return false
end

-- Setting & Removing Permissions
-- Principals go through the library ACE helpers (exports.w_lib:addPrincipal / removePrincipal).
-- The checks themselves stay on IsPlayerAceAllowed on purpose: the library's HasPermission /
-- GetPlayerGroup / IsAdmin / HasPermissionNode resolve through this core's HasPermission and
-- GetPermission (the framework hook), so the core is the ground truth and must not call back.

function WCore.Functions.AddPermission(source, permission)
    if not IsPlayerAceAllowed(source, permission) then
        exports.w_lib:addPrincipal(tonumber(source), ('wcore.%s'):format(permission))
        WCore.Commands.Refresh(source)
    end
end

function WCore.Functions.RemovePermission(source, permission)
    if permission then
        if IsPlayerAceAllowed(source, permission) then
            exports.w_lib:removePrincipal(tonumber(source), ('wcore.%s'):format(permission))
            WCore.Commands.Refresh(source)
        end
    else
        for _, v in pairs(WCore.Config.Server.Permissions) do
            if IsPlayerAceAllowed(source, v) then
                exports.w_lib:removePrincipal(tonumber(source), ('wcore.%s'):format(v))
                WCore.Commands.Refresh(source)
            end
        end
    end
end

-- Checking for Permission Level

function WCore.Functions.HasPermission(source, permission)
    if type(permission) == "string" then
        if IsPlayerAceAllowed(source, permission) then return true end
    elseif type(permission) == "table" then
        for _, permLevel in pairs(permission) do
            if IsPlayerAceAllowed(source, permLevel) then return true end
        end
    end

    return false
end

function WCore.Functions.GetPermission(source)
    local src = source
    local perms = {}
    for _, v in pairs (WCore.Config.Server.Permissions) do
        if IsPlayerAceAllowed(src, v) then
            perms[v] = true
        end
    end
    return perms
end

-- Opt in or out of admin reports

function WCore.Functions.IsOptin(source)
    local license = WCore.Functions.GetIdentifier(source, 'license')
    if not license or not WCore.Functions.HasPermission(source, 'admin') then return false end
    local Player = WCore.Functions.GetPlayer(source)
    return Player.PlayerData.optin
end

function WCore.Functions.ToggleOptin(source)
    local license = WCore.Functions.GetIdentifier(source, 'license')
    if not license or not WCore.Functions.HasPermission(source, 'admin') then return end
    local Player = WCore.Functions.GetPlayer(source)
    Player.PlayerData.optin = not Player.PlayerData.optin
    Player.Functions.SetPlayerData('optin', Player.PlayerData.optin)
end

-- Check if player is banned

function WCore.Functions.IsPlayerBanned(source)
    -- the one ban store (server/bans.lua): license, Discord or Steam, whichever side banned him
    local ban = WBans.check(WBans.idsOf(source))
    if not ban then return false end
    return true, WBans.message(ban.reason, ban.expire)
end

-- Check for duplicate license

function WCore.Functions.IsLicenseInUse(license, ignoreSource)
    local players = GetPlayers()
    for _, player in pairs(players) do
        local identifiers = tonumber(player) ~= tonumber(ignoreSource) and GetPlayerIdentifiers(player) or {}
        for _, id in pairs(identifiers) do
            if string.find(id, 'license') then
                if id == license then
                    return true
                end
            end
        end
    end
    return false
end

-- Utility functions

function WCore.Functions.HasItem(source, items, amount)
    if GetResourceState('w_inventory') == 'missing' then return end
    return exports['rsg-inventory']:HasItem(source, items, amount)
end

-- The text may be a dictionary key or { key = 'info.x', subs = { ... } }: the client translates
-- it in the player's own language before handing it to w.notify.
function WCore.Functions.Notify(source, text, type, length)
    TriggerClientEvent('WCore:Notify', source, text, type, length)
end
