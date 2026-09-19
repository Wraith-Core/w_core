-- w_core · compat/rsg_server.lua -- server-side RSG-Core event mirroring (see rsg_shared.lua)

-- Local lifecycle events the core fires; RSG-written resources listen under the RSG name.
for _, pair in ipairs({
    { 'WCore:Server:PlayerLoaded',   'RSGCore:Server:PlayerLoaded' },
    { 'WCore:Server:OnPlayerUnload', 'RSGCore:Server:OnPlayerUnload' },
    { 'WCore:Server:OnJobUpdate',    'RSGCore:Server:OnJobUpdate' },
    { 'WCore:Server:OnGangUpdate',   'RSGCore:Server:OnGangUpdate' },
    { 'WCore:Server:OnMoneyChange',  'RSGCore:Server:OnMoneyChange' },
    { 'WCore:Player:SetPlayerData',  'RSGCore:Player:SetPlayerData' },
    { 'WCore:Server:UpdateObject',   'RSGCore:Server:UpdateObject' },
}) do
    WCore.Compat_MirrorBoth(pair[1], pair[2])
end

