-- Event Handler

AddEventHandler('chatMessage', function(_, _, message)
    if string.sub(message, 1, 1) == '/' then
        CancelEvent()
        return
    end
end)

AddEventHandler('playerDropped', function(reason)
    local src = source
    if not WCore.Players[src] then return end
    local Player = WCore.Players[src]
    TriggerEvent('w_log:server:CreateLog', 'joinleave', 'Dropped', 'red', '**' .. GetPlayerName(src) .. '** (' .. Player.PlayerData.license .. ') left..' ..'\n **Reason:** ' .. reason)
    Player.Functions.Save()
    WCore.Player_Buckets[Player.PlayerData.license] = nil
    WCore.Players[src] = nil
end)

-- Player Connecting

local function onPlayerConnecting(name, _, deferrals)
    local src = source
    deferrals.defer()

    -- Mandatory wait
    Wait(0)

    local valid, reason, identifiers = WCore.Functions.ValidatePlayerIdentifiers(src)
    if not valid then return deferrals.done(reason) end
    local license = identifiers.license

    -- with w_connector running ITS switch is the one (the website, w_admin and /closeserver set it) and its
    -- queue is the gate that applies it; this flag is only the fallback without it (2026-10-22)
    if WCore.Config.Server.Closed and GetResourceState('w_connector') ~= 'started' then
        if not IsPlayerAceAllowed(src, 'wraithadmin.join') then
            return deferrals.done(Lang:t(WCore.Config.Server.ClosedReason))
        end
    end

    deferrals.update(string.format(Lang:t('info.checking_ban'), name))

    -- Mandatory wait
    Wait(0)

    deferrals.update(string.format(Lang:t('info.checking_whitelisted'), name))

    local isBanned, Reason = WCore.Functions.IsPlayerBanned(src)
    local isLicenseAlreadyInUse = WCore.Functions.IsLicenseInUse(license)
    local isWhitelist, whitelisted = WCore.Config.Server.Whitelist, WCore.Functions.IsWhitelisted(src)

    Wait(0)

    deferrals.update(string.format(Lang:t('info.join_server'), name))
    Wait(0)

    -- ★ The ban check stays on (2026-10-14). It sat commented out with the rest below, so a ban from
    --   w_admin's console (or BanPlayer / ExploitBan) dropped the player and he walked straight back
    --   in: nothing else reads the `bans` table at connect (w_connector reads only its own wc_bans).
    if isBanned then
        return deferrals.done(Reason)
    end

    -- if not license then
    --   return deferrals.done(Lang:t('error.no_valid_license'))
    -- elseif isBanned then
    --     return deferrals.done(Reason)
    -- elseif isLicenseAlreadyInUse and WCore.Config.Server.CheckDuplicateLicense then
    --     return deferrals.done(Lang:t('error.duplicate_license'))
    -- elseif isWhitelist and not whitelisted then
    --   return deferrals.done(Lang:t('error.not_whitelisted'))
    -- end

    deferrals.done()

    -- Add any additional defferals you may need!
end

AddEventHandler('playerConnecting', onPlayerConnecting)

-- Open & Close Server (prevents players from joining)

RegisterNetEvent('WCore:Server:CloseServer', function(reason)
    local src = source
    if WCore.Functions.HasPermission(src, 'admin') then
        reason = reason or 'info.no_reason'
        WCore.Functions.SetServerClosed(true, GetPlayerName(src))
        WCore.Config.Server.ClosedReason = reason
        for k in pairs(WCore.Players) do
            if not WCore.Functions.HasPermission(k, WCore.Config.Server.WhitelistPermission) then
                WCore.Functions.Kick(k, reason, nil, nil)
            end
        end
    else
        WCore.Functions.Kick(src, 'error.no_permission', nil, nil)
    end
end)

RegisterNetEvent('WCore:Server:OpenServer', function()
    local src = source
    if WCore.Functions.HasPermission(src, 'admin') then
        WCore.Functions.SetServerClosed(false, GetPlayerName(src))
    else
        WCore.Functions.Kick(src, 'error.no_permission', nil, nil)
    end
end)

-- Legacy callback wire: the core itself rides on w.callback now; these two events stay as thin
-- adapters onto the same registry for an external caller that still fires them by hand.
RegisterNetEvent('WCore:Server:TriggerClientCallback', function(name, ...)
    if WCore.ClientCallbacks[name] then
        WCore.ClientCallbacks[name](...)
        WCore.ClientCallbacks[name] = nil
    end
end)

RegisterNetEvent('WCore:Server:TriggerCallback', function(name, ...)
    local src = source
    WCore.Functions.TriggerCallback(name, src, function(...)
        TriggerClientEvent('WCore:Client:TriggerCallback', src, name, ...)
    end, ...)
end)

-- Player

-- w_hud owns hunger and thirst (its own table, mirrored into the metadata) and broadcasts
-- them itself; while it runs the core neither decays nor announces them.
local function hudOwnsNeeds()
    return GetResourceState('w_hud') == 'started'
end

RegisterNetEvent('WCore:UpdatePlayer', function()
    local src = source
    local Player = WCore.Functions.GetPlayer(src)
    if not Player then return end
    if not hudOwnsNeeds() then
        local newHunger = Player.PlayerData.metadata.hunger - WCore.Config.Player.HungerRate
        local newThirst = Player.PlayerData.metadata.thirst - WCore.Config.Player.ThirstRate
        if newHunger <= 0 then
            newHunger = 0
        end
        if newThirst <= 0 then
            newThirst = 0
        end
        Player.Functions.SetMetaData('thirst', newThirst)
        Player.Functions.SetMetaData('hunger', newHunger)
        TriggerClientEvent('hud:client:UpdateNeeds', src, newHunger, newThirst, 100)
    end
    Player.Functions.Save()
end)

-- ⚠️ A net event: any client can fire it, with any key and any value, and it used to write both
--   into the sender's own metadata as sent: 'injail' 0 walked out of prison, 'criminalrecord' wiped
--   a file, 'isdead' / 'inlaststand' / 'ishandcuffed' faked what the police and medic checks read,
--   and 'hunger' / 'thirst' 100 fed a player whenever he liked, around w_hud's food rules.
--   Nothing a client sends here is written any more. Its last two callers are the server's now:
--     hunger / thirst  w_ambulancejob refills them on the server with every heal it grants
--                      (exports.w_hud:SetNeed, or this metadata when w_hud is not running)
--     ishandcuffed     w_policejob clears it on the server when a character loads or logs out
--   A server script sets metadata with Player.Functions.SetMetaData and needs with
--   exports.w_hud:SetNeed. The event stays registered so an old client script that still fires it
--   is dropped here, quietly, instead of warning in the console on every call.
RegisterNetEvent('WCore:Server:SetMetaData', function() end)

RegisterNetEvent('WCore:ToggleDuty', function()
    local src = source
    local Player = WCore.Functions.GetPlayer(src)
    if not Player then return end
    if Player.PlayerData.job.onduty then
        Player.Functions.SetJobDuty(false)
        TriggerClientEvent('WCore:Notify', src, 'info.off_duty')
    else
        Player.Functions.SetJobDuty(true)
        TriggerClientEvent('WCore:Notify', src, 'info.on_duty')
    end
    TriggerClientEvent('WCore:Client:SetDuty', src, Player.PlayerData.job.onduty)
end)

-- Non-Chat Command Calling (ex: w_adminmenu)

RegisterNetEvent('WCore:CallCommand', function(command, args)
    local src = source
    if not WCore.Commands.List[command] then return end
    local Player = WCore.Functions.GetPlayer(src)
    if not Player then return end
    local hasPerm = WCore.Functions.HasPermission(src, "command."..WCore.Commands.List[command].name)
    if hasPerm then
        if WCore.Commands.List[command].argsrequired and #WCore.Commands.List[command].arguments ~= 0 and not args[#WCore.Commands.List[command].arguments] then
            TriggerClientEvent('WCore:Notify', src, 'error.missing_args2', 'error')
        else
            WCore.Commands.List[command].callback(src, args)
        end
    else
        TriggerClientEvent('WCore:Notify', src, 'error.no_access', 'error')
    end
end)

-- Wagon spawning for players (wagons, carriages, boats)
-- server-side spawning callback (netId): the client turns the net id into the entity with
-- NetworkGetEntityFromNetworkId / NetToVeh
-- ★ Admins only (2026-10-14). Nothing in resources/ calls it, and open it let any client spawn any
--   model anywhere, as often as it liked -- and an invalid model or far coords left SpawnVehicle's wait
--   loops spinning forever.
WCore.Functions.CreateCallback('WCore:Server:SpawnVehicle', function(source, cb, model, coords, warp)
    if not WCore.Functions.HasPermission(source, 'admin') then return cb(nil) end
    cb(NetworkGetNetworkIdFromEntity(WCore.Functions.SpawnVehicle(source, model, coords, warp)))
end)
