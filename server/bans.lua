-- ════════════════════════════════════════════════════════════════════════════
-- w_core · server/bans.lua -- THE ban store of the server (2026-10-22: one admin system)
--
-- One table, `bans`, for every ban: w_admin's console, the website (w_connector), ExploitBan and
-- BanCitizen all write here through WBans, and both join gates (w_core's playerConnecting and
-- w_connector's queue) ask WBans.check. Until now the website kept its own wc_bans, so a ban from one
-- side let the player in through the other's records.
--
-- A ban is never deleted: lifting it or its expiry sets active = 0, which is the history the website
-- shows. `expire` is unix seconds; 2147483647 = permanent. Identifiers are kept in their prefixed form
-- (license:… discord:… steam:…). The columns added below are additive only.
-- ════════════════════════════════════════════════════════════════════════════

WBans = { PERMANENT = 2147483647, ready = false }
local PERMANENT = WBans.PERMANENT

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `bans` (
            `id` int(11) NOT NULL AUTO_INCREMENT, `name` varchar(50) DEFAULT NULL, `license` varchar(50) DEFAULT NULL,
            `discord` varchar(50) DEFAULT NULL, `ip` varchar(50) DEFAULT NULL, `reason` text DEFAULT NULL,
            `expire` int(11) DEFAULT NULL, `bannedby` varchar(255) NOT NULL DEFAULT 'System',
            PRIMARY KEY (`id`), KEY `license` (`license`), KEY `discord` (`discord`), KEY `ip` (`ip`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]])
        for _, sql in ipairs({
            'ALTER TABLE `bans` ADD COLUMN IF NOT EXISTS `steam` VARCHAR(64) NULL',
            'ALTER TABLE `bans` ADD COLUMN IF NOT EXISTS `character_name` VARCHAR(100) NULL',
            'ALTER TABLE `bans` ADD COLUMN IF NOT EXISTS `created` INT NULL',
            'ALTER TABLE `bans` ADD COLUMN IF NOT EXISTS `active` TINYINT(1) NOT NULL DEFAULT 1',
            'ALTER TABLE `bans` ADD COLUMN IF NOT EXISTS `unbanned_by` VARCHAR(255) NULL',
            'ALTER TABLE `bans` ADD COLUMN IF NOT EXISTS `unbanned_at` INT NULL',
            'ALTER TABLE `bans` ADD INDEX IF NOT EXISTS `idx_active` (`active`)',
            'ALTER TABLE `bans` ADD INDEX IF NOT EXISTS `idx_steam` (`steam`)',
        }) do MySQL.query.await(sql) end
    end)
    if not ok then print('^1[w_core] bans: schema update failed: ' .. tostring(err) .. '^0') end
    WBans.ready = true
end)

--- An identifier in the form the table keeps: lowercase, prefixed ('discord:123'), or nil.
local function norm(kind, v)
    if v == nil then return nil end
    v = tostring(v):lower():gsub('%s', '')
    if v == '' then return nil end
    if not v:find(':', 1, true) then v = kind .. ':' .. v end
    return v
end
WBans.norm = norm

--- { license, discord, steam } of a connected player (prefixed), from his live identifiers.
function WBans.idsOf(src)
    local out = {}
    for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
        local kind = id:match('^(%w+):')
        if kind == 'license' or kind == 'discord' or kind == 'steam' or kind == 'ip' then out[kind] = id:lower() end
    end
    return out
end

local function where(ids)
    local clauses, values = {}, {}
    local function m(col, v) if v then clauses[#clauses + 1] = ('`%s` = ?'):format(col) values[#values + 1] = v end end
    m('license', norm('license', ids.license))
    m('discord', norm('discord', ids.discord))
    m('steam', norm('steam', ids.steam))
    if #clauses == 0 then return nil end
    return '(' .. table.concat(clauses, ' OR ') .. ')', values
end

--- The ban that keeps these identifiers out right now, or nil. An expired one met on the way is closed
--- (active = 0), never deleted.
function WBans.check(ids)
    local cond, values = where(type(ids) == 'table' and ids or {})
    if not cond then return nil end
    local rows = MySQL.query.await('SELECT `id`, `reason`, `expire`, `bannedby` FROM `bans` WHERE `active` = 1 AND ' .. cond ..
        ' ORDER BY `expire` DESC', values) or {}
    local now = os.time()
    for _, r in ipairs(rows) do
        if (tonumber(r.expire) or 0) > now then return r end
        MySQL.update('UPDATE `bans` SET `active` = 0 WHERE `id` = ?', { r.id })
    end
    return nil
end

--- The text a banned player reads (join refused or dropped).
function WBans.message(reason, expire)
    local t = os.date('*t', tonumber(expire) or PERMANENT)
    return Lang:t('error.banned', { reason = reason or '', date = ('%s/%s/%s %s:%02d'):format(t.day, t.month, t.year, t.hour, t.min) })
end

--- Drop everyone connected under one of these identifiers.
function WBans.drop(ids, message)
    local wanted = {}
    for _, kind in ipairs({ 'license', 'discord', 'steam' }) do
        local v = norm(kind, ids[kind])
        if v then wanted[v] = true end
    end
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        for _, id in ipairs(GetPlayerIdentifiers(src) or {}) do
            if wanted[id:lower()] then DropPlayer(src, message) break end
        end
    end
end

--- Ban by identifiers. t = { license, discord, steam, ip, name, characterName, reason, minutes (0/nil =
--- permanent), bannedBy }. Drops whoever is connected under them. -> id, expire | nil, err
function WBans.add(t)
    t = type(t) == 'table' and t or {}
    local license, discord, steam = norm('license', t.license), norm('discord', t.discord), norm('steam', t.steam)
    if not (license or discord or steam) then return nil, 'no_identifier' end
    local minutes = math.max(0, tonumber(t.minutes) or 0)
    local expire = PERMANENT
    if minutes > 0 then expire = math.min(PERMANENT, os.time() + math.floor(minutes) * 60) end
    local reason = tostring(t.reason or 'No reason'):sub(1, 500)
    local by = tostring(t.bannedBy or 'System'):sub(1, 255)
    local name = t.name and tostring(t.name):sub(1, 50) or nil
    -- only the columns that have a value: a nil in the middle of a parameter list leaves a hole the
    -- driver may read short (a ban without a Discord id is the common case)
    local cols, values = {}, {}
    local function put(col, v) if v ~= nil then cols[#cols + 1] = '`' .. col .. '`' values[#values + 1] = v end end
    put('name', name)
    put('license', license)
    put('discord', discord)
    put('steam', steam)
    put('ip', t.ip and tostring(t.ip):sub(1, 50) or nil)
    put('reason', reason)
    put('expire', expire)
    put('bannedby', by)
    put('character_name', t.characterName and tostring(t.characterName):sub(1, 100) or nil)
    put('created', os.time())
    put('active', 1)
    local id = MySQL.insert.await(('INSERT INTO `bans` (%s) VALUES (%s)'):format(table.concat(cols, ', '),
        ('?, '):rep(#cols - 1) .. '?'), values)
    if not id then return nil, 'database_error' end
    TriggerEvent('w_log:server:CreateLog', 'bans', 'Player Banned', 'red',
        ('%s was banned by %s for %s'):format(name or license or discord or steam, by, reason), true)
    WBans.drop({ license = license, discord = discord, steam = steam }, t.dropMessage or WBans.message(reason, expire))
    return id, expire
end

--- Lift a ban (kept as history). -> true | false, 'not_found'
function WBans.lift(id, by)
    id = tonumber(id)
    if not id or id <= 0 then return false, 'invalid_id' end
    local n = MySQL.update.await('UPDATE `bans` SET `active` = 0, `unbanned_by` = ?, `unbanned_at` = ? WHERE `id` = ? AND `active` = 1',
        { tostring(by or 'System'):sub(1, 255), os.time(), id })
    if (tonumber(n) or 0) == 0 then return false, 'not_found' end
    TriggerEvent('w_log:server:CreateLog', 'bans', 'Player Unbanned', 'green', ('ban #%s lifted by %s'):format(id, tostring(by or 'System')), true)
    return true
end

--- Change a live ban's reason and/or length (minutes from now; 0 = permanent; nil = keep). -> true | false, err
function WBans.edit(id, reason, minutes)
    id = tonumber(id)
    if not id or id <= 0 then return false, 'invalid_id' end
    local sets, values = {}, {}
    if reason ~= nil then sets[#sets + 1] = '`reason` = ?' values[#values + 1] = tostring(reason):sub(1, 500) end
    if minutes ~= nil then
        minutes = math.max(0, tonumber(minutes) or 0)
        sets[#sets + 1] = '`expire` = ?'
        values[#values + 1] = minutes > 0 and math.min(PERMANENT, os.time() + math.floor(minutes) * 60) or PERMANENT
    end
    if #sets == 0 then return false, 'nothing_to_change' end
    values[#values + 1] = id
    local n = MySQL.update.await('UPDATE `bans` SET ' .. table.concat(sets, ', ') .. ' WHERE `id` = ? AND `active` = 1', values)
    if (tonumber(n) or 0) == 0 then return false, 'not_found' end
    return true
end

local COLS = '`id`, `name`, `license`, `discord`, `steam`, `ip`, `reason`, `expire`, `bannedby`, `character_name`, `created`, ' ..
    '`active`, `unbanned_by`, `unbanned_at`'

--- Every ban in force, newest first.
function WBans.list(limit)
    return MySQL.query.await('SELECT ' .. COLS .. ' FROM `bans` WHERE `active` = 1 AND `expire` > ? ORDER BY `id` DESC LIMIT ?',
        { os.time(), tonumber(limit) or 1000 }) or {}
end

--- Every ban (in force, lifted or expired) of these identifiers, newest first.
function WBans.history(ids)
    local cond, values = where(type(ids) == 'table' and ids or {})
    if not cond then return {} end
    return MySQL.query.await('SELECT ' .. COLS .. ' FROM `bans` WHERE ' .. cond .. ' ORDER BY `id` DESC LIMIT 200', values) or {}
end

function WBans.count()
    return tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM `bans` WHERE `active` = 1 AND `expire` > ?', { os.time() })) or 0
end
