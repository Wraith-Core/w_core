-- Human-only density controls keep shops and authored job actors available.
-- Both RDR3 natives apply for one frame and do not remove existing entities.
local function density(value)
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
        return 1.0
    end
    return math.max(0.0, math.min(1.0, value)) + 0.0
end

CreateThread(function()
    while true do
        local population = WConfig.Population
        if LocalPlayer.state.isLoggedIn and population and population.Enabled
            and GetResourceState('w_survival') ~= 'started' then
            Citizen.InvokeNative(0xBA0980B5C0A11924, density(population.AmbientHumans))
            Citizen.InvokeNative(0x28CB6391ACEDD9DB, density(population.ScenarioHumans))
            Wait(0)
        else
            Wait(500)
        end
    end
end)
