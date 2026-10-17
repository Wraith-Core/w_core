-- Proximity prompts for third-party scripts (exports createPrompt / createPromptGroup /
-- getPrompt / getPromptGroup / deletePrompt / deletePromptGroup). A thin layer over the
-- library's proximity prompt: one record = one w.prompt.at rec, shown while the player stands
-- within RANGE of its coords; the record's options run in the key's onComplete. Wraith
-- resources call w.prompt.at / w.prompt.atEntity directly; this file only keeps the historical
-- contract alive for scripts written against it.

local Prompts = {}
local PromptGroups = {}
local RANGE <const> = 1.5
local FALLBACK_KEY <const> = 'J' -- not E: E on foot grabs the player beside you

-- ── keys ─────────────────────────────────────────────────────────────────────────────
-- Callers pass the RedM control hash (WKeybinds / WCore.Shared.GetKey) or a key name; the
-- engine wants the key name of the library's rawKeys table.
local keyNameByHash = {}
local keyAlias = {
    SPACEBAR = 'SPACE',
    CTRL = 'LCONTROL',
    SHIFT = 'LSHIFT',
    LALT = 'LMENU',
    DEL = 'DELETE',
    PGUP = 'PAGEUP',
    PGDN = 'PAGEDOWN',
    LEFTBRACKET = '[',
    RIGHTBRACKET = ']',
    ENTER = 'RETURN',
    MOUSE1 = 'LBUTTON',
    MOUSE2 = 'RBUTTON',
    MOUSE3 = 'MBUTTON',
}

for name, hash in pairs(WKeybinds) do
    keyNameByHash[hash & 0xFFFFFFFF] = keyAlias[name] or name
end

-- A name the library's key listener does not know (MWUP, HorseCommandFlee...) would never
-- complete: it falls back to J with a warning.
---@param name string
---@param original string|number
---@return string
local function checkKey(name, original)
    if w.rawKeys.getVK(name) then return name end
    w.print.warn('prompt key %s is not a keyboard key, falling back to %s', tostring(original), FALLBACK_KEY)
    return FALLBACK_KEY
end

---@param key string|number control hash or key name
---@return string
local function resolveKey(key)
    if type(key) == 'number' then
        local hash = math.tointeger(key)
        local name = hash and keyNameByHash[hash & 0xFFFFFFFF]
        if not name then
            w.print.warn('prompt key hash %s has no keyboard name, falling back to %s', tostring(key), FALLBACK_KEY)
            return FALLBACK_KEY
        end
        return checkKey(name, key)
    end
    local upper = tostring(key):upper()
    return checkKey(keyAlias[upper] or upper, key)
end

-- ── labels ───────────────────────────────────────────────────────────────────────────
-- A label may be a dictionary key of this resource; plain text is shown as it is.
---@param text any
---@return string
local function translate(text)
    if text == nil then return '' end
    return locale(tostring(text))
end

-- ── options ──────────────────────────────────────────────────────────────────────────
local function executeOptions(options)
    if not options or not options.event then return end
    if options.type == 'client' then
        if options.args == nil then
            TriggerEvent(options.event)
        else
            TriggerEvent(options.event, table.unpack(options.args))
        end
    else
        if options.args == nil then
            TriggerServerEvent(options.event)
        else
            TriggerServerEvent(options.event, table.unpack(options.args))
        end
    end
end

-- Something else (a menu, a dialog, a progress bar) may own the screen; the prompt is only
-- shown, and only completes, while nothing of the library is in the way.
local function screenIsFree()
    if IsNuiFocused() then return false end
    if w.getOpenMenu() or w.getOpenContextMenu() or w.progressActive() then return false end
    return true
end

-- The prompt steps aside while its action runs (the action usually opens a menu) and comes
-- back on the next tick if the screen is still free.
local function runOptions(rec, options)
    rec.suspend(true)
    executeOptions(options)
    SetTimeout(250, function()
        if rec.suspended then rec.suspend(false) end
    end)
end

-- ── records ──────────────────────────────────────────────────────────────────────────
-- vector3 / vector4 / { x, y, z } / { [1], [2], [3] } all become a vector3
local function toVector(coords)
    local t = type(coords)
    if t == 'vector3' then return coords end
    if t == 'vector4' or t == 'table' then
        local x = coords.x or coords[1]
        local y = coords.y or coords[2]
        local z = coords.z or coords[3]
        if x and y and z then return vector3(x + 0.0, y + 0.0, z + 0.0) end
    end
    return coords
end

local function createPrompt(name, coords, key, text, options)
    if Prompts[name] ~= nil then
        w.print.warn('prompt %s already exists', name)
        return
    end
    local record = {
        name = name,
        coords = toVector(coords),
        key = key,
        keyName = resolveKey(key),
        text = text,
        options = options,
    }
    record.rec = w.prompt.at({
        coords = record.coords,
        distance = RANGE,
        title = false,
        prompts = {
            {
                key = record.keyName,
                label = translate(record.text),
                hold = false,
                onComplete = function(rec) runOptions(rec, record.options) end,
            },
        },
        canInteract = screenIsFree,
    })
    Prompts[name] = record
    return record
end

local function createPromptGroup(group, label, coords, prompts)
    if PromptGroups[group] ~= nil then
        w.print.warn('prompt group %s already exists', group)
        return
    end
    local rows = {}
    for _, p in pairs(prompts or {}) do
        p.keyName = resolveKey(p.key)
        rows[#rows + 1] = {
            key = p.keyName,
            label = translate(p.text),
            hold = false,
            onComplete = function(rec) runOptions(rec, p.options) end,
        }
    end
    local record = {
        coords = toVector(coords),
        label = label,
        group = group,
        prompts = prompts,
    }
    record.rec = w.prompt.at({
        coords = record.coords,
        distance = RANGE,
        title = label and translate(label) or false,
        prompts = rows,
        canInteract = screenIsFree,
    })
    PromptGroups[group] = record
    return record
end

local function getPrompt()
    return Prompts
end

local function getPromptGroup()
    return PromptGroups
end

local function deletePrompt(name)
    local record = Prompts[name]
    if not record then return end
    record.rec.remove()
    Prompts[name] = nil
end

local function deletePromptGroup(name)
    local record = PromptGroups[name]
    if not record then return end
    record.rec.remove()
    PromptGroups[name] = nil
end

-- Labels given as dictionary keys follow a language switch (after the dictionary reloaded)
AddEventHandler('w_lib:setLocale', function()
    SetTimeout(0, function()
        for _, record in pairs(Prompts) do
            record.rec.setLabel(record.keyName, translate(record.text))
        end
        for _, record in pairs(PromptGroups) do
            if record.label then record.rec.setTitle(translate(record.label)) end
            for _, p in pairs(record.prompts or {}) do
                record.rec.setLabel(p.keyName, translate(p.text))
            end
        end
    end)
end)

-- A caller that stops takes its prompts with it; when this resource stops every record goes
-- (the library also drops the groups, the point records go through rec.remove here)
AddEventHandler('onClientResourceStop', function(resource)
    local all = resource == GetCurrentResourceName()
    for name, record in pairs(Prompts) do
        if all or record.owner == resource then deletePrompt(name) end
    end
    for name, record in pairs(PromptGroups) do
        if all or record.owner == resource then deletePromptGroup(name) end
    end
end)

exports('createPrompt', function(name, coords, key, text, options)
    local record = createPrompt(name, coords, key, text, options)
    if record then record.owner = GetInvokingResource() end
end)
exports('createPromptGroup', function(group, label, coords, prompts)
    local record = createPromptGroup(group, label, coords, prompts)
    if record then record.owner = GetInvokingResource() end
end)
exports('getPrompt', getPrompt)
exports('getPromptGroup', getPromptGroup)
exports('deletePrompt', deletePrompt)
exports('deletePromptGroup', deletePromptGroup)
