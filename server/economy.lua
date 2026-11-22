-- Economy layer: delegates to w_centralbank when started (closed economy),
-- and manages standard server balances directly on PlayerData / players.money when w_centralbank is not installed.
WCore.Economy = {}

local function roundCents(n)
    return math.floor((tonumber(n) or 0) * 100 + 0.5) / 100
end

local function disallowsMinus(kind)
    for _, k in ipairs((WCore.Config and WCore.Config.Money and WCore.Config.Money.DontAllowMinus) or {}) do
        if k == kind then return true end
    end
    return false
end

function WCore.Economy.usesCentralBank()
    return GetResourceState('w_centralbank') == 'started'
end

function WCore.Economy.ready()
    if WCore.Economy.usesCentralBank() then
        return exports.w_centralbank:IsReady() == true
    end
    return true
end

function WCore.Economy.hydrate(data, isNew)
    if WCore.Economy.usesCentralBank() then
        if not WCore.Economy.ready() then return false end
        local money = exports.w_centralbank:HydratePlayer(data.citizenid, isNew)
        if not money then return false end
        data.money = money
        return true
    end

    -- Standard server-managed economy (no w_centralbank)
    local money = type(data.money) == 'table' and data.money or {}
    local defaults = (WCore.Config and WCore.Config.Money and WCore.Config.Money.MoneyTypes) or { cash = 30, bank = 50, gold = 0, bloodmoney = 0 }
    for kind, startAmt in pairs(defaults) do
        if isNew or money[kind] == nil then
            money[kind] = roundCents(startAmt)
        else
            money[kind] = roundCents(money[kind])
        end
    end
    -- Keep gold and bloodmoney aligned
    local g = roundCents(money.gold ~= nil and money.gold or money.bloodmoney or 0)
    money.gold = g
    money.bloodmoney = g
    data.money = money

    if isNew and data.citizenid then
        TriggerEvent('w_centralbank:starterPaid', data.citizenid)
    end
    return true
end

function WCore.Economy.change(self, kind, amount, mode, reason)
    if not WCore.Economy.ready() or type(kind) ~= 'string' then return false end
    kind = kind:lower()
    if kind == 'bloodmoney' then kind = 'gold' end
    amount = tonumber(amount)
    if not amount or amount ~= amount or amount < 0 or amount > 1000000000 then return false end
    if kind ~= 'cash' and kind ~= 'bank' and kind ~= 'gold' then return false end

    if WCore.Economy.usesCentralBank() then
        local ok
        if mode == 'set' then
            ok = exports.w_centralbank:SetPlayerBalance(self.PlayerData.citizenid, kind, amount, reason or 'core-set')
        else
            ok = exports.w_centralbank:AdjustPlayer(self.PlayerData.citizenid, kind, mode == 'remove' and -amount or amount, reason or ('core-' .. mode))
        end
        if not ok then return false end
        WCore.Economy.hydrate(self.PlayerData, false)
        if not self.Offline then self.Functions.UpdatePlayerData() end
        return true
    end

    -- Standard server-managed economy
    amount = roundCents(amount)
    self.PlayerData.money = type(self.PlayerData.money) == 'table' and self.PlayerData.money or {}
    local current = roundCents(self.PlayerData.money[kind] or 0)
    local nextVal = current

    if mode == 'add' then
        nextVal = roundCents(current + amount)
    elseif mode == 'remove' then
        if disallowsMinus(kind) and (current + 0.0001) < amount then
            return false
        end
        nextVal = roundCents(current - amount)
    elseif mode == 'set' then
        if disallowsMinus(kind) and amount < 0 then
            return false
        end
        nextVal = amount
    else
        return false
    end

    self.PlayerData.money[kind] = nextVal
    if kind == 'gold' then self.PlayerData.money.bloodmoney = nextVal end

    local delta = roundCents(nextVal - current)
    if not self.Offline then
        self.Functions.UpdatePlayerData()
        if delta ~= 0 then
            TriggerClientEvent('hud:client:OnMoneyChange', self.PlayerData.source, kind, math.abs(delta), delta < 0)
            TriggerEvent('WCore:Server:OnMoneyChange', self.PlayerData.source, kind, math.abs(delta), delta < 0 and 'remove' or 'add', reason or ('core-' .. mode))
        end
    else
        self.Functions.Save()
    end
    return true
end

AddEventHandler('w_centralbank:balanceChanged', function(account, balance)
    if not WCore.Economy.usesCentralBank() then return end
    local cid, kind = account:match('^player:(.-):([^:]+)$')
    if not cid then return end
    balance = exports.w_centralbank:GetBalance(account)
    if balance == nil then return end
    local p = WCore.Functions.GetPlayerByCitizenId(cid)
    if not p then return end
    local previous = tonumber(p.PlayerData.money[kind]) or 0
    p.PlayerData.money[kind] = balance
    if kind == 'gold' then p.PlayerData.money.bloodmoney = balance end
    p.Functions.UpdatePlayerData()
    local delta = balance - previous
    if delta ~= 0 then
        TriggerClientEvent('hud:client:OnMoneyChange', p.PlayerData.source, kind, math.abs(delta), delta < 0)
        TriggerEvent('WCore:Server:OnMoneyChange', p.PlayerData.source, kind, math.abs(delta), delta < 0 and 'remove' or 'add', 'central-ledger')
    end
end)
