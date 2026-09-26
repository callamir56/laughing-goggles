PlayerGang = nil
PlayerGrade = 0
Gangs = {}
Spawned = {}

function HasFeature(feature)
    if not PlayerGang or not Gangs[PlayerGang] then return false end
    local g = Gangs[PlayerGang]
    if g.active == false then return false end
    local list = g.access and g.access[feature]
    if type(list) ~= 'table' then return false end
    local grade = tonumber(PlayerGrade) or 0
    for _, n in pairs(list) do
        if tonumber(n) == grade then return true end
    end
    return false
end

RegisterNetEvent('esx_gangs:sync', function(data)
    Gangs = data or {}
    RefreshZones()
    SendNUIMessage({ action = 'syncGangs', gangs = Gangs })
    SendNUIMessage({ action = 'syncGangs', gangs = Gangs })
end)

-- گنگ غیرفعال (دستی یا منقضی شده) -> هیچ امکاناتی کار نمیکنه
local function gangDisabled()
    return PlayerGang and Gangs[PlayerGang] and Gangs[PlayerGang].active == false
end

RegisterNetEvent('esx_gangs:setPlayerGang', function(name, grade)
    PlayerGang = name
    PlayerGrade = grade or 0
    LocalPlayer.state:set('gang', name, true)
    LocalPlayer.state:set('gang_grade', grade or 0, true)
    -- compatibility with PlayerData.gang.name used by other resources
    if ESX and ESX.PlayerData then
        if name then
            ESX.PlayerData.gang = { name = name, grade = grade or 0, label = (Gangs[name] and Gangs[name].label) or name }
        else
            ESX.PlayerData.gang = nil
        end
    end
    if name then
        TriggerServerEvent('esx_gangs:imOnline', name, grade or 0)
    end
    RefreshZones()
end)

CreateThread(function()
    while not ESX.PlayerLoaded do Wait(200) end
    while GetResourceState('esx_gangs') ~= 'started' do Wait(200) end
    lib.callback('esx_gangs:getMyGang', false, function(data)
        if data and data.gang then
            PlayerGang = data.gang.name
            PlayerGrade = data.grade
            LocalPlayer.state:set('gang', PlayerGang, true)
            LocalPlayer.state:set('gang_grade', PlayerGrade, true)
            if ESX and ESX.PlayerData then
                ESX.PlayerData.gang = { name = PlayerGang, grade = PlayerGrade, label = data.gang.label or PlayerGang }
            end
            TriggerServerEvent('esx_gangs:imOnline', PlayerGang, PlayerGrade)
            RefreshZones()
        else
            if ESX and ESX.PlayerData then
                ESX.PlayerData.gang = nil
            end
        end
    end)
end)

local function modelNameFromVeh(veh)
    local model = GetEntityModel(veh)
    local name = GetDisplayNameFromVehicleModel(model)
    return string.lower(name)
end

RegisterNetEvent('esx_gangs:tryAddCar', function(gangName)
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        return ESX.ShowNotification('You must be in a vehicle')
    end
    local veh = GetVehiclePedIsIn(ped, false)
    if GetPedInVehicleSeat(veh, -1) ~= ped then
        return ESX.ShowNotification('You must be the driver')
    end
    local name = modelNameFromVeh(veh)
    local label = GetLabelText(GetDisplayNameFromVehicleModel(GetEntityModel(veh)))
    if not label or label == 'NULL' then label = name end
    local props = lib.getVehicleProperties(veh)
    TriggerServerEvent('esx_gangs:addVehicle', gangName, name, label, props)
end)

function IsGangBoss()
    if not PlayerGang or not Gangs[PlayerGang] then return false end
    local maxGrade = -1
    for _, r in ipairs(Gangs[PlayerGang].ranks or {}) do
        if r.grade > maxGrade then maxGrade = r.grade end
    end
    return PlayerGrade >= maxGrade and maxGrade >= 0
end

function OpenBossMenu()
    if gangDisabled() then
        return ESX.ShowNotification('Gang is disabled')
    end
    if not IsGangBoss() then
        return ESX.ShowNotification('Boss only')
    end
    lib.callback('esx_gangs:bossData', false, function(data)
        if not data then
            return ESX.ShowNotification('No permission')
        end
        -- ensure allGangs fallback from client sync if server didn't send
        if not data.allGangs or next(data.allGangs) == nil then
            data.allGangs = Gangs or {}
        end
        SendNUIMessage({ action = 'openBoss', data = data, allGangs = Gangs })
        SetNuiFocus(true, true)
    end)
end

function OpenStash()
    if not PlayerGang then return end
    if gangDisabled() then
        return ESX.ShowNotification('Gang is disabled')
    end
    if not HasFeature('stash') then
        return ESX.ShowNotification('No stash access')
    end
    exports.ox_inventory:openInventory('stash', Config.StashPrefix .. PlayerGang)
end

local function getSkin(cb)
    local ped = PlayerPedId()
    if GetResourceState('illenium-appearance') == 'started' then
        cb(exports['illenium-appearance']:getPedAppearance(ped))
        return
    end
    if GetResourceState('fivem-appearance') == 'started' then
        cb(exports['fivem-appearance']:getPedAppearance(ped))
        return
    end
    TriggerEvent('skinchanger:getSkin', function(skin)
        cb(skin)
    end)
end

local function applySkin(skin)
    if not skin then
        return ESX.ShowNotification('No outfit set')
    end
    local ped = PlayerPedId()
    if GetResourceState('illenium-appearance') == 'started' then
        exports['illenium-appearance']:setPedAppearance(ped, skin)
        return
    end
    if GetResourceState('fivem-appearance') == 'started' then
        exports['fivem-appearance']:setPedAppearance(ped, skin)
        return
    end
    TriggerEvent('skinchanger:loadSkin', skin)
end

function SaveBossOutfit(kind, grade)
    getSkin(function(skin)
        if type(skin) ~= 'table' then
            return ESX.ShowNotification('Could not read current outfit')
        end
        local g = tonumber(grade)
        if kind == 'rob' then g = -1 end
        if g == nil then g = -1 end
        TriggerServerEvent('esx_gangs:saveOutfit', kind, g, skin)
    end)
end

local wearing = 'citizen'

local function wear(kind)
    if wearing == 'citizen' and kind ~= 'citizen' then
        getSkin(function(cur)
            TriggerServerEvent('esx_gangs:saveCitizen', cur)
            lib.callback('esx_gangs:getOutfit', false, function(skin)
                applySkin(skin)
                if skin then wearing = kind end
            end, kind)
        end)
    else
        lib.callback('esx_gangs:getOutfit', false, function(skin)
            applySkin(skin)
            if skin then wearing = kind end
        end, kind)
    end
end

function OpenWardrobe()
    if gangDisabled() then
        return ESX.ShowNotification('Gang is disabled')
    end
    if not HasFeature('wardrobe') then
        return ESX.ShowNotification('No wardrobe access')
    end
    lib.registerContext({
        id = 'gang_wardrobe',
        title = 'Wardrobe',
        options = {
            { title = 'Civilian clothes', icon = 'shirt', onSelect = function() wear('citizen') end },
            { title = 'Gang clothes', icon = 'user-ninja', onSelect = function() wear('gang') end },
            { title = 'Rob clothes', icon = 'mask', onSelect = function() wear('rob') end }
        }
    })
    lib.showContext('gang_wardrobe')
end

function OpenCraft()
    if not PlayerGang then return end
    if gangDisabled() then
        return ESX.ShowNotification('Gang is disabled')
    end
    if not HasFeature('craft') then
        return ESX.ShowNotification('No craft access')
    end
    local options = {}
    local recipes = (Gangs[PlayerGang] and Gangs[PlayerGang].recipes) or {}
    for _, rec in ipairs(recipes) do
        local need = {}
        for _, ing in ipairs(rec.ingredients or {}) do
            need[#need + 1] = ing.count .. 'x ' .. ing.item
        end
        local title = rec.label or rec.result
        options[#options + 1] = {
            title = title .. ' x' .. tostring(rec.resultCount or 1),
            description = (rec.time or 5) .. 's · ' .. table.concat(need, ' · '),
            icon = 'hammer',
            onSelect = function()
                if lib.progressCircle({
                    duration = (rec.time or 5) * 1000,
                    label = 'Crafting ' .. title,
                    position = 'bottom',
                    useWhileDead = false,
                    canCancel = true,
                    disable = { move = true, car = true, combat = true }
                }) then
                    TriggerServerEvent('esx_gangs:craft', rec.id)
                end
            end
        }
    end
    if #options == 0 then
        return ESX.ShowNotification('No recipes')
    end
    lib.registerContext({ id = 'gang_craft', title = 'Craft table', options = options })
    lib.showContext('gang_craft')
end

function OpenGarage()
    if not PlayerGang or not Gangs[PlayerGang] then return end
    if gangDisabled() then
        return ESX.ShowNotification('Gang is disabled')
    end
    if not HasFeature('parking') then
        return ESX.ShowNotification('No parking access')
    end
    local g = Gangs[PlayerGang]
    if not g.spawn then
        return ESX.ShowNotification('Vehicle spawn is not set')
    end
    local options = {}
    for _, v in ipairs(g.vehicles) do
        options[#options + 1] = {
            title = v.label,
            description = v.stored and 'In garage' or 'Out',
            disabled = not v.stored,
            onSelect = function()
                TriggerServerEvent('esx_gangs:takeVehicle', v.model)
            end
        }
    end
    if #options == 0 then
        return ESX.ShowNotification('No vehicles')
    end
    lib.registerContext({ id = 'gang_garage', title = 'Garage ' .. g.label, options = options })
    lib.showContext('gang_garage')
end

function StoreCurrentVehicle()
    if gangDisabled() then
        return ESX.ShowNotification('Gang is disabled')
    end
    if not HasFeature('parking') then
        return ESX.ShowNotification('No parking access')
    end
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        veh = lib.getClosestVehicle(GetEntityCoords(ped), 5.0, false)
    end
    if not veh or veh == 0 then
        return ESX.ShowNotification('No vehicle nearby')
    end
    local model = modelNameFromVeh(veh)
    local owned = false
    for _, v in ipairs(Gangs[PlayerGang].vehicles or {}) do
        if v.model == model then owned = true break end
    end
    if not owned then
        return ESX.ShowNotification('This is not a gang vehicle')
    end
    local props = lib.getVehicleProperties(veh)
    TriggerServerEvent('esx_gangs:storeVehicle', model, props)
    Spawned[model] = nil
    if DoesEntityExist(veh) then
        DeleteEntity(veh)
    end
end

RegisterNetEvent('esx_gangs:spawnVehicle', function(model, spawn, props)
    if Spawned[model] and DoesEntityExist(Spawned[model]) then
        return ESX.ShowNotification('This vehicle is already out')
    end
    local hash = joaat(model)
    if not IsModelInCdimage(hash) then
        return ESX.ShowNotification('Invalid model')
    end
    lib.requestModel(hash)
    local veh = CreateVehicle(hash, spawn.x, spawn.y, spawn.z, spawn.w or 0.0, true, false)
    SetVehicleOnGroundProperly(veh)
    if props then
        lib.setVehicleProperties(veh, props)
    end
    SetPedIntoVehicle(PlayerPedId(), veh, -1)
    SetModelAsNoLongerNeeded(hash)
    Spawned[model] = veh
    TriggerServerEvent('esx_gangs:setVehNet', model, NetworkGetNetworkIdFromEntity(veh))
end)

RegisterNetEvent('esx_gangs:vehicleStored', function(model)
    if Spawned[model] and DoesEntityExist(Spawned[model]) then
        DeleteEntity(Spawned[model])
    end
    Spawned[model] = nil
end)

RegisterNetEvent('esx_gangs:refreshBoss', function()
    lib.callback('esx_gangs:bossData', false, function(data)
        if data then
            if not data.allGangs or next(data.allGangs) == nil then
                data.allGangs = Gangs or {}
            end
            SendNUIMessage({ action = 'openBoss', data = data, allGangs = Gangs })
        end
    end)
end)

RegisterNetEvent('esx_gangs:chatRefresh', function(gangA, gangB)
    if not PlayerGang then return end
    local myGang = PlayerGang
    local target = nil
    if gangA == myGang then target = gangB
    elseif gangB == myGang then target = gangA
    else return end
    if not target then return end
    lib.callback('esx_gangs:getChats', false, function(chats)
        SendNUIMessage({ action = 'chats', target = target, chats = chats or {} })
    end, target)
end)

RegisterNetEvent('esx_gangs:groupRefresh', function()
    lib.callback('esx_gangs:getGroups', false, function(groups)
        SendNUIMessage({ action = 'groups', groups = groups or {} })
    end)
end)

RegisterNetEvent('esx_gangs:groupChatRefresh', function(groupId)
    lib.callback('esx_gangs:getGroupChats', false, function(chats)
        SendNUIMessage({ action = 'groupChats', groupId = groupId, chats = chats or {} })
    end, groupId)
end)

RegisterNetEvent('esx_gangs:blockRefresh', function()
    lib.callback('esx_gangs:getBlocks', false, function(blocks)
        SendNUIMessage({ action = 'blocks', blocks = blocks or {} })
    end)
    lib.callback('esx_gangs:bossData', false, function(data)
        if data then
            if not data.allGangs or next(data.allGangs) == nil then
                data.allGangs = Gangs or {}
            end
            SendNUIMessage({ action = 'openBoss', data = data, allGangs = Gangs })
        end
    end)
end)
