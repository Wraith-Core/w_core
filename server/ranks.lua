-- ════════════════════════════════════════════════════════════════════════════
-- w_core · server/ranks.lua — staff ranks, kept in the database
--
-- A rank is a row of w_ranks: a name, a label, a colour, an order and a list of permissions (ACE nodes,
-- see server/ranks_catalog.lua). A staff member is a row of w_rank_members per rank he holds (one player
-- may hold several: their permissions add up). Nothing here is checked by the scripts directly: every
-- check in this server ends in IsPlayerAceAllowed, so a rank simply BECOMES ACE --
--
--     add_ace       wrank.<rank> <node> allow                (each permission of the rank)
--     add_principal wrank.<rank> group.<g>                   (a 'group.<g>' permission: joins that group)
--     add_principal identifier.<license:..> wrank.<rank>     (each member)
--
-- -- applied at boot and again the moment the master changes anything. An identifier principal holds
-- across reconnects and works the instant it is added, so no script needs to know ranks exist.
--
-- The master rank (protected, cannot be edited or deleted) holds everything: every level, every command
-- and every catalogue node and script root -- but not by joining group.admin, which permissions.cfg denies
-- the commands that hand out permissions (add_principal, exec, stop...); no other rank may hold those.
-- Only a master manages ranks and hands them out. The first masters come from the convar w_ranks:masters
-- (falls back to w_connector_owners) and are applied on every boot BEFORE the database is read, so the
-- owner can never lock himself out from the panel, nor lose his rights when the database is down.
--
-- ONE system with the website (wraith7.com): w_connector reads and writes these same ranks (a rank's
-- website permissions sit beside its in-game ones, catalogue groups web_*), and the site's 'owner' is
-- the master. A rank tied to a Discord role (discord_role_id) is the site's rank for whoever holds it.
--
-- Exports (every change is checked again here: the actor must be a master or the server console):
--   RanksState()                              -> { ranks, members, catalog }   ranks carry discord (a Discord role id or '')
--   RanksIsMaster(src)                        -> boolean
--   RanksOfPlayer(src)                        -> { rankName, ... }
--   RanksSave(actor, data)                    -> true | false, errKey
--   RanksDelete(actor, name)                  -> true | false, errKey
--   RanksAssign(actor, target, rank)          -> true | false, errKey   target = { source = n } | { identifier = 'license:...', name? }
--   RanksRevoke(actor, identifier, rank)      -> true | false, errKey
--   RanksRevokePlayer(actor, src, rank)       -> true | false, errKey   every identifier of an online player
-- ════════════════════════════════════════════════════════════════════════════

local MASTER = 'master'
local PREFIX = 'wrank.'
local MAX_PERMS = 200

local Ranks = {}      -- [name] = { name, label, color, sort, permissions = {node...}, protected }
local Members = {}    -- [identifier] = { name, ranks = { [rank] = { by, at, locked } } }
local Applied = {}    -- [rank] = { aces = { [node] = true }, parents = { [group] = true } }  what ExecuteCommand added
local ready = false

local function say(level, msg, ...)
    local ok, text = pcall(string.format, msg, ...)
    print(('[w_core] [ranks] %s%s'):format(level == 'error' and '^1' or '', ok and text or msg) .. '^7')
end

-- ── what may reach ExecuteCommand ───────────────────────────────────────────
-- Everything that goes into a console line is checked against these first: no space, no ';', no quote
-- can ever reach add_ace / add_principal, so no value can smuggle a second command.

local function validName(s)
    return type(s) == 'string' and #s >= 2 and #s <= 32 and s:match('^[a-z][a-z0-9_]*$') ~= nil
end

--- Only the characters a console line can take safely (the master's computed list is checked with this)
local function safeNode(s)
    return type(s) == 'string' and #s >= 2 and #s <= 64 and s:match('^[%w_%-%.]+$') ~= nil
        and not s:find('%.%.') and s:sub(1, 1) ~= '.' and s:sub(-1) ~= '.'
end

-- The commands that hand out permissions or run the server: no rank but the master may hold them, and
-- not the bare 'command' either (it holds them all). permissions.cfg denies them to group.admin too.
local FORBIDDEN_COMMANDS = {
    add_ace = true, remove_ace = true, add_principal = true, remove_principal = true, exec = true,
    set = true, sets = true, setr = true, seta = true, ensure = true, start = true, stop = true,
    restart = true, refresh = true, quit = true, rcon_password = true, sv_licensekey = true, steam_webapikey = true,
}

--- May a rank the master builds hold this node? (FXServer lowercases every ACE object: so does this.)
local function validNode(s)
    if not safeNode(s) then return false end
    local low = s:lower()
    -- reserved: the master's node (and its parent 'wranks', which would pass it) and the rank principals
    if low == 'wranks' or low:sub(1, 7) == 'wranks.' or low == 'wrank' or low:sub(1, #PREFIX) == PREFIX then return false end
    if low:sub(1, 6) == 'group.' and not low:match('^group%.[a-z0-9_]+$') then return false end
    if low == 'command' then return false end
    local cmd = low:match('^command%.(.+)$')
    if cmd and (FORBIDDEN_COMMANDS[cmd] or FORBIDDEN_COMMANDS[cmd:match('^([^.]+)') or '']) then return false end
    return true
end

local ID_TYPES = { license = true, license2 = true, steam = true, discord = true, fivem = true, xbl = true, live = true }

local function validIdentifier(s)
    if type(s) ~= 'string' or #s > 100 or s ~= s:lower() then return false end
    local kind, value = s:match('^(%a[%w]*):([%w]+)$')
    return kind ~= nil and ID_TYPES[kind] == true and #value >= 4
end

local function exec(fmt, ...)
    ExecuteCommand(fmt:format(...))
end

-- ── applying a rank as ACE ──────────────────────────────────────────────────

local function permsOf(rank)
    if rank.name ~= MASTER then return rank.permissions end
    -- the master: everything, computed (never stored, so a new catalogue line reaches it at once). It does
    -- NOT join group.god / group.admin: those carry the denies on add_principal, exec, stop... (permissions.cfg),
    -- and the owner keeps them. The levels come as bare ACE (god, admin, mod) and every command as 'command'.
    local all = { 'wranks.master' }
    for _, root in ipairs(RanksMasterRoots or {}) do all[#all + 1] = root end
    for _, node in ipairs(RanksCatalogNodes and RanksCatalogNodes() or {}) do
        -- the catalogue's levels are groups (group.mod...): the master holds their ACE bare instead
        if node:sub(1, 6) ~= 'group.' then all[#all + 1] = node end
    end
    return all
end

local function applyRank(name)
    local rank = Ranks[name]
    local principal = PREFIX .. name
    local old = Applied[name] or { aces = {}, parents = {} }
    local new = { aces = {}, parents = {} }
    if rank then
        for _, node in ipairs(permsOf(rank)) do
            -- the master's list is computed here, not typed: only the console-safe characters are asked of it
            local okNode
            if name == MASTER then okNode = safeNode(node) else okNode = validNode(node) end
            -- the website's permissions (ranks_catalog.lua, web = true) are checked by w_connector by
            -- name, never by ACE: no add_ace for them
            if okNode and RanksWebNodes and RanksWebNodes[node:lower()] then okNode = false end
            if okNode then
                node = node:lower()
                if node:sub(1, 6) == 'group.' then new.parents[node] = true else new.aces[node] = true end
            end
        end
    end
    for node in pairs(old.aces) do if not new.aces[node] then exec('remove_ace %s %s allow', principal, node) end end
    for group in pairs(old.parents) do if not new.parents[group] then exec('remove_principal %s %s', principal, group) end end
    for node in pairs(new.aces) do if not old.aces[node] then exec('add_ace %s %s allow', principal, node) end end
    for group in pairs(new.parents) do if not old.parents[group] then exec('add_principal %s %s', principal, group) end end
    Applied[name] = rank and new or nil
end

local function bindMember(identifier, rank, on)
    if not validIdentifier(identifier) or not validName(rank) then return end
    exec(on and 'add_principal identifier.%s %s%s' or 'remove_principal identifier.%s %s%s', identifier, PREFIX, rank)
end

-- ── the database ────────────────────────────────────────────────────────────

local function decodePerms(raw)
    local ok, list = pcall(json.decode, raw or '[]')
    if not ok or type(list) ~= 'table' then return {} end
    local out, seen = {}, {}
    for _, node in ipairs(list) do
        if validNode(node) then
            node = node:lower()
            if not seen[node] then seen[node] = true out[#out + 1] = node end
        end
    end
    return out
end

local function masterIdentifiers()
    local raw = GetConvar('w_ranks:masters', '')
    if raw == '' then raw = GetConvar('w_connector_owners', '') end
    local out = {}
    for id in raw:gmatch('[^%s,]+') do
        id = id:lower()
        if validIdentifier(id) then out[#out + 1] = id end
    end
    return out
end

local function load()
    -- ★ The master first, from the convar alone, before any query: should the database be down or a query
    --   throw, the owner still holds every permission (no staff ACE is written in permissions.cfg any more).
    Ranks[MASTER] = { name = MASTER, label = 'ماستر', color = '#c8a24a', sort = 1000, permissions = {}, protected = true }
    applyRank(MASTER)
    local masters = masterIdentifiers()
    for _, id in ipairs(masters) do bindMember(id, MASTER, true) end
    if #masters == 0 then
        say('error', 'no valid master in the convar w_ranks:masters (or w_connector_owners): nobody can manage the ranks')
    end

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS w_ranks (
            name VARCHAR(32) NOT NULL PRIMARY KEY,
            label VARCHAR(64) NOT NULL,
            color VARCHAR(16) NOT NULL DEFAULT '#c8a24a',
            sort INT NOT NULL DEFAULT 0,
            permissions LONGTEXT NOT NULL,
            protected TINYINT(1) NOT NULL DEFAULT 0,
            updated_by VARCHAR(100) NULL,
            updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS w_rank_members (
            identifier VARCHAR(100) NOT NULL,
            rank_name VARCHAR(32) NOT NULL,
            name VARCHAR(100) NULL,
            assigned_by VARCHAR(100) NULL,
            assigned_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            locked TINYINT(1) NOT NULL DEFAULT 0,
            PRIMARY KEY (identifier, rank_name),
            KEY rank_name (rank_name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])

    -- the Discord role a rank is tied to: who holds that role on the Discord server holds the rank on the
    -- website (w_connector hands the list to the site, which matches the member's roles against it)
    MySQL.query.await('ALTER TABLE w_ranks ADD COLUMN IF NOT EXISTS discord_role_id VARCHAR(32) NULL')

    -- the master rank always exists
    MySQL.query.await([[
        INSERT IGNORE INTO w_ranks (name, label, color, sort, permissions, protected, updated_by)
        VALUES ('master', 'ماستر', '#c8a24a', 1000, '[]', 1, 'system')
    ]])
    -- the masters of the convar, every boot (locked: the panel cannot take it from them). One taken out
    -- of the convar loses the lock, not the rank: a master in the panel can then take it from him.
    MySQL.query.await('UPDATE w_rank_members SET locked = 0 WHERE locked = 1')
    for _, id in ipairs(masters) do
        MySQL.query.await([[
            INSERT INTO w_rank_members (identifier, rank_name, name, assigned_by, locked) VALUES (?, 'master', NULL, 'config', 1)
            ON DUPLICATE KEY UPDATE locked = 1
        ]], { id })
    end

    for _, row in ipairs(MySQL.query.await('SELECT * FROM w_ranks') or {}) do
        if validName(row.name) then
            Ranks[row.name] = {
                name = row.name, label = tostring(row.label or row.name), color = tostring(row.color or '#c8a24a'),
                sort = tonumber(row.sort) or 0, permissions = decodePerms(row.permissions),
                protected = row.protected == 1 or row.protected == true or row.name == MASTER,
                discord = (row.name ~= MASTER and type(row.discord_role_id) == 'string' and row.discord_role_id:match('^%d+$')) or nil,
            }
        end
    end
    for _, row in ipairs(MySQL.query.await('SELECT * FROM w_rank_members') or {}) do
        local identifier = type(row.identifier) == 'string' and row.identifier:lower() or nil
        if validIdentifier(identifier) and Ranks[row.rank_name] then
            local m = Members[identifier] or { name = row.name, ranks = {} }
            if row.name and row.name ~= '' then m.name = row.name end
            m.ranks[row.rank_name] = { by = row.assigned_by, at = row.assigned_at, locked = row.locked == 1 or row.locked == true }
            Members[identifier] = m
        end
    end

    for name in pairs(Ranks) do applyRank(name) end
    local bound = 0
    for identifier, m in pairs(Members) do
        for rank in pairs(m.ranks) do bindMember(identifier, rank, true) bound = bound + 1 end
    end
    ready = true
    local count = 0
    for _ in pairs(Ranks) do count = count + 1 end
    say('info', '%d rank(s), %d assignment(s) applied', count, bound)
end

CreateThread(function()
    local ok, err = pcall(load)
    if not ok then say('error', 'loading failed: %s', tostring(err)) end
end)

-- ── who is who ──────────────────────────────────────────────────────────────

local function identifiersOf(src)
    local out = {}
    for _, kind in ipairs({ 'license', 'steam', 'discord', 'fivem', 'license2' }) do
        local id = GetPlayerIdentifierByType(src, kind)
        id = type(id) == 'string' and id:lower() or nil
        if id and validIdentifier(id) then out[#out + 1] = id end
    end
    return out
end

local function isMaster(src)
    src = tonumber(src)
    if src == 0 then return true end
    return src ~= nil and IsPlayerAceAllowed(src, 'wranks.master') == true
end

local function actorName(src)
    src = tonumber(src)
    if src == 0 then return 'console' end
    local license = src and GetPlayerIdentifierByType(src, 'license')
    return ('%s (%s)'):format(GetPlayerName(src) or ('#' .. tostring(src)), license or '?')
end

local function onlineByIdentifier()
    local map = {}
    for _, p in ipairs(GetPlayers()) do
        local src = tonumber(p)
        for _, id in ipairs(identifiersOf(src)) do map[id] = src end
    end
    return map
end

-- ── the state the panel draws ───────────────────────────────────────────────

local function state()
    local ranks = {}
    for _, r in pairs(Ranks) do
        local count = 0
        for _, m in pairs(Members) do if m.ranks[r.name] then count = count + 1 end end
        ranks[#ranks + 1] = {
            name = r.name, label = r.label, color = r.color, sort = r.sort, protected = r.protected,
            permissions = r.name == MASTER and { '*' } or r.permissions, members = count, discord = r.discord or '',
        }
    end
    table.sort(ranks, function(a, b) if a.sort ~= b.sort then return a.sort > b.sort end return a.name < b.name end)

    local online = onlineByIdentifier()
    local members = {}
    for identifier, m in pairs(Members) do
        local list, locked = {}, {}
        for rank, info in pairs(m.ranks) do
            list[#list + 1] = rank
            if info.locked then locked[#locked + 1] = rank end
        end
        if #list > 0 then
            table.sort(list)
            local src = online[identifier]
            members[#members + 1] = {
                identifier = identifier, name = (src and GetPlayerName(src)) or m.name or identifier,
                online = src or false, ranks = list, locked = locked,
            }
        end
    end
    table.sort(members, function(a, b) return tostring(a.name):lower() < tostring(b.name):lower() end)
    return { ranks = ranks, members = members, catalog = RanksCatalog or {} }
end

-- ── changes (the master only) ───────────────────────────────────────────────

local function save(actor, data)
    if not ready then return false, 'err_ranks_loading' end
    if not isMaster(actor) then return false, 'no_access' end
    if type(data) ~= 'table' then return false, 'err_invalid_value' end
    local name = type(data.name) == 'string' and data.name:lower() or nil
    if not validName(name) then return false, 'err_rank_name' end
    if name == MASTER or (Ranks[name] and Ranks[name].protected) then return false, 'err_rank_protected' end

    local label = type(data.label) == 'string' and data.label:gsub('[%c]', ''):gsub('^%s+', ''):gsub('%s+$', '') or ''
    -- measured in characters: an Arabic letter is two bytes
    local chars = label ~= '' and utf8.len(label) or nil
    if not chars or chars > 64 then return false, 'err_rank_label' end
    local color = type(data.color) == 'string' and data.color:match('^#%x%x%x%x%x%x$') or '#c8a24a'
    local sort = math.floor(math.min(999, math.max(0, tonumber(data.sort) or 0)))

    if type(data.permissions) ~= 'table' then return false, 'err_invalid_value' end
    local perms, seen = {}, {}
    for _, node in ipairs(data.permissions) do
        if type(node) ~= 'string' or not validNode(node) then return false, 'err_rank_node' end
        node = node:lower()
        if not seen[node] then
            seen[node] = true
            perms[#perms + 1] = node
            if #perms > MAX_PERMS then return false, 'err_rank_too_many' end
        end
    end
    table.sort(perms)

    -- the Discord role: nil keeps the one the rank has (the in-game page does not send it), '' clears it
    local discord = Ranks[name] and Ranks[name].discord or nil
    if data.discord_role_id ~= nil then
        local d = tostring(data.discord_role_id):gsub('%s', '')
        if d == '' then discord = nil
        elseif d:match('^%d+$') and #d <= 32 then discord = d
        else return false, 'err_rank_discord' end
    end

    local ok = pcall(MySQL.query.await, [[
        INSERT INTO w_ranks (name, label, color, sort, permissions, protected, updated_by, discord_role_id) VALUES (?, ?, ?, ?, ?, 0, ?, ?)
        ON DUPLICATE KEY UPDATE label = VALUES(label), color = VALUES(color), sort = VALUES(sort),
            permissions = VALUES(permissions), updated_by = VALUES(updated_by), discord_role_id = VALUES(discord_role_id)
    ]], { name, label, color, sort, json.encode(perms), actorName(actor), discord })
    if not ok then return false, 'err_db' end

    local isNew = Ranks[name] == nil
    Ranks[name] = { name = name, label = label, color = color, sort = sort, permissions = perms, protected = false, discord = discord }
    applyRank(name)
    say('info', '%s %s rank %s (%d permission(s))', actorName(actor), isNew and 'created' or 'edited', name, #perms)
    TriggerEvent('w_core:ranks:changed', 'save', name)
    return true
end

local function delete(actor, name)
    if not ready then return false, 'err_ranks_loading' end
    if not isMaster(actor) then return false, 'no_access' end
    name = type(name) == 'string' and name:lower() or nil
    local rank = validName(name) and Ranks[name] or nil
    if not rank then return false, 'err_rank_unknown' end
    if rank.protected or name == MASTER then return false, 'err_rank_protected' end

    local ok = pcall(function()
        MySQL.query.await('DELETE FROM w_rank_members WHERE rank_name = ?', { name })
        MySQL.query.await('DELETE FROM w_ranks WHERE name = ?', { name })
    end)
    if not ok then return false, 'err_db' end

    for identifier, m in pairs(Members) do
        if m.ranks[name] then
            m.ranks[name] = nil
            bindMember(identifier, name, false)
        end
    end
    Ranks[name] = nil
    applyRank(name)   -- takes every ACE of the rank away
    say('info', '%s deleted rank %s', actorName(actor), name)
    TriggerEvent('w_core:ranks:changed', 'delete', name)
    return true
end

local function assign(actor, target, rank)
    if not ready then return false, 'err_ranks_loading' end
    if not isMaster(actor) then return false, 'no_access' end
    rank = type(rank) == 'string' and rank:lower() or nil
    if not validName(rank) or not Ranks[rank] then return false, 'err_rank_unknown' end
    if type(target) ~= 'table' then return false, 'err_invalid_value' end

    local identifier, name
    if tonumber(target.source) then
        local src = tonumber(target.source)
        if not GetPlayerName(src) then return false, 'err_player_offline' end
        identifier = GetPlayerIdentifierByType(src, 'license')
        identifier = type(identifier) == 'string' and identifier:lower() or nil
        name = GetPlayerName(src)
    elseif type(target.identifier) == 'string' then
        identifier = target.identifier:gsub('%s', ''):lower()
        name = type(target.name) == 'string' and target.name:sub(1, 100) or nil
    end
    if not validIdentifier(identifier) then return false, 'err_rank_identifier' end

    local ok = pcall(MySQL.query.await, [[
        INSERT INTO w_rank_members (identifier, rank_name, name, assigned_by) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE name = COALESCE(VALUES(name), name), assigned_by = VALUES(assigned_by), assigned_at = CURRENT_TIMESTAMP
    ]], { identifier, rank, name, actorName(actor) })
    if not ok then return false, 'err_db' end

    local m = Members[identifier] or { name = name, ranks = {} }
    if name then m.name = name end
    local had = m.ranks[rank] ~= nil
    m.ranks[rank] = m.ranks[rank] or { by = actorName(actor), at = os.time(), locked = false }
    Members[identifier] = m
    if not had then bindMember(identifier, rank, true) end
    say('info', '%s gave rank %s to %s (%s)', actorName(actor), rank, tostring(name or '?'), identifier)
    TriggerEvent('w_core:ranks:changed', 'assign', rank, identifier)
    return true
end

local function revoke(actor, identifier, rank)
    if not ready then return false, 'err_ranks_loading' end
    if not isMaster(actor) then return false, 'no_access' end
    rank = type(rank) == 'string' and rank:lower() or nil
    identifier = type(identifier) == 'string' and identifier:lower() or identifier
    if not validIdentifier(identifier) or not validName(rank) then return false, 'err_invalid_value' end
    local m = Members[identifier]
    local info = m and m.ranks[rank]
    if not info then return false, 'err_rank_not_held' end
    -- a master from the convar stays one: that is what keeps the owner from locking himself out
    if info.locked then return false, 'err_rank_locked' end

    local ok = pcall(MySQL.query.await, 'DELETE FROM w_rank_members WHERE identifier = ? AND rank_name = ?', { identifier, rank })
    if not ok then return false, 'err_db' end
    m.ranks[rank] = nil
    bindMember(identifier, rank, false)
    say('info', '%s took rank %s from %s (%s)', actorName(actor), rank, tostring(m.name or '?'), identifier)
    TriggerEvent('w_core:ranks:changed', 'revoke', rank, identifier)
    return true
end

--- Take a rank from an online player under every identifier he holds it by (a master from the convar is
--- kept by steam:, a rank given in the panel by license:). true when he no longer holds it.
local function revokePlayer(actor, src, rank)
    src = tonumber(src)
    if not src or not GetPlayerName(src) then return false, 'err_player_offline' end
    rank = type(rank) == 'string' and rank:lower() or nil
    local held, lastErr = false, nil
    for _, id in ipairs(identifiersOf(src)) do
        local m = Members[id]
        if m and rank and m.ranks[rank] then
            held = true
            local ok, err = revoke(actor, id, rank)
            if not ok then lastErr = err end
        end
    end
    if not held then return false, 'err_rank_not_held' end
    if lastErr then return false, lastErr end
    return true
end

local function ranksOf(src)
    local out, seen = {}, {}
    for _, id in ipairs(identifiersOf(tonumber(src) or -1)) do
        local m = Members[id]
        for rank in pairs(m and m.ranks or {}) do
            if not seen[rank] then seen[rank] = true out[#out + 1] = rank end
        end
    end
    table.sort(out)
    return out
end

-- a member's name stays current: the panel lists him by the name he plays under
AddEventHandler('playerJoining', function()
    local src = source
    local license = GetPlayerIdentifierByType(src, 'license')
    license = type(license) == 'string' and license:lower() or nil
    local m = license and Members[license]
    local name = GetPlayerName(src)
    if m and name and m.name ~= name then
        m.name = name
        MySQL.update('UPDATE w_rank_members SET name = ? WHERE identifier = ?', { name, license })
    end
end)

exports('RanksState', state)
exports('RanksIsMaster', isMaster)
exports('RanksOfPlayer', ranksOf)
exports('RanksSave', save)
exports('RanksDelete', delete)
exports('RanksAssign', assign)
exports('RanksRevoke', revoke)
exports('RanksRevokePlayer', revokePlayer)

WCore.Ranks = { state = state, isMaster = isMaster, ranksOf = ranksOf, save = save, delete = delete, assign = assign, revoke = revoke,
    revokePlayer = revokePlayer }
