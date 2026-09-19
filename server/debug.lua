-- Debug printers over the library print module (w.print; tables are serialised by it and the
-- level honours w_lib:printlevel). WCore.Debug / ShowError / ShowSuccess keep their names.

-- Server callers send (tbl, indent); the client's WCore.Debug(resource, obj, depth) sends the
-- resource name first.
RegisterServerEvent('WCore:DebugSomething', function(tbl, indent, depth)
    local resource = GetInvokingResource() or 'w_core'
    if type(tbl) == 'string' and indent ~= nil and type(indent) ~= 'number' then
        resource, tbl, indent = tbl, indent, depth
    end
    w.print.debug(('[%s] debug'):format(resource), tbl, indent)
end)

function WCore.Debug(tbl, indent)
    TriggerEvent('WCore:DebugSomething', tbl, indent)
end

function WCore.ShowError(resource, msg)
    w.print.error(('[%s] %s'):format(resource, msg))
end

function WCore.ShowSuccess(resource, msg)
    w.print.info(('[%s] %s'):format(resource, msg))
end
