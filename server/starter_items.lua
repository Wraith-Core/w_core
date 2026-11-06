-- ════════════════════════════════════════════════════════════════════════════
-- w_core · server/starter_items.lua — the bag a new character starts with (owner 2026-11-06)
--
--   WConfig.StarterItems (2 water + 2 bread) go into the bag once, right after w_centralbank paid the
--   character's starter money (event w_centralbank:starterPaid). The bank already limits starters per
--   account (starterPerLicense), so deleting and creating a character again does not hand them out again.
--   w_inventory sets the bag up after the player loaded; we wait for it (up to 30 s). Done once per
--   character id (KVP), even if the player leaves at once.
-- ════════════════════════════════════════════════════════════════════════════

local function bagReady(src)
    local ok, inv = pcall(function() return exports.w_inventory:GetInventory(src) end)
    return ok and inv ~= nil
end

AddEventHandler('w_centralbank:starterPaid', function(cid)
    if type(cid) ~= 'string' or cid == '' then return end
    local key = 'starteritems:' .. cid
    if GetResourceKvpInt(key) == 1 then return end
    CreateThread(function()
        local deadline = GetGameTimer() + 30000
        local src
        while GetGameTimer() < deadline do
            local Player = WCore.Functions.GetPlayerByCitizenId(cid)
            src = Player and Player.PlayerData and Player.PlayerData.source
            if src and GetPlayerName(src) and bagReady(src) then break end
            src = nil
            Wait(500)
        end
        if not src then
            print(('^1[w_core] starter items failed: the bag of %s was not ready^7'):format(cid))
            return
        end
        SetResourceKvpInt(key, 1)
        for _, e in ipairs(WConfig.StarterItems or {}) do
            local ok, added = pcall(function() return exports.w_inventory:AddItem(src, e.item, e.amount) end)
            if not ok or not added then
                print(('^1[w_core] starter item failed: %s x%d for %s^7'):format(tostring(e.item), tonumber(e.amount) or 0, cid))
            end
        end
    end)
end)
