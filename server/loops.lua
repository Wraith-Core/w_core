-- Update Player Loop --
CreateThread(function()
    local timeout = 60000 * WCore.Config.UpdateInterval
    while true do
        Wait(timeout)

        -- w_hud owns hunger and thirst (its own table, mirrored into the metadata); when it
        -- runs, decaying them here as well would double the rate. Only the save remains.
        local hudOwnsNeeds = GetResourceState('w_hud') == 'started'

        for src, Player in pairs(WCore.Players) do
            if Player then
                if not hudOwnsNeeds then
                    local newHunger = Player.PlayerData.metadata.hunger - WCore.Config.Player.HungerRate
                    local newThirst = Player.PlayerData.metadata.thirst - WCore.Config.Player.ThirstRate
                    if newHunger <= 0 then
                        newHunger = 0
                    end
                    if newThirst <= 0 then
                        newThirst = 0
                    end
                    Player.Functions.SetMetaData('thirst', newThirst)
                    Player.Functions.SetMetaData('hunger', newHunger)
                    TriggerClientEvent('hud:client:UpdateNeeds', src, newHunger, newThirst)
                end
                Player.Functions.Save()
                Wait(150) -- Smooth staggering for database writes under high player load
            end
        end
    end
end)

-- Paycheck Loop --
CreateThread(function()
    while true do
        Wait(60000 * WCore.Config.Money.PayCheckTimeOut)

        -- One cycle id, stamped once per round: the journal key has to be single-use
        -- (w_centralbank answers idempotency_conflict on a repeat under the same key), so it must
        -- separate one employee from the next AND one round from the next. It used to be the job
        -- name alone, which meant the first medic on the server took the money and everyone else
        -- was told the company was too poor.
        local cycle = os.time()

        for _, Player in pairs(WCore.Players) do
            if Player then
                local payment = WJobs[Player.PlayerData.job.name]['grades'][tonumber(Player.PlayerData.job.grade.level)].payment
                if not payment then payment = Player.PlayerData.job.payment end
                if Player.PlayerData.job and payment > 0 and (WJobs[Player.PlayerData.job.name].offDutyPay or Player.PlayerData.job.onduty) then
                    local paid,reason=false,'economy_not_ready'
                    if WCore.Economy.ready() then
                        local from=WCore.Config.Money.PayCheckSociety and ('society:'..Player.PlayerData.job.name) or 'central:reserve'
                        paid,reason=exports.w_centralbank:Transfer(from,'player:'..Player.PlayerData.citizenid..':bank',payment,'paycheck:'..Player.PlayerData.citizenid..':'..cycle)
                    end
                    if paid then
                        TriggerClientEvent('WCore:Notify',Player.PlayerData.source,{key='info.received_paycheck',subs={value=payment}})
                    else
                        local key = reason == 'insufficient_funds' and WCore.Config.Money.PayCheckSociety and 'error.company_too_poor' or 'error.paycheck_unavailable'
                        TriggerClientEvent('WCore:Notify',Player.PlayerData.source,key,'error')
                    end
                end
            end
        end
    end
end)