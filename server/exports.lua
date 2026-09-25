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
    MySQL.insert('INSERT INTO bans (name, license, discord, ip, reason, expire, bannedby) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        name,
        WCore.Functions.GetIdentifier(playerId, 'license'),
        WCore.Functions.GetIdentifier(playerId, 'discord'),
        WCore.Functions.GetIdentifier(playerId, 'ip'),
        origin,
        2147483647,
        'Anti Cheat'
    })
    DropPlayer(playerId, Lang:t('info.exploit_banned', {discord = WCore.Config.Server.Discord}))
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
local BAN_PERMANENT = 2147483647

--- Ban a connected player and drop them (same row shape as ExploitBan and w_admin's ban).
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

    local license = WCore.Functions.GetIdentifier(playerId, 'license')
    if not license then return false, 'no_license' end

    minutes = tonumber(minutes) or 0
    if minutes < 0 then minutes = 0 end

    local expire = BAN_PERMANENT
    if minutes > 0 then
        expire = os.time() + math.floor(minutes) * 60
        if expire > BAN_PERMANENT then expire = BAN_PERMANENT end
    end

    reason = tostring(reason or 'No reason'):sub(1, 500)
    bannedBy = tostring(bannedBy or 'System'):sub(1, 255)

    MySQL.insert.await('INSERT INTO bans (name, license, discord, ip, reason, expire, bannedby) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        name,
        license,
        WCore.Functions.GetIdentifier(playerId, 'discord'),
        WCore.Functions.GetIdentifier(playerId, 'ip'),
        reason,
        expire,
        bannedBy,
    })

    TriggerEvent('w_log:server:CreateLog', 'bans', 'Player Banned', 'red',
        ('%s was banned by %s for %s'):format(name, bannedBy, reason), true)

    if type(dropMessage) ~= 'string' or dropMessage == '' then
        local t = os.date('*t', expire)
        local date = ('%s/%s/%s %s:%02d'):format(t.day, t.month, t.year, t.hour, t.min)
        dropMessage = Lang:t('error.banned', { reason = reason, date = date })
    end

    DropPlayer(playerId, dropMessage)
    return true, 'success'
end

WCore.Functions.BanPlayer = BanPlayer
exports('BanPlayer', BanPlayer)

--- Ban a character's account by its citizen id, in play or not. Staff names players by the citizen
--- id only (w_core/server/citizen.lua): in play this is BanPlayer on his server id (row + drop);
--- offline the ban row is written from the saved players row (its license, the account the ban
--- checks at connect), with no discord / ip to add. '#5' names server id 5 explicitly.
---@param citizenId string|number  the citizen id ('12', an old 'ABC12345') or '#<server id>'
---@param reason string|nil
---@param minutes number|nil       0 / nil = permanent
---@param bannedBy string|nil
---@param dropMessage string|nil   only used when the player is in play
---@return boolean ok, string result  'success' | 'invalid_id' | 'not_found' | 'no_license' | BanPlayer's
local function BanCitizen(citizenId, reason, minutes, bannedBy, dropMessage)
    local target, why = w.citizen.resolve(citizenId)
    if not target then return false, why or 'not_found' end
    if target.online then return BanPlayer(target.source, reason, minutes, bannedBy, dropMessage) end

    local license = target.license
    if type(license) ~= 'string' or license == '' then return false, 'no_license' end

    minutes = tonumber(minutes) or 0
    if minutes < 0 then minutes = 0 end
    local expire = BAN_PERMANENT
    if minutes > 0 then
        expire = os.time() + math.floor(minutes) * 60
        if expire > BAN_PERMANENT then expire = BAN_PERMANENT end
    end
    reason = tostring(reason or 'No reason'):sub(1, 500)
    bannedBy = tostring(bannedBy or 'System'):sub(1, 255)
    -- bans.name: the account name the row was saved with, else the character's
    local name = (target.row and target.row.name) or target.name or target.citizenid

    MySQL.insert.await('INSERT INTO bans (name, license, discord, ip, reason, expire, bannedby) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        name, license, nil, nil, reason, expire, bannedBy,
    })
    TriggerEvent('w_log:server:CreateLog', 'bans', 'Player Banned', 'red',
        ('%s [%s] was banned (offline) by %s for %s'):format(name, target.citizenid, bannedBy, reason), true)

    -- the ban is on the account: someone connected with it (on another character) leaves now,
    -- otherwise the ban would only bite at his next connection
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        if src and WCore.Functions.GetIdentifier(src, 'license') == license then
            if type(dropMessage) ~= 'string' or dropMessage == '' then
                local t = os.date('*t', expire)
                dropMessage = Lang:t('error.banned', { reason = reason, date = ('%s/%s/%s %s:%02d'):format(t.day, t.month, t.year, t.hour, t.min) })
            end
            DropPlayer(src, dropMessage)
        end
    end
    return true, 'success'
end

WCore.Functions.BanCitizen = BanCitizen
exports('BanCitizen', BanCitizen)

--- Remove one ban row by its id.
---@param id number  bans.id
---@return boolean ok, string result  'success' | 'invalid_id' | 'not_found'
local function UnbanId(id)
    id = tonumber(id)
    if not id or id <= 0 then return false, 'invalid_id' end

    local affected = MySQL.update.await('DELETE FROM bans WHERE id = ?', { id })
    if not affected or affected == 0 then return false, 'not_found' end

    TriggerEvent('w_log:server:CreateLog', 'bans', 'Player Unbanned', 'green', ('ban #%s removed'):format(id), true)
    return true, 'success'
end

WCore.Functions.UnbanId = UnbanId
exports('UnbanId', UnbanId)

--- Every active ban (expired rows are left alone: the core deletes them on the next join).
--- `expire` is a unix timestamp; 2147483647 means permanent. The table has no `created`
--- column, so `created` is nil -- rows are ordered newest first by id.
---@return { id: number, name: string, license: string, discord: string, ip: string, reason: string, expire: number, bannedby: string, created: nil }[]
local function GetBans()
    local rows = MySQL.query.await('SELECT id, name, license, discord, ip, reason, expire, bannedby FROM bans WHERE expire > ? ORDER BY id DESC', { os.time() })
    return rows or {}
end

WCore.Functions.GetBans = GetBans
exports('GetBans', GetBans)

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
