-- Add or change (a) method(s) in the WCore.Functions table
local function SetMethod(methodName, handler)
    if type(methodName) ~= "string" then
        return false, "invalid_method_name"
    end

    WCore.Functions[methodName] = handler

    TriggerEvent('WCore:Server:UpdateObject')

    return true, "success"
end

WCore.Functions.SetMethod = SetMethod
exports("SetMethod", SetMethod)

-- Add or change (a) field(s) in the WCore table
local function SetField(fieldName, data)
    if type(fieldName) ~= "string" then
        return false, "invalid_field_name"
    end

    WCore[fieldName] = data

    TriggerEvent('WCore:Server:UpdateObject')

    return true, "success"
end

WCore.Functions.SetField = SetField
exports("SetField", SetField)

-- Single add job function which should only be used if you planning on adding a single job
local function AddJob(jobName, job)
    if type(jobName) ~= "string" then
        return false, "invalid_job_name"
    end

    if WJobs[jobName] then
        return false, "job_exists"
    end

    WJobs[jobName] = job

    TriggerClientEvent('WCore:Client:OnSharedUpdate', -1, 'Jobs', jobName, job)
    TriggerEvent('WCore:Server:UpdateObject')
    return true, "success"
end

WCore.Functions.AddJob = AddJob
exports('AddJob', AddJob)

-- Multiple Add Jobs
local function AddJobs(jobs)
    local shouldContinue = true
    local message = "success"
    local errorItem = nil

    for key, value in pairs(jobs) do
        if type(key) ~= "string" then
            message = 'invalid_job_name'
            shouldContinue = false
            errorItem = jobs[key]
            break
        end

        if WJobs[key] then
            message = 'job_exists'
            shouldContinue = false
            errorItem = jobs[key]
            break
        end

        WJobs[key] = value
    end

    if not shouldContinue then return false, message, errorItem end
    TriggerClientEvent('WCore:Client:OnSharedUpdateMultiple', -1, 'Jobs', jobs)
    TriggerEvent('WCore:Server:UpdateObject')
    return true, message, nil
end

WCore.Functions.AddJobs = AddJobs
exports('AddJobs', AddJobs)

-- Single Remove Job
local function RemoveJob(jobName)
    if type(jobName) ~= "string" then
        return false, "invalid_job_name"
    end

    if not WJobs[jobName] then
        return false, "job_not_exists"
    end

    WJobs[jobName] = nil

    TriggerClientEvent('WCore:Client:OnSharedUpdate', -1, 'Jobs', jobName, nil)
    TriggerEvent('WCore:Server:UpdateObject')
    return true, "success"
end

WCore.Functions.RemoveJob = RemoveJob
exports('RemoveJob', RemoveJob)

-- Single Update Job
local function UpdateJob(jobName, job)
    if type(jobName) ~= "string" then
        return false, "invalid_job_name"
    end

    if not WJobs[jobName] then
        return false, "job_not_exists"
    end

    WJobs[jobName] = job

    TriggerClientEvent('WCore:Client:OnSharedUpdate', -1, 'Jobs', jobName, job)
    TriggerEvent('WCore:Server:UpdateObject')
    return true, "success"
end

WCore.Functions.UpdateJob = UpdateJob
exports('UpdateJob', UpdateJob)

-- Single add item
local function AddItem(itemName, item)
    if type(itemName) ~= "string" then
        return false, "invalid_item_name"
    end

    if WItems[itemName] then
        return false, "item_exists"
    end

    WItems[itemName] = item

    TriggerClientEvent('WCore:Client:OnSharedUpdate', -1, 'Items', itemName, item)
    TriggerEvent('WCore:Server:UpdateObject')
    return true, "success"
end

WCore.Functions.AddItem = AddItem
exports('AddItem', AddItem)

-- Single update item
local function UpdateItem(itemName, item)
    if type(itemName) ~= "string" then
        return false, "invalid_item_name"
    end
    if not WItems[itemName] then
        return false, "item_not_exists"
    end
    WItems[itemName] = item
    TriggerClientEvent('WCore:Client:OnSharedUpdate', -1, 'Items', itemName, item)
    TriggerEvent('WCore:Server:UpdateObject')
    return true, "success"
end

WCore.Functions.UpdateItem = UpdateItem
exports('UpdateItem', UpdateItem)

-- Multiple Add Items
local function AddItems(items)
    local shouldContinue = true
    local message = "success"
    local errorItem = nil

    for key, value in pairs(items) do
        if type(key) ~= "string" then
            message = "invalid_item_name"
            shouldContinue = false
            errorItem = items[key]
            break
        end

        if WItems[key] then
            message = "item_exists"
            shouldContinue = false
            errorItem = items[key]
            break
        end

        WItems[key] = value
    end

    if not shouldContinue then return false, message, errorItem end
    TriggerClientEvent('WCore:Client:OnSharedUpdateMultiple', -1, 'Items', items)
    TriggerEvent('WCore:Server:UpdateObject')
    return true, message, nil
end

WCore.Functions.AddItems = AddItems
exports('AddItems', AddItems)

-- Single Remove Item
local function RemoveItem(itemName)
    if type(itemName) ~= "string" then
        return false, "invalid_item_name"
    end

    if not WItems[itemName] then
        return false, "item_not_exists"
    end

    WItems[itemName] = nil

    TriggerClientEvent('WCore:Client:OnSharedUpdate', -1, 'Items', itemName, nil)
    TriggerEvent('WCore:Server:UpdateObject')
    return true, "success"
end

WCore.Functions.RemoveItem = RemoveItem
exports('RemoveItem', RemoveItem)

-- Single Add Gang
local function AddGang(gangName, gang)
    if type(gangName) ~= "string" then
        return false, "invalid_gang_name"
    end

    if WGangs[gangName] then
        return false, "gang_exists"
    end

    WGangs[gangName] = gang

    TriggerClientEvent('WCore:Client:OnSharedUpdate', -1, 'Gangs', gangName, gang)
    TriggerEvent('WCore:Server:UpdateObject')
    return true, "success"
end

WCore.Functions.AddGang = AddGang
exports('AddGang', AddGang)

-- Multiple Add Gangs
local function AddGangs(gangs)
    local shouldContinue = true
    local message = "success"
    local errorItem = nil

    for key, value in pairs(gangs) do
        if type(key) ~= "string" then
            message = "invalid_gang_name"
            shouldContinue = false
            errorItem = gangs[key]
            break
        end

        if WGangs[key] then
            message = "gang_exists"
            shouldContinue = false
            errorItem = gangs[key]
            break
        end

        WGangs[key] = value
    end

    if not shouldContinue then return false, message, errorItem end
    TriggerClientEvent('WCore:Client:OnSharedUpdateMultiple', -1, 'Gangs', gangs)
    TriggerEvent('WCore:Server:UpdateObject')
    return true, message, nil
end

WCore.Functions.AddGangs = AddGangs
exports('AddGangs', AddGangs)

-- Single Remove Gang
local function RemoveGang(gangName)
    if type(gangName) ~= "string" then
        return false, "invalid_gang_name"
    end

    if not WGangs[gangName] then
        return false, "gang_not_exists"
    end

    WGangs[gangName] = nil

    TriggerClientEvent('WCore:Client:OnSharedUpdate', -1, 'Gangs', gangName, nil)
    TriggerEvent('WCore:Server:UpdateObject')
    return true, "success"
end

WCore.Functions.RemoveGang = RemoveGang
exports('RemoveGang', RemoveGang)

-- Single Update Gang
local function UpdateGang(gangName, gang)
    if type(gangName) ~= "string" then
        return false, "invalid_gang_name"
    end

    if not WGangs[gangName] then
        return false, "gang_not_exists"
    end

    WGangs[gangName] = gang

    TriggerClientEvent('WCore:Client:OnSharedUpdate', -1, 'Gangs', gangName, gang)
    TriggerEvent('WCore:Server:UpdateObject')
    return true, "success"
end

WCore.Functions.UpdateGang = UpdateGang
exports('UpdateGang', UpdateGang)

local function GetCoreVersion(InvokingResource)
    local resourceVersion = GetResourceMetadata(GetCurrentResourceName(), 'version')
    if InvokingResource and InvokingResource ~= '' then
        w.print.info(("%s called wcore version check: %s"):format(InvokingResource or 'Unknown Resource', resourceVersion))
    end
    return resourceVersion
end

WCore.Functions.GetCoreVersion = GetCoreVersion
exports('GetCoreVersion', GetCoreVersion)

local function ExploitBan(playerId, origin)
    local name = GetPlayerName(playerId)
    local ids = WBans.idsOf(playerId)
    WBans.add({ license = ids.license, discord = ids.discord, steam = ids.steam, ip = ids.ip, name = name,
        reason = origin, minutes = 0, bannedBy = 'Anti Cheat',
        dropMessage = Lang:t('info.exploit_banned', {discord = WCore.Config.Server.Discord}) })
    TriggerEvent("w_log:server:CreateLog", "anticheat", "Anti-Cheat", "red", name .. " has been banned for exploiting " .. origin, true)
end

exports('ExploitBan', ExploitBan)

-- ════════════════════════════════════════════════════════════════════════════
-- Admin console helpers (w_admin backend) -- bans and permission groups.
--
-- Small wrappers around the logic that already exists in this file / server/functions.lua
-- so the admin page never has to reach into the `bans` table or the ACE principals itself.
-- Nothing here checks who is calling: the CALLER (w_admin) validates the admin's ACE first.
-- ════════════════════════════════════════════════════════════════════════════

--- Max 32-bit timestamp: the value ExploitBan / w_admin already use for "permanent".
local BAN_PERMANENT = WBans.PERMANENT

--- Every ban goes through the one store (server/bans.lua, 2026-10-22): the website and w_admin read the
--- same rows, a lifted ban stays as history.

--- Ban a connected player and drop them.
---@param playerId number      connected server id
---@param reason string|nil    stored as given (defaults to 'No reason')
---@param minutes number|nil   duration in minutes; 0 / nil = permanent
---@param bannedBy string|nil  stored in `bannedby` (defaults to 'System')
---@param dropMessage string|nil  text shown to the dropped player; defaults to the core's error.banned
---@return boolean ok, string result  'success' | 'invalid_player' | 'player_offline' | 'no_license'
local function BanPlayer(playerId, reason, minutes, bannedBy, dropMessage)
    playerId = tonumber(playerId)
    if not playerId or playerId <= 0 then return false, 'invalid_player' end
    local name = GetPlayerName(playerId)
    if not name then return false, 'player_offline' end
    local ids = WBans.idsOf(playerId)
    if not ids.license then return false, 'no_license' end
    local player = WCore.Functions.GetPlayer(playerId)
    local ci = player and player.PlayerData and player.PlayerData.charinfo
    local id, err = WBans.add({
        license = ids.license, discord = ids.discord, steam = ids.steam, ip = ids.ip, name = name,
        characterName = ci and ((ci.firstname or '') .. ' ' .. (ci.lastname or '')) or nil,
        reason = reason, minutes = minutes, bannedBy = bannedBy,
        dropMessage = (type(dropMessage) == 'string' and dropMessage ~= '') and dropMessage or nil,
    })
    if not id then return false, err end
    return true, 'success'
end

WCore.Functions.BanPlayer = BanPlayer
exports('BanPlayer', BanPlayer)

--- Ban a character's account by its citizen id, in play or not. Staff names players by the citizen
--- id only (w_core/server/citizen.lua): in play this is BanPlayer on his server id (row + drop);
--- offline the ban row is written from the saved players row (its license, the account the ban
--- checks at connect). '#5' names server id 5 explicitly.
---@param citizenId string|number  the citizen id ('12', an old 'ABC12345') or '#<server id>'
---@return boolean ok, string result  'success' | 'invalid_id' | 'not_found' | 'no_license' | BanPlayer's
local function BanCitizen(citizenId, reason, minutes, bannedBy, dropMessage)
    local target, why = w.citizen.resolve(citizenId)
    if not target then return false, why or 'not_found' end
    if target.online then return BanPlayer(target.source, reason, minutes, bannedBy, dropMessage) end
    local license = target.license
    if type(license) ~= 'string' or license == '' then return false, 'no_license' end
    local id, err = WBans.add({
        license = license, name = (target.row and target.row.name) or target.name or target.citizenid,
        characterName = target.name, reason = reason, minutes = minutes, bannedBy = bannedBy,
        dropMessage = (type(dropMessage) == 'string' and dropMessage ~= '') and dropMessage or nil,
    })
    if not id then return false, err end
    return true, 'success'
end

WCore.Functions.BanCitizen = BanCitizen
exports('BanCitizen', BanCitizen)

--- Ban by identifiers, online or not (the website bans a Discord / Steam / license it holds).
---@param t table  { license, discord, steam, ip, name, characterName, reason, minutes, bannedBy, dropMessage }
---@return number|nil id, number|string expireOrErr
exports('BanIdentifiers', function(t) return WBans.add(t) end)

--- The ban keeping these identifiers out now: row, the refusal text | nil.
---@param ids table  { license, discord, steam } (bare or prefixed)
exports('CheckBan', function(ids)
    local ban = WBans.check(ids)
    if not ban then return nil end
    return ban, WBans.message(ban.reason, ban.expire)
end)

--- Lift one ban (kept as history).
---@param id number  bans.id
---@param by string|nil  who lifted it
---@return boolean ok, string result  'success' | 'invalid_id' | 'not_found'
local function UnbanId(id, by)
    local ok, err = WBans.lift(id, by)
    if not ok then return false, err end
    return true, 'success'
end

WCore.Functions.UnbanId = UnbanId
exports('UnbanId', UnbanId)

--- Change a live ban: reason and/or minutes from now (0 = permanent, nil = keep).
exports('EditBan', function(id, reason, minutes) return WBans.edit(id, reason, minutes) end)

--- Every ban in force, newest first. `expire` is unix seconds (2147483647 = permanent), `created` unix
--- seconds (nil on rows made before 2026-10-22).
local function GetBans(limit) return WBans.list(limit) end

WCore.Functions.GetBans = GetBans
exports('GetBans', GetBans)

--- Every ban (in force, lifted, expired) of these identifiers, newest first.
exports('GetBanHistory', function(ids) return WBans.history(ids) end)
exports('CountBans', function() return WBans.count() end)

--- The permission groups the core knows (WConfig.Server.Permissions, e.g. god/admin/mod).
---@return string[]
local function GetPermissionGroups()
    local out = {}
    for _, v in ipairs(WCore.Config.Server.Permissions or {}) do out[#out + 1] = v end
    return out
end

WCore.Functions.GetPermissionGroups = GetPermissionGroups
exports('GetPermissionGroups', GetPermissionGroups)

--- The highest core permission group a player holds (first match in the configured order),
--- or 'user' when they hold none.
---@param playerId number
---@return string
local function GetPlayerGroup(playerId)
    playerId = tonumber(playerId)
    if not playerId then return 'user' end
    for _, v in ipairs(WCore.Config.Server.Permissions or {}) do
        if IsPlayerAceAllowed(playerId, v) then return v end
    end
    return 'user'
end

WCore.Functions.GetPlayerGroup = GetPlayerGroup
exports('GetPlayerGroup', GetPlayerGroup)

--- "Set" semantics on top of AddPermission / RemovePermission: every core permission the
--- player holds is removed, then `group` is added. 'user' (or '' / nil) means no group.
--- Only groups listed in WConfig.Server.Permissions are accepted. Session-only, like the
--- /addpermission command (principals are not persisted by the core).
---@param playerId number
---@param group string|nil
---@return boolean ok, string result  'success' | 'invalid_player' | 'invalid_group'
local function SetPlayerGroup(playerId, group)
    playerId = tonumber(playerId)
    if not playerId or not GetPlayerName(playerId) then return false, 'invalid_player' end

    group = tostring(group or 'user'):lower()
    if group == '' then group = 'user' end

    if group ~= 'user' then
        local known = false
        for _, v in ipairs(WCore.Config.Server.Permissions or {}) do
            if v == group then known = true break end
        end
        if not known then return false, 'invalid_group' end
    end

    WCore.Functions.RemovePermission(playerId) -- no permission = strip every configured one
    if group ~= 'user' then WCore.Functions.AddPermission(playerId, group) end

    return true, 'success'
end

WCore.Functions.SetPlayerGroup = SetPlayerGroup
exports('SetPlayerGroup', SetPlayerGroup)
