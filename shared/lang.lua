-- Lang:t(key, subs) — the core's historical translation API, now a thin wrapper over the
-- library dictionary (locales/en.json + locales/ar.json, preloaded by `w_lib { 'locale' }`).
-- The language is the library's: the player's choice on the client, the w_lib:locale convar
-- on the server. `%{name}` substitution is kept for every existing call site; a missing key
-- comes back as the key itself so it is visible in-game instead of crashing.

Lang = {}

--- @param key string
--- @param subs table<string, any> | nil
--- @return string
function Lang:t(key, subs)
    local phrase = locale(key)

    if type(phrase) ~= 'string' then
        return tostring(key)
    end

    if not subs then return phrase end

    for k, v in pairs(subs) do
        local replacement = tostring(v):gsub('%%', '%%%%')
        phrase = phrase:gsub('%%{' .. k .. '}', replacement)
    end

    return phrase
end

--- @param key string
--- @return boolean
function Lang:has(key)
    return w.getLocales()[key] ~= nil
end

-- The client keeps the dictionary in step with the player's language switch; the library
-- reloads it before the listeners run, w.locale(key) here only guards the handler order.
if not IsDuplicityVersion() then
    AddEventHandler('w_lib:setLocale', function(key)
        w.locale(key)
        TriggerEvent('WCore:Client:OnLocaleChange', key)
    end)
end
