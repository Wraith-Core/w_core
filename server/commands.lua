WCore.Commands = {}
WCore.Commands.List = {}
WCore.Commands.IgnoreList = { -- Ignore old perm levels while keeping backwards compatibility
    ['god'] = true, -- We don't need to create an ace because god is allowed all commands
    ['user'] = true -- We don't need to create an ace because builtin.everyone
}

-- Chat help texts come from the dictionary in the server language (w_lib:locale convar);
-- notifications are sent as keys and translated on the client in the player's language.
-- The server console (source 0) has no client to notify: the answer is printed there instead,
-- otherwise a staff command typed in the txAdmin console would fail or succeed in silence.
local function notify(source, key, subs, style)
    if source == 0 then
        print(('[w_core] %s'):format(Lang:t(key, subs)))
        return
    end
    if subs then
        TriggerClientEvent('WCore:Notify', source, { key = key, subs = subs }, style)
    else
        TriggerClientEvent('WCore:Notify', source, key, style)
    end
end

local function params(command, names)
    local list = {}
    for i = 1, #names do
        local base = ('command.%s.params.%s'):format(command, names[i])
        list[#list + 1] = { name = Lang:t(base .. '.name'), help = Lang:t(base .. '.help') }
    end
    return list
end

-- ── the player a staff command names: his citizen id ───────────────────────
-- Staff types the citizen id (the fixed id: 12, or an old one such as ABC12345 until the
-- migration ran); '#5' names server id 5 on purpose. A plain number is never read as a server
-- id: since citizen ids became digits the two collide, and "player not online" answered a valid
-- citizen id. w.citizen asks WCore.Citizen directly inside w_core (it answers while w_core is
-- still starting), so an online character comes back with his server id and an offline one
-- with his saved row.
local CITIZEN_ERRORS = {
    invalid_id = 'error.invalid_citizen_id',
    not_found = 'error.citizen_not_found',
    offline = 'error.not_online',
}

--- The target the command names, or nil after telling the caller why.
---@param needsOnline boolean|nil the action works on the live player only (a teleport, a session ACE)
local function commandTarget(source, value, needsOnline)
    local resolve = needsOnline and w.citizen.requireOnline or w.citizen.resolve
    local target, reason = resolve(value, { self = source ~= 0 and source or nil })
    if not target then
        notify(source, CITIZEN_ERRORS[reason] or CITIZEN_ERRORS.not_found, nil, 'error')
        return nil
    end
    return target
end

--- The Player object behind a target, and whether it is the offline one. Offline it is w_core's
--- offline player (the saved row): the same Functions as in play, and Functions.Save() writes it.
--- Money needs no save either way: the central ledger books it by citizen id (server/economy.lua).
local function playerOf(target)
    if target.online then
        return WCore.Functions.GetPlayer(target.source), false
    end
    return WCore.Functions.GetOfflinePlayerByCitizenId(target.citizenid), true
end

--- How a change on a named player ended. In play the player sees the change himself, as before;
--- an offline change is confirmed to staff (nothing else would show it), a refused one always.
local function report(source, target, ok, offline)
    local who = { name = w.citizen.label(target) }
    if ok == false then
        notify(source, 'error.not_applied', who, 'error')
    elseif offline then
        notify(source, 'success.offline_saved', who, 'success')
    end
end

CreateThread(function() -- Add ace to node for perm checking
    local permissions = WConfig.Server.Permissions
    for i = 1, #permissions do
        local permission = permissions[i]
        exports.w_lib:addAce(('wcore.%s'):format(permission), permission)
    end
end)

-- Register & Refresh Commands

function WCore.Commands.Add(name, help, arguments, argsrequired, callback, permission, ...)
    local restricted = true -- Default to restricted for all commands
    if not permission then permission = 'user' end -- some commands don't pass permission level
    if permission == 'user' then restricted = false end -- allow all users to use command

    RegisterCommand(name, function(source, args, rawCommand) -- Register command within the runtime
        if argsrequired and #args < #arguments then
            return TriggerClientEvent('chat:addMessage', source, {
                color = {255, 0, 0},
                multiline = true,
                args = { Lang:t('info.system'), Lang:t('error.missing_args2') }
            })
        end
        callback(source, args, rawCommand)
    end, restricted)

    local extraPerms = ... and table.pack(...) or nil
    if extraPerms then
        extraPerms[extraPerms.n + 1] = permission -- The `n` field is the number of arguments in the packed table
        extraPerms.n += 1
        permission = extraPerms
        for i = 1, permission.n do
            if not WCore.Commands.IgnoreList[permission[i]] then -- only create aces for extra perm levels
                exports.w_lib:addAce(('wcore.%s'):format(permission[i]), ('command.%s'):format(name))
            end
        end
        permission.n = nil
    else
        permission = tostring(permission:lower())
        if not WCore.Commands.IgnoreList[permission] then -- only create aces for extra perm levels
            exports.w_lib:addAce(('wcore.%s'):format(permission), ('command.%s'):format(name))
        end
    end

    WCore.Commands.List[name:lower()] = {
        name = name:lower(),
        permission = permission,
        help = help,
        arguments = arguments,
        argsrequired = argsrequired,
        callback = callback
    }
end

-- The ACE 'command.<name>' is the permission the library helpers grant (w.addAce); the check
-- stays on the core's HasPermission (see server/functions.lua for why it must not call back).
function WCore.Commands.Refresh(source)
    local src = source
    local Player = WCore.Functions.GetPlayer(src)
    local suggestions = {}
    if Player then
        for command, info in pairs(WCore.Commands.List) do
            local hasPerm = WCore.Functions.HasPermission(src, 'command.' .. command)
            if hasPerm then
                suggestions[#suggestions + 1] = {
                    name = '/' .. command,
                    help = info.help,
                    params = info.arguments
                }
            else
                TriggerClientEvent('chat:removeSuggestion', src, '/' .. command)
            end
        end
        TriggerClientEvent('chat:addSuggestions', src, suggestions)
    end
end

-- Teleport
-- A permit belongs to one command that already passed its native ACE gate, never to a staff rank.
-- The waypoint client is bounded to 45 s; the 50 s permit adds a best-effort delivery/cleanup margin.
local function allowCommandTeleport(source, waypoint)
    if GetResourceState('w_guard') ~= 'started' then return true end
    if source <= 0 or not GetPlayerName(source) then return false end
    local ok, allowed = pcall(function() return exports.w_guard:AllowMove(source, waypoint and 50 or 10) end)
    if not ok or allowed ~= true then return false end
    if waypoint then
        ok, allowed = pcall(function() return exports.w_guard:AllowFlag(source, 'fly', 50) end)
        if not ok or allowed ~= true then return false end
    end
    return true
end

WCore.Commands.Add('tp', Lang:t('command.tp.help'), params('tp', { 'x', 'y', 'z' }), false, function(source, args)
    if args[1] and not args[2] and not args[3] then
        -- one argument: a citizen id (12, ABC12345) or '#5' is a player, any other word a location
        -- name (three arguments are always x y z, so the digits never meet coordinates)
        local kind = w.citizen.parse(args[1])
        if kind == 'citizen' or kind == 'server' then
            local target = commandTarget(source, args[1], true)
            if not target then return end
            local ped = GetPlayerPed(target.source)
            if ped ~= 0 then
                local coords = GetEntityCoords(ped)
                if not allowCommandTeleport(source, false) then return notify(source, 'error.tp_error', nil, 'error') end
                TriggerClientEvent('WCore:Command:TeleportToPlayer', source, coords)
            else
                notify(source, 'error.not_online', nil, 'error')
            end
        else
            local location = WShared.Locations[args[1]]
            if location then
                if not allowCommandTeleport(source, false) then return notify(source, 'error.tp_error', nil, 'error') end
                TriggerClientEvent('WCore:Command:TeleportToCoords', source, location.x, location.y, location.z, location.w)
            else
                notify(source, 'error.location_not_exist', nil, 'error')
            end
        end
    else
        if args[1] and args[2] and args[3] then
            local x = tonumber((args[1]:gsub(",", ""))) + .0
            local y = tonumber((args[2]:gsub(",", ""))) + .0
            local z = tonumber((args[3]:gsub(",", ""))) + .0
            if x ~= 0 and y ~= 0 and z ~= 0 then
                if not allowCommandTeleport(source, false) then return notify(source, 'error.tp_error', nil, 'error') end
                TriggerClientEvent('WCore:Command:TeleportToCoords', source, x, y, z)
            else
                notify(source, 'error.wrong_format', nil, 'error')
            end
        else
            notify(source, 'error.missing_args', nil, 'error')
        end
    end
end, 'admin')

WCore.Commands.Add('tpm', Lang:t('command.tpm.help'), {}, false, function(source)
    if not allowCommandTeleport(source, true) then return notify(source, 'error.tp_error', nil, 'error') end
    TriggerClientEvent('WCore:Command:GoToMarker', source)
end, 'admin')

-- Permissions

-- ★ A rank of the database now (server/ranks.lua), kept on the player's license across reconnects and
--   restarts -- it used to be a runtime ACE on the connection, gone at the next login. The master only:
--   the command ACE is held by every group.admin, so the handler asks for the master itself.
local function rankCommand(source, args, give)
    if not WCore.Ranks.isMaster(source) then return notify(source, 'error.ranks_master_only', nil, 'error') end
    local target = commandTarget(source, args[1], true)
    if not target then return end
    local rank = tostring(args[2] or ''):lower()
    local ok, err
    if give then
        ok, err = WCore.Ranks.assign(source, { source = target.source }, rank)
    else
        -- whichever identifier holds it (a convar master is kept by steam:, a panel rank by license:)
        ok, err = WCore.Ranks.revokePlayer(source, target.source, rank)
    end
    if ok then
        notify(source, give and 'success.rank_given' or 'success.rank_taken', { rank = rank, name = GetPlayerName(target.source) or '?' }, 'success')
    else
        notify(source, 'error.rank_failed', { rank = rank, reason = tostring(err) }, 'error')
    end
end

WCore.Commands.Add('addpermission', Lang:t('command.addpermission.help'), params('addpermission', { 'id', 'permission' }), true, function(source, args)
    rankCommand(source, args, true)
end, 'god')

WCore.Commands.Add('removepermission', Lang:t('command.removepermission.help'), params('removepermission', { 'id', 'permission' }), true, function(source, args)
    rankCommand(source, args, false)
end, 'god')

-- Open & Close Server
-- One switch (2026-10-22): with w_connector running, these set ITS switch (kept across restarts, the one
-- the website shows and the queue applies); WCore.Config.Server.Closed is only the fallback without it.

local function connectorUp() return GetResourceState('w_connector') == 'started' end
local function isClosed()
    if connectorUp() then
        local ok, closed = pcall(function() return exports.w_connector:IsServerClosed() end)
        if ok then return closed == true end
    end
    return WCore.Config.Server.Closed == true
end
local function setClosed(closed, by)
    WCore.Config.Server.Closed = closed
    if connectorUp() then pcall(function() exports.w_connector:SetServerClosed(closed, by) end) end
end
WCore.Functions.IsServerClosed = isClosed
WCore.Functions.SetServerClosed = setClosed

WCore.Commands.Add('openserver', Lang:t('command.openserver.help'), {}, false, function(source)
    if not isClosed() then
        notify(source, 'error.server_already_open', nil, 'error')
        return
    end
    if WCore.Functions.HasPermission(source, 'admin') then
        setClosed(false, source == 0 and 'console' or GetPlayerName(source))
        notify(source, 'success.server_opened', nil, 'success')
    else
        WCore.Functions.Kick(source, 'error.no_permission', nil, nil)
    end
end, 'admin')

WCore.Commands.Add('closeserver', Lang:t('command.closeserver.help'), params('closeserver', { 'reason' }), false, function(source, args)
    if isClosed() then
        notify(source, 'error.server_already_closed', nil, 'error')
        return
    end
    if WCore.Functions.HasPermission(source, 'admin') then
        local reason = args[1] or 'info.no_reason'
        setClosed(true, source == 0 and 'console' or GetPlayerName(source))
        WCore.Config.Server.ClosedReason = reason
        for k in pairs(WCore.Players) do
            if not WCore.Functions.HasPermission(k, WCore.Config.Server.WhitelistPermission) then
                WCore.Functions.Kick(k, reason, nil, nil)
            end
        end
        notify(source, 'success.server_closed', nil, 'success')
    else
        WCore.Functions.Kick(source, 'error.no_permission', nil, nil)
    end
end, 'admin')

-- HORSES / WAGONS
WCore.Commands.Add('dv', Lang:t('command.dv.help'), {}, false, function(source)
    TriggerClientEvent('WCore:Command:DeleteVehicle', source)
end, 'admin')

WCore.Commands.Add('dh', Lang:t('command.dh.help'), {}, false, function(source)
    TriggerClientEvent('WCore:Command:DeleteHorse', source)
end, 'admin')

WCore.Commands.Add('wagon', Lang:t('command.spawnwagon.help'), params('spawnwagon', { 'model' }), true, function(source, args)
    TriggerClientEvent('WCore:Command:SpawnVehicle', source, args[1])
end, 'admin')

WCore.Commands.Add('horse', Lang:t('command.spawnhorse.help'), params('spawnhorse', { 'model' }), true, function(source, args)
    TriggerClientEvent('WCore:Command:SpawnHorse', source, args[1])
end, 'admin')

-- Money

-- Money works offline too: the balance lives in the central ledger under the citizen id, and the
-- offline player's AddMoney / SetMoney book it there (no players-row save involved).
local function changeMoney(source, args, method)
    local target = commandTarget(source, args[1])
    if not target then return end
    local Player, offline = playerOf(target)
    if not Player then return notify(source, 'error.citizen_not_found', nil, 'error') end
    local ok = Player.Functions[method](tostring(args[2]), tonumber(args[3]))
    report(source, target, ok, offline)
end

WCore.Commands.Add('givemoney', Lang:t('command.givemoney.help'), params('givemoney', { 'id', 'moneytype', 'amount' }), true, function(source, args)
    changeMoney(source, args, 'AddMoney')
end, 'admin')

WCore.Commands.Add('setmoney', Lang:t('command.setmoney.help'), params('setmoney', { 'id', 'moneytype', 'amount' }), true, function(source, args)
    changeMoney(source, args, 'SetMoney')
end, 'admin')

-- Job

WCore.Commands.Add('job', Lang:t('command.job.help'), {}, false, function(source)
    local Player = WCore.Functions.GetPlayer(source)
    if not Player then return end
    local PlayerJob = Player.PlayerData.job
    -- the duty flag is translated on the client as well (it is a dictionary key)
    -- job and grade names in the player's language (label_ar / name_ar when it is 'ar')
    notify(source, 'info.job_info', { value = WShared.JobLabel(PlayerJob, source), value2 = WShared.GradeName(PlayerJob, source), value3 = PlayerJob.onduty and 'info.duty_on' or 'info.duty_off' })
end, 'user')

-- Job and gang work offline too: the offline player's SetJob / SetGang (the same checks as in
-- play), then its row is saved; the character finds the new role when he joins.
local function changeRole(source, args, method)
    local target = commandTarget(source, args[1])
    if not target then return end
    local Player, offline = playerOf(target)
    if not Player then return notify(source, 'error.citizen_not_found', nil, 'error') end
    local ok = Player.Functions[method](tostring(args[2]), tonumber(args[3]))
    if ok ~= false and offline then Player.Functions.Save() end
    report(source, target, ok, offline)
end

WCore.Commands.Add('setjob', Lang:t('command.setjob.help'), params('setjob', { 'id', 'job', 'grade' }), true, function(source, args)
    changeRole(source, args, 'SetJob')
end, 'admin')

-- Gang

WCore.Commands.Add('gang', Lang:t('command.gang.help'), {}, false, function(source)
    local Player = WCore.Functions.GetPlayer(source)
    if not Player then return end
    local PlayerGang = Player.PlayerData.gang
    notify(source, 'info.gang_info', { value = WShared.JobLabel(PlayerGang, source), value2 = WShared.GradeName(PlayerGang, source) })
end, 'user')

WCore.Commands.Add('setgang', Lang:t('command.setgang.help'), params('setgang', { 'id', 'gang', 'grade' }), true, function(source, args)
    changeRole(source, args, 'SetGang')
end, 'admin')

-- XP / Levels

-- XP and levels live in the metadata: offline, the offline player's metadata is changed the same
-- way and its row saved.
local function changeSkill(source, args, field, method, doneKey)
    local target = commandTarget(source, args[1])
    if not target then return end
    local Player, offline = playerOf(target)
    if not Player then return notify(source, 'error.citizen_not_found', nil, 'error') end
    local skill = tostring(args[2]):lower()
    -- AddXp & co. compare the amount with 0: a word there would raise instead of answering
    local amount = tonumber(args[3])
    if not amount then return notify(source, 'error.wrong_format', nil, 'error') end
    if Player.PlayerData.metadata[field] and Player.PlayerData.metadata[field][skill] then
        local ok = Player.Functions[method](skill, amount)
        if ok == false then return report(source, target, false, offline) end
        if offline then
            Player.Functions.Save()
            report(source, target, true, true)
        else
            notify(source, doneKey, nil, 'success')
        end
    else
        notify(source, 'error.no_skill', nil, 'error')
    end
end

WCore.Commands.Add('givexp', Lang:t('command.givexp.help'), params('givexp', { 'id', 'skill', 'amount' }), true, function(source, args)
    changeSkill(source, args, 'xp', 'AddXp', 'info.xp_added')
end, 'admin')

-- /removexp is w_level's (the server's XP) when it is on the server: two resources holding one command
-- name swap owners on every hot restart (2026-10-22)
if GetResourceState('w_level') == 'missing' then
    WCore.Commands.Add('removexp', Lang:t('command.removexp.help'), params('removexp', { 'id', 'skill', 'amount' }), true, function(source, args)
        changeSkill(source, args, 'xp', 'RemoveXp', 'info.xp_removed')
    end, 'admin')
end

WCore.Commands.Add('xp', Lang:t('command.xp.help'), params('xp', { 'skill' }), true, function(source, args)
    local Player = WCore.Functions.GetPlayer(source)
    if not Player then return end
    local skill = tostring(args[1])
    local Xp = Player.PlayerData.metadata.xp and Player.PlayerData.metadata.xp[skill]
    if Xp then
        notify(source, 'info.xp_info', { value = Xp, value2 = skill }, 'success')
    else
        notify(source, 'error.no_skill', nil, 'error')
    end
end, 'user')

-- levels are their own metadata table: AddXp here checked 'levels' and then added XP instead
WCore.Commands.Add('givelevel', Lang:t('command.givelevel.help'), params('givelevel', { 'id', 'skill', 'amount' }), true, function(source, args)
    changeSkill(source, args, 'levels', 'AddLevel', 'info.xp_added')
end, 'admin')

WCore.Commands.Add('removelevel', Lang:t('command.removelevel.help'), params('removelevel', { 'id', 'skill', 'amount' }), true, function(source, args)
    changeSkill(source, args, 'levels', 'RemoveLevel', 'info.xp_removed')
end, 'admin')

WCore.Commands.Add('level', Lang:t('command.level.help'), params('level', { 'skill' }), true, function(source, args)
    local Player = WCore.Functions.GetPlayer(source)
    if not Player then return end
    local skill = tostring(args[1])
    local Level = Player.PlayerData.metadata.levels and Player.PlayerData.metadata.levels[skill]
    if Level then
        notify(source, 'info.level_info', { value = Level, value2 = skill }, 'success')
    else
        notify(source, 'error.no_skill', nil, 'error')
    end
end, 'user')

-- Out of Character Chat

WCore.Commands.Add('ooc', Lang:t('command.ooc.help'), {}, false, function(source, args)
    local message = table.concat(args, ' ')
    local Players = WCore.Functions.GetPlayers()
    local Player = WCore.Functions.GetPlayer(source)
    local playerCoords = GetEntityCoords(GetPlayerPed(source))
    local prefix = Lang:t('info.ooc_prefix', { name = GetPlayerName(source) })
    for _, v in pairs(Players) do
        if v == source then
            TriggerClientEvent('chat:addMessage', v, {
                color = { 180, 180, 180 }, -- dim paper (was blue)
                multiline = true,
                args = { prefix, message }
            })
        elseif #(playerCoords - GetEntityCoords(GetPlayerPed(v))) < 20.0 then
            TriggerClientEvent('chat:addMessage', v, {
                color = { 180, 180, 180 }, -- dim paper (was blue)
                multiline = true,
                args = { prefix, message }
            })
        elseif WCore.Functions.HasPermission(v, 'admin') then
            if WCore.Functions.IsOptin(v) then
                TriggerClientEvent('chat:addMessage', v, {
                    color = { 180, 180, 180 }, -- dim paper (was blue)
                    multiline = true,
                    args = { Lang:t('info.ooc_proximity', { name = GetPlayerName(source) }), message }
                })
                TriggerEvent('w_log:server:CreateLog', 'ooc', 'OOC', 'white', '**' .. GetPlayerName(source) .. '** (CitizenID: ' .. Player.PlayerData.citizenid .. ' | ID: ' .. source .. ') **Message:** ' .. message, false)
            end
        end
    end
end, 'user')

-- /me /do /try: the 3D line is drawn by every nearby client (client/events.lua) in the viewer's
-- language; the proximity chat copy is built here in the server language.

local function joinArgs(args)
    local text = ''
    for i = 1, #args do
        text = text .. ' ' .. args[i]
    end
    return text .. ' '
end

-- "Citizen [12]": the speaker's citizen id, the one id staff and players use everywhere (a server
-- id changes on every connection and, being digits too, would be read as someone else's citizen
-- id). A player with no character in play yet shows his server id written the '#5' way.
local function speakerLabel(source)
    local Player = WCore.Functions.GetPlayer(source)
    local id = Player and Player.PlayerData.citizenid or ('#' .. tostring(source))
    return Lang:t('info.citizen', { id = id })
end

WCore.Commands.Add('me', Lang:t('command.me.help'), params('me', { 'message' }), false, function(source, args)
    local text = joinArgs(args)
    TriggerClientEvent('WCore:triggerDisplay', -1, text, source, 'me')
    TriggerClientEvent('sendProximityMessage', -1, source, speakerLabel(source), text, { 242, 242, 242 }) -- paper
end, 'user')

WCore.Commands.Add('do', Lang:t('command.do.help'), params('me', { 'message' }), false, function(source, args)
    local text = joinArgs(args)
    TriggerClientEvent('WCore:triggerDisplay', -1, text, source, 'do')
    TriggerClientEvent('sendProximityMessage', -1, source, speakerLabel(source), text, { 180, 180, 180 }) -- dim paper (was green)
end, 'user')

WCore.Commands.Add('try', Lang:t('command.try.help'), params('me', { 'message' }), false, function(source, args)
    local text = joinArgs(args)
    local succeeded = math.random(1, 2) == 1
    TriggerClientEvent('WCore:triggerDisplay', -1, text, source, 'try', nil, succeeded)
    TriggerClientEvent('sendProximityMessage', -1, source, speakerLabel(source),
        Lang:t(succeeded and 'info.try_success' or 'info.try_fail', { text = text }), { 180, 180, 180 }) -- dim paper (was blue)
end, 'user')

-- IDs
WCore.Commands.Add('id', Lang:t('command.id.help'), {}, false, function(source)
    notify(source, 'info.your_id', { value = source }, 'success')
end, 'user')

WCore.Commands.Add('cid', Lang:t('command.cid.help'), {}, false, function(source)
    local Player = WCore.Functions.GetPlayer(source)
    if not Player then return end
    notify(source, 'info.your_cid', { value = Player.PlayerData.citizenid }, 'success')
end, 'user')
