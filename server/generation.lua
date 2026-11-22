-- A generation lease fences delete/reassign while a trusted resource settles one character's work.
-- It is separate from Citizen.IsBusy: normal money APIs must remain usable inside the lease.
local C = WCore.Citizen
local generationLeases = {}
local TRUSTED = {w_lib=true,w_heists=true,w_pets=true,w_crafting=true,w_gunsmith=true,w_creators=true,w_clothing=true,w_barber=true}
function C.HasGenerationLease(citizenid)
    return (generationLeases[citizenid] or 0)>0
end
function C.AnyGenerationLease()
    return next(generationLeases)~=nil
end
local function callable(fn)
    return type(fn)=='function' or (type(fn)=='table' and getmetatable(fn) and type(getmetatable(fn).__call)=='function')
end
exports('WithCitizenGeneration',function(citizenid,expectedPlayersRowId,fn)
    if not TRUSTED[GetInvokingResource()] then return false,'forbidden' end
    citizenid=C.Normalize(citizenid)
    local rowId=tonumber(expectedPlayersRowId)
    if not citizenid or not rowId or rowId~=rowId or rowId<1 or rowId>9007199254740991 or rowId%1~=0 or not callable(fn) then
        return false,'invalid_generation'
    end
    if C.IsBusy(citizenid) then return false,'generation_busy' end
    if C.RowPurged(rowId) or C.RowMoved(rowId,citizenid) then return false,'generation_changed' end
    -- No yield between the mutation check and taking the lease. Mutations check this counter too.
    generationLeases[citizenid]=(generationLeases[citizenid] or 0)+1
    local result=table.pack(pcall(function()
        local ok,row=pcall(MySQL.single.await,'SELECT id FROM players WHERE id=? AND citizenid=?',{rowId,citizenid})
        if not ok then return false,'generation_unavailable' end
        if not row or tonumber(row.id)~=rowId or C.RowPurged(rowId) or C.RowMoved(rowId,citizenid) then
            return false,'generation_changed'
        end
        if C.IsBusy(citizenid) then return false,'generation_busy' end
        return fn()
    end))
    local left=(generationLeases[citizenid] or 1)-1
    generationLeases[citizenid]=left>0 and left or nil
    if not result[1] then
        print('^1[w_core] Character generation callback failed; lease released^0')
        return false,'generation_callback_failed'
    end
    return table.unpack(result,2,result.n)
end)
