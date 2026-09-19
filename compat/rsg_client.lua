-- w_core · compat/rsg_client.lua -- client-side RSG-Core event mirroring (see rsg_shared.lua)

-- Events the server sends to this client under the core's name (net), re-broadcast locally
-- under the RSG name, and the other way round. The "loaded" signal itself is raised by
-- client/events.lua once w_creators has spawned the ped. Player:SetPlayerData is not mirrored:
-- w_inventory's handler drops local re-triggers, so the server sends it under both names.
for _, pair in ipairs({
    { 'WCore:Client:OnPlayerLoaded',         'RSGCore:Client:OnPlayerLoaded' },
    { 'WCore:Client:OnPlayerUnload',         'RSGCore:Client:OnPlayerUnload' },
    { 'WCore:Client:OnJobUpdate',            'RSGCore:Client:OnJobUpdate' },
    { 'WCore:Client:OnGangUpdate',           'RSGCore:Client:OnGangUpdate' },
    { 'WCore:Client:SetDuty',                'RSGCore:Client:SetDuty' },
    { 'WCore:Client:UseItem',                'RSGCore:Client:UseItem' },
    { 'WCore:Client:UpdateObject',           'RSGCore:Client:UpdateObject' },
    { 'WCore:Client:OnSharedUpdate',         'RSGCore:Client:OnSharedUpdate' },
    { 'WCore:Client:OnSharedUpdateMultiple', 'RSGCore:Client:OnSharedUpdateMultiple' },
    { 'WCore:Player:UpdatePlayerData',       'RSGCore:Player:UpdatePlayerData' },
    { 'WCore:Notify',                        'RSGCore:Notify' },
}) do
    WCore.Compat_MirrorBoth(pair[1], pair[2], true)
end

-- The core reports money changes under the old HUD's name; RSG resources resync on this.
WCore.Compat_Mirror('hud:client:OnMoneyChange', 'RSGCore:Client:OnMoneyChange', true)
