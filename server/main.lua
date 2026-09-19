WCore = {}
WCore.Config = WConfig
WCore.Shared = WShared
WCore.ClientCallbacks = {}
WCore.ServerCallbacks = {}

exports('GetCoreObject', function()
    return WCore
end)

-- To use this export in a script instead of manifest method
-- Just put this line of code below at the very top of the script
-- local WCore = exports['w_core']:GetCoreObject()
