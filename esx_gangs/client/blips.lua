-- esx_gangs - Live Gang Member Blips
-- هر عضو گنگ میتونه هم تیمی هاش رو لایو روی مپ ببینه
-- بلیپ سیاه برای هر بازیکن، اسم + رنک
-- با Config.MemberBlip.showSelf بلیپ خود پلیر هم نمایش داده میشه

local gangBlips = {} -- [serverId] = blipHandle
local lastList = {}  -- [serverId] = { name, rank }

local function getMyServerId()
    return GetPlayerServerId(PlayerId())
end

local function rankLabelLocal()
    if not PlayerGang or not Gangs[PlayerGang] then return 'Member' end
    for _, r in ipairs(Gangs[PlayerGang].ranks or {}) do
        if tonumber(r.grade) == tonumber(PlayerGrade) then return r.label end
    end
    return tostring(PlayerGrade or 'Member')
end

local function setBlipName(blip, name, rankName)
    if not DoesBlipExist(blip) then return end
    local label = tostring(name or 'Unknown')
    if rankName and rankName ~= '' then
        label = label .. ' | ' .. tostring(rankName)
    end
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)
end

local function makeBlip(x, y, z)
    local b = AddBlipForCoord(x + 0.0, y + 0.0, z + 0.0)
    local cfg = Config.MemberBlip or {}
    SetBlipSprite(b, cfg.sprite or 1) -- 1 = standard circle
    SetBlipColour(b, cfg.color or 40) -- 40 = black
    SetBlipScale(b, cfg.scale or 0.85)
    SetBlipDisplay(b, cfg.display or 4) -- both map + minimap
    SetBlipAsShortRange(b, cfg.shortRange or false) -- show globally, not short range
    if cfg.category then
        SetBlipCategory(b, cfg.category) -- 7 = "Other Players" legend
    end
    SetBlipPriority(b, 10)
    return b
end

local function wipe()
    for id, b in pairs(gangBlips) do
        if b and DoesBlipExist(b) then
            RemoveBlip(b)
        end
        gangBlips[id] = nil
    end
    lastList = {}
end

local function upsertBlip(id, x, y, z, name, rankName)
    local blip = gangBlips[id]
    if not blip or not DoesBlipExist(blip) then
        blip = makeBlip(x, y, z)
        gangBlips[id] = blip
    else
        SetBlipCoords(blip, x + 0.0, y + 0.0, z + 0.0)
    end
    setBlipName(blip, name, rankName)
    lastList[id] = { name = name, rank = rankName }
end

-- Core update handler - server sends only same-gang list every interval
RegisterNetEvent('esx_gangs:updatePlayers', function(list)
    if not PlayerGang or PlayerGang == '' then
        wipe()
        return
    end

    local cfg = Config.MemberBlip or {}
    local me = getMyServerId()
    local seen = {}
    list = list or {}

    for i = 1, #list do
        local d = list[i]
        local id = tonumber(d.id)
        if id and d.gang == PlayerGang then
            local isMe = (id == me)
            -- اگر showSelf روشن نیست بلیپ خودت ساخته نمیشه (رفتار قبلی)
            if not isMe or cfg.showSelf then
                seen[id] = true
                local name = d.name or ('ID ' .. tostring(id))
                local rank = d.gradeName or d.rank or ''
                if isMe then
                    name = name .. ' (You)'
                end
                upsertBlip(id, d.x or 0.0, d.y or 0.0, d.z or 0.0, name, rank)
            end
        end
    end

    -- امنیتی: هیچ بلیپی از دیتای لوکال ساخته نمیشه - فقط لیست تاییدشده سرور
    -- اگه سرور من رو توی لیست نذاشته یعنی عضو گنگ تاییدشده نیستم و نباید بلیپ داشته باشم

    -- remove blips for players who left / went offline / changed gang
    for id, blip in pairs(gangBlips) do
        if not seen[id] then
            if blip and DoesBlipExist(blip) then
                RemoveBlip(blip)
            end
            gangBlips[id] = nil
            lastList[id] = nil
        end
    end
end)

-- بلیپ خود پلیر رو نرم دنبال خودش نگه میداره (لیست سرور فقط هر interval میاد)
CreateThread(function()
    while true do
        Wait(250)
        local cfg = Config.MemberBlip or {}
        if cfg.showSelf and PlayerGang and PlayerGang ~= '' then
            local me = getMyServerId()
            local b = gangBlips[me]
            if b and DoesBlipExist(b) then
                local c = GetEntityCoords(PlayerPedId())
                SetBlipCoords(b, c.x, c.y, c.z)
            end
        end
    end
end)

-- gang removed -> wipe | gang changed -> wipe old blips and request fresh list
local myLastGang = nil
RegisterNetEvent('esx_gangs:setPlayerGang', function(name)
    if not name or name == '' then
        wipe()
    elseif myLastGang and myLastGang ~= name then
        wipe()
        TriggerServerEvent('esx_gangs:requestPlayers')
    end
    myLastGang = name or nil
end)

-- Thread: هر یک ثانیه وضعیت آنلاین بودن رو به سرور بفرست
CreateThread(function()
    while true do
        Wait(Config.GangBlipInterval or 1000)
        if PlayerGang and PlayerGang ~= '' then
            -- ارسال gang + grade + rank label
            local ok, label = pcall(rankLabelLocal)
            if not ok then label = 'Member' end
            TriggerServerEvent('esx_gangs:imOnline', PlayerGang, PlayerGrade, label)
        end
    end
end)

-- ضد stale: هر ۵ ثانیه وضعیت واقعی گنگ مستقیم از سرور پرسیده میشه
-- اگه کلاینت فکر کنه عضوه ولی سرور نگه (یا برعکس) -> همگام میشه و بلیپ‌های بیخود پاک میشن
CreateThread(function()
    while true do
        Wait(5000)
        lib.callback('esx_gangs:getMyGang', false, function(data)
            local serverGang = (data and data.gang) and data.gang.name or nil
            local serverGrade = (data and data.grade) or 0
            if serverGang ~= PlayerGang then
                -- همگام‌سازی با حقیقت سرور (عضویت حذف شده یا عوض شده)
                TriggerEvent('esx_gangs:setPlayerGang', serverGang, serverGrade)
            end
        end)
    end
end)

-- Watch loop: تا PlayerGang ست نشده منتظر میمونه (race ورود به سرور / ریستارت resource)
-- به محض ست شدن گنگ، بلافاصله لیست هم‌گنگی‌ها رو میگیره
local requestedFor = nil
CreateThread(function()
    while true do
        Wait(500)
        if PlayerGang and PlayerGang ~= '' then
            if requestedFor ~= PlayerGang then
                requestedFor = PlayerGang
                TriggerServerEvent('esx_gangs:requestPlayers')
            end
        else
            requestedFor = nil
        end
    end
end)

-- Optional: command to toggle blips (debug)
RegisterCommand('gangblips', function()
    if not PlayerGang or PlayerGang == '' then
        return ESX.ShowNotification('You are not in a gang')
    end
    local c = 0
    for _ in pairs(gangBlips) do c = c + 1 end
    ESX.ShowNotification(('Gang: %s | Active blips: %d'):format(tostring(PlayerGang), c))
end, false)

-- Ensure cleanup on resource stop
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        wipe()
    end
end)
