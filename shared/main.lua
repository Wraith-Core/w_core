WShared = WShared or {}

-- Keybinds --
local function GetKeys()
    return WKeybinds
end

WShared.GetKeys = GetKeys
exports('GetKeys', GetKeys)

local function GetKey(key)
    if type(key) == 'string' then
        if not WKeybinds[key] then w.print.warn('keybind does not exist: %s', key) return end
        return WKeybinds[tostring(key)]
    elseif type(key) == 'table' then
        local xKeybinds = {}
        for x = 1, #key do
            if not WKeybinds[key[x]] then w.print.warn('keybind does not exist: %s', key[x]) return end
            xKeybinds[key[x]] = WKeybinds[tostring(key[x])]
        end
        return xKeybinds
    end
end

WShared.GetKey = GetKey
exports('GetKey', GetKey)

-- Items --
local function GetItems()
    return WItems
end

WShared.GetItems = GetItems
exports('GetItems', GetItems)

local function GetItem(item)
    if type(item) == 'string' then
        if not WItems[item] then w.print.warn('item does not exist: %s', item) return end
        return WItems[item]
    elseif type(item) == 'table' then
        local xItems = {}
        for x = 1, #item do
            if not WItems[item[x]] then w.print.warn('item does not exist: %s', item[x]) return end
            xItems[item[x]] = WItems[item[x]]
        end
        return xItems
    end
end

WShared.GetItem = GetItem
exports('GetItem', GetItem)

-- Jobs --
local function GetJobs()
    return WJobs
end

WShared.GetJobs = GetJobs
exports('GetJobs', GetJobs)

local function GetJob(job)
    if type(job) == 'string' then
        if not WJobs[job] then w.print.warn('job does not exist: %s', job) return end
        return WJobs[job]
    elseif type(job) == 'table' then
        local xJobs = {}
        for x = 1, #job do
            if not WJobs[job[x]] then w.print.warn('job does not exist: %s', job[x]) return end
            xJobs[job[x]] = WJobs[job[x]]
        end
        return xJobs
    end
end

WShared.GetJob = GetJob
exports('GetJob', GetJob)

-- Gangs --
local function GetGangs()
    return WGangs
end

WShared.GetGangs = GetGangs
exports('GetGangs', GetGangs)

local function GetGang(gang)
    if type(gang) == 'string' then
        if not WGangs[gang] then w.print.warn('gang does not exist: %s', gang) return end
        return WGangs[gang]
    elseif type(gang) == 'table' then
        local xGangs = {}
        for x = 1, #gang do
            if not WGangs[gang[x]] then w.print.warn('gang does not exist: %s', gang[x]) return end
            xGangs[gang[x]] = WGangs[gang[x]]
        end
        return xGangs
    end
end

WShared.GetGang = GetGang
exports('GetGang', GetGang)

-- Job / gang names in the player's language --
-- The catalogues carry label / grade.name (English) next to label_ar / grade.name_ar; SetJob
-- and SetGang copy both into PlayerData. These pick the field for the language: on the
-- client the player's choice (w.getLocaleKey), on the server the w_lib:locale convar or,
-- when `source` is given, that player's choice (state bag 'w_lib:locale').
local isServer = IsDuplicityVersion()

local function LocaleKey(source)
    if isServer and source then
        local key = Player(source).state['w_lib:locale']
        if type(key) == 'string' and key ~= '' then return key end
    end
    return (w.getLocaleKey and w.getLocaleKey()) or 'en'
end

WShared.LocaleKey = LocaleKey

-- entry: a PlayerData.job / PlayerData.gang table or a WJobs / WGangs definition
local function JobLabel(entry, source)
    if type(entry) ~= 'table' then return '' end
    local key = LocaleKey(source)
    if key ~= 'en' then
        local localized = entry['label_' .. key]
        if type(localized) == 'string' and localized ~= '' then return localized end
    end
    return entry.label or ''
end

WShared.JobLabel = JobLabel
WShared.GangLabel = JobLabel
exports('JobLabel', JobLabel)

-- entry: a PlayerData.job / PlayerData.gang table (its .grade) or a grade definition itself
local function GradeName(entry, source)
    if type(entry) ~= 'table' then return '' end
    local grade = type(entry.grade) == 'table' and entry.grade or entry
    local key = LocaleKey(source)
    if key ~= 'en' then
        local localized = grade['name_' .. key]
        if type(localized) == 'string' and localized ~= '' then return localized end
    end
    return grade.name or ''
end

WShared.GradeName = GradeName
exports('GradeName', GradeName)

-- Horses --
local function GetHorses()
    return WHorses
end

WShared.GetHorses = GetHorses
exports('GetHorses', GetHorses)

local function GetHorse(horse)
    if type(horse) == 'string' then
        if not WHorses[horse] then w.print.warn('horse does not exist: %s', horse) return end
        return WHorses[horse]
    elseif type(horse) == 'table' then
        local xHorses = {}
        for x = 1, #horse do
            if not WHorses[horse[x]] then w.print.warn('horse does not exist: %s', horse[x]) return end
            xHorses[horse[x]] = WHorses[horse[x]]
        end
        return xHorses
    end
end

WShared.GetHorse = GetHorse
exports('GetHorse', GetHorse)

-- Vehicles --
local function GetVehicles()
    return WVehicles
end

WShared.GetVehicles = GetVehicles
exports('GetVehicles', GetVehicles)

local function GetVehicle(vehicle)
    if type(vehicle) == 'string' then
        if not WVehicles[vehicle] then w.print.warn('vehicle does not exist: %s', vehicle) return end
        return WVehicles[vehicle]
    elseif type(vehicle) == 'table' then
        local xVehicles = {}
        for x = 1, #vehicle do
            if not WVehicles[vehicle[x]] then w.print.warn('vehicle does not exist: %s', vehicle[x]) return end
            xVehicles[vehicle[x]] = WVehicles[vehicle[x]]
        end
        return xVehicles
    end
end

WShared.GetVehicle = GetVehicle
exports('GetVehicle', GetVehicle)

-- Weapons --
local function GetWeapons()
    return WWeapons
end

WShared.GetWeapons = GetWeapons
exports('GetWeapons', GetWeapons)

local function GetWeapon(weapon)
    if type(weapon) == 'string' then
        if not WWeapons[weapon] then w.print.warn('weapon does not exist: %s', weapon) return end
        return WWeapons[weapon]
    elseif type(weapon) == 'table' then
        local xWeapons = {}
        for x = 1, #weapon do
            if not WWeapons[weapon[x]] then w.print.warn('weapon does not exist: %s', weapon[x]) return end
            xWeapons[weapon[x]] = WWeapons[weapon[x]]
        end
        return xWeapons
    end
end

WShared.GetWeapon = GetWeapon
exports('GetWeapon', GetWeapon)

-- Other Shared Functions --
local StringCharset = {}
local NumberCharset = {}

for i = 48, 57 do NumberCharset[#NumberCharset + 1] = string.char(i) end
for i = 65, 90 do StringCharset[#StringCharset + 1] = string.char(i) end
for i = 97, 122 do StringCharset[#StringCharset + 1] = string.char(i) end

function WShared.RandomStr(length)
    if length <= 0 then return '' end
    return WShared.RandomStr(length - 1) .. StringCharset[math.random(1, #StringCharset)]
end

function WShared.RandomInt(length)
    if length <= 0 then return '' end
    return WShared.RandomInt(length - 1) .. NumberCharset[math.random(1, #NumberCharset)]
end

function WShared.SplitStr(str, delimiter)
    local result = {}
    local from = 1
    local delim_from, delim_to = string.find(str, delimiter, from)
    while delim_from do
        result[#result + 1] = string.sub(str, from, delim_from - 1)
        from = delim_to + 1
        delim_from, delim_to = string.find(str, delimiter, from)
    end
    result[#result + 1] = string.sub(str, from)
    return result
end

-- string helpers of the library (modules/string)
function WShared.Trim(value)
    if not value then return nil end
    return value:trim()
end

function WShared.FirstToUpper(value)
    if not value then return nil end
    return value:firstToUpper()
end

function WShared.Round(value, numDecimalPlaces)
    if not numDecimalPlaces then return math.floor(value + 0.5) end
    local power = 10 ^ numDecimalPlaces
    return math.floor((value * power) + 0.5) / (power)
end

-- Wagon extras (lanterns, covers...): the RDR3 extra natives take the same arguments
function WShared.ChangeVehicleExtra(vehicle, extra, enable)
    if DoesExtraExist(vehicle, extra) then
        if enable then
            SetVehicleExtra(vehicle, extra, false)
            if not IsVehicleExtraTurnedOn(vehicle, extra) then
                WShared.ChangeVehicleExtra(vehicle, extra, enable)
            end
        else
            SetVehicleExtra(vehicle, extra, true)
            if IsVehicleExtraTurnedOn(vehicle, extra) then
                WShared.ChangeVehicleExtra(vehicle, extra, enable)
            end
        end
    end
end

function WShared.SetDefaultVehicleExtras(vehicle, config)
    -- Clear Extras
    for i = 1, 20 do
        if DoesExtraExist(vehicle, i) then
            SetVehicleExtra(vehicle, i, 1)
        end
    end

    for id, enabled in pairs(config) do
        WShared.ChangeVehicleExtra(vehicle, tonumber(id), type(enabled) == 'boolean' and enabled or true)
    end
end

-- Backwards Compatability --
WShared.StarterItems = WConfig.StarterItems

