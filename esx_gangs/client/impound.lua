local ped
local targetId
local impoundBlip

function addImpoundBlip()
    if impoundBlip and DoesBlipExist(impoundBlip) then
        RemoveBlip(impoundBlip)
        impoundBlip = nil
    end
    if not PlayerGang or not Config.Impound then return end
    local c = Config.Impound.coords
    impoundBlip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(impoundBlip, 68)
    SetBlipColour(impoundBlip, 5)
    SetBlipScale(impoundBlip, 0.85)
    SetBlipAsShortRange(impoundBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Gang Impound')
    EndTextCommandSetBlipName(impoundBlip)
end

function OpenImpound()
    if not PlayerGang then
        return ESX.ShowNotification('No gang')
    end
    lib.callback('esx_gangs:impoundList', false, function(list)
        list = list or {}
        if #list == 0 then
            return ESX.ShowNotification('No vehicles at impound')
        end
        local options = {}
        for _, v in ipairs(list) do
            options[#options + 1] = {
                title = v.label,
                description = v.model .. ' · $500 · 10s to parking',
                icon = 'car',
                onSelect = function()
                    if lib.progressCircle({
                        duration = (Config.ImpoundDelay or 10) * 1000,
                        label = 'Releasing vehicle',
                        position = 'bottom',
                        useWhileDead = false,
                        canCancel = true,
                        disable = { move = true, car = true, combat = true }
                    }) then
                        TriggerServerEvent('esx_gangs:retrieveImpound', v.model)
                    end
                end
            }
        end
        lib.registerContext({ id = 'gang_impound', title = 'Gang impound', options = options })
        lib.showContext('gang_impound')
    end)
end

local function spawnNpc()
    local cfg = Config.Impound
    if not cfg then return end
    local c = cfg.coords
    if targetId then
        pcall(function() exports.ox_target:removeZone(targetId) end)
        targetId = nil
    end
    targetId = exports.ox_target:addSphereZone({
        coords = vec3(c.x, c.y, c.z),
        radius = 2.0,
        debug = false,
        options = {
            {
                name = 'gang_impound',
                icon = 'fa-solid fa-warehouse',
                label = 'Gang impound',
                distance = 2.4,
                canInteract = function()
                    return PlayerGang ~= nil
                end,
                onSelect = OpenImpound
            }
        }
    })
    if ped and DoesEntityExist(ped) then
        DeleteEntity(ped)
        ped = nil
    end
    local hash = joaat(cfg.model)
    RequestModel(hash)
    local n = 0
    while not HasModelLoaded(hash) and n < 100 do
        Wait(50)
        n = n + 1
    end
    if not HasModelLoaded(hash) then return end
    ped = CreatePed(0, hash, c.x, c.y, c.z - 1.0, c.w or 0.0, false, false)
    if ped and ped ~= 0 then
        SetEntityAsMissionEntity(ped, true, true)
        SetPedDiesWhenInjured(ped, false)
        SetEntityInvincible(ped, true)
        FreezeEntityPosition(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_CLIPBOARD', 0, true)
    end
    SetModelAsNoLongerNeeded(hash)
end

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(200) end
    Wait(1500)
    spawnNpc()
end)

CreateThread(function()
    while true do
        Wait(4000)
        if not PlayerGang then goto cont end
        local pedId = PlayerPedId()
        if IsPedInAnyVehicle(pedId, false) then
            local veh = GetVehiclePedIsIn(pedId, false)
            local model = string.lower(GetDisplayNameFromVehicleModel(GetEntityModel(veh)))
            TriggerServerEvent('esx_gangs:touchVehicle', model)
            if IsEntityInWater(veh) then
                TriggerServerEvent('esx_gangs:waterImpound', model)
            end
        else
            for model, ent in pairs(Spawned or {}) do
                if not ent or not DoesEntityExist(ent) then
                    Spawned[model] = nil
                    TriggerServerEvent('esx_gangs:missingVehicle', model)
                elseif IsEntityInWater(ent) then
                    TriggerServerEvent('esx_gangs:waterImpound', model)
                end
            end
        end
        ::cont::
    end
end)
