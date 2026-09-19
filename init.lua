-- Compatibility import for a dependency supplied by Wraith Core.
if type(w)=='table' and rawget(w,'name')=='w_lib' then lib=w;return w end
local code=assert(LoadResourceFile('w_lib','init.lua'),'w_lib bootstrap is missing')
return assert(load(code,'@@w_lib/init.lua','t',_ENV))()
