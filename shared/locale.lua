-- Import-compatible Locale class. Translation tables belong to the calling resource.
Locale={};Locale.__index=Locale
local function merge(target,source)
    for key,value in pairs(source or {}) do
        if type(value)=='table' then target[key]=type(target[key])=='table' and target[key] or {};merge(target[key],value)
        else target[key]=value end
    end
end
function Locale:new(options)
    options=options or {};return setmetatable({phrases=options.phrases or {},fallback=options.fallbackLang,warnOnMissing=options.warnOnMissing},self)
end
function Locale:extend(phrases) merge(self.phrases,phrases) end
function Locale:clear() self.phrases={} end
function Locale:replace(phrases) self.phrases=phrases or {} end
function Locale:has(key)
    local value=self.phrases;for part in tostring(key):gmatch('[^.]+') do value=type(value)=='table' and value[part] or nil end
    return value~=nil
end
function Locale:t(key,args)
    local value=self.phrases;for part in tostring(key):gmatch('[^.]+') do value=type(value)=='table' and value[part] or nil end
    if type(value)~='string' then return self.fallback and self.fallback:t(key,args) or key end
    for name,replacement in pairs(args or {}) do value=value:gsub('%%{'..name..'}',function() return tostring(replacement) end) end
    return value
end
