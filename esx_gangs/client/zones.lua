local blips = {}
local zones = {}

local function wipeBlips()
    for _, b in ipairs(blips) do
        if DoesBlipExist(b) then RemoveBlip(b) end
    end
    blips = {}
end

local function wipeZones()
    for _, id in ipairs(zones) do
        exports.ox_target:removeZone(id)
    end
    zones = {}
end

local function addBlip(coords, text)
    if not Config.Blip.enabled or not coords then return end
    local b = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(b, Config.Blip.sprite)
    SetBlipColour(b, Config.Blip.color)
    SetBlipScale(b, Config.Blip.scale)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(text)
    EndTextCommandSetBlipName(b)
    blips[#blips + 1] = b
end

local function addZone(coords, name, label, icon, fn, feature)
    if not coords then return end
    local id = exports.ox_target:addSphereZone({
        coords = vec3(coords.x, coords.y, coords.z),
        radius = 1.8,
        debug = false,
        options = {
            {
                name = name,
                icon = icon,
                label = label,
                distance = 2.2,
                canInteract = function()
                    if PlayerGang and Gangs[PlayerGang] and Gangs[PlayerGang].active == false then return false end
                    return not feature or HasFeature(feature)
                end,
                onSelect = fn
            }
        }
    })
    zones[#zones + 1] = id
end

function RefreshZones()
    wipeBlips()
    wipeZones()
    if addImpoundBlip then addImpoundBlip() end
    if not PlayerGang or not Gangs[PlayerGang] then return end
    local g = Gangs[PlayerGang]
    -- گنگ غیرفعال / منقضی -> لوکیشن‌ها و بلیپ گنگ نمایش داده نمیشه
    if g.active == false then return end
    if g.parking then
        addBlip(g.parking, g.label)
        local id = exports.ox_target:addSphereZone({
            coords = vec3(g.parking.x, g.parking.y, g.parking.z),
            radius = 2.4,
            debug = false,
            options = {
                {
                    name = 'gang_park_' .. g.name,
                    icon = 'fa-solid fa-warehouse',
                    label = 'Take vehicle',
                    distance = 2.5,
                    canInteract = function() return HasFeature('parking') end,
                    onSelect = OpenGarage
                },
                {
                    name = 'gang_store_' .. g.name,
                    icon = 'fa-solid fa-car',
                    label = 'Park vehicle',
                    distance = 2.5,
                    canInteract = function() return HasFeature('parking') end,
                    onSelect = StoreCurrentVehicle
                }
            }
        })
        zones[#zones + 1] = id
    end
    if g.stash then
        addZone(g.stash, 'gang_stash_' .. g.name, 'Gang stash', 'fa-solid fa-box', OpenStash, 'stash')
    end
    if g.wardrobe then
        addZone(g.wardrobe, 'gang_cloth_' .. g.name, 'Wardrobe', 'fa-solid fa-shirt', OpenWardrobe, 'wardrobe')
    end
    if g.boss then
        addZone(g.boss, 'gang_boss_' .. g.name, 'Boss menu', 'fa-solid fa-crown', OpenBossMenu)
    end
    if g.craft then
        addZone(g.craft, 'gang_craft_' .. g.name, 'Craft table', 'fa-solid fa-hammer', OpenCraft, 'craft')
    end
end
