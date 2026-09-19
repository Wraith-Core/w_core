WCore.Commands = {}
WCore.Commands.List = {}
WCore.Commands.IgnoreList = { -- Ignore old perm levels while keeping backwards compatibility
    ['god'] = true, -- We don't need to create an ace because god is allowed all commands
    ['user'] = true -- We don't need to create an ace because builtin.everyone
}

-- Chat help texts come from the dictionary in the server language (w_lib:locale convar);
-- notifications are sent as keys and translated on the client in the player's language.
local function notify(source, key, subs, style)
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
WCore.Commands.Add('tp', Lang:t('command.tp.help'), params('tp', { 'x', 'y', 'z' }), false, function(source, args)
    if args[1] and not args[2] and not args[3] then
        if tonumber(args[1]) then
            local target = GetPlayerPed(tonumber(args[1]))
            if target ~= 0 then
                local coords = GetEntityCoords(target)
                TriggerClientEvent('WCore:Command:TeleportToPlayer', source, coords)
            else
                notify(source, 'error.not_online', nil, 'error')
            end
        else
            local location = WShared.Locations[args[1]]
            if location then
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
    TriggerClientEvent('WCore:Command:GoToMarker', source)
end, 'admin')

-- Permissions

WCore.Commands.Add('addpermission', Lang:t('command.addpermission.help'), params('addpermission', { 'id', 'permission' }), true, function(source, args)
    local Player = WCore.Functions.GetPlayer(tonumber(args[1]))
    local permission = tostring(args[2]):lower()
    if Player then
        WCore.Functions.AddPermission(Player.PlayerData.source, permission)
    else
        notify(source, 'error.not_online', nil, 'error')
    end
end, 'god')

WCore.Commands.Add('removepermission', Lang:t('command.removepermission.help'), params('removepermission', { 'id', 'permission' }), true, function(source, args)
    local Player = WCore.Functions.GetPlayer(tonumber(args[1]))
    local permission = tostring(args[2]):lower()
    if Player then
        WCore.Functions.RemovePermission(Player.PlayerData.source, permission)
    else
        notify(source, 'error.not_online', nil, 'error')
    end
end, 'god')

-- Open & Close Server

WCore.Commands.Add('openserver', Lang:t('command.openserver.help'), {}, false, function(source)
    if not WCore.Config.Server.Closed then
        notify(source, 'error.server_already_open', nil, 'error')
        return
    end
    if WCore.Functions.HasPermission(source, 'admin') then
        WCore.Config.Server.Closed = false
        notify(source, 'success.server_opened', nil, 'success')
    else
        WCore.Functions.Kick(source, 'error.no_permission', nil, nil)
    end
end, 'admin')

WCore.Commands.Add('closeserver', Lang:t('command.closeserver.help'), params('closeserver', { 'reason' }), false, function(source, args)
    if WCore.Config.Server.Closed then
        notify(source, 'error.server_already_closed', nil, 'error')
        return
    end
    if WCore.Functions.HasPermission(source, 'admin') then
        local reason = args[1] or 'info.no_reason'
        WCore.Config.Server.Closed = true
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

WCore.Commands.Add('givemoney', Lang:t('command.givemoney.help'), params('givemoney', { 'id', 'moneytype', 'amount' }), true, function(source, args)
    local Player = WCore.Functions.GetPlayer(tonumber(args[1]))
    if Player then
        Player.Functions.AddMoney(tostring(args[2]), tonumber(args[3]))
    else
        notify(source, 'error.not_online', nil, 'error')
    end
end, 'admin')

WCore.Commands.Add('setmoney', Lang:t('command.setmoney.help'), params('setmoney', { 'id', 'moneytype', 'amount' }), true, function(source, args)
    local Player = WCore.Functions.GetPlayer(tonumber(args[1]))
    if Player then
        Player.Functions.SetMoney(tostring(args[2]), tonumber(args[3]))
    else
        notify(source, 'error.not_online', nil, 'error')
    end
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

WCore.Commands.Add('setjob', Lang:t('command.setjob.help'), params('setjob', { 'id', 'job', 'grade' }), true, function(source, args)
    local Player = WCore.Functions.GetPlayer(tonumber(args[1]))
    if Player then
        Player.Functions.SetJob(tostring(args[2]), tonumber(args[3]))
    else
        notify(source, 'error.not_online', nil, 'error')
    end
end, 'admin')

-- Gang

WCore.Commands.Add('gang', Lang:t('command.gang.help'), {}, false, function(source)
    local Player = WCore.Functions.GetPlayer(source)
    if not Player then return end
    local PlayerGang = Player.PlayerData.gang
    notify(source, 'info.gang_info', { value = WShared.JobLabel(PlayerGang, source), value2 = WShared.GradeName(PlayerGang, source) })
end, 'user')

WCore.Commands.Add('setgang', Lang:t('command.setgang.help'), params('setgang', { 'id', 'gang', 'grade' }), true, function(source, args)
    local Player = WCore.Functions.GetPlayer(tonumber(args[1]))
    if Player then
        Player.Functions.SetGang(tostring(args[2]), tonumber(args[3]))
    else
        notify(source, 'error.not_online', nil, 'error')
    end
end, 'admin')

-- XP / Levels

local function changeSkill(source, args, field, method, doneKey)
    local Player = WCore.Functions.GetPlayer(tonumber(args[1]))
    if not Player then
        notify(source, 'error.not_online', nil, 'error')
        return
    end
    local skill = tostring(args[2])
    if Player.PlayerData.metadata[field] and Player.PlayerData.metadata[field][skill] then
        Player.Functions[method](skill, tonumber(args[3]))
        notify(source, doneKey, nil, 'success')
    else
        notify(source, 'error.no_skill', nil, 'error')
    end
end

WCore.Commands.Add('givexp', Lang:t('command.givexp.help'), params('givexp', { 'id', 'skill', 'amount' }), true, function(source, args)
    changeSkill(source, args, 'xp', 'AddXp', 'info.xp_added')
end, 'admin')

WCore.Commands.Add('removexp', Lang:t('command.removexp.help'), params('removexp', { 'id', 'skill', 'amount' }), true, function(source, args)
    changeSkill(source, args, 'xp', 'RemoveXp', 'info.xp_removed')
end, 'admin')

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

WCore.Commands.Add('givelevel', Lang:t('command.givelevel.help'), params('givelevel', { 'id', 'skill', 'amount' }), true, function(source, args)
    changeSkill(source, args, 'levels', 'AddXp', 'info.xp_added')
end, 'admin')

WCore.Commands.Add('removelevel', Lang:t('command.removelevel.help'), params('removelevel', { 'id', 'skill', 'amount' }), true, function(source, args)
    changeSkill(source, args, 'levels', 'RemoveXp', 'info.xp_removed')
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
                color = { 0, 0, 255 },
                multiline = true,
                args = { prefix, message }
            })
        elseif #(playerCoords - GetEntityCoords(GetPlayerPed(v))) < 20.0 then
            TriggerClientEvent('chat:addMessage', v, {
                color = { 0, 0, 255 },
                multiline = true,
                args = { prefix, message }
            })
        elseif WCore.Functions.HasPermission(v, 'admin') then
            if WCore.Functions.IsOptin(v) then
                TriggerClientEvent('chat:addMessage', v, {
                    color = { 0, 0, 255 },
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

WCore.Commands.Add('me', Lang:t('command.me.help'), params('me', { 'message' }), false, function(source, args)
    local text = joinArgs(args)
    TriggerClientEvent('WCore:triggerDisplay', -1, text, source, 'me')
    TriggerClientEvent('sendProximityMessage', -1, source, Lang:t('info.citizen', { id = source }), text, { 255, 255, 255 })
end, 'user')

WCore.Commands.Add('do', Lang:t('command.do.help'), params('me', { 'message' }), false, function(source, args)
    local text = joinArgs(args)
    TriggerClientEvent('WCore:triggerDisplay', -1, text, source, 'do')
    TriggerClientEvent('sendProximityMessage', -1, source, Lang:t('info.citizen', { id = source }), text, { 145, 209, 144 })
end, 'user')

WCore.Commands.Add('try', Lang:t('command.try.help'), params('me', { 'message' }), false, function(source, args)
    local text = joinArgs(args)
    local succeeded = math.random(1, 2) == 1
    TriggerClientEvent('WCore:triggerDisplay', -1, text, source, 'try', nil, succeeded)
    TriggerClientEvent('sendProximityMessage', -1, source, Lang:t('info.citizen', { id = source }),
        Lang:t(succeeded and 'info.try_success' or 'info.try_fail', { text = text }), { 32, 151, 247 })
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
