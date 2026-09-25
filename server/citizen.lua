-- ════════════════════════════════════════════════════════════════════════════
-- w_core · server/citizen.lua — the citizen id: sequential, stable, the one id staff works with
--
-- ═══ The id ═══
--   A new character gets the next free number: 1, 2, 3 ... (WCore.Citizen.Next). It is stored as a
--   STRING of digits in players.citizenid, the same column and type as before, so every resource
--   that compares, concatenates or length-checks it keeps working. A number an admin handed out
--   ("vanity": 7, 100, 777) is simply skipped by the counter.
--   A number is USED while a character holds it or anything is still filed under it (used()).
--   Deleting a character (Purge) and moving it to another number (Reassign) both leave the number
--   clean, so staff can hand it to another character at once (a vanity id that was not renewed).
--   w_core_citizen_map only records what happened (migration, reassign, deleted); it never
--   decides whether a number is free.
--
-- ═══ Staff never types a server id ═══
--   WCore.Citizen.Resolve(id) -> { citizenid, source? } : online = the live server id, offline = the
--   saved row. w_admin runs every action through it; an offline character gets the offline path.
--
-- ═══ Moving a character to another id (a vanity id, the migration) ═══
--   WCore.Citizen.Reassign(old, new): the character must be offline. Every place the id lives is
--   rewritten in ONE transaction, its history included (the old number is left clean):
--     EXACT      columns that hold the id as their whole value            (REGISTRY.exact)
--     SHAPED     columns that embed it in a known shape (player:<id>:cash) (REGISTRY.shaped)
--   ⚠️ A numeric id is ambiguous inside free data ("3" is also a count, a horse, a house), so a
--      reassign NEVER searches blindly: only the registry's columns and shapes are touched. The
--      one-time migration of the old random ids (3 letters + 5 digits, unmistakable) also sweeps
--      every text column of the database for them (Migrate), and reports what it rewrote.
--   While w_centralbank runs, the ledger renames the character's accounts itself, under its own
--   lock and in the same transaction (RenameCharacterAccounts): a transfer it plans from memory
--   never meets an account renamed behind its back. The migration does the same, one character
--   (one transaction) at a time.
--
-- ═══ Handing a number to another character (TransferNumber) ═══
--   WCore.Citizen.TransferNumber(n, target, by): the character holding n moves to a fresh number
--   (Next) with everything it has, then the target character moves onto n with everything it has
--   (its old number is left clean). Both are kicked if in play. Two moves, the holder's first: if
--   the second cannot be done, the holder keeps its new number and the answer says n has no holder.
--
-- ═══ Deleting a character (staff, or the player from the character selection) ═══
--   WCore.Citizen.Purge(id, by): the player is kicked and its logout save awaited, then every
--   resource removes what it keeps for the character through its own PurgeCharacter export
--   (PURGE_ORDER; w_centralbank last: it returns every balance to the reserve), and w_core ends
--   with one transaction over the registry: leftover own rows are deleted, history (logs, the
--   ledger journal) is moved OFF the number to a tombstone 'deleted-<id>-<unixtime>', the players
--   row goes. Afterwards nothing is filed under the number any more; if a late write still left
--   something, the answer says so (report.clean = false) and one automatic retry runs 30 s later.
--
-- ═══ Blocked characters ═══
--   w_core_character_blocks: the character cannot be played ("contact the administration"); the
--   account's other characters can. Checked by w_creators before the login and by Login itself.
-- ════════════════════════════════════════════════════════════════════════════
WCore.Citizen = {}
local C = WCore.Citizen

local OLD_FORMAT = '^%u%u%u%d%d%d%d%d$'
-- ⚠️ a number from the database may arrive as a float (3.0): an id is always written as '%d'
local function idOf(n) return ('%d'):format(math.floor(tonumber(n) or 0)) end
local MAX_DIGITS = 9

-- ── one collation for the ids (utf8mb4_general_ci) ──────────────────────────
-- players.citizenid and the tables that store an id are utf8mb4_general_ci. MySQL refuses "="
-- between two columns of different implicit collations ("Illegal mix of collations"), so a table
-- left in another one breaks every JOIN or IN (SELECT ...) that meets players: w_admin's list of
-- blocked characters failed that way. The CREATE statements name the collation now; this converts
-- a table created before them, once (information_schema shows nothing left to do on the next
-- start). keep = { [table] = { [column] = 'its definition' } }: a column binary on purpose (JSON)
-- is put back after the conversion. A table is left as it is, with the reason printed, when a
-- unique key would merge two of its values under the new collation (the ALTER would stop on a
-- duplicate key, or two ids would become one) or when it holds a binary column nobody named.
local ID_COLLATION = 'utf8mb4_general_ci'
local function alignCollation(db, tag, tables, keep)
    keep = keep or {}
    for _, t in ipairs(tables) do
        local ok, err = pcall(function()
            local current = db.scalar.await('SELECT TABLE_COLLATION FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { t })
            if not current then return end
            local kept, todo, binary, needed = keep[t] or {}, {}, nil, current ~= ID_COLLATION
            for _, c in ipairs(db.query.await('SELECT COLUMN_NAME AS n, COLLATION_NAME AS k FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLLATION_NAME IS NOT NULL', { t }) or {}) do
                if c.k ~= ID_COLLATION and not kept[c.n] then
                    todo[c.n], needed = true, true
                    if c.k:sub(-4) == '_bin' then binary = c.n end
                end
            end
            if not needed then return end
            if binary then error(('column %s is binary and nobody said to keep it'):format(binary), 0) end
            -- every unique key holding a converted column, grouped the way the new collation compares
            local keys = {}
            for _, s in ipairs(db.query.await('SELECT INDEX_NAME AS i, COLUMN_NAME AS n, SUB_PART AS p FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND NON_UNIQUE = 0 ORDER BY INDEX_NAME, SEQ_IN_INDEX', { t }) or {}) do
                local key = keys[s.i] or { by = {}, set = {} }
                keys[s.i] = key
                local e = ('`%s`'):format(s.n)
                if todo[s.n] then e, key.text = ('CONVERT(`%s` USING utf8mb4) COLLATE %s'):format(s.n, ID_COLLATION), true end
                if tonumber(s.p) then e = ('LEFT(%s, %d)'):format(e, tonumber(s.p)) end
                key.by[#key.by + 1], key.set[#key.set + 1] = e, ('`%s` IS NOT NULL'):format(s.n)
            end
            for name, key in pairs(keys) do
                if key.text and (tonumber(db.scalar.await(('SELECT COUNT(*) FROM (SELECT 1 FROM `%s` WHERE %s GROUP BY %s HAVING COUNT(*) > 1) d')
                    :format(t, table.concat(key.set, ' AND '), table.concat(key.by, ', ')))) or 0) > 0 then
                    error(('unique key %s would merge two of its values'):format(name), 0)
                end
            end
            db.query.await(('ALTER TABLE `%s` CONVERT TO CHARACTER SET utf8mb4 COLLATE %s'):format(t, ID_COLLATION))
            for _, def in pairs(kept) do db.query.await(('ALTER TABLE `%s` MODIFY %s'):format(t, def)) end
            print(('^3[%s] %s converted to %s^0'):format(tag, t, ID_COLLATION))
        end)
        if not ok then print(('^1[%s] %s keeps its collation: %s^0'):format(tag, t, tostring(err))) end
    end
end

-- ── the schema ─────────────────────────────────────────────────────────────
local ready = false
CreateThread(function()
    local statements = {
        [[CREATE TABLE IF NOT EXISTS `w_core_citizen_seq` (
            `k` VARCHAR(16) NOT NULL, `v` INT NOT NULL DEFAULT 0, PRIMARY KEY (`k`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]],
        [[CREATE TABLE IF NOT EXISTS `w_core_character_blocks` (
            `citizenid` VARCHAR(64) NOT NULL, `reason` VARCHAR(255) NULL, `blocked_by` VARCHAR(96) NULL,
            `blocked_at` INT NOT NULL DEFAULT 0, PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]],
        [[CREATE TABLE IF NOT EXISTS `w_core_citizen_map` (
            `id` INT NOT NULL AUTO_INCREMENT, `old_id` VARCHAR(64) NOT NULL, `new_id` VARCHAR(64) NOT NULL,
            `kind` VARCHAR(16) NOT NULL, `done_by` VARCHAR(96) NULL, `done_at` INT NOT NULL,
            PRIMARY KEY (`id`), KEY `old_id` (`old_id`), KEY `new_id` (`new_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]],
    }
    for _, sql in ipairs(statements) do
        local ok, err = pcall(MySQL.query.await, sql)
        if not ok then print('^1[w_core] citizen tables: ' .. tostring(err)) return end
    end
    -- the three above were utf8mb4_unicode_ci before (any JOIN of them with players failed);
    -- players and bans come from wcore.sql and are the reference the other tables are compared to
    alignCollation(MySQL, 'w_core', { 'players', 'bans', 'w_core_citizen_seq', 'w_core_character_blocks', 'w_core_citizen_map' })
    ready = true
end)

-- ── ids ────────────────────────────────────────────────────────────────────
--- The canonical form of an id typed by staff or sent by a page: '12' (a string of digits, no
--- leading zero). A number becomes its string. The old random form is accepted too (upper case).
function C.Normalize(value)
    if type(value) == 'number' then
        if value ~= value or value < 1 or value % 1 ~= 0 then return nil end
        value = ('%d'):format(value)
    end
    if type(value) ~= 'string' then return nil end
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if value:match('^[1-9]%d*$') and #value <= MAX_DIGITS then return value end
    local up = value:upper()
    if up:match(OLD_FORMAT) then return up end
    return nil
end

--- May this id be handed out as a new id (digits, 1..999999999)?
function C.IsNumeric(value)
    return type(value) == 'string' and value:match('^[1-9]%d*$') ~= nil and #value <= MAX_DIGITS
end

local function onlineWith(citizenid)
    for src, p in pairs(WCore.Players) do
        if p and p.PlayerData and p.PlayerData.citizenid == citizenid then return src, p end
    end
    return nil
end

local function exists(citizenid)
    if onlineWith(citizenid) then return true end
    return (MySQL.scalar.await('SELECT COUNT(*) FROM players WHERE citizenid = ?', { citizenid }) or 0) > 0
end
C.Exists = exists

-- ── ids being worked on ────────────────────────────────────────────────────
-- [citizenid] = true while a purge or a reassign works on it: the character is not logged in
-- meanwhile (Login asks IsBusy), no second purge or reassign starts on it, the counter skips it.
local busy = {}
-- [citizenid] = GetGameTimer() deadline: a number whose character was just purged, or just moved
-- to another number (Reassign, TransferNumber). A players-row save still in flight for it (an
-- offline Player object another resource holds, a late logout save) would bring the row back
-- under that number (INSERT ... ON DUPLICATE KEY UPDATE): player.lua skips such saves, and the
-- counter does not hand the number out while the guard holds. A reassign onto the number lifts it
-- (staff gives the number to another character on purpose).
local purgedGuard = {}
local PURGED_GUARD_MS = 10 * 60 * 1000
-- [players.id] = true: the rows purges deleted, for the whole session. A Player object of a deleted
-- character keeps the row id it was loaded with: its save never lands, not even once staff gave the
-- number to someone else (its ON DUPLICATE KEY UPDATE would overwrite that character's row), and
-- it is never put in play (a login that read the row just before the purge deleted it).
local purgedRows = {}
-- [players.id] = the number the row holds since a reassign or a transfer moved it (this session).
-- A Player object loaded before the move still carries the old number: its save would write a
-- ghost row under that number (players is keyed by citizenid), or, once staff gave the number to
-- someone else, overwrite that character's row. Such an object neither saves nor is put in play;
-- one loaded after the move (the row's current number) does both.
local movedRows = {}

function C.IsBusy(citizenid) return citizenid ~= nil and busy[citizenid] == true end

function C.SaveBlocked(citizenid)
    local deadline = citizenid and purgedGuard[citizenid]
    if not deadline then return false end
    if GetGameTimer() > deadline then purgedGuard[citizenid] = nil return false end
    return true
end

--- Was this players row (players.id) deleted by a purge this session?
function C.RowPurged(rowId)
    rowId = tonumber(rowId)
    return rowId ~= nil and purgedRows[math.floor(rowId)] == true
end

--- Is this a stale copy of a moved players row: the row (players.id) was moved to another number
--- this session, and `citizenid` is not the number it holds now?
function C.RowMoved(rowId, citizenid)
    rowId = tonumber(rowId)
    if rowId == nil then return false end
    local now = movedRows[math.floor(rowId)]
    return now ~= nil and now ~= citizenid
end

-- ── where the id lives ─────────────────────────────────────────────────────
-- EXACT: the whole value of the column is the id. `kind`:
--   'data'    the character's own rows: deleted with it;
--   'asset'   something it owns that others see (a house, a store, a bank...): its resource
--             RELEASES it in its own PurgeCharacter (back to unowned / the government). A row
--             still there when w_core's own pass runs refuses the deletion, never a raw delete
--             of a shared world row. `release` = an SQL SET clause w_core applies itself, only
--             for a resource without a PurgeCharacter of its own that is not running (`owner`:
--             it loads the row from the database when it starts, so no copy in memory is stale).
--             `res`: the resource whose PurgeCharacter releases it. While that resource is not
--             started nothing can release it, and the purge refuses BEFORE anyone is kicked or any
--             resource purged (never half way, after the others released theirs);
--   'history' logs and journals: kept, moved to the tombstone by a deletion, renamed by a reassign;
--   'core'    players, and the ledger accounts (w_centralbank empties and deletes them itself;
--             one found later goes back to its purge; w_core deletes an account row itself only
--             while no ledger runs, and only at balance 0, `money`).
-- 4th field: an SQL filter. A row counts as `kind` only while it holds, the rest is history (a
-- paid loan, a closed case, a settled order: the bank and the market keep them forever).
-- `where`: rows outside it are not about a character at all (a tribe's treasury account is owned
-- by the tribe's id, and a number such as '3' is both a tribe and a character).
local EXACT = {
    { 'players', 'citizenid', 'core' },
    -- w_banking
    { 'bank_accounts', 'citizenid', 'data' }, { 'bank_statements', 'citizenid', 'history' },
    -- w_centralbank: the character's own accounts; a store's till and a bank's capital belong to the
    -- store and the bank (w_store and w_centralbank hand them to the government, never deleted here)
    { 'cb_accounts', 'owner', 'core', where = "`kind` NOT IN ('tribe', 'store', 'bank_capital')", money = 'balance' },
    -- (the ledger's purge hands both to the government, whatever w_store does: CB.characterAccount 'institution')
    { 'cb_accounts', 'owner', 'asset', where = "`kind` IN ('store', 'bank_capital')", res = 'w_centralbank' },
    { 'cb_staff', 'citizenid', 'data' }, { 'cb_staff', 'hired_by', 'history' },
    { 'cb_banks', 'owner', 'asset', res = 'w_centralbank' }, { 'cb_requests', 'borrower', 'data' }, { 'cb_requests', 'offered_by', 'history' },
    { 'cb_loans', 'borrower', 'asset', 'remaining > 0', res = 'w_centralbank' },
    { 'cb_cases', 'borrower', 'asset', "status <> 'closed'", res = 'w_centralbank' }, { 'cb_journal', 'actor', 'history' },
    -- w_inventory (the custody record and the market receipt are kept, under the tombstone: the
    -- items in custody belong to the bank, and a receipt stops an old claim from being delivered twice)
    { 'w_inventory', 'owner', 'data' }, { 'w_inventory_market_receipts', 'citizenid', 'history' },
    { 'w_inventory_debt_custody', 'citizenid', 'history' },
    { 'player_weapons', 'citizenid', 'data' },
    -- w_creators, w_hud
    { 'characters_appearence', 'charid', 'data' }, { 'w_creators_clothes', 'charid', 'data' }, { 'w_creators_outfits', 'charid', 'data' },
    { 'w_creators_colorways', 'charid', 'data' },
    { 'w_hud_needs', 'cid', 'data' }, { 'w_hud_satchels', 'cid', 'data' }, { 'w_hud_settings', 'cid', 'data' }, { 'telegrams', 'citizenid', 'data' },
    -- w_housing
    { 'w_housing_houses', 'owner', 'asset', res = 'w_housing' }, { 'w_housing_purchases', 'owner', 'history' }, { 'w_housing_furniture', 'owner', 'data' },
    { 'w_housing_keys', 'citizenid', 'data' }, { 'w_housing_seizures', 'previous_owner', 'history' },
    -- w_legal
    { 'w_legal_cooldowns', 'char_id', 'data' }, { 'w_legal_jobs', 'char_id', 'data' }, { 'w_legal_stats', 'char_id', 'data' },
    { 'w_legal_wallet', 'char_id', 'data' }, { 'w_legal_settings', 'updated_by', 'history' },
    -- w_logs
    { 'w_logs_entries', 'char_id', 'history' }, { 'w_logs_entries', 'identifier', 'history' },
    { 'w_logs_entries', 'target_char_id', 'history' }, { 'w_logs_entries', 'target_identifier', 'history' },
    { 'w_logs_players', 'char_id', 'history' }, { 'w_logs_players', 'identifier', 'history' },
    -- w_marketplace: an unpaid refund (refund = 0) and a claimed order still owe money
    { 'w_market_selling', 'charid', 'asset', res = 'w_marketplace' }, { 'w_market_selling', 'identifier', 'asset', res = 'w_marketplace' },
    { 'w_market_shopsdata', 'charid', 'data' },
    { 'w_market_payments', 'charid', 'asset', 'refund = 0', res = 'w_marketplace' }, { 'w_market_pending', 'charid', 'data' },
    { 'w_market_log', 'charid', 'history' }, { 'w_market_log', 'party', 'history' },
    { 'w_market_avatars', 'charid', 'data' },
    { 'w_market_orders', 'seller', 'asset', "state = 'claimed'", res = 'w_marketplace' },
    { 'w_market_orders', 'buyer', 'asset', "state = 'claimed'", res = 'w_marketplace' },
    { 'w_market_deliveries', 'charid', 'data' }, { 'w_market_bid_intents', 'charid', 'data' }, { 'w_market_listing_intents', 'charid', 'data' },
    -- w_pets, w_stables (horses and wagons are the character's own: deleted by their purge)
    { 'w_pets', 'citizenid', 'data' },
    { 'stables', 'charidentifier', 'data' }, { 'w_stables_businesses', 'owner_charid', 'asset', res = 'w_stables' }, { 'w_stables_employees', 'charid', 'data' },
    { 'w_stables_employees', 'hired_by', 'history' }, { 'w_stables_transactions', 'charid', 'history' }, { 'w_stables_history', 'charid', 'history' },
    -- ⚠️ w_stables_audit.target is NOT registered: it holds horse and wagon ids as well as charids
    --    (w_stables moves its character targets to the tombstone itself)
    { 'w_stables_orders', 'ordered_by', 'history' }, { 'w_stables_audit', 'actor', 'history' }, { 'w_stables_stables', 'updated_by', 'history' },
    { 'w_stables_config', 'updated_by', 'history' },
    -- w_store
    { 'w_store_stores', 'owner_char', 'asset', res = 'w_store' }, { 'w_store_employees', 'char_id', 'data' }, { 'w_store_orders', 'created_by', 'history' },
    { 'w_store_orders', 'closed_by', 'history' }, { 'w_store_ledger', 'actor_char', 'history' },
    -- w_tribes
    { 'tribes', 'boss_citizenid', 'asset', res = 'w_tribes' }, { 'tribe_members', 'citizenid', 'data' }, { 'tribe_rewards_claimed', 'citizenid', 'data' },
    { 'tribe_fences', 'placed_by', 'history' }, { 'tribe_quest_daily', 'citizenid', 'data' }, { 'tribe_player_strikes', 'citizenid', 'data' },
    { 'tribe_wars', 'declared_by', 'history' }, { 'tribe_election_votes', 'voter', 'data' },
    -- w_baloot (w_baloot_tables.created_by is the account's NAME, not a character id)
    { 'w_baloot_players', 'identifier', 'data' },
    -- w_butcher (its PurgeCharacter deletes them; bp_Butcher's bp_butcher_relations below until w_butcher renames it)
    { 'w_butcher_relations', 'citizenid', 'data' },
    -- resources without a PurgeCharacter of their own
    { 'bp_butcher_relations', 'citizenid', 'data' }, { 'mdt_records', 'citizenid', 'history' }, { 'mdt_warrants', 'target_citizenid', 'history' },
    -- w_kingdom_v2 deposes a king by storing '' (Store.SeatKing)
    { 'wk2_kingdoms', 'king_charid', 'asset', release = "`king_charid` = '', `king_name` = ''", owner = 'w_kingdom_v2' },
    { 'wk2_places', 'updated_by', 'history' },
    { 'w_core_character_blocks', 'citizenid', 'data' },
    -- w_admin: the admin log (the staff member who acted, and the character it was done to)
    { 'w_admin_log', 'admin_cid', 'history' }, { 'w_admin_log', 'target_cid', 'history' },
    -- w_lib w.settings (the live settings w_admin edits): who changed a value, who is in the audit, who saved a preset
    { 'w_admin_settings', 'updated_by', 'history' }, { 'w_admin_settings_audit', 'actor_cid', 'history' },
    { 'w_admin_settings_presets', 'created_by', 'history' },
}
-- SHAPED: the id inside a known shape. Lua patterns; %s is the (escaped) id. Anchored shapes only:
-- a numeric id is never replaced where it merely appears ("7" is also an amount or a store). The
-- JSON shapes carry their quotes, which anchor them the same way.
-- A stash's cash lives in the ledger account 'inventory:stash:<identifier>:cash' (w_inventory
-- economy.lua): every stash shape of `inventories` has its account shape here, so the two move
-- together. Stable keys are [a-z0-9_] (w_stables admin), hence [%w_]+ and not %a+.
-- `filter` (SQL), `where` (SQL), `money` and `res` as in EXACT: `where` scopes a generic key ("from",
-- "value") to the rows that hold a character id under it, so a horse named "12" is not history of
-- character 12. `whole`: the deletion replaces the whole value with the tombstone instead of the
-- id inside it ('<id>|<id>' twice would not fit its VARCHAR(50)).
local LEGACY_CRAFT = '^license:%x+|%s$' -- w_crafting before the ids were numbers: '<license>|<id>'
local CRAFT = { '^%s|%s$', '^%s$', LEGACY_CRAFT }
local SHAPED = {
    -- w_centralbank: the character's own accounts (a store till and a bank's capital are the
    -- store's and the bank's, filed by owner, relabelled by their purge)
    { 'cb_accounts', 'id', { '^player:%s:', '^marketplace:%s:', '^legal:%s$', '^legal:%s:', '^bench:.+:%s$', '^bench:.+:%s:gold$',
                             '^inventory:stash:stable_[%w_]+_%s:', '^inventory:stash:policestash_%s:', '^inventory:stash:ambulancestash_%s:',
                             '^inventory:stash:[^:]+:%s:' }, 'core', money = 'balance' },
    -- an open loan is counted by cb_loans.borrower (filtered above); the account name is history
    { 'cb_loans', 'borrower_account', { '^player:%s:' }, 'history' },
    -- the journal: its request keys (the bank panel's '<id>:<action>:<key>', a collection names the
    -- account it collected from), the accounts inside each movement, a housing reason
    { 'cb_journal', 'request_key', { '^%s:', '^starter:%s:', '^bank:%s:', '^tribe%-quest:%s:',
                                     '^housing:purchase:%s:', '^housing:refund:%s:', '^housing:sweep:%s:',
                                     '^collect:%d+:%d+:player:%s:', '^collect:%d+:%d+:marketplace:%s:',
                                     '^collect:%d+:%d+:legal:%s$', '^collect:%d+:%d+:legal:%s:',
                                     '^collect:%d+:%d+:bench:.+:%s$', '^collect:%d+:%d+:bench:.+:%s:gold$',
                                     '^collect:%d+:%d+:inventory:stash:stable_[%w_]+_%s:',
                                     '^collect:%d+:%d+:inventory:stash:policestash_%s:',
                                     '^collect:%d+:%d+:inventory:stash:ambulancestash_%s:',
                                     '^collect:%d+:%d+:inventory:stash:[^:]+:%s:' }, 'history' },
    { 'cb_journal', 'movements', { '"player:%s:', '"marketplace:%s:', '"legal:%s"', '"legal:%s:',
                                   '"bench:[^"]+:%s"', '"bench:[^"]+:%s:gold"',
                                   '"inventory:stash:stable_[%w_]+_%s:', '"inventory:stash:policestash_%s:',
                                   '"inventory:stash:ambulancestash_%s:', '"inventory:stash:[^:"]+:%s:' }, 'history' },
    { 'cb_journal', 'reason', { '^Housing purchase %s:' }, 'history' },
    { 'cb_assets', 'payload', { '"owner":"%s"' }, 'history' },
    -- w_banking: '<id>:<kind>:<key>', a received transfer '<receiver>:Received-<payer>:<key>'
    { 'bank_statements', 'request_key', { '^%s:', ':Received%-%s:' }, 'history' },
    -- w_housing: the purchase token '<cid>:<requestId>' is the purchase row's id, its sweep's id,
    -- a reserved house's marker and part of the ledger keys above: all of them move together, in
    -- the same transaction, so a replay after a reassign still finds its own journal row
    { 'w_housing_purchases', 'account', { '^player:%s:' }, 'history' },
    { 'w_housing_purchases', 'id', { '^%s:' }, 'history' },
    { 'w_housing_sweeps', 'purchase_id', { '^%s:' }, 'history' },
    -- history, not data: a piece of furniture may belong to someone else by now
    { 'w_housing_furniture', 'purchase_id', { '^%s:' }, 'history' },
    { 'w_housing_houses', 'reserved_by', { '^%s$', '^%s:' }, 'asset', res = 'w_housing' },
    { 'w_housing_seizures', 'snapshot', { '"previousOwner":"%s"', '"owner":"%s"', '"purchase_id":"%s:' }, 'history' },
    -- w_inventory: '<stash>:<owner>' (an owner-scoped stash); a debt custody stash is the bank's
    { 'inventories', 'identifier', { '^stable_[%w_]+_%s$', '^policestash_%s$', '^ambulancestash_%s$', '^[^:]+:%s$' }, 'data' },
    { 'inventories', 'identifier', { '^__w_debt:%s:' }, 'history' },
    { 'w_inventory_market_receipts', 'request', { '"owner":"%s"' }, 'history' },
    -- w_stables: per-character limit overrides (a whole key or a sub-key)
    { 'w_stables_config', 'key', { '^Limits%.perChar%.%s$', '^Limits%.perChar%.%s%.' }, 'data' },
    { 'w_stables_history', 'meta', { '"from":"%s"', '"by":"%s"' }, 'history' },
    { 'w_stables_audit', 'payload', { '"charid":"%s"', '"previous":"%s"', '"owner":"%s"' }, 'history' },
    -- an admin transfer or unstock stores the charid staff typed as "value" (admin.lua
    -- resolveCharacter; other actions: a name, a level); business:owner's "target" is a server id
    -- (a JSON number), never a character
    { 'w_stables_audit', 'payload', { '"value":"%s"' }, 'history',
      where = "`action` IN ('horse:transfer', 'wagon:transfer', 'horse:unstock', 'wagon:unstock')" },
    -- w_store: a buyback still unfinished ('preparing', 'taking', 'settling') owes the character its
    -- share, which w_store's loop pays to the account this row names: it is w_store's to settle (its
    -- purge does), never tombstoned while that payout is still to come (it would go to a tombstone
    -- account); only a complete one is history. A move takes both along (the share follows its owner).
    { 'w_store_buyback_settlements', 'player_account', { '^player:%s:' }, 'asset', filter = "`status` <> 'complete'", res = 'w_store' },
    { 'w_store_ledger', 'detail', { '"charId":"%s"' }, 'history' },
    -- a shelf snapshot: the owner, the orders' authors, the staff (a map keyed by character id)
    { 'w_store_stock_history', 'snapshot', { '"ownerChar":"%s"', '"created_by":"%s"', '"closed_by":"%s"', '"charId":"%s"', '"%s":{' }, 'history' },
    -- w_crafting: '<id>|<id>', the bare id, or the legacy '<license>|<id>'
    { 'bp_craft_known', 'citizenid', CRAFT, 'data' },
    { 'bp_craft_earnings', 'citizenid', CRAFT, 'data' },
    { 'bp_craft_player_levels', 'citizenid', CRAFT, 'data' },
    { 'bp_craft_table_access', 'citizenid', CRAFT, 'data' },
    { 'bp_craft_table_access', 'added_by', CRAFT, 'history', whole = true },
    { 'bp_craft_workbenches', 'placed_by', CRAFT, 'history', whole = true },
    { 'bp_craft_workbenches', 'owner_citizenid', CRAFT, 'asset', res = 'w_crafting' },
    -- w_citizens: '<id>:<id>', or the legacy '<license>:<id>'
    { 'w_citizen_reputation', 'character_id', { '^%s:%s$', '^license:%x+:%s$' }, 'data' },
    -- w_marketplace: a standing top bid holds money in escrow; an open bid intent may still owe
    -- this character its outbid refund; order payloads carry the listing (escaped JSON inside)
    { 'w_market_selling', 'offerdata', { '"charid":"%s"' }, 'asset', res = 'w_marketplace' },
    { 'w_market_orders', 'payload', { '"charid":"%s"', '"identifier":"%s"', '\\"charid\\":\\"%s\\"' }, 'asset', filter = "state = 'claimed'", res = 'w_marketplace' },
    { 'w_market_bid_intents', 'payload', { '"charid":"%s"', '\\"charid\\":\\"%s\\"' }, 'asset', filter = "state NOT IN ('done','canceled')", res = 'w_marketplace' },
    -- w_logs
    { 'w_logs_entries', 'transaction_id', { '^wcdel%-%s%-' }, 'history' },
    { 'w_logs_entries', 'payload', { '"charid":"%s"' }, 'history' },
    -- w_creators' character_switch_lapsed violation nests the other ids under detail (the keys are
    -- too generic to register for every log)
    { 'w_logs_entries', 'payload', { '"from":"%s"', '"pending":"%s"' }, 'history',
      where = "`script` = 'w_creators' AND `type_key` = 'security_violation'" },
    -- w_stables' own events name the character under generic keys: a repossessed stable's and a
    -- newborn foal's "owner", a horse unstocked "to" a character (elsewhere those keys hold a stable,
    -- a horse or an amount, so only these two event types)
    { 'w_logs_entries', 'payload', { '"owner":"%s"', '"to":"%s"' }, 'history',
      where = "`script` = 'w_stables' AND `type_key` IN ('stable-business', 'horse-breed')" },
    -- w_survival (no PurgeCharacter of its own): the character key is '<account>|<citizenid>'
    { 'w_survival_player_infections', 'character_key', { '^[^|]+|%s$' }, 'data' },
    { 'w_survival_loot_claims', 'character_key', { '^[^|]+|%s$' }, 'data' },
    { 'w_survival_intelligence', 'character_key', { '^[^|]+|%s$' }, 'data' },
    { 'w_survival_audit', 'character_key', { '^[^|]+|%s$' }, 'history' },
    { 'w_survival_loot_nodes', 'last_looted_by', { '^[^|]+|%s$' }, 'history' },
    { 'w_survival_regions', 'last_actor', { '^[^|]+|%s$' }, 'history' },
    -- bp_mdt (no PurgeCharacter of its own): the people a report names, stored as citizen ids
    -- joined by ', ' ('12, 7, ABC12345'). Each entry is anchored by the list's start, its end or
    -- the separator, so '12' never matches inside '112' or a word of the report's text.
    { 'mdt_reports', 'involved_ids', { '^%s$', '^%s,', ', %s,', ', %s$' }, 'history' },
}
C.REGISTRY = { exact = EXACT, shaped = SHAPED }

local function esc(s) return (s:gsub('[%%%^%$%(%)%.%[%]%*%+%-%?]', '%%%0')) end

--- At most `n` bytes, never cut inside a multi-byte letter (an Arabic staff name): MySQL refuses a
--- row with broken UTF-8.
local function clip(s, n)
    s = tostring(s or ''):sub(1, n)
    while #s > 0 and not utf8.len(s) do s = s:sub(1, -2) end
    return s
end

-- ── the schema as the database has it ──────────────────────────────────────
-- (table, column) pairs that exist (a registry entry of a resource the server does not run is
-- skipped, never an error) and each table's single-column primary key (rows are rewritten by
-- key, not by comparing a long JSON value against the whole table). Re-read after a minute: a
-- resource started later creates its tables after the first read.
local columnsCache, keysCache, cacheAt
local SCHEMA_TTL_MS = 60000
local function loadSchema()
    if columnsCache and GetGameTimer() - cacheAt < SCHEMA_TTL_MS then return end
    local cols, keys = {}, {}
    for _, r in ipairs(MySQL.query.await('SELECT table_name AS t, column_name AS c, column_key AS k FROM information_schema.columns WHERE table_schema = DATABASE()') or {}) do
        cols[r.t .. '.' .. r.c] = true
        if r.k == 'PRI' then
            if keys[r.t] == nil then keys[r.t] = r.c else keys[r.t] = false end -- a composite key: none
        end
    end
    columnsCache, keysCache, cacheAt = cols, keys, GetGameTimer()
end
local function forgetSchema() columnsCache, keysCache, cacheAt = nil, nil, nil end
local function has(t, c) loadSchema() return columnsCache[t .. '.' .. c] == true end
local function primaryKey(t) loadSchema() return keysCache[t] or nil end

--- A shape compiled for one id: the pieces around each %s are captured, so the rewrite puts the
--- new id exactly where the old one stood and nowhere else ('bench:wb3:3' keeps its 'wb3').
local function compile(shape, eo)
    local body, head, tail = shape, '', ''
    if body:sub(1, 1) == '^' then head, body = '^', body:sub(2) end
    if body:sub(-1) == '$' and body:sub(-2, -2) ~= '%' then tail, body = '$', body:sub(1, -2) end
    local pieces, i = {}, 1
    while true do
        local a, b = body:find('%s', i, true)
        if not a then pieces[#pieces + 1] = body:sub(i) break end
        pieces[#pieces + 1] = body:sub(i, a - 1)
        i = b + 1
    end
    local parts, layout = { head }, {}
    for k, piece in ipairs(pieces) do
        if piece ~= '' then parts[#parts + 1] = '(' .. piece .. ')' layout[k] = true end
        if k < #pieces then parts[#parts + 1] = eo end
    end
    parts[#parts + 1] = tail
    return { pat = table.concat(parts), pieces = pieces, layout = layout }
end

--- A shape list compiled once for `old`: a scan rewrites many rows with the same shapes (a journal
--- of thousands), and compiling per row cost more than the match itself.
local function compileAll(shapes, old)
    local eo, out = esc(old), {}
    for k, shape in ipairs(shapes) do out[k] = compile(shape, eo) end
    return out
end

--- Rewrite `value` with a compiled shape list (compileAll) to `new`; nil when no shape matched.
local function reshape(value, compiled, new)
    if type(value) ~= 'string' then return nil end
    local changed = false
    for _, s in ipairs(compiled) do
        local pieces, layout = s.pieces, s.layout
        local out, n = value:gsub(s.pat, function(...)
            local caps, c, rebuilt = { ... }, 0, {}
            for k = 1, #pieces do
                if layout[k] then c = c + 1 rebuilt[#rebuilt + 1] = caps[c] end
                if k < #pieces then rebuilt[#rebuilt + 1] = new end
            end
            return table.concat(rebuilt)
        end)
        if n > 0 then value, changed = out, true end
    end
    return changed and value or nil
end

--- A pattern piece item by item: its plain character, or false for anything a match does not
--- contain literally (a class, a set, a wildcard, an anchor, a quantified item).
local function patternItems(piece)
    local items, i = {}, 1
    while i <= #piece do
        local ch = piece:sub(i, i)
        if ch == '%' then
            local nx = piece:sub(i + 1, i + 1)
            items[#items + 1] = (not nx:match('%w')) and nx or false -- '%-' is a '-', '%d' a class
            i = i + 2
        elseif ch == '[' then
            local j = i + 1
            if piece:sub(j, j) == '^' then j = j + 1 end
            if piece:sub(j, j) == ']' then j = j + 1 end
            while j <= #piece and piece:sub(j, j) ~= ']' do
                if piece:sub(j, j) == '%' then j = j + 1 end
                j = j + 1
            end
            items[#items + 1] = false
            i = j + 1
        elseif ch == '*' or ch == '+' or ch == '-' or ch == '?' then
            if #items > 0 then items[#items] = false end
            i = i + 1
        elseif ch == '.' or ch == '(' or ch == ')' or ch == '^' or ch == '$' then
            items[#items + 1] = false
            i = i + 1
        else
            items[#items + 1] = ch
            i = i + 1
        end
    end
    return items
end

--- The plain text at the start (lead) and at the end (tail) of a pattern piece: what every match
--- of it contains literally. A class, a set, a wildcard or a quantified item breaks the run.
local function literalRuns(piece)
    local items = patternItems(piece)
    local lead, tail = {}, {}
    for k = 1, #items do if not items[k] then break end lead[#lead + 1] = items[k] end
    for k = #items, 1, -1 do if not items[k] then break end table.insert(tail, 1, items[k]) end
    return table.concat(lead), table.concat(tail)
end

--- The literal text every match of `shape` for `id` contains: the plain text right before the
--- first %s, the id, the plain text right after it.
local function needle(shape, id)
    local body = shape
    if body:sub(1, 1) == '^' then body = body:sub(2) end
    if body:sub(-1) == '$' and body:sub(-2, -2) ~= '%' then body = body:sub(1, -2) end
    local a, b = body:find('%s', 1, true)
    if not a then return id end
    local after = body:sub(b + 1)
    local c = after:find('%s', 1, true)
    if c then after = after:sub(1, c - 1) end
    local _, tail = literalRuns(body:sub(1, a - 1))
    local lead = literalRuns(after)
    return tail .. id .. lead
end
C.Needle = needle

local function likeEscape(s) return (s:gsub('[!%%_]', '!%0')) end

--- The SQL that narrows column `col` to the rows `shape` can match for `id`, before Lua matches the
--- shape itself (a short id alone, '1', is in nearly every journal key: 'w_store:1790...:1'). Every
--- plain run of the shape, the id written in, must be in the value (INSTR); the run a '^' or '$'
--- anchor pins to the start or the end is a LIKE, which also lets MySQL use the column's index
--- ('collect:%' ... '%:1'). A superset of the matches (LIKE may fold case): Lua decides.
--- Returns the condition and its values.
local function prefilter(col, shape, id)
    local body, head, tail = shape, false, false
    if body:sub(1, 1) == '^' then head, body = true, body:sub(2) end
    if body:sub(-1) == '$' and body:sub(-2, -2) ~= '%' then tail, body = true, body:sub(1, -2) end
    local items = patternItems((body:gsub('%%s', function() return esc(id) end)))
    local conds, values, run = {}, {}, {}
    local function flush(first, last)
        if #run == 0 then return end
        local text = table.concat(run)
        run = {}
        local pinned = false
        if head and first then
            conds[#conds + 1] = ("`%s` LIKE ? ESCAPE '!'"):format(col) values[#values + 1] = likeEscape(text) .. '%'
            pinned = true
        end
        if tail and last then
            conds[#conds + 1] = ("`%s` LIKE ? ESCAPE '!'"):format(col) values[#values + 1] = '%' .. likeEscape(text)
            pinned = true
        end
        -- a lone ':' or '"' narrows nothing; the run holding the id always does
        if not pinned and (#text >= 2 or text:find(id, 1, true)) then
            conds[#conds + 1] = ('INSTR(BINARY `%s`, ?) > 0'):format(col) values[#values + 1] = text
        end
    end
    local start = 1
    for k = 1, #items do
        if items[k] then
            if #run == 0 then start = k end
            run[#run + 1] = items[k]
        else
            flush(start == 1, false)
        end
    end
    flush(start == 1, true)
    if #conds == 0 then return ('INSTR(BINARY `%s`, ?) > 0'):format(col), { id } end
    return table.concat(conds, ' AND '), values
end
C.Prefilter = prefilter

--- EXACT: the condition (and its values) for the rows of `e` that hold `id`. The plain `=` finds
--- them through the column's index (BINARY alone scans the whole table, ~100 entries on every
--- Dependencies call); BINARY then keeps only the exact value (a collation may fold case).
local function exactWhere(e, id)
    local w = ('`%s` = ? AND BINARY `%s` = ?'):format(e[2], e[2])
    if e.where then w = w .. ' AND (' .. e.where .. ')' end
    return w, { id, id }
end

--- { first, <the values of v> }: an UPDATE's SET value in front of its WHERE values.
local function withFirst(first, v)
    local out = { first }
    for i = 1, #v do out[#out + 1] = v[i] end
    return out
end

local function countWhere(t, w, values)
    return tonumber(MySQL.scalar.await(('SELECT COUNT(*) FROM `%s` WHERE %s'):format(t, w), values)) or 0
end

--- SHAPED: the rows of `e` whose value holds `id` in one of its shapes.
--- { { key = <primary key value>|nil, value = <value>, live = <the entry's filter holds>, money = n|nil } }, pk,
--- the shapes compiled for `id` (compileAll, for the caller's rewrite)
local function shapedMatches(e, id)
    local t, c, shapes = e[1], e[2], e[3]
    local conds, values, seen = {}, {}, {}
    for _, s in ipairs(shapes) do
        local w, v = prefilter(c, s, id)
        local sig = w .. '\0' .. table.concat(v, '\0')
        if not seen[sig] then
            seen[sig] = true
            conds[#conds + 1] = '(' .. w .. ')'
            for _, x in ipairs(v) do values[#values + 1] = x end
        end
    end
    local where = table.concat(conds, ' OR ')
    if e.where then where = ('(%s) AND (%s)'):format(where, e.where) end
    local pk = primaryKey(t)
    local cols = pk and ('`%s` AS k, `%s` AS v'):format(pk, c) or ('DISTINCT `%s` AS v'):format(c)
    if e.filter then cols = cols .. (', IF(%s, 1, 0) AS live'):format(e.filter) end
    if e.money then cols = cols .. (', `%s` AS m'):format(e.money) end
    local compiled = compileAll(shapes, id)
    local out = {}
    for _, r in ipairs(MySQL.query.await(('SELECT %s FROM `%s` WHERE %s'):format(cols, t, where), values) or {}) do
        if reshape(r.v, compiled, id .. '\1') then
            out[#out + 1] = { key = r.k, value = r.v, live = (e.filter == nil) or tonumber(r.live) == 1, money = tonumber(r.m) }
        end
    end
    return out, pk, compiled
end

--- The condition for one matched SHAPED row: by its primary key (and its value, so a row that
--- changed meanwhile is left alone), or by the value itself for a table without a single key.
local function rowWhere(e, pk, m)
    if pk and m.key ~= nil then return ('`%s` = ? AND BINARY `%s` = ?'):format(pk, e[2]), { m.key, m.value } end
    return ('`%s` = ? AND BINARY `%s` = ?'):format(e[2], e[2]), { m.value, m.value }
end

--- One UPDATE per row, whichever entries rewrite it: two SHAPED entries on the same column (a
--- scoped one next to the general one) may match the same row, and a second UPDATE guarded by the
--- row's ORIGINAL value would find it already changed by the first and do nothing. The second
--- entry continues from the first one's result instead. Returns the new value, or nil (no match).
local function chainRewrite(chain, queries, e, pk, m, rewrite)
    local id = e[1] .. '\0' .. e[2] .. '\0' .. tostring((pk and m.key ~= nil) and m.key or m.value)
    local q = chain[id]
    local base = q and q.values[1] or m.value
    local nv = rewrite(base)
    if not nv or nv == base then return nil end
    if q then q.values[1] = nv return nv, false end
    local w, v = rowWhere(e, pk, m)
    q = { query = ('UPDATE `%s` SET `%s` = ? WHERE %s'):format(e[1], e[2], w), values = withFirst(nv, v) }
    queries[#queries + 1] = q
    chain[id] = q
    return nv, true
end

--- Where does this id live? { { table, column, kind, rows } } (only non-empty entries).
--- `first` = stop at the first entry found (used(): is anything at all left under this id?).
function C.Dependencies(citizenid, first)
    citizenid = C.Normalize(citizenid)
    if not citizenid then return {} end
    local out = {}
    for _, e in ipairs(EXACT) do
        local t, c, kind, filter = e[1], e[2], e[3], e[4]
        if has(t, c) then
            local w, v = exactWhere(e, citizenid)
            local n = countWhere(t, w, v)
            if n > 0 and filter then
                -- a filtered entry is `kind` only while its filter holds; the other rows are history
                local live = countWhere(t, w .. ' AND (' .. filter .. ')', v)
                if live > 0 then out[#out + 1] = { table = t, column = c, kind = kind, rows = live } end
                if n - live > 0 then out[#out + 1] = { table = t, column = c, kind = 'history', rows = n - live } end
            elseif n > 0 then
                out[#out + 1] = { table = t, column = c, kind = kind, rows = n }
            end
            if first and #out > 0 then return out end
        end
    end
    for _, e in ipairs(SHAPED) do
        local t, c, kind = e[1], e[2], e[4]
        if has(t, c) then
            local live, hist = 0, 0
            for _, m in ipairs((shapedMatches(e, citizenid))) do
                if m.live then live = live + 1 else hist = hist + 1 end
            end
            if live > 0 then out[#out + 1] = { table = t, column = c, kind = kind, rows = live, shaped = true } end
            if hist > 0 then out[#out + 1] = { table = t, column = c, kind = 'history', rows = hist, shaped = true } end
            if first and #out > 0 then return out end
        end
    end
    return out
end

--- Is this number taken? A live character, or anything still filed under it (a leftover a new
--- holder would inherit, or that would collide with a reassign's rewrite of the ledger's unique
--- account ids and journal keys). Purge and Reassign leave nothing, so the number is free again.
--- `fast` (C.Next, on every character creation): the character, and the ledger's traces of one
--- (its accounts, its starter money's journal keys). The full registry scan is for staff's
--- reassign onto a chosen number, where a missed leftover would join the character.
local function used(citizenid, fast)
    if exists(citizenid) then return true end
    if fast then
        if has('cb_accounts', 'owner') and (tonumber(MySQL.scalar.await("SELECT COUNT(*) FROM cb_accounts WHERE (BINARY owner = ? AND `kind` <> 'tribe') OR id LIKE ?",
            { citizenid, 'player:' .. citizenid .. ':%' })) or 0) > 0 then return true end
        if has('cb_journal', 'request_key') and (tonumber(MySQL.scalar.await('SELECT COUNT(*) FROM cb_journal WHERE request_key LIKE ?',
            { 'starter:' .. citizenid .. ':%' })) or 0) > 0 then return true end
        return false
    end
    return #C.Dependencies(citizenid, true) > 0
end

local nextLock = false
--- The next free sequential id. The counter lives in w_core_citizen_seq; it starts at the highest
--- numeric id already used, and a number that is taken (see used()), being worked on or just
--- purged is skipped. The counter only climbs: a freed number goes back out through Reassign.
function C.Next()
    while nextLock do Wait(0) end
    nextLock = true
    local ok, id = pcall(function()
        local cur = tonumber(MySQL.scalar.await("SELECT v FROM w_core_citizen_seq WHERE k = 'citizen'"))
        if not cur then
            cur = tonumber(MySQL.scalar.await("SELECT COALESCE(MAX(CAST(citizenid AS UNSIGNED)), 0) FROM players WHERE citizenid REGEXP '^[0-9]+$'")) or 0
            MySQL.insert.await("INSERT IGNORE INTO w_core_citizen_seq (k, v) VALUES ('citizen', ?)", { cur })
        end
        local n = cur
        repeat
            n = n + 1
            local candidate = idOf(n)
        until not (busy[candidate] or C.SaveBlocked(candidate) or used(candidate, true))
        MySQL.update.await("UPDATE w_core_citizen_seq SET v = ? WHERE k = 'citizen'", { math.floor(n) })
        return idOf(n)
    end)
    nextLock = false
    if not ok then error(id) end
    return id
end

--- Who is this id? { citizenid, source = <server id> | nil, name, license, row } or nil.
function C.Resolve(value)
    local citizenid = C.Normalize(value)
    if not citizenid then return nil, 'invalid_id' end
    local src, player = onlineWith(citizenid)
    if src then
        local pd = player.PlayerData
        local ci = pd.charinfo or {}
        return { citizenid = citizenid, source = src, online = true, license = pd.license,
                 name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '') }
    end
    local row = MySQL.single.await('SELECT citizenid, cid, license, name, charinfo, job, gang, last_updated FROM players WHERE citizenid = ?', { citizenid })
    if not row then return nil, 'not_found' end
    local ci = type(row.charinfo) == 'string' and json.decode(row.charinfo) or {}
    return { citizenid = citizenid, online = false, license = row.license, row = row,
             name = (((ci or {}).firstname or '') .. ' ' .. ((ci or {}).lastname or '')):gsub('^%s+', ''):gsub('%s+$', '') }
end

-- ── blocks ─────────────────────────────────────────────────────────────────
function C.GetBlock(citizenid)
    citizenid = C.Normalize(citizenid)
    if not citizenid then return nil end
    return MySQL.single.await('SELECT reason, blocked_by, blocked_at FROM w_core_character_blocks WHERE citizenid = ?', { citizenid })
end
function C.IsBlocked(citizenid) return C.GetBlock(citizenid) ~= nil end

function C.Block(citizenid, reason, by)
    citizenid = C.Normalize(citizenid)
    if not citizenid or not exists(citizenid) then return false, 'not_found' end
    reason = tostring(reason or ''):sub(1, 255)
    MySQL.insert.await('INSERT INTO w_core_character_blocks (citizenid, reason, blocked_by, blocked_at) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE reason = VALUES(reason), blocked_by = VALUES(blocked_by), blocked_at = VALUES(blocked_at)',
        { citizenid, reason, tostring(by or 'console'):sub(1, 96), os.time() })
    -- a blocked character in play goes back to the character selection
    local src = onlineWith(citizenid)
    if src then DropPlayer(src, Lang:t('info.character_blocked', { reason = reason ~= '' and reason or '-' })) end
    return true
end

function C.Unblock(citizenid)
    citizenid = C.Normalize(citizenid)
    if not citizenid then return false, 'invalid_id' end
    MySQL.update.await('DELETE FROM w_core_character_blocks WHERE citizenid = ?', { citizenid })
    return true
end

-- ── the bare id inside the character's own journal rows ────────────────────
--- The journal also stores the id as a plain query value ("7" in the bank panel's own actions,
--- in w_centralbank's purge row: DELETE FROM cb_staff WHERE citizenid = ?). No shape can anchor
--- a bare "7" (it is also an amount or a store elsewhere), so it is rewritten only in the rows
--- that are this character's: its panel actions ('<id>:<action>:<key>'), the rows it is the actor
--- of, and the purge's own row ('purge:<tombstone>:...'). The rows are picked now, by those keys
--- (the transaction moves the keys and the actors), and rewritten by their id at the END of the
--- transaction: the shaped rewrite of the same row ('"player:7:...') is guarded by the row's value
--- as it was read, and would find nothing to update after this REPLACE had changed it.
--- Adds its queries to `queries`.
local BARE_CHUNK = 500
local function addBareJournal(queries, id, replacement, purgeKey)
    if not (has('cb_journal', 'movements') and has('cb_journal', 'request_key') and has('cb_journal', 'actor')) then return end
    local conds, values = { 'request_key LIKE ?', 'BINARY actor = ?' }, { id .. ':%', id }
    if purgeKey then conds[#conds + 1] = 'request_key LIKE ?' values[#values + 1] = purgeKey .. ':%' end
    local quoted = '"' .. id .. '"'
    local rows = MySQL.query.await(('SELECT id FROM cb_journal WHERE INSTR(BINARY movements, ?) > 0 AND (%s)'):format(table.concat(conds, ' OR ')),
        withFirst(quoted, values)) or {}
    for i = 1, #rows, BARE_CHUNK do
        local ids, marks = {}, {}
        for k = i, math.min(i + BARE_CHUNK - 1, #rows) do ids[#ids + 1] = rows[k].id marks[#marks + 1] = '?' end
        queries[#queries + 1] = { query = ('UPDATE cb_journal SET movements = REPLACE(movements, ?, ?) WHERE id IN (%s)'):format(table.concat(marks, ', ')),
                                  values = withFirst(quoted, withFirst('"' .. replacement .. '"', ids)) }
    end
end

-- ── waiting for a character to leave ───────────────────────────────────────
local LOGOUT_WAIT_MS = 20000
-- other resources save the character on playerDropped too, some without waiting (w_hud's needs):
-- their writes land before any purge reads the rows
local SETTLE_MS = 1500

local function saving(citizenid) return WCore.Player.SaveInFlight ~= nil and WCore.Player.SaveInFlight(citizenid) end

--- Waits until no players-row save of this number is in flight (an offline Player object staff or a
--- resource just saved): landing after a DELETE or a move, its INSERT ... ON DUPLICATE KEY UPDATE
--- would bring the row back under the number. (SaveInFlight gives up on a write after 15 s, so this
--- ends before the deadline.)
local function waitSaves(citizenid, deadline)
    deadline = deadline or (GetGameTimer() + LOGOUT_WAIT_MS)
    while saving(citizenid) do
        if GetGameTimer() > deadline then return false, 'still_online' end
        Wait(100)
    end
    return true
end

--- A character in play is kicked, and the caller waits until it is gone from WCore.Players AND its
--- logout save has landed: that INSERT ... ON DUPLICATE KEY UPDATE, landing after the DELETE (or
--- the move), would bring the players row back. An offline character's save still in flight (an
--- offline Player object staff or a resource just saved) is waited for the same way.
--- opts.message: what the kicked player reads (a deletion's text by default).
local function kickAndWait(citizenid, opts)
    local deadline = GetGameTimer() + LOGOUT_WAIT_MS
    local src = onlineWith(citizenid)
    if not src then return waitSaves(citizenid, deadline) end
    -- the player deleting from the selection never has this character in play (w_creators
    -- refuses it); a caller that asks anyway is told to try again, not kicked
    if opts.requester and src == opts.requester then return false, 'busy' end
    DropPlayer(src, opts.message or Lang:t('info.character_deleted'))
    while true do
        local still = onlineWith(citizenid)
        local inFlight = saving(citizenid)
        if not still and not inFlight then break end
        if GetGameTimer() > deadline then
            -- a source that left without its playerDropped clearing it: the save loop would keep
            -- saving that stale entry and bring the row back after the delete
            if still and not inFlight and GetPlayerName(still) == nil then
                WCore.Players[still] = nil
                break
            end
            return false, 'still_online'
        end
        Wait(100)
    end
    Wait(SETTLE_MS)
    return true
end

-- ── moving a character to another id ───────────────────────────────────────
--- The queries that move `old` to `new` everywhere the registry knows: every kind, the history
--- too, so the old number is left clean. Returns queries, touched, accounts.
--- `ledger` (w_centralbank runs): the ledger's own account rows are NOT in `queries` (renamed
--- outside its lock, a transfer it plans from memory would credit a row that is gone: money
--- destroyed); `accounts` is their plan for RenameCharacterAccounts instead:
--- { { id = <account id>, to = <its new id>, owner = <new owner> | nil } }.
local function renameQueries(old, new, ledger)
    local queries, touched = {}, {}
    local accounts, plan = ledger and {} or nil, {}
    local function planned(id)
        local p = plan[id]
        if not p then p = { id = id, to = id } plan[id] = p accounts[#accounts + 1] = p end
        return p
    end
    for _, e in ipairs(EXACT) do
        local t, c = e[1], e[2]
        if has(t, c) then
            local w, v = exactWhere(e, old)
            if ledger and t == 'cb_accounts' then
                local rows = MySQL.query.await(('SELECT `id` FROM `cb_accounts` WHERE %s'):format(w), v) or {}
                for _, r in ipairs(rows) do planned(r.id).owner = new end
                if #rows > 0 then touched[#touched + 1] = ('%s.%s (%d)'):format(t, c, #rows) end
            else
                local n = countWhere(t, w, v)
                if n > 0 then
                    queries[#queries + 1] = { query = ('UPDATE `%s` SET `%s` = ? WHERE %s'):format(t, c, w), values = withFirst(new, v) }
                    touched[#touched + 1] = ('%s.%s (%d)'):format(t, c, n)
                end
            end
        end
    end
    local chain = {}
    for _, e in ipairs(SHAPED) do
        local t, c = e[1], e[2]
        if has(t, c) then
            local n = 0
            local rows, pk, compiled = shapedMatches(e, old)
            for _, m in ipairs(rows) do
                if ledger and t == 'cb_accounts' and c == 'id' then
                    local p = planned(m.value)
                    local nv = reshape(p.to, compiled, new)
                    if nv then p.to, n = nv, n + 1 end
                elseif chainRewrite(chain, queries, e, pk, m, function(value) return reshape(value, compiled, new) end) then
                    n = n + 1
                end
            end
            if n > 0 then touched[#touched + 1] = ('%s.%s (%d value(s))'):format(t, c, n) end
        end
    end
    addBareJournal(queries, old, new, nil)
    return queries, touched, accounts
end

local function ledgerStarted() return GetResourceState('w_centralbank') == 'started' end

--- A ledger that runs but is not ready (not opened yet, or halted) renames nothing: a move waits
--- for it rather than renaming its rows behind it.
local function ledgerNotReady()
    if not ledgerStarted() then return false end
    local okR, isReady = pcall(function() return exports.w_centralbank:IsReady() end)
    return not okR or isReady ~= true
end

--- The ledger keeps every account in memory: account rows w_core renamed or deleted in the
--- database are reloaded (under the ledger's own lock) right after the transaction that changed
--- them. Until then a transfer onto a deleted account would book only its other side.
local function reloadLedger()
    if ledgerStarted() then
        pcall(function() exports.w_centralbank:ReloadAccounts() end)
    end
end

--- Refresh the in-memory caches of the resources that keep one by character id. `viaLedger`: the
--- ledger renamed the accounts itself, its memory already follows.
local function afterRename(old, new, viaLedger)
    -- (old, new): server-side listeners re-key their caches (the database is already moved):
    -- w_store (store owner / employees), w_banking (savings accounts), w_housing (houses),
    -- w_stables (per-character limits), w_connector, w_centralbank. Keep firing it for every rename.
    TriggerEvent('w_core:server:citizenIdChanged', old, new)
    if not viaLedger then reloadLedger() end
end

local function describe(deps)
    local out = {}
    for _, d in ipairs(deps) do out[#out + 1] = ('%s.%s [%s] (%d)'):format(d.table, d.column, d.kind, d.rows) end
    return table.concat(out, ', ')
end

-- the ledger's refusals -> a move's reasons (its own words where they mean the same)
local LEDGER_REASONS = { database_error = 'database', invalid_citizenid = 'invalid_id', invalid_plan = 'error', forbidden = 'error' }

--- The running ledger renames the character's accounts (the plan) and memory under its own lock,
--- in ONE transaction with `queries` (every other place the id lives, the map row).
--- Returns true | nil (a ledger without the export: an older w_centralbank, the caller takes the
--- old path) | false, reason, detail.
local function ledgerRename(old, new, accounts, queries)
    local called, ok, why, detail = pcall(function()
        return exports.w_centralbank:RenameCharacterAccounts(old, new, { accounts = accounts, queries = queries })
    end)
    if not called then
        if tostring(ok):find('No such export', 1, true) then return nil end
        print(('^1[w_core] citizen: the ledger rename %s -> %s failed: %s^7'):format(old, new, tostring(ok)))
        return false, 'database'
    end
    if ok == true then return true end
    why = tostring(why or 'database')
    return false, LEDGER_REASONS[why] or why, detail
end

--- Move the character at `old` (offline, held busy by the caller with `new`) to `new`: every place
--- the registry knows, its history included, in ONE transaction -- the ledger's, with its accounts,
--- while w_centralbank runs. `kind` names the map row ('reassign', 'transfer').
--- Returns true, touched | false, reason, detail.
local function move(old, new, by, kind)
    local rowId = tonumber(MySQL.scalar.await('SELECT id FROM players WHERE citizenid = ?', { old }))
    rowId = rowId and math.floor(rowId)
    -- from here on a Player object that still carries `old` does not save: once the row moved, its
    -- INSERT ... ON DUPLICATE KEY UPDATE would write a ghost row under `old` (or over the row of
    -- whoever holds it next). Set before the wait, so a save starting meanwhile is skipped rather
    -- than raced; given back as it was if the move does not happen.
    local prevRow, prevGuard = rowId and movedRows[rowId], purgedGuard[old]
    if rowId then movedRows[rowId] = new end
    purgedGuard[old] = GetGameTimer() + PURGED_GUARD_MS
    local function undo(why, detail)
        if rowId then movedRows[rowId] = prevRow end
        purgedGuard[old] = prevGuard
        return false, why, detail
    end
    -- a save already in flight (an offline Player object staff or a resource just saved) lands first
    local okW, whyW = waitSaves(old)
    if not okW then return undo(whyW) end

    local ledger = ledgerStarted()
    local mapRow = { query = 'INSERT INTO w_core_citizen_map (old_id, new_id, kind, done_by, done_at) VALUES (?, ?, ?, ?, ?)',
                     values = { old, new, kind, clip(by or 'console', 96), os.time() } }
    local touched, viaLedger
    local attempt = 0
    while not touched do
        attempt = attempt + 1
        -- a read that raises gives the guard back (nothing moved): kept, the character still on
        -- `old` would be refused at every login until a restart (C.RowMoved), as in migrateOne
        local okQ, queries, t, accounts = pcall(renameQueries, old, new, ledger)
        if not okQ then return undo('database', tostring(queries)) end
        queries[#queries + 1] = mapRow
        if ledger then
            local ok, why, detail = ledgerRename(old, new, accounts, queries)
            if ok == nil then
                ledger = false -- an older ledger: planned again the old way (then its memory reloads)
            elseif ok then
                touched, viaLedger = t, true
            elseif why == 'accounts_changed' and attempt < 3 then
                -- an account of the character was created between the plan and the lock: plan again
            elseif why == 'database' and rowId then
                -- maybe a lost commit acknowledgement: the rows moved. The ledger's own reload may be
                -- what failed after the commit, so its memory is reloaded once more (viaLedger false).
                -- Unreadable: the rows may have moved, so the guard stays (a stale save of `old` must
                -- not write a ghost row) and staff is told the outcome is unknown
                local okC, n = pcall(MySQL.scalar.await, 'SELECT COUNT(*) FROM players WHERE citizenid = ? AND id = ?', { new, rowId })
                if not okC then return false, 'database', 'commit unknown: ' .. tostring(n) end
                if (tonumber(n) or 0) == 0 then return undo(why, detail) end
                touched, viaLedger = t, false
            else
                return undo(why, detail)
            end
        else
            local okT, done = pcall(MySQL.transaction.await, queries)
            if not okT or done ~= true then return undo('database') end
            touched = t
        end
    end
    -- staff gave the number to this character: a guard left on it no longer applies
    purgedGuard[new] = nil
    afterRename(old, new, viaLedger)
    return true, touched
end

local function reassign(old, new, by)
    if not exists(old) then return false, 'not_found' end
    if onlineWith(old) then return false, 'online' end
    -- the new number must be clean: no character, nothing left under it (a leftover would join
    -- this character, and the ledger's unique account ids and journal keys would collide)
    if used(new) then return false, 'id_taken' end
    if ledgerNotReady() then return false, 'economy_not_ready' end
    local ok, touched, detail = move(old, new, by, 'reassign')
    if not ok then return false, touched, detail end
    -- its own channel: w_logs drops the legacy 'joinleave' while w_core reports joins itself
    TriggerEvent('w_log:server:CreateLog', 'character-reassign', 'Citizen ID changed', 'orange', ('%s -> %s by %s'):format(old, new, tostring(by or 'console')))
    local left = C.Dependencies(old)
    if #left > 0 then
        print(('^3[w_core] citizen: %s -> %s done, but %s is not clean: %s^7'):format(old, new, old, describe(left)))
    end
    return true, touched
end

--- Move a character (offline) to another id. by = who (for the map / logs).
--- Returns true, touched | false, reason, detail ('invalid_id', 'same_id', 'busy', 'not_found',
--- 'online', 'id_taken', 'still_online' (a save of it did not land), 'economy_not_ready' (the
--- ledger runs but is not ready), 'accounts_changed' (its accounts kept changing under the plan),
--- 'database', 'error', 'not_ready').
function C.Reassign(old, new, by)
    if not ready then return false, 'not_ready' end
    old, new = C.Normalize(old), C.Normalize(new)
    if not old or not new then return false, 'invalid_id' end
    if not C.IsNumeric(new) then return false, 'invalid_id' end
    if old == new then return false, 'same_id' end
    if busy[old] or busy[new] then return false, 'busy' end
    busy[old], busy[new] = true, true
    local result = table.pack(pcall(reassign, old, new, by))
    busy[old], busy[new] = nil, nil
    if not result[1] then
        print(('^1[w_core] citizen: reassign %s -> %s failed: %s^7'):format(old, new, tostring(result[2])))
        return false, 'database'
    end
    return table.unpack(result, 2, result.n)
end

-- ── deleting a character: the full purge ───────────────────────────────────
-- Every resource that keeps something for a character removes it through its own
-- exports.<res>:PurgeCharacter(citizenid, ctx) -> true, { what = count } | false, reason. The
-- order matters: the ones that release shared assets and settle money in flight first (a store's
-- refunds, a house purchase's refund, a market escrow), their money landing on the character's
-- ledger accounts; w_centralbank LAST, which returns every balance to the reserve, writes off an
-- open loan and deletes the accounts. A resource that is not started is skipped (w_core's own pass
-- still deletes its leftover rows, and refuses if one of them is an asset); a started one without
-- the export is skipped with a warning.
local PURGE_ORDER = { 'w_store', 'w_housing', 'w_stables', 'w_pets', 'w_marketplace', 'w_tribes', 'w_crafting', 'w_citizens',
                      'w_baloot', 'w_legal', 'w_butcher', 'w_hud', 'w_banking', 'w_creators', 'w_inventory', 'w_connector', 'w_centralbank' }
C.PURGE_ORDER = PURGE_ORDER

--- The money cannot be returned without the ledger: asked before anyone is kicked.
--- Returns true | false, 'economy_not_ready', detail (the funded accounts, while no ledger runs).
local function economyPreflight(citizenid)
    if ledgerStarted() then
        if ledgerNotReady() then return false, 'economy_not_ready' end
        return true
    end
    -- no ledger running: its table is the truth; a funded account of this character would stay.
    -- By its owner, and by the id shapes the registry knows: a stash's cash (owned by '' or by the
    -- stash's owner), the legal wallet, a bench, the market's account are found by their id alone.
    if has('cb_accounts', 'balance') then
        local funded, seen = {}, {}
        local function add(id)
            id = tostring(id)
            if not seen[id] then seen[id] = true funded[#funded + 1] = id .. ' (1)' end
        end
        for _, r in ipairs(MySQL.query.await("SELECT id FROM cb_accounts WHERE balance <> 0 AND ((BINARY owner = ? AND `kind` <> 'tribe') OR id LIKE ?)",
            { citizenid, 'player:' .. citizenid .. ':%' }) or {}) do add(r.id) end
        for _, e in ipairs(SHAPED) do
            if e[1] == 'cb_accounts' and e.money and has(e[1], e[2]) then
                for _, m in ipairs((shapedMatches(e, citizenid))) do
                    if (m.money or 0) ~= 0 then add(m.key or m.value) end
                end
            end
        end
        if #funded > 0 then return false, 'economy_not_ready', clip(table.concat(funded, ', '), 600) end
    end
    return true
end

--- Assets nothing can release now: the resource whose purge releases one (`res`) is not started (a
--- store while w_store is stopped), or it is a row w_core releases itself only while its resource
--- does NOT run (a kingdom while w_kingdom_v2 runs). w_core's own pass would refuse them only after
--- every other resource purged (a half-deleted character, held): refused here instead, before
--- anyone is kicked. Returns nil | the blockers ('<table>.<column> (n) [<resource>: <state>]', ...).
local function assetPreflight(citizenid)
    local out = {}
    local function stuck(e)
        if e.release then
            if e.owner and GetResourceState(e.owner) == 'started' then return e.owner end
            return nil
        end
        if e.res and GetResourceState(e.res) ~= 'started' then return e.res end
        return nil
    end
    local function add(t, c, n, res) out[#out + 1] = ('%s.%s (%d) [%s: %s]'):format(t, c, n, res, GetResourceState(res)) end
    for _, e in ipairs(EXACT) do
        local t, c, kind, filter = e[1], e[2], e[3], e[4]
        local res = kind == 'asset' and stuck(e)
        if res and has(t, c) then
            local w, v = exactWhere(e, citizenid)
            if filter then w = w .. ' AND (' .. filter .. ')' end
            local n = countWhere(t, w, v)
            if n > 0 then add(t, c, n, res) end
        end
    end
    for _, e in ipairs(SHAPED) do
        local t, c, kind = e[1], e[2], e[4]
        local res = kind == 'asset' and stuck(e)
        if res and has(t, c) then
            local n = 0
            for _, m in ipairs((shapedMatches(e, citizenid))) do if m.live then n = n + 1 end end
            if n > 0 then add(t, c, n, res) end
        end
    end
    if #out == 0 then return nil end
    return clip(table.concat(out, ', '), 600)
end

--- A resource loading or unloading right now: its purge cannot run, and its rows may still be
--- written from its memory. Asked before anyone is kicked; the deletion is simply tried again.
local function resourceSettling()
    for _, res in ipairs(PURGE_ORDER) do
        local state = GetResourceState(res)
        if state == 'starting' or state == 'stopping' then return res end
    end
    return nil
end

--- A resource's summary in the shared contract, whatever it answered:
---   { <what> = <integer count>, money = { USD = <dollars>, GOLD = <gold> }, notes = '<text>' }
--- The admin panel shows counts, money and notes apart, so an amount must never pass for a count
--- ($1237.56 is not 1238 records): a fractional number, a '<x>:USD' / '<x>:GOLD' amount (the older
--- ledger summary) or any other plain value is kept as a note 'key value' instead.
local CURRENCIES = { 'USD', 'GOLD' }
local function contractSummary(detail)
    local out, notes = {}, {}
    if type(detail) ~= 'table' then return out end
    for k, v in pairs(detail) do
        if k == 'money' then
            if type(v) == 'table' then
                for _, cur in ipairs(CURRENCIES) do
                    local n = tonumber(v[cur])
                    if n and n == n and n ~= 0 then out.money = out.money or {} out.money[cur] = n end
                end
            elseif v ~= nil and v ~= 0 then
                notes[#notes + 1] = 'money ' .. tostring(v) -- no currency: an amount, never a count
            end
        elseif k == 'notes' then
            if v ~= nil and v ~= '' then table.insert(notes, 1, tostring(v)) end
        elseif type(k) == 'string' and type(v) ~= 'table' then
            if type(v) == 'number' and v % 1 == 0 and not k:find(':USD$') and not k:find(':GOLD$') then
                if v ~= 0 then out[k] = math.tointeger(v) or v end
            elseif v ~= nil and v ~= false and v ~= 0 and v ~= '' then
                notes[#notes + 1] = ('%s %s'):format(k, tostring(v))
            end
        end
    end
    if #notes > 0 then out.notes = clip(table.concat(notes, '; '), 300) end
    return out
end

--- Every started resource's PurgeCharacter, in PURGE_ORDER. The first refusal or error stops the
--- purge and is returned (a purge is idempotent: the retry finds done what was done).
local function callPurges(citizenid, ctx, report)
    for _, res in ipairs(PURGE_ORDER) do
        if GetResourceState(res) == 'started' then
            local called, ok, detail = pcall(function() return exports[res]:PurgeCharacter(citizenid, ctx) end)
            if not called then
                if tostring(ok):find('No such export', 1, true) then
                    print(('^3[w_core] purge %s: %s is started but has no PurgeCharacter export: skipped^7'):format(citizenid, res))
                    report[res] = { notes = 'no PurgeCharacter export: skipped' }
                else
                    print(('^1[w_core] purge %s: %s failed: %s^7'):format(citizenid, res, tostring(ok)))
                    return false, 'error', res
                end
            elseif ok ~= true then
                local why = tostring(detail or 'refused')
                -- an old random id (ABC12345) a resource that only knows numbers cannot hold: its
                -- rows, if any, are w_core's own pass's
                if not C.IsNumeric(citizenid) and why:find('^invalid') then
                    report[res] = { notes = 'skipped: ' .. clip(why, 200) }
                else
                    print(('^3[w_core] purge %s: %s refused: %s^7'):format(citizenid, res, why))
                    return false, why, res
                end
            else
                report[res] = contractSummary(detail)
            end
        end
    end
    return true
end

--- w_core's own pass, one transaction over the registry: a leftover own row is deleted, history is
--- moved to the tombstone, the players row goes. Refused before anything changes while an asset is
--- still owned (its resource did not release it: not started, or it failed) or an account still
--- holds money. `ledger` (w_centralbank is running): an account row is the ledger's to delete, never
--- w_core's -- deleted outside the ledger's lock, a transfer onto it that the ledger already has in
--- memory would book only its other side (money destroyed); it is counted in `handed` and purge()
--- hands it over. Returns queries, { counts, accounts, handed } | nil, reason, detail (what refused).
local function purgeQueries(citizenid, ctx, withMap, ledger)
    local tomb = ctx.tombstone
    local queries, counts, accounts, handed = {}, {}, false, 0
    local blockers, blocked, funded, fundedBy = {}, {}, {}, {}
    local function note(key, n) counts[key] = (counts[key] or 0) + n end
    local function tally(list, by, key, n)
        if n <= 0 then return end
        if not by[key] then by[key] = 0 list[#list + 1] = key end
        by[key] = by[key] + n
    end
    for _, e in ipairs(EXACT) do
        local t, c, kind, filter = e[1], e[2], e[3], e[4]
        if has(t, c) then
            local w, v = exactWhere(e, citizenid)
            local n = countWhere(t, w, v)
            if n > 0 then
                local key = t .. '.' .. c
                local live = (kind == 'asset' and filter) and countWhere(t, w .. ' AND (' .. filter .. ')', v) or 0
                if kind == 'history' or (kind == 'asset' and filter and live == 0) then
                    queries[#queries + 1] = { query = ('UPDATE `%s` SET `%s` = ? WHERE %s'):format(t, c, w), values = withFirst(tomb, v) }
                    note(key .. ':tombstoned', n)
                elseif kind == 'asset' then
                    if e.release and not (e.owner and GetResourceState(e.owner) == 'started') then
                        queries[#queries + 1] = { query = ('UPDATE `%s` SET %s WHERE %s'):format(t, e.release, w), values = v }
                        note(key .. ':released', n)
                    else
                        tally(blockers, blocked, key, filter and live or n)
                    end
                elseif ledger and t == 'cb_accounts' then
                    handed = handed + n
                else -- data, core
                    if e.money then
                        tally(funded, fundedBy, key, countWhere(t, w .. (' AND `%s` <> 0'):format(e.money), v))
                        queries[#queries + 1] = { query = ('DELETE FROM `%s` WHERE %s AND `%s` = 0'):format(t, w, e.money), values = v }
                    else
                        queries[#queries + 1] = { query = ('DELETE FROM `%s` WHERE %s'):format(t, w), values = v }
                    end
                    if t == 'cb_accounts' then accounts = true end
                    note(key, n)
                end
            end
        end
    end
    local chain = {}
    for _, e in ipairs(SHAPED) do
        local t, c, kind = e[1], e[2], e[4]
        if has(t, c) then
            local key = t .. '.' .. c
            local rows, pk, compiled = shapedMatches(e, citizenid)
            for _, m in ipairs(rows) do
                if kind == 'history' or not m.live then
                    local _, fresh = chainRewrite(chain, queries, e, pk, m, function(value)
                        if e.whole then return tomb end
                        return reshape(value, compiled, tomb)
                    end)
                    if fresh then note(key .. ':tombstoned', 1) end
                elseif kind == 'asset' then
                    tally(blockers, blocked, key, 1)
                elseif ledger and t == 'cb_accounts' then
                    handed = handed + 1
                else -- data, core
                    local w, v = rowWhere(e, pk, m)
                    if e.money then
                        -- the account's id names it better than the column
                        if (m.money or 0) ~= 0 then tally(funded, fundedBy, tostring(m.key or m.value), 1) end
                        w = w .. (' AND `%s` = 0'):format(e.money)
                    end
                    queries[#queries + 1] = { query = ('DELETE FROM `%s` WHERE %s'):format(t, w), values = v }
                    if t == 'cb_accounts' then accounts = true end
                    note(key, 1)
                end
            end
        end
    end
    local function listed(list, by)
        local out = {}
        for k, key in ipairs(list) do out[k] = ('%s (%d)'):format(key, by[key]) end
        return clip(table.concat(out, ', '), 600)
    end
    if #blockers > 0 then return nil, 'assets', listed(blockers, blocked) end
    if #funded > 0 then
        -- the ledger's purge ran (or could not): money landed on an account of the character since,
        -- or no ledger is running to return it. Nothing is deleted: money is never destroyed.
        return nil, GetResourceState('w_centralbank') == 'started' and 'balance_changed' or 'economy_not_ready', listed(funded, fundedBy)
    end
    addBareJournal(queries, citizenid, tomb, 'purge:' .. tomb)
    if withMap then
        -- informational only: which tombstone the history went to (used() never reads the map)
        queries[#queries + 1] = { query = 'INSERT INTO w_core_citizen_map (old_id, new_id, kind, done_by, done_at) VALUES (?, ?, ?, ?, ?)',
                                  values = { citizenid, tomb, 'deleted', clip(ctx.by, 96), ctx.at } }
    end
    return queries, { counts = counts, accounts = accounts, handed = handed }
end

--- One line per resource for the log: its records removed, the money it returned to the reserve,
--- its notes.
local function summarize(report)
    local out = {}
    local function line(res, r)
        local n = 0
        for k, v in pairs(r) do if k ~= 'money' and type(v) == 'number' then n = n + v end end
        local text = ('%s %s'):format(res, n % 1 == 0 and ('%d'):format(n) or ('%.2f'):format(n))
        if type(r.money) == 'table' then
            local m = {}
            if r.money.USD then m[#m + 1] = ('$%.2f'):format(r.money.USD) end
            if r.money.GOLD then m[#m + 1] = ('%.2f gold'):format(r.money.GOLD) end
            text = text .. ' (' .. table.concat(m, ' + ') .. ' to the reserve)'
        end
        if type(r.notes) == 'string' then text = text .. ' [' .. r.notes .. ']' end
        out[#out + 1] = text
    end
    for _, res in ipairs(PURGE_ORDER) do
        if type(report[res]) == 'table' then line(res, report[res]) end
    end
    if type(report.w_core) == 'table' then line('w_core', report.w_core) end
    return table.concat(out, ' · ')
end

--- Did any purge change something (a count above 0, money moved)?
local function removedSomething(report)
    for _, r in pairs(report) do
        if type(r) == 'table' then
            if r.money ~= nil then return true end
            for _, v in pairs(r) do if type(v) == 'number' and v > 0 then return true end end
        end
    end
    return false
end

--- A deletion that stopped half way (a released house, deleted horses...): the character is not
--- played half-deleted meanwhile. The retry deletes this block with the rest (w_core_character_blocks
--- is 'data'); staff can also lift it in the panel if the deletion is called off. An existing
--- block (staff's own reason) is kept.
local function holdForDeletion(citizenid, by)
    pcall(MySQL.insert.await, 'INSERT IGNORE INTO w_core_character_blocks (citizenid, reason, blocked_by, blocked_at) VALUES (?, ?, ?, ?)',
        { citizenid, clip(Lang:t('info.character_deletion_pending'), 255), clip(by, 96), os.time() })
end

--- Account rows of the character that w_core's pass found after the ledger's purge (a payment in
--- flight re-created one, money landed on one): the ledger's own purge once more, which returns
--- their money to the reserve and deletes them under its lock, out of its memory too. Its summary
--- joins report.w_centralbank. False when the ledger could not (they stay: a leftover, retried).
local function ledgerAgain(citizenid, ctx, report)
    local called, ok, detail = pcall(function() return exports.w_centralbank:PurgeCharacter(citizenid, ctx) end)
    if not called or ok ~= true then
        print(('^3[w_core] purge %s: the ledger did not take the accounts found after its purge: %s^7'):format(
            citizenid, tostring(called and (detail or 'refused') or ok)))
        return false
    end
    local into = type(report.w_centralbank) == 'table' and report.w_centralbank or {}
    for k, v in pairs(contractSummary(detail)) do
        if k == 'money' then
            into.money = into.money or {}
            for cur, n in pairs(v) do into.money[cur] = (into.money[cur] or 0) + n end
        elseif k == 'notes' then
            into.notes = into.notes and clip(into.notes .. '; ' .. v, 300) or v
        else
            into[k] = (into[k] or 0) + v
        end
    end
    report.w_centralbank = into
    return true
end

local RETRY_MS = 30000
--- Something was still filed under the number after the second pass (a row a resource wrote late,
--- money that reached an account after the ledger's purge): one more purge runs by itself once
--- things have settled, the same as `wcore_purge <id> leftovers`. Only once, and never onto a
--- number that has a character again.
local function retryLater(citizenid, by)
    SetTimeout(RETRY_MS, function()
        CreateThread(function()
            if busy[citizenid] or exists(citizenid) or #C.Dependencies(citizenid, true) == 0 then return end
            local ok, a, b, d = C.Purge(citizenid, by .. ' (retry)', { leftovers = true, retry = true })
            if ok and a.clean then
                print(('^2[w_core] purge %s: the automatic retry cleaned the number^7'):format(citizenid))
            elseif ok then
                print(('^1[w_core] purge %s: still not clean after the automatic retry: %s (run `wcore_purge %s leftovers` once it is settled)^7'):format(
                    citizenid, tostring(a.leftovers), citizenid))
            else
                print(('^1[w_core] purge %s: the automatic retry was refused: %s (%s%s)^7'):format(
                    citizenid, tostring(a), tostring(b), d and ('; ' .. tostring(d)) or ''))
            end
        end)
    end)
end

local function purge(citizenid, by, opts)
    local alive = exists(citizenid)
    -- no players row: only a request for the leftovers of a character deleted before the purge
    -- existed (the console's `wcore_purge <id> leftovers`) goes on
    if not alive and not (opts.leftovers and #C.Dependencies(citizenid, true) > 0) then return false, 'not_found', 'w_core' end
    -- the automatic retry cleans a deleted character's leftovers, never a character that holds the
    -- number again (asked here, under `busy`: retryLater's own look was before the scan's awaits)
    if opts.retry and alive then return false, 'id_taken', 'w_core' end
    -- 'restarting', not 'busy': the resource named is starting or stopping, the character is free
    local settling = resourceSettling()
    if settling then return false, 'restarting', settling end
    local okE, whyE, detailE = economyPreflight(citizenid)
    if not okE then return false, whyE, 'w_centralbank', detailE end
    -- an asset whose resource cannot release it now: refused before the kick and before any
    -- resource purged, not by w_core's own pass once the others released theirs
    local stuckAssets = assetPreflight(citizenid)
    if stuckAssets then return false, 'assets', 'w_core', stuckAssets end
    local okK, whyK = kickAndWait(citizenid, opts)
    if not okK then return false, whyK, 'w_core' end

    local at = os.time()
    local ctx = { by = by, at = at, tombstone = ('deleted-%s-%d'):format(citizenid, at) }
    local report = {}
    local okP, whyP, res = callPurges(citizenid, ctx, report)
    if not okP then
        if alive and removedSomething(report) then holdForDeletion(citizenid, by) end
        return false, whyP, res
    end

    -- from here on a late save of this character must not bring its row back: guarded by its
    -- number (C.Next skips it meanwhile) and by its players row, which a Player object of the
    -- deleted character still carries once staff has given the number to someone else
    local rowId = tonumber(MySQL.scalar.await('SELECT id FROM players WHERE citizenid = ?', { citizenid }))
    rowId = rowId and math.floor(rowId)
    -- a refusal below gives the guard back as it was: a retry of leftovers must not lift the guard
    -- the character's own deletion set (its row is gone either way)
    local prevGuard = purgedGuard[citizenid]
    purgedGuard[citizenid] = GetGameTimer() + PURGED_GUARD_MS
    if rowId then purgedRows[rowId] = true end
    local function unguard(why, detail)
        purgedGuard[citizenid] = prevGuard
        if rowId then purgedRows[rowId] = nil end
        if alive and removedSomething(report) then holdForDeletion(citizenid, by) end
        return false, why, 'w_core', detail
    end
    -- the character cannot have been put in play since the kick (Login and CreatePlayer refuse a
    -- busy id), but its rows are about to go: a player in play now is kicked, and a save that
    -- started during the resource purges (an offline Player object) lands first
    local okK2, whyK2 = kickAndWait(citizenid, {})
    if not okK2 then return unguard(whyK2) end
    -- while the ledger runs, the character's account rows are its own to delete: one found after
    -- its purge (a payment in flight re-created it, money landed on it) goes back to its purge
    -- first, and the pass is planned again (with its new journal row). An account row the ledger
    -- then leaves is not one it counts as the character's (w_core's registry names more kinds):
    -- w_core takes it as with no ledger, at balance 0, and a funded one refuses before any change.
    local ledger = GetResourceState('w_centralbank') == 'started'
    local ledgerTook = false
    local queries, info, detail = purgeQueries(citizenid, ctx, true, ledger)
    if queries and info.handed > 0 then
        ledgerTook = ledgerAgain(citizenid, ctx, report)
        queries, info, detail = purgeQueries(citizenid, ctx, true, ledger and not ledgerTook)
    end
    if not queries then
        print(('^3[w_core] purge %s refused by w_core: %s (%s)^7'):format(citizenid, tostring(info), tostring(detail)))
        return unguard(info, detail)
    end
    local okT, done = pcall(MySQL.transaction.await, queries)
    if not okT or done ~= true then
        print(('^1[w_core] purge %s: the final transaction failed: %s^7'):format(citizenid, tostring(done)))
        return unguard('database')
    end
    -- the account rows w_core deleted (no ledger running, or ones the ledger left) leave its memory
    -- before anything else runs
    if info.accounts then reloadLedger() end

    -- nothing may be left under the number: a late write (a save, a resource re-creating a row)
    -- is taken by one more pass over the registry (an account the ledger has not been offered
    -- stays: the automatic retry's ledger purge takes it)
    local left = C.Dependencies(citizenid)
    if #left > 0 then
        local again, info2 = purgeQueries(citizenid, ctx, false, ledger and not ledgerTook)
        if again and #again > 0 then
            local okA, doneA = pcall(MySQL.transaction.await, again)
            if okA and doneA == true then
                for k, n in pairs(info2.counts) do info.counts[k] = (info.counts[k] or 0) + n end
                if info2.accounts then reloadLedger() end
            end
        end
        left = C.Dependencies(citizenid)
    end
    report.w_core = info.counts
    report.tombstone = ctx.tombstone
    report.clean = #left == 0
    if #left > 0 then
        report.leftovers = clip(describe(left), 600)
        print(('^3[w_core] purge %s: still filed under the number: %s (%s)^7'):format(citizenid, report.leftovers,
            opts.retry and ('run `wcore_purge ' .. citizenid .. ' leftovers` once it is settled') or 'an automatic retry runs in 30 s'))
        if not opts.retry then retryLater(citizenid, by) end
    end

    -- its own channel: w_logs drops the legacy 'joinleave' while w_core reports joins itself
    TriggerEvent('w_log:server:CreateLog', 'character-delete', 'Character Deleted', 'red',
        ('Character **%s** deleted by %s; its history is kept as %s.\n%s%s'):format(citizenid, tostring(by), ctx.tombstone, summarize(report),
            report.clean and '' or ('\nStill under the number: ' .. report.leftovers)))
    TriggerEvent('w_core:server:characterDeleted', citizenid, ctx.tombstone)
    return true, report
end

--- Delete a character and EVERYTHING it has, so its number is clean for someone else:
--- the player is kicked (and its logout save awaited), every resource purges its own part
--- (assets released, money returned to the reserve by w_centralbank), w_core deletes what is
--- left and moves the history to the tombstone 'deleted-<id>-<unixtime>'.
--- opts: { requester = <source asking for its own character>, leftovers = true (no players row:
--- only what a character deleted before the purge existed left behind), retry = true (the
--- automatic retry itself: never schedules another) }.
--- Returns
---   true, report:
---     report[<resource>] = what its PurgeCharacter did, in the shared contract (every field optional):
---                          { <what> = <integer count>, money = { USD = <dollars>, GOLD = <gold> },
---                            notes = '<text>' }; a started resource without the export:
---                          { notes = 'no PurgeCharacter export: skipped' }
---     report.w_core      = w_core's own pass: { ['<table>.<column>'] = rows deleted,
---                          ['<table>.<column>:tombstoned'] = history rows moved,
---                          ['<table>.<column>:released'] = assets released }
---     report.tombstone   = 'deleted-<id>-<unixtime>': where the history went
---     report.clean       = true: nothing is filed under the number any more
---     report.leftovers   = (clean == false only) what is still under it; one automatic retry runs
---                          30 s later (`wcore_purge <id> leftovers` does the same by hand)
---   false, reason, resource, detail:
---     resource  'w_core' for w_core's own reasons, else the resource that refused;
---     detail    the blockers for 'assets', the funded accounts for 'balance_changed' and w_core's
---               'economy_not_ready' ('<table>.<column> (n)' / '<account id> (1)', comma separated;
---               an asset refused up front adds its resource: '<table>.<column> (n) [<res>: <state>]').
---     w_core's reasons: not_ready, invalid_id, not_found, busy (being deleted or moved, or the
---     requester has it in play), still_online (the kick or a save did not finish), assets (before
---     anyone is kicked when the resource that releases one is not started; else one it did not release),
---     balance_changed / economy_not_ready (an account still funded while no ledger runs to return
---     it; a running ledger takes it itself), database, error (w_core threw), forbidden (the export's
---     caller), id_taken (the automatic retry only: the number holds a character again).
---     From a resource: 'restarting' (w_core: it is starting or stopping),
---     'economy_not_ready' from w_centralbank (the ledger is not ready), 'error' (its PurgeCharacter
---     threw), or its own refusal word.
function C.Purge(value, by, opts)
    opts = type(opts) == 'table' and opts or {}
    if not ready then return false, 'not_ready', 'w_core' end
    local citizenid = C.Normalize(value)
    if not citizenid then return false, 'invalid_id', 'w_core' end
    if busy[citizenid] then return false, 'busy', 'w_core' end
    busy[citizenid] = true
    by = clip((tostring(by or 'console'):gsub('%c', ' ')), 96)
    if by == '' then by = 'console' end
    local result = table.pack(pcall(purge, citizenid, by, opts))
    busy[citizenid] = nil
    if not result[1] then
        print(('^1[w_core] purge %s failed: %s^7'):format(citizenid, tostring(result[2])))
        return false, 'error', 'w_core'
    end
    return table.unpack(result, 2, result.n)
end
-- the name the admin panel and older callers use
C.Delete = C.Purge

-- ── handing a number to another character ──────────────────────────────────
local FRESH_TRIES = 5

--- The steps of TransferNumber (its doc below), under `busy` for n and target; `hold` marks the
--- fresh number busy too, `state.movedTo` records that the holder moved (for an error after it).
local function transfer(n, target, by, hold, state)
    if not exists(n) then return false, 'not_found' end
    if not exists(target) then return false, 'target_not_found' end
    -- everything that can refuse is asked before anyone is kicked
    local settling = resourceSettling()
    if settling then return false, 'restarting', settling end
    if ledgerNotReady() then return false, 'economy_not_ready' end
    -- the holder's new number: clean in full (C.Next looks at the quick signs only), held at once.
    -- A number Next handed out and this skips stays unused (the counter only climbs).
    local fresh
    for _ = 1, FRESH_TRIES do
        local f = C.Next()
        if not busy[f] then
            hold(f)
            if not used(f) then fresh = f break end
        end
    end
    if not fresh then return false, 'no_fresh_id' end
    -- both leave the game; their logout saves and the other resources' playerDropped saves land
    -- before any row moves (a save landing after it would file a row under the old number)
    local message = Lang:t('info.character_moved')
    local okA, whyA = kickAndWait(n, { message = message })
    if not okA then return false, whyA end
    local okB, whyB = kickAndWait(target, { message = message })
    if not okB then return false, whyB end

    -- 1. the holder leaves n with everything it has (nothing of it stays for the target)
    local okM, a, detailA = move(n, fresh, by, 'transfer')
    -- id_taken here: the fresh number turned out not clean (an account the ledger has under it);
    -- nothing moved, and it is not the "n not clean after the holder left" of the second step
    if not okM then return false, a == 'id_taken' and 'no_fresh_id' or a, detailA end
    state.movedTo = fresh
    -- 2. the target takes n, only onto a clean number: a row written late under n would join it
    local left = C.Dependencies(n)
    if #left > 0 or exists(n) then
        local what = clip(describe(left), 600)
        print(('^1[w_core] citizen: transfer of %s stopped half way: %s moved to %s, but %s is not clean (%s); %s keeps %s^7'):format(
            n, n, fresh, n, what, target, target))
        TriggerEvent('w_log:server:CreateLog', 'character-reassign', 'Citizen ID transfer stopped half way', 'red',
            ('%s -> %s done; %s -> %s NOT done (%s not clean: %s) by %s'):format(n, fresh, target, n, n, what, by))
        return false, 'id_taken', what, fresh
    end
    local okN, b, detailB = move(target, n, by, 'transfer')
    if not okN then
        print(('^1[w_core] citizen: transfer of %s stopped half way: %s moved to %s, but %s -> %s failed: %s%s; %s has no holder^7'):format(
            n, n, fresh, target, n, tostring(b), detailB and (' (' .. tostring(detailB) .. ')') or '', n))
        TriggerEvent('w_log:server:CreateLog', 'character-reassign', 'Citizen ID transfer stopped half way', 'red',
            ('%s -> %s done; %s -> %s NOT done (%s) by %s'):format(n, fresh, target, n, tostring(b), by))
        return false, b, detailB, fresh
    end
    TriggerEvent('w_log:server:CreateLog', 'character-reassign', 'Citizen ID transferred', 'orange',
        ('%s handed to %s by %s: %s -> %s, %s -> %s'):format(n, target, by, n, fresh, target, n))
    local rest = C.Dependencies(target)
    if #rest > 0 then print(('^3[w_core] citizen: transfer of %s done, but %s is not clean: %s^7'):format(n, target, describe(rest))) end
    return true, { number = n, movedTo = fresh, freed = target, a = a, b = b }
end

--- Hand the number `n` to another character in one step: the character holding it moves to a
--- fresh number (C.Next) with everything it has, then `target` (a character's number) moves onto
--- `n` with everything it has; the target's old number is left clean. Both are kicked if in play
--- (their logout saves awaited); n, target and the fresh number are held busy throughout.
--- Refused before anyone is kicked when a step cannot be done. Two transactions, the holder's
--- first: if the target's move then fails, the holder keeps its new number, `n` has no holder, and
--- the answer says so (movedTo) -- never silently.
--- Returns
---   true, { number = n, movedTo = <the holder's new number>, freed = <the target's old number>,
---           a = <the holder's move: touched>, b = <the target's move: touched> }
---   false, reason, detail, movedTo (set only once the holder moved: the target's move failed)
---     reasons: not_ready, invalid_id, same_id, busy, not_found (no character holds n),
---     target_not_found, restarting (detail = the resource), economy_not_ready, no_fresh_id (no clean
---     new number for the holder, also when the ledger finds one taken at the first move),
---     still_online, id_taken (n not clean after the holder left; detail = what is under it),
---     accounts_changed, database, error, forbidden (the export's caller)
function C.TransferNumber(value, target, by)
    if not ready then return false, 'not_ready' end
    local n, t = C.Normalize(value), C.Normalize(target)
    -- the target takes n: a number, as any id handed out (Reassign)
    if not n or not t or not C.IsNumeric(n) then return false, 'invalid_id' end
    if n == t then return false, 'same_id' end
    if busy[n] or busy[t] then return false, 'busy' end
    busy[n], busy[t] = true, true
    local held, state = {}, {}
    local function hold(id) busy[id] = true held[#held + 1] = id end
    by = clip((tostring(by or 'console'):gsub('%c', ' ')), 96)
    if by == '' then by = 'console' end
    local result = table.pack(pcall(transfer, n, t, by, hold, state))
    busy[n], busy[t] = nil, nil
    for _, id in ipairs(held) do busy[id] = nil end
    if not result[1] then
        print(('^1[w_core] citizen: transfer of %s to %s failed: %s%s^7'):format(n, t, tostring(result[2]),
            state.movedTo and ('; the holder already moved to ' .. state.movedTo) or ''))
        return false, 'error', nil, state.movedTo
    end
    return table.unpack(result, 2, result.n)
end

-- ── the one-time migration: random ids -> 1, 2, 3 ... ──────────────────────
local function oldIdsInOrder()
    local out = {}
    for _, r in ipairs(MySQL.query.await('SELECT citizenid FROM players ORDER BY id') or {}) do
        if tostring(r.citizenid):match(OLD_FORMAT) then out[#out + 1] = r.citizenid end
    end
    return out
end

local OLD_TOKEN = '%f[%w](%u%u%u%d%d%d%d%d)%f[%W]'

--- Every text column of the database (the migration sweeps them all: an old id is unmistakable).
local function textColumns()
    return MySQL.query.await([[SELECT table_name AS t, column_name AS c FROM information_schema.columns
        WHERE table_schema = DATABASE() AND data_type IN ('char','varchar','text','tinytext','mediumtext','longtext','json')
        AND table_name NOT LIKE '%\_\_cid\_backup']]) or {}
end

--- The values of `cols` that match `regex` and that `rewrite` changes: { t, c, old, new }.
local function sweep(cols, regex, rewrite)
    local plan = {}
    for _, col in ipairs(cols) do
        local rows = MySQL.query.await(('SELECT DISTINCT `%s` AS v FROM `%s` WHERE `%s` REGEXP BINARY ?'):format(col.c, col.t, col.c), { regex }) or {}
        for _, r in ipairs(rows) do
            local nv = rewrite(tostring(r.v))
            if nv ~= r.v then plan[#plan + 1] = { t = col.t, c = col.c, old = r.v, new = nv } end
        end
    end
    return plan
end

--- A copy of every table the plan changes (<table>__cid_backup, once). Returns true | false, err.
local function backupTables(plan, done)
    for _, p in ipairs(plan) do
        if not done[p.t] then
            local okB, errB = pcall(MySQL.query.await, ('CREATE TABLE IF NOT EXISTS `%s__cid_backup` AS SELECT * FROM `%s`'):format(p.t, p.t))
            if not okB then return false, ('backup of %s failed: %s'):format(p.t, tostring(errB)) end
            done[p.t] = true
        end
    end
    return true
end

--- As move(): from here on a Player object that still carries `old` does not save (its INSERT ...
--- ON DUPLICATE KEY UPDATE would bring a ghost row back under the old id, which the next
--- `wcore_citizenid run` would take for a character still to migrate). Returns rowId, the undo.
local function holdMovedRow(old, new)
    local rowId = tonumber(MySQL.scalar.await('SELECT id FROM players WHERE citizenid = ?', { old }))
    rowId = rowId and math.floor(rowId)
    local prevRow, prevGuard = rowId and movedRows[rowId], purgedGuard[old]
    if rowId then movedRows[rowId] = new end
    purgedGuard[old] = GetGameTimer() + PURGED_GUARD_MS
    return rowId, function()
        if rowId then movedRows[rowId] = prevRow end
        purgedGuard[old] = prevGuard
    end
end

--- One character of the migration while w_centralbank runs, the way move() does a reassign: its
--- accounts (every cb_accounts row whose id or owner holds the old id) are renamed by the ledger
--- under its own lock, in ONE transaction with every other value that holds the old id and its
--- map row. Renamed in w_core's own transaction and reloaded afterwards, a ledger transfer planned
--- from memory meanwhile would book only one side (CB.transact does not check the rows it updates).
--- Each attempt sweeps again, for this old id only: the characters before it already moved (a
--- value may hold several old ids), and a row written while it waited for the ledger's lock is
--- in the new plan. Returns true | nil (a ledger without the export: nothing done) | false, reason, detail.
local function migrateOne(old, new, cols, backedUp)
    local rowId, undo = holdMovedRow(old, new)
    local okW, whyW = waitSaves(old)
    if not okW then undo() return false, whyW end
    local swap = function(v) return (v:gsub(OLD_TOKEN, function(tok) if tok == old then return new end end)) end
    local mapRow = { query = 'INSERT INTO w_core_citizen_map (old_id, new_id, kind, done_by, done_at) VALUES (?, ?, ?, ?, ?)',
                     values = { old, new, 'migration', 'console', os.time() } }
    local seqRow = { query = "INSERT INTO w_core_citizen_seq (k, v) VALUES ('citizen', ?) ON DUPLICATE KEY UPDATE v = GREATEST(v, VALUES(v))",
                     values = { math.floor(tonumber(new)) } }
    for attempt = 1, 3 do
        -- a read that raises gives the guard back (nothing moved): kept, the character still on
        -- `old` would be refused at every login until a restart (C.RowMoved)
        local okS, plan = pcall(sweep, cols, old, swap)
        if not okS then undo() return false, 'database', tostring(plan) end
        local okB, errB = backupTables(plan, backedUp)
        if not okB then undo() return false, 'database', errB end
        local queries, accounts = {}, {}
        for _, p in ipairs(plan) do
            -- the ledger's own rows go in its plan (below), renamed by it
            if not (p.t == 'cb_accounts' and (p.c == 'id' or p.c == 'owner')) then
                queries[#queries + 1] = { query = ('UPDATE `%s` SET `%s` = ? WHERE BINARY `%s` = ?'):format(p.t, p.c, p.c), values = { p.new, p.old } }
            end
        end
        queries[#queries + 1] = mapRow
        queries[#queries + 1] = seqRow
        local okA, rows = pcall(MySQL.query.await, 'SELECT `id`, `owner` FROM `cb_accounts` WHERE INSTR(BINARY `id`, ?) > 0 OR INSTR(BINARY `owner`, ?) > 0', { old, old })
        if not okA then undo() return false, 'database', tostring(rows) end
        for _, r in ipairs(rows or {}) do
            local owner = r.owner ~= nil and tostring(r.owner) or nil
            local to, newOwner = swap(tostring(r.id)), owner and swap(owner)
            if to ~= r.id or newOwner ~= owner then
                accounts[#accounts + 1] = { id = r.id, to = to, owner = newOwner ~= owner and newOwner or nil }
            end
        end
        local ok, why, detail = ledgerRename(old, new, accounts, queries)
        if ok == nil then undo() return nil end
        -- 'database' may be a lost commit acknowledgement: the rows moved (then the ledger's own
        -- reload may be what failed, so its memory is reloaded once more: viaLedger false)
        local moved = ok
        if not ok and why == 'database' and rowId then
            local okC, n = pcall(MySQL.scalar.await, 'SELECT COUNT(*) FROM players WHERE citizenid = ? AND id = ?', { new, rowId })
            -- unreadable: the rows may have moved, so the guard stays (a stale save of `old` must
            -- not write a ghost row); the run stops and says so
            if not okC then return false, 'database', 'commit unknown: ' .. tostring(n) end
            moved = (tonumber(n) or 0) > 0
        end
        if moved then
            purgedGuard[new] = nil
            afterRename(old, new, ok == true)
            return true
        end
        -- an account of the character was created between the plan and the lock: plan again
        if why ~= 'accounts_changed' or attempt == 3 then undo() return false, why, detail end
    end
end

--- The migration's writes (C.Migrate 'run', the ids held busy): with the ledger running, one
--- transaction per character through it (migrateOne); without it (or an older ledger without
--- RenameCharacterAccounts, which answers so before anything moved), the old way: `plan` in one
--- transaction for all, then the ledger's memory reloads (afterRename). `state.done` counts the
--- characters migrated (for an error half way). Returns done, failure message | nil.
local function migrateRun(olds, map, plan, last, cols, state)
    local backedUp = {}
    local okB, errB = backupTables(plan, backedUp)
    if not okB then return 0, 'stopped: ' .. errB end
    if ledgerStarted() then
        for i, old in ipairs(olds) do
            local ok, why, detail = migrateOne(old, map[old], cols, backedUp)
            if ok == nil and i == 1 then break end
            if not ok then
                return state.done, ('stopped at %s -> %s: %s%s'):format(old, map[old], tostring(why or 'error'), detail and (' (' .. tostring(detail) .. ')') or '')
            end
            state.done = i
        end
        if state.done == #olds then return state.done end
    end
    local undos = {}
    for _, old in ipairs(olds) do
        -- its read raising leaves the guards already taken given back (see migrateOne)
        local okH, errH, undo = pcall(holdMovedRow, old, map[old])
        if not okH then for _, u in ipairs(undos) do u() end return 0, ('%s: %s'):format(old, tostring(errH)) end
        undos[#undos + 1] = undo
        local okW, whyW = waitSaves(old)
        if not okW then for _, u in ipairs(undos) do u() end return 0, ('%s: %s'):format(old, whyW) end
    end
    local queries = {}
    for _, p in ipairs(plan) do
        queries[#queries + 1] = { query = ('UPDATE `%s` SET `%s` = ? WHERE BINARY `%s` = ?'):format(p.t, p.c, p.c), values = { p.new, p.old } }
    end
    for _, old in ipairs(olds) do
        queries[#queries + 1] = { query = 'INSERT INTO w_core_citizen_map (old_id, new_id, kind, done_by, done_at) VALUES (?, ?, ?, ?, ?)',
                                  values = { old, map[old], 'migration', 'console', os.time() } }
    end
    queries[#queries + 1] = { query = "INSERT INTO w_core_citizen_seq (k, v) VALUES ('citizen', ?) ON DUPLICATE KEY UPDATE v = GREATEST(v, VALUES(v))", values = { math.floor(last) } }
    local ok, committed = pcall(MySQL.transaction.await, queries)
    if not ok or committed ~= true then
        for _, u in ipairs(undos) do u() end
        return 0, 'failed and was rolled back: ' .. tostring(committed)
    end
    state.done = #olds
    for _, old in ipairs(olds) do
        purgedGuard[map[old]] = nil
        afterRename(old, map[old])
    end
    return #olds
end

--- mode 'check' prints the plan; 'run' does it (every player must be offline; a backup copy of
--- each table touched is kept as <table>__cid_backup). While w_centralbank runs, each character
--- is one transaction through the ledger (migrateOne); a run that stops half way says how many
--- moved, and running it again migrates the rest (the characters still on an old id).
function C.Migrate(mode)
    if not ready then return print('[w_core] citizen: not ready yet') end
    local olds = oldIdsInOrder()
    if #olds == 0 then return print('[w_core] citizen: no character with an old id; nothing to migrate') end
    local start = tonumber(MySQL.scalar.await("SELECT COALESCE(MAX(CAST(citizenid AS UNSIGNED)), 0) FROM players WHERE citizenid REGEXP '^[0-9]+$'")) or 0
    -- the counter may be ahead of the players (a number C.Next handed out whose character was
    -- deleted since): never go below it, and skip every taken number on the way (used())
    local seq = tonumber(MySQL.scalar.await("SELECT v FROM w_core_citizen_seq WHERE k = 'citizen'")) or 0
    if seq > start then start = math.floor(seq) end
    local map, reverse, last = {}, {}, start
    for _, old in ipairs(olds) do
        repeat last = last + 1 until not used(idOf(last))
        map[old] = idOf(last) reverse[#reverse + 1] = old
    end
    -- every text column of the database that holds an old id (they are unmistakable: AAA00000);
    -- the old ids are [A-Z]{3}[0-9]{5}: one REGEXP finds every value that may hold one
    local cols = textColumns()
    local plan = sweep(cols, '[A-Z]{3}[0-9]{5}', function(v) return (v:gsub(OLD_TOKEN, function(tok) return map[tok] end)) end)
    local byColumn = {}
    for _, p in ipairs(plan) do local k = p.t .. '.' .. p.c byColumn[k] = (byColumn[k] or 0) + 1 end
    print(('[w_core] citizen migration: %d character(s)'):format(#olds))
    for _, old in ipairs(olds) do print(('    %s -> %s'):format(old, map[old])) end
    for k, n in pairs(byColumn) do print(('    %-48s %d value(s)'):format(k, n)) end
    if mode ~= 'run' then return print('[w_core] citizen: check only; run `wcore_citizenid run` with the server empty') end
    if #GetPlayers() > 0 then return print('^1[w_core] citizen: every player must be offline^7') end
    -- a ledger that runs but is not ready renames nothing (as a reassign waits for it)
    if ledgerNotReady() then return print('^1[w_core] citizen: the economy (w_centralbank) is not ready; nothing migrated^7') end
    for _, old in ipairs(olds) do
        if busy[old] or busy[map[old]] then return print(('^1[w_core] citizen: %s or %s is being worked on; try again^7'):format(old, map[old])) end
    end
    -- the old ids and their new numbers are held for the whole run: no login of an old id, no
    -- purge or reassign of either, and C.Next hands out no planned number while the run waits
    -- for the ledger's lock between two characters
    for _, old in ipairs(olds) do busy[old], busy[map[old]] = true, true end
    local state = { done = 0 }
    local okR, done, failure = pcall(migrateRun, olds, map, plan, last, cols, state)
    for _, old in ipairs(olds) do busy[old], busy[map[old]] = nil, nil end
    forgetSchema()
    if not okR then failure, done = 'failed: ' .. tostring(done), state.done end
    if failure then
        return print(('^1[w_core] citizen: the migration %s; %d of %d character(s) migrated, run it again for the rest^7'):format(failure, done, #olds))
    end
    print(('^2[w_core] citizen: %d character(s) migrated, %d value(s) rewritten; backups: <table>__cid_backup^7'):format(#olds, #plan))
end

RegisterCommand('wcore_citizenid', function(source, args)
    if source ~= 0 then return end -- the server console only
    CreateThread(function() C.Migrate(args[1] == 'run' and 'run' or 'check') end)
end, true)

-- `wcore_purge <id>`: delete a character from the console (the same purge as the admin panel).
-- `wcore_purge <id> leftovers`: the rows and the money a character deleted before the purge
-- existed left under its id (no players row any more), so the number (or the old id's money) is
-- cleaned up the same way.
RegisterCommand('wcore_purge', function(source, args)
    if source ~= 0 then return end -- the server console only
    CreateThread(function()
        local ok, a, b, d = C.Purge(args[1], 'console', { leftovers = args[2] == 'leftovers' })
        if ok then print(('^2[w_core] purge %s: done %s^7'):format(tostring(args[1]), json.encode(a)))
        else print(('^1[w_core] purge %s refused: %s (%s%s)^7'):format(tostring(args[1]), tostring(a), tostring(b), d and ('; ' .. tostring(d)) or '')) end
    end)
end, true)

-- ── exports (w_admin, w_creators, any resource) ────────────────────────────
exports('ResolveCitizen', function(id) return C.Resolve(id) end)
exports('NormalizeCitizenId', function(id) return C.Normalize(id) end)
exports('GetCharacterBlock', function(id) return C.GetBlock(id) end)
exports('CharacterDependencies', function(id) return C.Dependencies(id) end)
-- Deleting, moving and blocking a character is staff's (the admin panel) and w_core's own (the
-- console; the player's own deletion reaches WCore.Player.DeleteCharacter through the core object,
-- not these exports): any other resource could otherwise wipe a live character or move it onto a
-- sold number, and every resource's PurgeCharacter trusts w_core alone.
local function mayDelete()
    local caller = GetInvokingResource()
    return caller == nil or caller == 'w_admin' or caller == GetCurrentResourceName()
end
exports('BlockCharacter', function(id, reason, by)
    if not mayDelete() then return false, 'forbidden' end
    return C.Block(id, reason, by)
end)
exports('UnblockCharacter', function(id)
    if not mayDelete() then return false, 'forbidden' end
    return C.Unblock(id)
end)
exports('ReassignCitizenId', function(old, new, by)
    if not mayDelete() then return false, 'forbidden' end
    return C.Reassign(old, new, by)
end)
-- C.TransferNumber's answer: true, report | false, reason, detail, movedTo
exports('TransferCitizenNumber', function(n, target, by)
    if not mayDelete() then return false, 'forbidden' end
    return C.TransferNumber(n, target, by)
end)
-- C.Purge's answer: true, report | false, reason, resource, detail
exports('DeleteCharacterByStaff', function(id, by)
    if not mayDelete() then return false, 'forbidden', 'w_core' end
    return C.Purge(id, by)
end)
exports('PurgeCharacterAll', function(id, by, opts)
    if not mayDelete() then return false, 'forbidden', 'w_core' end
    return C.Purge(id, by, opts)
end)
