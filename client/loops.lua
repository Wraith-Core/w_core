-- Update Player Hunger / Thirst --
-- (w_hud applies its own starvation effects; the core's only run when it is absent)
CreateThread(function()
    while true do
        if LocalPlayer.state.isLoggedIn and GetResourceState('w_hud') ~= 'started' then
            if (WCore.PlayerData.metadata.hunger <= 0 or WCore.PlayerData.metadata.thirst <= 0) and not WCore.PlayerData.metadata.isdead then
                local currentHealth = GetEntityHealth(cache.ped)
                local decreaseThreshold = math.random(5, 10)
                SetEntityHealth(cache.ped, currentHealth - decreaseThreshold)
            end
        end
        Wait(WCore.Config.StatusInterval * 1000)
    end
end)
