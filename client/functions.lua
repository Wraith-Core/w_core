WCore.Functions = {}

-- Player

function WCore.Functions.GetPlayerData(cb)
    if not cb then return WCore.PlayerData end
    cb(WCore.PlayerData)
end

function WCore.Functions.GetCoords(entity)
    local coords = GetEntityCoords(entity)
    return vector4(coords.x, coords.y, coords.z, GetEntityHeading(entity))
end

function WCore.Functions.HasItem(items, amount)
    return exports['rsg-inventory']:HasItem(items, amount)
end

-- Utility
-- On-screen text is the library's NUI text (call every frame, as with the natives). The old
-- position / colour arguments are accepted for API parity; the frame decides the styling.
function WCore.Functions.DrawText(_, _, _, _, _, _, _, _, _, text)
    w.drawText2D(tostring(text))
end

function WCore.Functions.DrawText3D(x, y, z, text)
    w.drawText3D(x, y, z, tostring(text))
end

WCore.Functions.RequestAnimDict = w.requestAnimDict

function WCore.Functions.PlayAnim(animDict, animName, upperbodyOnly, duration)
    local flags = upperbodyOnly and 16 or 0
    local runTime = duration or -1
    WCore.Functions.RequestAnimDict(animDict)
    -- RDR3 signature: speed, speedMultiplier, duration, flags, playbackRate, p8, ikFlags, p10, taskFilter, p12
    TaskPlayAnim(cache.ped, animDict, animName, 8.0, 8.0, runTime, flags, 0.0, false, 0, false, 0, false)
    RemoveAnimDict(animDict)
end

WCore.Functions.LoadModel = w.requestModel

WCore.Functions.LoadAnimSet = w.requestAnimSet

-- WCore.Functions.Notify is w.notify: `type` is the variant (icon and title colour come from
-- it) and `position` is mapped to a placement by the library. Strings are run through the
-- dictionary first, so the server can send keys and the player reads them in his language;
-- `{ key = 'info.x', subs = { ... } }` carries %{name} substitutions across the wire.
---@param text table|string text of the notification, a dictionary key, or { key, subs } / { text, caption }
---@param notifyType? string 'success' | 'error' | 'inform' | 'warning' | 'law' ('primary' = 'inform')
---@param duration? integer milliseconds on screen, default 5000
local function translateNotify(text)
    if type(text) == 'table' then
        if text.key then
            -- a substitution that is itself a dictionary key is translated too
            local subs = {}
            for k, v in pairs(text.subs or {}) do
                subs[k] = (type(v) == 'string' and Lang:has(v)) and Lang:t(v) or v
            end
            return Lang:t(text.key, subs)
        end
        return text
    end
    if text == nil then return '' end
    return Lang:t(tostring(text))
end

function WCore.Functions.Notify(text, notifyType, duration)
    notifyType = notifyType or 'inform'
    if notifyType == 'primary' then notifyType = 'inform' end
    duration = duration or 5000
    -- nil hands the placement to the library (the player's /w_lib setting)
    local position = WConfig.NotifyPosition or nil
    text = translateNotify(text)
    if type(text) == 'table' then
        w.notify({
            title = translateNotify(text.text or text.title),
            description = translateNotify(text.caption or text.description),
            type = notifyType,
            duration = duration,
            position = position,
        })
    else
        w.notify({ description = text, type = notifyType, duration = duration, position = position })
    end
end

-- Use Native Notifications --
-- w.requestStreamedTextureDict raises an error when the dictionary is not streamed in
-- before the timeout; the native notify falls back to 'generic_textures' on false instead.
function WCore.Functions.LoadTexture(dict)
    if not Citizen.InvokeNative(0x7332461FC59EB7EC, dict) then return false end
    return pcall(w.requestStreamedTextureDict, dict, 100) == true
end

-- Native Notifications --
function WCore.Functions.NativeNotify(id, text, duration, subtext, dict, icon, color)
    local display = tostring(text) or 'Placeholder'
	local subdisplay = tostring(subtext) or 'Placeholder'
	local length = tonumber(duration) or 4000
	local dictionary = tostring(dict) or 'generic_textures'
	local image = tostring(icon) or 'tick'
	local colour = tostring(color) or 'COLOR_WHITE'

    local notifications = {
        [1] = function() return exports['w_core']:ShowTooltip(display, length) end,
        [2] = function() return exports['w_core']:DisplayRightText(display, length) end,
        [3] = function() return exports['w_core']:ShowObjective(display, length) end,
        [4] = function() return exports['w_core']:ShowBasicTopNotification(display, length) end,
        [5] = function() return exports['w_core']:ShowSimpleCenterText(display, length) end,
        [6] = function() return exports['w_core']:ShowLocationNotification(display, subdisplay, length) end,
        [7] = function() return exports['w_core']:ShowTopNotification(display, subdisplay, length) end,
        [8] = function() if not WCore.Functions.LoadTexture(dictionary) then WCore.Functions.LoadTexture('generic_textures') end
            return exports['w_core']:ShowAdvancedLeftNotification(display, subdisplay, dictionary, image, length) end,
        [9] = function() if not WCore.Functions.LoadTexture(dictionary) then WCore.Functions.LoadTexture('generic_textures') end
            return exports['w_core']:ShowAdvancedRightNotification(display, dictionary, image, colour, length) end
    }

    if not notifications[id] then
        w.print.error('invalid native notify id %s', tostring(id))
        return nil
    else
        return notifications[id]()
    end
end

function WCore.Debug(resource, obj, depth)
    TriggerServerEvent('WCore:DebugSomething', resource, obj, depth)
end

-- Callback Functions --
-- Both directions ride on w.callback (the library wire, '__w_cb_<name>'). The WCore signatures
-- are unchanged: a client callback is still written as cb(callback, ...) and answers by
-- calling `callback(...)`; the adapter turns that into the return values w.callback expects.

---Run a (cb, ...) style handler and yield until it answers.
---@param handler function
---@param ... any
---@return ...
local function awaitHandler(handler, ...)
    local p = promise.new()
    local answered = false
    local function answer(...)
        if answered then return end
        answered = true
        p:resolve(table.pack(...))
    end
    local ok, err = pcall(handler, answer, ...)
    if not ok then
        answer()
        error(err, 0)
    end
    local result = Citizen.Await(p)
    return table.unpack(result, 1, result.n)
end

-- Client Callback (answers the server)
function WCore.Functions.CreateClientCallback(name, cb)
    WCore.ClientCallbacks[name] = cb
    w.callback.register(name, function(...)
        return awaitHandler(WCore.ClientCallbacks[name], ...)
    end)
end

-- Runs a client callback locally (same VM), the way the old net adapter did
function WCore.Functions.TriggerClientCallback(name, cb, ...)
    if not WCore.ClientCallbacks[name] then return end
    WCore.ClientCallbacks[name](cb, ...)
end

-- Server Callback (asks the server); the answer goes to cb
function WCore.Functions.TriggerCallback(name, cb, ...)
    w.callback(name, false, cb or function() end, ...)
end

function WCore.Functions.Progressbar(_, label, duration, useWhileDead, canCancel, disableControls, animation, prop, propTwo, onFinish, onCancel)
    if w.progressBar({
        duration = duration,
        label = label,
        useWhileDead = useWhileDead,
        canCancel = canCancel,
        disable = {
            move = disableControls?.disableMovement,
            -- wagon controls; `car` is the library's option name, `disableCarMovement` the key the older job callers still pass
            car = disableControls?.disableVehicleMovement or disableControls?.disableCarMovement,
            combat = disableControls?.disableCombat,
            mouse = disableControls?.disableMouse,
        },
        -- w_lib only accepts anim/prop tables that carry data: an empty table aborts the bar
        anim = animation?.animDict and {
            dict = animation.animDict,
            clip = animation.anim,
            flag = animation.flags
        } or nil,
        prop = prop?.model and {
            model = prop.model,
            pos = prop.coords,
            rot = prop.rotation,
        } or nil,
    }) then
        if onFinish then
            onFinish()
        end
    else
        if onCancel then
            onCancel()
        end
    end
end

-- Getters

function WCore.Functions.GetVehicles()
    return GetGamePool('CVehicle')
end

function WCore.Functions.GetObjects()
    return GetGamePool('CObject')
end

function WCore.Functions.GetPlayers()
    return GetActivePlayers()
end

function WCore.Functions.GetPeds(ignoreList)
    local pedPool = GetGamePool('CPed')
    local peds = {}
    ignoreList = ignoreList or {}
    for i = 1, #pedPool, 1 do
        local found = false
        for j = 1, #ignoreList, 1 do
            if ignoreList[j] == pedPool[i] then
                found = true
            end
        end
        if not found then
            peds[#peds + 1] = pedPool[i]
        end
    end
    return peds
end

-- The GetClosest* getters keep the RSG contract: (-1, -1) when nothing is within 50 m.
function WCore.Functions.GetClosestPed(coords, ignoreList)
    coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords or GetEntityCoords(cache.ped)
    local ped, pedCoords = w.getClosestPed(coords, 50)
    if not ped then return -1, -1 end
    return ped, #(pedCoords - coords)
end

-- RDR3 peds are metapeds: a glove is a component of the 'gloves' category (library component module)
function WCore.Functions.IsWearingGloves()
    local equipped = w.component.isCategoryEquiped(cache.ped, 'gloves')
    return equipped == true
end

function WCore.Functions.GetClosestPlayer(coords)
    coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords or GetEntityCoords(cache.ped)
    local playerId, _, playerCoords = w.getClosestPlayer(coords, 50, false)
    if not playerId then return -1, -1 end
    return playerId, #(playerCoords - coords)
end

function WCore.Functions.GetPlayersFromCoords(coords, distance)
    coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords or GetEntityCoords(cache.ped)
    local players = w.getNearbyPlayers(coords, distance or 5, true)

    -- This is for backwards compatability as beforehand it only returned the PlayerId, where Lib returns PlayerPed, PlayerId and PlayerCoords
    for i = 1, #players do
        players[i] = players[i].id
    end

    return players
end

function WCore.Functions.GetClosestVehicle(coords)
    coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords or GetEntityCoords(cache.ped)
    local vehicle, vehicleCoords = w.getClosestVehicle(coords, 50, true)
    if not vehicle then return -1, -1 end
    return vehicle, #(vehicleCoords - coords)
end

function WCore.Functions.GetClosestObject(coords)
    coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords or GetEntityCoords(cache.ped)
    local closestObject, objectCoords = w.getClosestObject(coords, 50)
    if not closestObject then return -1, -1 end
    return closestObject, #(objectCoords - coords)
end

function WCore.Functions.GetBoneDistance(entity, boneType, boneIndex)
    local bone
    if boneType == 1 then
        bone = GetPedBoneIndex(entity, boneIndex)
    else
        bone = GetEntityBoneIndexByName(entity, boneIndex)
    end
    local boneCoords = GetWorldPositionOfEntityBone(entity, bone)
    local playerCoords = GetEntityCoords(cache.ped)
    return #(boneCoords - playerCoords)
end

function WCore.Functions.AttachProp(ped, model, boneId, x, y, z, xR, yR, zR, vertex)
    local modelHash = type(model) == 'string' and GetHashKey(model) or model
    local bone = GetPedBoneIndex(ped, boneId)
    WCore.Functions.LoadModel(modelHash)
    local prop = CreateObject(modelHash, 1.0, 1.0, 1.0, 1, 1, 0)
    AttachEntityToEntity(prop, ped, bone, x, y, z, xR, yR, zR, true, true, false, true, not vertex and 2 or 0, true, false, false)
    SetModelAsNoLongerNeeded(modelHash)
    return prop
end

-- Vehicles (wagons, carriages, boats): a vehicle in RDR3 is a wagon, there is no fuel, radio,
-- ignition or number plate to set once it exists.

function WCore.Functions.SpawnVehicle(model, cb, coords, isnetworked, teleportInto)
    model = type(model) == 'string' and GetHashKey(model) or model
    if not IsModelInCdimage(model) then return end
    if coords then
        coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords
    else
        coords = GetEntityCoords(cache.ped)
    end
    isnetworked = isnetworked == nil or isnetworked
    WCore.Functions.LoadModel(model)
    local heading = coords.w or GetEntityHeading(cache.ped)
    local veh = CreateVehicle(model, coords.x, coords.y, coords.z, heading, isnetworked, false)
    SetVehicleHasBeenOwnedByPlayer(veh, true)
    Citizen.InvokeNative(0x9587913B9E772D29, veh, 0) -- PLACE_ENTITY_ON_GROUND_PROPERLY
    SetModelAsNoLongerNeeded(model)
    if teleportInto then TaskWarpPedIntoVehicle(cache.ped, veh, -1) end
    if cb then cb(veh) end
end

function WCore.Functions.DeleteVehicle(vehicle)
    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteVehicle(vehicle)
end

-- The readable name of a wagon comes from the catalogue (shared/vehicles.lua), matched on the
-- model hash; an unknown model gives nil.
function WCore.Functions.GetVehicleLabel(vehicle)
    if vehicle == nil or vehicle == 0 then return end
    local model = GetEntityModel(vehicle)
    for _, entry in pairs(WVehicles) do
        local hash = tonumber(entry.hash) or (entry.model and joaat(entry.model))
        if hash == model or (entry.model and joaat(entry.model) == model) then
            return entry.name
        end
    end
    return nil
end

function WCore.Functions.SpawnClear(coords, radius)
    if coords then
        coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords
    else
        coords = GetEntityCoords(cache.ped)
    end
    local vehicles = GetGamePool('CVehicle')
    local closeVeh = {}
    for i = 1, #vehicles, 1 do
        local vehicleCoords = GetEntityCoords(vehicles[i])
        local distance = #(vehicleCoords - coords)
        if distance <= radius then
            closeVeh[#closeVeh + 1] = vehicles[i]
        end
    end
    if #closeVeh > 0 then return false end
    return true
end

WCore.Functions.LoadParticleDictionary = w.requestNamedPtfxAsset

function WCore.Functions.StartParticleAtCoord(dict, ptName, looped, coords, rot, scale, alpha, color, duration)
    if coords then
        coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords
    else
        coords = GetEntityCoords(cache.ped)
    end
    WCore.Functions.LoadParticleDictionary(dict)
    UseParticleFxAsset(dict)
    local particleHandle
    if looped then
        particleHandle = StartParticleFxLoopedAtCoord(ptName, coords.x, coords.y, coords.z, rot.x, rot.y, rot.z, scale or 1.0)
        if color then
            SetParticleFxLoopedColour(particleHandle, color.r, color.g, color.b, false)
        end
        SetParticleFxLoopedAlpha(particleHandle, alpha or 10.0)
        if duration then
            Wait(duration)
            StopParticleFxLooped(particleHandle, 0)
        end
    else
        SetParticleFxNonLoopedAlpha(alpha or 10.0)
        if color then
            SetParticleFxNonLoopedColour(color.r, color.g, color.b)
        end
        StartParticleFxNonLoopedAtCoord(ptName, coords.x, coords.y, coords.z, rot.x, rot.y, rot.z, scale or 1.0)
    end
    return particleHandle
end

function WCore.Functions.StartParticleOnEntity(dict, ptName, looped, entity, bone, offset, rot, scale, alpha, color, evolution, duration)
    WCore.Functions.LoadParticleDictionary(dict)
    UseParticleFxAsset(dict)
    local particleHandle, boneID
    if bone and GetEntityType(entity) == 1 then
        boneID = GetPedBoneIndex(entity, bone)
    elseif bone then
        boneID = GetEntityBoneIndexByName(entity, bone)
    end
    if looped then
        if bone then
            particleHandle = StartParticleFxLoopedOnEntityBone(ptName, entity, offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, boneID, scale)
        else
            particleHandle = StartParticleFxLoopedOnEntity(ptName, entity, offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, scale)
        end
        if evolution then
            SetParticleFxLoopedEvolution(particleHandle, evolution.name, evolution.amount, false)
        end
        if color then
            SetParticleFxLoopedColour(particleHandle, color.r, color.g, color.b, false)
        end
        SetParticleFxLoopedAlpha(particleHandle, alpha)
        if duration then
            Wait(duration)
            StopParticleFxLooped(particleHandle, 0)
        end
    else
        SetParticleFxNonLoopedAlpha(alpha or 10.0)
        if color then
            SetParticleFxNonLoopedColour(color.r, color.g, color.b)
        end
        if bone then
            StartParticleFxNonLoopedOnPedBone(ptName, entity, offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, boneID, scale)
        else
            StartParticleFxNonLoopedOnEntity(ptName, entity, offset.x, offset.y, offset.z, rot.x, rot.y, rot.z, scale)
        end
    end
    return particleHandle
end

-- Map zones: the game names an area by a zone hash (town, district, state...). The readable
-- name is built from the zone's map texture in client/zones.lua ('town_saintdenis' -> 'Saintdenis');
-- an unknown zone gives the hash as text. zoneType: 1 town, 10 district, 0 state (default: the
-- most specific one found).
local zoneTypes <const> = { 1, 10, 12, 13, 0 }

local function zoneName(hash)
    local info = Zones and Zones[hash]
    if not info or not info.texture then return tostring(hash) end
    local label = info.texture:gsub('^[%a]+_', ''):gsub('_', ' ')
    return label:firstToUpper()
end

function WCore.Functions.GetZoneAtCoords(coords, zoneType)
    coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords or GetEntityCoords(cache.ped)
    if zoneType then
        local hash = GetMapZoneAtCoords(coords.x, coords.y, coords.z, zoneType)
        return hash ~= 0 and zoneName(hash) or nil, hash
    end
    for i = 1, #zoneTypes do
        local hash = GetMapZoneAtCoords(coords.x, coords.y, coords.z, zoneTypes[i])
        if hash and hash ~= 0 then return zoneName(hash), hash end
    end
    return nil, 0
end

function WCore.Functions.GetCardinalDirection(entity)
    entity = DoesEntityExist(entity) and entity or cache.ped
    if DoesEntityExist(entity) then
        local heading = GetEntityHeading(entity)
        if ((heading >= 0 and heading < 45) or (heading >= 315 and heading < 360)) then
            return "North"
        elseif (heading >= 45 and heading < 135) then
            return "West"
        elseif (heading >= 135 and heading < 225) then
            return "South"
        elseif (heading >= 225 and heading < 315) then
            return "East"
        end
    else
        return "Cardinal Direction Error"
    end
end

function WCore.Functions.GetCurrentTime()
    local obj = {}
    obj.min = GetClockMinutes()
    obj.hour = GetClockHours()

    if obj.hour <= 12 then
        obj.ampm = "AM"
    elseif obj.hour >= 13 then
        obj.ampm = "PM"
        obj.formattedHour = obj.hour - 12
        obj.hour = obj.formattedHour
    end

    if obj.min <= 9 then
        obj.formattedMin = "0" .. obj.min
        obj.min = obj.formattedMin
    end

    obj.time = (obj.hour..":"..obj.min.." "..obj.ampm)

    return obj
end

function WCore.Functions.GetTemperature()
	-- Get Temperatures
	local UseMetric = ShouldUseMetricTemperature()
	local temperature
	local temperatureUnit
    local playerCoords = GetEntityCoords(cache.ped)

	if UseMetric then
		temperature = math.floor(GetTemperatureAtCoords(playerCoords))
		temperatureUnit = 'C'
	else
		temperature = math.floor(GetTemperatureAtCoords(playerCoords) * 9/5 + 32)
		temperatureUnit = 'F'
	end

	return string.format('%d °%s', temperature, temperatureUnit)
end

function WCore.Functions.GetGroundZCoord(coords)
    if not coords then return end

    local retval, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z, 0)
    if retval then
        return vector3(coords.x, coords.y, groundZ)
    else
        w.print.warn('no ground Z for %s', coords)
        return coords
    end
end
