-- Player load and unload handling
-- New method for checking if logged in across all scripts (optional)
-- if LocalPlayer.state['isLoggedIn'] then

-- Player Spawned --
AddEventHandler('playerSpawned', function()
    Wait(2000)
    Citizen.InvokeNative(0x1E5B70E53DB661E5, 0, 0, 0, Lang:t("loading.text1"), Lang:t("loading.text2"), Lang:t("loading.text3")) -- Loading Screen Text
    ShutdownLoadingScreen() -- Stop Loading Screen
    DisplayRadar(false) -- Hide Radar
    SetMinimapHideFow(false) -- Hide Map
    Citizen.InvokeNative(0xA63FCAD3A6FEC6D2, cache.playerId, WConfig.Player.EnableEagleEye) -- ENABLE_EAGLEEYE (takes the player, not the ped)
    -- character selection: w_creators opens it on its own (it waits for playerSpawned itself)
end)

-- Character selection and spawning are w_creators'. Its last step, on every path, is the
-- net event 'w_creators:client:spawn'; once its handler has placed the ped and faded the
-- screen back in, the framework's own "loaded" signal fires here (the deleted multicharacter
-- used to fire it). The RSG mirror in compat/ carries it on to w_hud and w_inventory.
RegisterNetEvent('w_creators:client:spawn', function()
    CreateThread(function()
        local deadline = GetGameTimer() + 15000
        while IsScreenFadedOut() and GetGameTimer() < deadline do Wait(100) end
        Wait(500)
        local ok, err = pcall(TriggerEvent, 'WCore:Client:OnPlayerLoaded')
        if not ok then
            print(('^1[w_core] Error in OnPlayerLoaded handler: %s^7'):format(tostring(err)))
        end
    end)
end)

-- Player Load / Unload --
RegisterNetEvent('WCore:Client:OnPlayerLoaded', function()
    LocalPlayer.state:set('isLoggedIn', true, false)
    if WConfig.Player.RevealMap then
        SetMinimapHideFow(true)
        w.setRadarVisible(true)
    end
end)

RegisterNetEvent('WCore:Client:OnPlayerUnload', function()
    LocalPlayer.state:set('isLoggedIn', false, false)
end)

-- Player Data --
RegisterNetEvent('WCore:Player:SetPlayerData', function(val)
    WCore.PlayerData = val
end)

RegisterNetEvent('WCore:Player:UpdatePlayerData', function()
    TriggerServerEvent('WCore:UpdatePlayer')
end)

-- Notify --
RegisterNetEvent('WCore:Notify', function(text, type, length)
    WCore.Functions.Notify(text, type, length)
end)

-- This event is exploitable and should not be used. It has been deprecated, and will be removed soon.
RegisterNetEvent('WCore:Client:UseItem', function(item)
    WCore.Debug(string.format("%s triggered WCore:Client:UseItem by ID %s with the following data. This event is deprecated due to exploitation, and will be removed soon. Check w_inventory for the right use on this event.", GetInvokingResource(), GetPlayerServerId(PlayerId())))
    WCore.Debug(item)
end)

-- Legacy callback wire: the core itself rides on w.callback now; these two events stay as thin
-- adapters onto the same registry for an external caller that still fires them by hand.
RegisterNetEvent('WCore:Client:TriggerClientCallback', function(name, ...)
    WCore.Functions.TriggerClientCallback(name, function(...)
        TriggerServerEvent('WCore:Server:TriggerClientCallback', name, ...)
    end, ...)
end)

RegisterNetEvent('WCore:Client:TriggerCallback', function(name, ...)
    if WCore.ServerCallbacks[name] then
        WCore.ServerCallbacks[name](...)
        WCore.ServerCallbacks[name] = nil
    end
end)

-- Listen to Shared Being Updated --
RegisterNetEvent('WCore:Client:OnSharedUpdate', function(tableName, key, value)
    WCore.Shared[tableName][key] = value
    TriggerEvent('WCore:Client:UpdateObject')
end)

RegisterNetEvent('WCore:Client:OnSharedUpdateMultiple', function(tableName, values)
    for key, value in pairs(values) do
        WCore.Shared[tableName][key] = value
    end
    TriggerEvent('WCore:Client:UpdateObject')
end)


-----------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------- COMMAND EVENTS -----------------------------------------------------------
-----------------------------------------------------------------------------------------------------------------------------

-- Teleport to Plyer --
RegisterNetEvent('WCore:Command:TeleportToPlayer', function(coords)
    SetEntityCoords(cache.ped, coords.x, coords.y, coords.z)
end)

-- Teleport to Coords Command --
RegisterNetEvent('WCore:Command:TeleportToCoords', function(x, y, z, h)
    SetEntityCoords(cache.ped, x, y, z)
    SetEntityHeading(cache.ped, h or GetEntityHeading(cache.ped))
end)

-- Teleport to Waypoint --
RegisterNetEvent('WCore:Command:GoToMarker', function()
    local PlayerPedId = PlayerPedId
    local GetEntityCoords = GetEntityCoords
    local GetGroundZAndNormalFor_3dCoord = GetGroundZAndNormalFor_3dCoord

    if not IsWaypointActive() then
        WCore.Functions.Notify(Lang:t("error.no_waypoint"), "error", 5000)
        return 'marker'
    end

    --Fade screen to hide how clients get teleported.
    DoScreenFadeOut(650)
    while not IsScreenFadedOut() do Wait(0) end

    local ped, coords <const> = cache.ped, GetWaypointCoords()
    local vehicle = GetVehiclePedIsIn(ped, false)
    local oldCoords <const> = GetEntityCoords(ped)

    -- Unpack coords instead of having to unpack them while iterating.
    -- 825.0 seems to be the max a player can reach while 0.0 being the lowest.
    local x, y, groundZ, Z_START = coords['x'], coords['y'], 850.0, 950.0
    local found = false
    if vehicle > 0 then
        FreezeEntityPosition(vehicle, true)
    else
        FreezeEntityPosition(ped, true)
    end

    for i = Z_START, 0, -25.0 do
        local z = i
        if (i % 2) ~= 0 then
            z = Z_START - i
        end
        Citizen.InvokeNative(0x387AD749E3B69B70, x, y, z, x, y, z, 50.0, 0)
        local curTime = GetGameTimer()
        while Citizen.InvokeNative(0xCF45DF50C7775F2A) do
            if GetGameTimer() - curTime > 1000 then
                break
            end
            Wait(0)
        end
        Citizen.InvokeNative(0x5A8B01199C3E79C3)
        SetEntityCoords(ped, x, y, z - 1000)
        while Citizen.InvokeNative(0xCF45DF50C7775F2A) do
            RequestCollisionAtCoord(x, y, z)
            if GetGameTimer() - curTime > 1000 then
                break
            end
            Wait(0)
        end
        -- Get ground coord. As mentioned in the natives, this only works if the client is in render distance.
        --found, groundZ = GetGroundZFor_3dCoord(x, y, z, false)
        found, groundZ = GetGroundZAndNormalFor_3dCoord(x, y, z)
        if found then
            Wait(0)
            SetEntityCoords(ped, x, y, groundZ)
            break
        end
        Wait(0)
    end

    -- Remove black screen once the loop has ended.
    DoScreenFadeIn(650)
    if vehicle > 0 then
        FreezeEntityPosition(vehicle, false)
    else
        FreezeEntityPosition(ped, false)
    end

    if not found then
        -- If we can't find the coords, set the coords to the old ones.
        -- We don't unpack them before since they aren't in a loop and only called once.
        SetEntityCoords(ped, oldCoords['x'], oldCoords['y'], oldCoords['z'] - 1.0)
        WCore.Functions.Notify(Lang:t("error.tp_error"), "error", 5000)
    end

    -- If Z coord was found, set coords in found coords.
    SetEntityCoords(ped, x, y, groundZ)
    WCore.Functions.Notify(Lang:t("success.teleported_waypoint"), "success", 5000)
end)

-- Spawn Wagon --
RegisterNetEvent('WCore:Command:SpawnVehicle', function(WagonName)
    local hash = GetHashKey(WagonName)
    if not IsModelInCdimage(hash) then return end

    if cache.vehicle then
        w.entity.delete(cache.vehicle)
    elseif cache.mount then
        w.entity.delete(cache.mount)
    end

    -- admin spawn: networked and kept after a resource restart (w.entity.create cleans up its own)
    local vehicle = CreateVehicle(w.requestModel(hash), GetEntityCoords(cache.ped), GetEntityHeading(cache.ped), true, false)
    SetModelAsNoLongerNeeded(hash)
    Citizen.InvokeNative(0x9587913B9E772D29, vehicle, 0) -- Place on ground properly
    TaskWarpPedIntoVehicle(cache.ped, vehicle, -1) -- Spawn the player onto "drivers" seat
    Citizen.InvokeNative(0x283978A15512B2FE, vehicle, true) -- Set random outfit variation / skin
    NetworkSetEntityOnlyExistsForParticipants(vehicle, true)
end)

-- Spawn Horse --
RegisterNetEvent('WCore:Command:SpawnHorse', function(HorseName)
    local horseModel = WHorses[HorseName] and WHorses[HorseName].model
    if not horseModel or not IsModelInCdimage(horseModel) then return end
    local hashp = GetHashKey('PLAYER')

    if cache.mount then
        w.entity.delete(cache.mount)
    elseif cache.vehicle then
        w.entity.delete(cache.vehicle)
    end

    local hash = w.requestModel(horseModel)
    local Horse = CreatePed(hash, GetEntityCoords(cache.ped), GetEntityHeading(cache.ped), true, false)
    SetModelAsNoLongerNeeded(hash)
    Citizen.InvokeNative(0x9587913B9E772D29, Horse, 0) -- Place horse on ground properly
    Citizen.InvokeNative(0xADB3F206518799E8, Horse, hashp) -- Default Relationship
    Citizen.InvokeNative(0xCC97B29285B1DC3B, Horse, 1) -- Horse Mood
    Citizen.InvokeNative(0x028F76B6E78246EB, cache.ped, Horse, 0) -- On Saddle
    Citizen.InvokeNative(0x283978A15512B2FE, Horse, true) -- Set random outfit variation / skin
    NetworkSetEntityOnlyExistsForParticipants(Horse, true)
end)

-- Delete Wagons --
RegisterNetEvent('WCore:Command:DeleteVehicle', function()
    if cache.vehicle then
        SetEntityAsMissionEntity(cache.vehicle, true, true)
        w.entity.delete(cache.vehicle)
    else
        local pcoords = GetEntityCoords(cache.ped)
        local vehicle, dist = WCore.Functions.GetClosestVehicle(pcoords)
        if vehicle == -1 or dist > 10 then return end

        SetEntityAsMissionEntity(vehicle, true, true)
        w.entity.delete(vehicle)
    end
end)

-- Delete Horse --
RegisterNetEvent('WCore:Command:DeleteHorse', function()
    if cache.mount then
        SetEntityAsMissionEntity(cache.mount, true, true)
        w.entity.delete(cache.mount)
    else
        local pcoords = GetEntityCoords(cache.ped)
        local ped, dist = WCore.Functions.GetClosestPed(pcoords)
        if ped == -1 or dist > 10 then return end

        local model = GetEntityModel(ped)
        if not IsPedAPlayer(ped) and Citizen.InvokeNative(0x772A1969F649E902, model) == 1 then
            SetEntityAsMissionEntity(ped, true, true)
            w.entity.delete(ped)
        end
    end
end)

-- /Me /Do /Try Commands --
-- Drawn by the library's NUI text (w.drawText3D) above the speaker's head. Each line gets its
-- own id so several players' texts stay separate; /try carries its outcome and the sentence is
-- built here, in the viewer's language.
local RDisplaying = 1

local function display(mePlayer, text, offset, id)
    local displaying = true

    CreateThread(function()
        Wait(WConfig.ShowDoMeTryLength * 1000)
        displaying = false
    end)
    CreateThread(function()
        RDisplaying = RDisplaying + 1
        while displaying do
            local targetPed = GetPlayerPed(mePlayer)
            if targetPed == 0 or not DoesEntityExist(targetPed) then break end
            local coordsMe = GetPedBoneCoords(targetPed, 21030, 0.0, 0.0, 0.0) -- SKEL_HEAD (RDR3 bone id)
            local dist = #(coordsMe - GetEntityCoords(cache.ped, false))
            if dist < 15.0 then
                w.drawText3D(coordsMe.x, coordsMe.y, coordsMe.z + offset, text, id)
                Wait(0)
            else
                Wait(dist > 25 and 500 or 100)
            end
        end
        RDisplaying = RDisplaying - 1
    end)
end

RegisterNetEvent('WCore:triggerDisplay', function(text, source, kind, _, trySucceeded)
    local offset = 0.4 + (RDisplaying * 0.14)
    local target = GetPlayerFromServerId(source)
    if target == -1 then return end

    if kind == 'try' then
        text = Lang:t(trySucceeded and 'info.try_success' or 'info.try_fail', { text = text })
    end

    display(target, text, offset, ('wcore:%s:%s:%s'):format(kind or 'me', source, GetGameTimer()))
end)
