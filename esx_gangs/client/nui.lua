local open = false

local function nui(show)
    open = show
    SetNuiFocus(show, show)
    if not show then
        SendNUIMessage({ action = 'close' })
    end
end

RegisterNetEvent('esx_gangs:openPanel', function(gangs, selected)
    local ok = pcall(SendNUIMessage, {
        action = 'open',
        gangs = gangs or {},
        selected = selected,
        maxRanks = Config.MaxRanks
    })
    if not ok then
        -- حداقل payload ممکن تا پنل همیشه باز بشه
        pcall(SendNUIMessage, { action = 'open', gangs = {}, maxRanks = Config.MaxRanks })
    end
    SetNuiFocus(true, true)
    open = true
end)

RegisterNUICallback('close', function(_, cb)
    nui(false)
    cb(true)
end)

RegisterNUICallback('create', function(data, cb)
    TriggerServerEvent('esx_gangs:createGang', data.name, data.label, data.days)
    cb(true)
end)

RegisterNUICallback('renewGang', function(data, cb)
    TriggerServerEvent('esx_gangs:renewGang', data.gang)
    cb(true)
end)

RegisterNUICallback('setGangEnabled', function(data, cb)
    TriggerServerEvent('esx_gangs:setGangEnabled', data.gang, data.enabled == true)
    cb(true)
end)

RegisterNUICallback('setGangRenewDays', function(data, cb)
    TriggerServerEvent('esx_gangs:setGangRenewDays', data.gang, data.days)
    cb(true)
end)

RegisterNUICallback('setLocation', function(data, cb)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local h = GetEntityHeading(ped)
    TriggerServerEvent('esx_gangs:setLocation', data.gang, data.kind, {
        x = c.x, y = c.y, z = c.z, w = h
    })
    cb(true)
end)

RegisterNUICallback('saveRanks', function(data, cb)
    TriggerServerEvent('esx_gangs:saveRanks', data.gang, data.ranks)
    cb(true)
end)

RegisterNUICallback('deleteGang', function(data, cb)
    TriggerServerEvent('esx_gangs:deleteGang', data.gang)
    cb(true)
end)

RegisterNUICallback('removeVehicle', function(data, cb)
    TriggerServerEvent('esx_gangs:removeVehicle', data.gang, data.model)
    cb(true)
end)

RegisterNUICallback('getPos', function(_, cb)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    cb({ x = c.x, y = c.y, z = c.z, w = GetEntityHeading(ped) })
end)

RegisterNUICallback('memberAction', function(data, cb)
    TriggerServerEvent('esx_gangs:memberAction', data.identifier, data.action)
    cb(true)
end)

RegisterNUICallback('money', function(data, cb)
    TriggerServerEvent('esx_gangs:money', data.kind, data.amount)
    cb(true)
end)

RegisterNUICallback('saveOutfit', function(data, cb)
    SaveBossOutfit(data.kind, data.grade)
    cb(true)
end)

RegisterNUICallback('recallVehicle', function(data, cb)
    TriggerServerEvent('esx_gangs:recallVehicle', data.model)
    cb(true)
end)

RegisterNUICallback('clearLogs', function(_, cb)
    TriggerServerEvent('esx_gangs:clearLogs')
    cb(true)
end)

RegisterNUICallback('setAccess', function(data, cb)
    TriggerServerEvent('esx_gangs:setAccess', data.feature, data.grades or {})
    cb(true)
end)

RegisterNUICallback('saveRecipes', function(data, cb)
    TriggerServerEvent('esx_gangs:saveRecipes', data.gang, data.recipes or {})
    cb(true)
end)

RegisterNUICallback('setRelation', function(data, cb)
    TriggerServerEvent('esx_gangs:setRelation', data.target, data.status)
    cb(true)
end)

RegisterNUICallback('sendChat', function(data, cb)
    TriggerServerEvent('esx_gangs:sendChat', data.target, data.message)
    cb(true)
end)

RegisterNUICallback('sendChatLocation', function(data, cb)
    TriggerServerEvent('esx_gangs:sendChatLocation', data.target, data.loc or {})
    cb(true)
end)

RegisterNUICallback('getChats', function(data, cb)
    lib.callback('esx_gangs:getChats', false, function(chats)
        SendNUIMessage({ action = 'chats', target = data.target, chats = chats or {} })
    end, data.target)
    cb(true)
end)

RegisterNUICallback('getAllGangs', function(_, cb)
    lib.callback('esx_gangs:getAllGangsPublic', false, function(all)
        SendNUIMessage({ action = 'syncGangs', gangs = all or {} })
    end)
    cb(true)
end)

RegisterNUICallback('clearChats', function(data, cb)
    TriggerServerEvent('esx_gangs:clearChats', data.target)
    cb(true)
end)

RegisterNUICallback('showLocation', function(data, cb)
    if data.x and data.y then
        SetNewWaypoint(data.x + 0.0, data.y + 0.0)
        ESX.ShowNotification('Location marked on map')
        local blip = AddBlipForCoord(data.x + 0.0, data.y + 0.0, data.z + 0.0)
        SetBlipSprite(blip, 280)
        SetBlipColour(blip, data.kind == 'love' and 1 or 5)
        SetBlipScale(blip, 0.9)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentString(data.kind == 'love' and '❤️ Love Location' or '📍 Gang Location')
        EndTextCommandSetBlipName(blip)
        SetTimeout(60000, function()
            if DoesBlipExist(blip) then RemoveBlip(blip) end
        end)
    end
    cb(true)
end)

RegisterNUICallback('getMyCoords', function(_, cb)
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    cb({ x = c.x, y = c.y, z = c.z })
end)

RegisterNUICallback('createGroup', function(data, cb)
    TriggerServerEvent('esx_gangs:createGroup', data.name, data.label, data.members or {})
    cb(true)
end)

RegisterNUICallback('getGroups', function(_, cb)
    lib.callback('esx_gangs:getGroups', false, function(groups)
        SendNUIMessage({ action = 'groups', groups = groups or {} })
    end)
    cb(true)
end)

RegisterNUICallback('getGroupChats', function(data, cb)
    lib.callback('esx_gangs:getGroupChats', false, function(chats)
        SendNUIMessage({ action = 'groupChats', groupId = data.groupId, chats = chats or {} })
    end, data.groupId)
    cb(true)
end)

RegisterNUICallback('sendGroupChat', function(data, cb)
    TriggerServerEvent('esx_gangs:sendGroupChat', data.groupId, data.message)
    cb(true)
end)

RegisterNUICallback('deleteGroup', function(data, cb)
    TriggerServerEvent('esx_gangs:deleteGroup', data.groupId)
    cb(true)
end)

RegisterNUICallback('leaveGroup', function(data, cb)
    TriggerServerEvent('esx_gangs:leaveGroup', data.groupId)
    cb(true)
end)

RegisterNUICallback('blockGang', function(data, cb)
    TriggerServerEvent('esx_gangs:blockGang', data.target)
    cb(true)
end)

RegisterNUICallback('unblockGang', function(data, cb)
    TriggerServerEvent('esx_gangs:unblockGang', data.target)
    cb(true)
end)

RegisterNUICallback('getBlocks', function(_, cb)
    lib.callback('esx_gangs:getBlocks', false, function(blocks)
        SendNUIMessage({ action = 'blocks', blocks = blocks or {} })
    end)
    cb(true)
end)
