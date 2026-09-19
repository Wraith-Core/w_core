-- Shared item definitions are owned by w_lib (an RSG-shaped copy of w_inventory's catalogue).
-- Each core VM receives its own table.
WItems = exports.w_lib:CompatItems()

-- On the client w_inventory's files are readable only once that resource has started there,
-- which is after this one: fill the same table in place as soon as they are (WShared.Items
-- points at it, so RSG-written resources see the rows appear).
if not IsDuplicityVersion() and next(WItems) == nil then
    CreateThread(function()
        for _ = 1, 600 do
            Wait(500)
            if GetResourceState('w_inventory') == 'started' or GetResourceState('w_inventory') == 'missing' then
                local items = exports.w_lib:CompatItems()
                if type(items) == 'table' and next(items) ~= nil then
                    for name, item in pairs(items) do WItems[name] = item end
                    TriggerEvent('WCore:Client:OnSharedUpdateMultiple', 'Items', WItems)
                    return
                end
                if GetResourceState('w_inventory') == 'missing' then return end
            end
        end
    end)
end
