-- Connection identity is read only from the server runtime, never from client data.
-- All three providers are mandatory, including for staff and new characters.
local providers = { 'discord', 'steam', 'license' }
local formats = { discord = '^discord:%d+$', steam = '^steam:%x+$', license = '^license:%x+$' }

function WCore.Functions.GetIdentifiers(src)
    local result = {}
    for _, identifier in ipairs(GetPlayerIdentifiers(src) or {}) do
        if type(identifier) == 'string' then
            local kind = identifier:match('^([^:]+):')
            if kind and formats[kind] and identifier:match(formats[kind])
                and identifier:match(':.*[1-9a-fA-F]') then
                result[kind] = identifier
            end
        end
    end
    return result
end

function WCore.Functions.ValidatePlayerIdentifiers(src)
    local identifiers = WCore.Functions.GetIdentifiers(src)
    local missing = {}
    for _, provider in ipairs(providers) do
        if not identifiers[provider] then
            missing[#missing + 1] = Lang:t('error.identity_' .. provider)
        end
    end
    if #missing > 0 then
        return false, Lang:t('error.required_identifiers', { identifiers = table.concat(missing, ', ') })
    end
    return true, nil, identifiers
end

exports('ValidatePlayerIdentifiers', WCore.Functions.ValidatePlayerIdentifiers)
