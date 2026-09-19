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

        for _, Player in pairs(WCore.Players) do
            if Player then
                local payment = WJobs[Player.PlayerData.job.name]['grades'][tonumber(Player.PlayerData.job.grade.level)].payment
                if not payment then payment = Player.PlayerData.job.payment end
                if Player.PlayerData.job and payment > 0 and (WJobs[Player.PlayerData.job.name].offDutyPay or Player.PlayerData.job.onduty) then
                    if WCore.Config.Money.PayCheckSociety then
                        local account = exports['w_management']:GetAccount(Player.PlayerData.job.name)
                        if account ~= 0 then -- Checks if player is employed by a society
                            if account < payment then -- Checks if company has enough money to pay society
                                TriggerClientEvent('WCore:Notify', Player.PlayerData.source, 'error.company_too_poor', 'error')
                            else
                                Player.Functions.AddMoney('bank', payment)
                                exports['w_management']:RemoveMoney(Player.PlayerData.job.name, payment)
                                TriggerClientEvent('WCore:Notify', Player.PlayerData.source, { key = 'info.received_paycheck', subs = { value = payment } })
                            end
                        else
                            Player.Functions.AddMoney('bank', payment)
                            TriggerClientEvent('WCore:Notify', Player.PlayerData.source, { key = 'info.received_paycheck', subs = { value = payment } })
                        end
                    else
                        Player.Functions.AddMoney('bank', payment)
                        TriggerClientEvent('WCore:Notify', Player.PlayerData.source, { key = 'info.received_paycheck', subs = { value = payment } })
                    end
                end
            end
        end
    end
end)