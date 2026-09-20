-- The central ledger owns balances. PlayerData and players.money are projections.
WCore.Economy = {}
function WCore.Economy.ready()
    return GetResourceState('w_centralbank')=='started' and exports.w_centralbank:IsReady()
end
function WCore.Economy.hydrate(data,isNew)
    if not WCore.Economy.ready() then return false end
    local money=exports.w_centralbank:HydratePlayer(data.citizenid,isNew)
    if not money then return false end
    data.money=money
    return true
end
function WCore.Economy.change(self,kind,amount,mode,reason)
    if not WCore.Economy.ready() or type(kind)~='string' then return false end
    kind=kind:lower();if kind=='bloodmoney' then kind='gold' end
    amount=tonumber(amount)
    if not amount or amount~=amount or amount<0 or amount>1000000000 then return false end
    if kind~='cash' and kind~='bank' and kind~='gold' then return false end
    local ok
    if mode=='set' then ok=exports.w_centralbank:SetPlayerBalance(self.PlayerData.citizenid,kind,amount,reason or 'core-set')
    else ok=exports.w_centralbank:AdjustPlayer(self.PlayerData.citizenid,kind,mode=='remove' and -amount or amount,reason or ('core-'..mode)) end
    if not ok then return false end
    WCore.Economy.hydrate(self.PlayerData,false)
    if not self.Offline then self.Functions.UpdatePlayerData() end
    return true
end
AddEventHandler('w_centralbank:balanceChanged',function(account,balance)
    local cid,kind=account:match('^player:(.-):([^:]+)$')
    if not cid then return end
    balance=exports.w_centralbank:GetBalance(account)
    if balance==nil then return end
    local p=WCore.Functions.GetPlayerByCitizenId(cid)
    if not p then return end
    local previous=tonumber(p.PlayerData.money[kind]) or 0
    p.PlayerData.money[kind]=balance
    if kind=='gold' then p.PlayerData.money.bloodmoney=balance end
    p.Functions.UpdatePlayerData()
    local delta=balance-previous
    if delta~=0 then
        TriggerClientEvent('hud:client:OnMoneyChange',p.PlayerData.source,kind,math.abs(delta),delta<0)
        TriggerEvent('WCore:Server:OnMoneyChange',p.PlayerData.source,kind,math.abs(delta),delta<0 and 'remove' or 'add','central-ledger')
    end
end)
