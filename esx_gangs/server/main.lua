local Gangs = {}
local Online = {}

-- forward decl: بلیپ لایو - push فوری لیست هم‌گنگی‌ها (پایین‌تر تعریف میشه)
local sendGangPlayers

local function decodeCoords(raw)
    if not raw or raw == '' then return nil end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then return nil end
    if data.x then
        return { x = data.x + 0.0, y = data.y + 0.0, z = data.z + 0.0, w = data.w and (data.w + 0.0) or 0.0 }
    end
    return nil
end

local function encodeCoords(c)
    if not c then return nil end
    return json.encode({ x = c.x, y = c.y, z = c.z, w = c.w or 0.0 })
end

local function defaultAccess(ranks)
    local grades = {}
    for _, r in ipairs(ranks or {}) do
        grades[#grades + 1] = tonumber(r.grade)
    end
    if #grades == 0 then grades = { 0 } end
    return {
        stash = { table.unpack(grades) },
        wardrobe = { table.unpack(grades) },
        parking = { table.unpack(grades) },
        craft = { table.unpack(grades) }
    }
end

local function copyGrades(list)
    local t = {}
    for _, n in ipairs(list or {}) do t[#t + 1] = tonumber(n) end
    return t
end

local function decodeRecipes(raw)
    if not raw or raw == '' then return {} end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then return {} end
    return data
end

local function decodeAccess(raw, ranks)
    if not raw or raw == '' then return defaultAccess(ranks) end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then return defaultAccess(ranks) end
    return {
        stash = copyGrades(data.stash),
        wardrobe = copyGrades(data.wardrobe),
        parking = copyGrades(data.parking),
        craft = copyGrades(data.craft)
    }
end

local function gradeAllowed(list, grade)
    grade = tonumber(grade) or 0
    if type(list) ~= 'table' then return false end
    for _, n in pairs(list) do
        if tonumber(n) == grade then return true end
    end
    return false
end

function HasFeatureAccess(gname, grade, feature)
    if not gname or not Gangs[gname] then return false end
    if Gangs[gname].active == false then return false end
    local acc = Gangs[gname].access or {}
    return gradeAllowed(acc[feature], tonumber(grade) or 0)
end

-- ================== سیستم تمدید / انقضای گنگ ==================
local function toBool(v, default)
    if v == nil then return default end
    return v == true or v == 1 or v == '1'
end

local function gangActive(g)
    return g ~= nil and g.active ~= false
end

local function clampRenewDays(days)
    local n = math.floor(tonumber(days) or (Config.DefaultRenewDays or 30))
    if n < 0 then n = 0 end
    local max = Config.MaxRenewDays or 365
    if n > max then n = max end
    return n
end

local function expiryFromDays(days)
    if not days or days <= 0 then return nil end
    return os.time() + (days * 86400)
end

local function serializeGang(row)
    return {
        name = row.name,
        label = row.label,
        parking = decodeCoords(row.parking),
        spawn = decodeCoords(row.spawn),
        stash = decodeCoords(row.stash),
        wardrobe = decodeCoords(row.wardrobe),
        boss = decodeCoords(row.boss),
        craft = decodeCoords(row.craft),
        money = row.money or 0,
        ranks = row.ranks or {},
        vehicles = row.vehicles or {},
        access = row.access,
        recipes = row.recipes,
        renewDays = tonumber(row.renew_days) or 0,
        expiresAt = tonumber(row.expires_at) or nil,
        active = toBool(row.active, true)
    }
end

local function publicVehicles(list)
    local out = {}
    for _, v in ipairs(list or {}) do
        out[#out + 1] = {
            model = v.model,
            label = v.label,
            stored = v.stored == true or v.stored == 1,
            impounded = v.impounded == true or v.impounded == 1
        }
    end
    return out
end

local function publicOutfits(o)
    o = o or { rob = false, savedGrades = {} }
    local grades = {}
    if o.savedGrades then
        for _, n in ipairs(o.savedGrades) do
            grades[#grades + 1] = tonumber(n)
        end
    elseif o.ranks then
        for k, v in pairs(o.ranks) do
            if v == true then grades[#grades + 1] = tonumber(k) end
        end
    end
    return { rob = o.rob == true, savedGrades = grades }
end

local function publicGang(g)
    if not g then return nil end
    return {
        name = g.name,
        label = g.label,
        parking = g.parking,
        spawn = g.spawn,
        stash = g.stash,
        wardrobe = g.wardrobe,
        boss = g.boss,
        craft = g.craft,
        money = g.money,
        ranks = g.ranks,
        vehicles = publicVehicles(g.vehicles),
        outfits = publicOutfits(g.outfits),
        access = g.access or {},
        recipes = g.recipes or {},
        renewDays = g.renewDays or 0,
        expiresAt = g.expiresAt or nil,
        active = g.active ~= false
    }
end

local function publicAll()
    local t = {}
    for k, g in pairs(Gangs) do
        t[k] = publicGang(g)
    end
    return t
end

local function loadGangs()
    Gangs = {}
    -- =====================================================
    -- شرط ۳ ایمپاند: ریستارت سرور
    -- هر ماشینی که موقع ریستارت بیرون بوده (stored = 0) دیگه وجود نداره
    -- -> مستقیم میره ایمپاند گنگ
    -- ماشین‌های داخل پارکینگ گنگ (stored = 1) و ایمپاندی‌های قبلی دست نخورده میمونن
    -- =====================================================
    if Config.ImpoundOnRestart ~= false then
        MySQL.update.await('UPDATE gang_vehicles SET impounded = 1, stored = 0 WHERE stored = 0 AND impounded = 0')
    end
    local rows = MySQL.query.await('SELECT * FROM gangs')
    local ranks = MySQL.query.await('SELECT * FROM gang_ranks ORDER BY grade ASC')
    local vehicles = MySQL.query.await('SELECT * FROM gang_vehicles')

    local rankMap, vehMap = {}, {}
    for _, r in ipairs(ranks or {}) do
        rankMap[r.gang] = rankMap[r.gang] or {}
        rankMap[r.gang][#rankMap[r.gang] + 1] = { grade = r.grade, label = r.label }
    end
    for _, v in ipairs(vehicles or {}) do
        vehMap[v.gang] = vehMap[v.gang] or {}
        local props = nil
        if v.props and v.props ~= '' then
            local ok, d = pcall(json.decode, v.props)
            if ok then props = d end
        end
        vehMap[v.gang][#vehMap[v.gang] + 1] = {
            model = v.model,
            label = v.label,
            props = props,
            stored = v.stored == 1 or v.stored == true,
            impounded = v.impounded == 1 or v.impounded == true,
            lastUsed = tonumber(v.last_used) or 0,
            netId = nil
        }
    end

    for _, row in ipairs(rows or {}) do
        row.ranks = rankMap[row.name] or {}
        row.vehicles = vehMap[row.name] or {}
        Gangs[row.name] = serializeGang(row)
        Gangs[row.name].vehicles = row.vehicles
        Gangs[row.name].outfits = { rob = false, savedGrades = {} }
        Gangs[row.name].access = decodeAccess(row.access, row.ranks)
        Gangs[row.name].recipes = decodeRecipes(row.recipes)
        exports.ox_inventory:RegisterStash(Config.StashPrefix .. row.name, row.label, Config.DefaultSlots, Config.DefaultWeight)
    end
    local outfits = MySQL.query.await('SELECT gang, kind, grade FROM gang_outfits')
    for _, o in ipairs(outfits or {}) do
        if Gangs[o.gang] then
            if o.kind == 'rob' then
                Gangs[o.gang].outfits.rob = true
            elseif o.kind == 'rank' and o.grade ~= nil then
                Gangs[o.gang].outfits.savedGrades[#Gangs[o.gang].outfits.savedGrades + 1] = tonumber(o.grade)
            end
        end
    end
end

local function broadcastGangs()
    TriggerClientEvent('esx_gangs:sync', -1, publicAll())
end

-- چک انقضای گنگ‌ها: هر گنگی که وقتش تموم شده به صورت خودکار غیرفعال میشه
local function checkExpiries()
    local now = os.time()
    local changed = false
    for name, g in pairs(Gangs) do
        if g.active ~= false and g.expiresAt and now >= g.expiresAt then
            g.active = false
            changed = true
            MySQL.update.await('UPDATE gangs SET active = 0 WHERE name = ?', { name })
            for _, pid in ipairs(GetPlayers()) do
                local src = tonumber(pid)
                local xp = ESX.GetPlayerFromId(src)
                if xp and xp.get('gang') == name then
                    TriggerClientEvent('esx:showNotification', src, 'Gang expired, now disabled: ' .. (g.label or name))
                end
            end
        end
    end
    if changed then
        broadcastGangs()
    end
end

CreateThread(function()
    while true do
        Wait(Config.ExpiryCheckInterval or 60000)
        checkExpiries()
    end
end)

local function hasPermission(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return false end
    local group = xPlayer.getGroup and xPlayer.getGroup() or 'user'
    return Config.AllowedGroups[group] == true
end

local function getPlayerGang(xPlayer)
    return xPlayer.get('gang'), tonumber(xPlayer.get('gang_grade')) or 0
end

local function maxGrade(gangName)
    local max = -1
    if not Gangs[gangName] then return max end
    for _, r in ipairs(Gangs[gangName].ranks) do
        if r.grade > max then max = r.grade end
    end
    return max
end

local function isBoss(xPlayer)
    local g, gr = getPlayerGang(xPlayer)
    if not g or not Gangs[g] then return false end
    return gr >= maxGrade(g) and maxGrade(g) >= 0
end

local function rankLabel(gangName, grade)
    for _, r in ipairs(Gangs[gangName] and Gangs[gangName].ranks or {}) do
        if r.grade == grade then return r.label end
    end
    return tostring(grade)
end

local function nextGrade(gangName, current, dir)
    local ranks = Gangs[gangName].ranks
    table.sort(ranks, function(a, b) return a.grade < b.grade end)
    for i, r in ipairs(ranks) do
        if r.grade == current then
            local n = ranks[i + dir]
            return n and n.grade or nil
        end
    end
    return nil
end

-- ================== HUD compatibility ==================
-- دیتای گنگ دقیقاً با ساختار جاب ESX ساخته میشه تا هر HUD ای که job رو نشون میده، گنگ رو هم بشناسه
local function gangStateObject(name, grade)
    if not name or name == '' or not Gangs[name] then return nil end
    grade = tonumber(grade) or 0
    local gradeLabel = rankLabel(name, grade)
    local maxG = maxGrade(name)
    return {
        name = name,
        label = Gangs[name].label or name,
        grade = grade,
        grade_name = gradeLabel,
        grade_label = gradeLabel,
        grade_salary = 0,
        isboss = maxG >= 0 and grade >= maxG
    }
end

-- استایل setJob خود ESX: state:set('gang', obj, true) — سمت سرور، همه می‌بیننش
local function pushGangState(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local obj = gangStateObject(xPlayer.get('gang'), xPlayer.get('gang_grade'))
    local state = Player(src).state
    state:set('gang', obj, true)
    state:set('gang_grade', obj and (tonumber(xPlayer.get('gang_grade')) or 0) or 0, true)
end

local function playerName(xPlayer)
    if not xPlayer then return 'Unknown' end
    local n = xPlayer.getName and xPlayer.getName() or nil
    if n and n ~= '' and n ~= GetPlayerName(xPlayer.source) then return n end
    if xPlayer.get then
        local fn = xPlayer.get('firstName') or xPlayer.get('firstname')
        local ln = xPlayer.get('lastName') or xPlayer.get('lastname')
        if fn or ln then return ((fn or '') .. ' ' .. (ln or '')):gsub('^%s+', ''):gsub('%s+$', '') end
    end
    return GetPlayerName(xPlayer.source) or xPlayer.identifier
end

local function upsertMember(identifier, gang, grade, name)
    if not identifier then return end
    if not gang then
        MySQL.update.await('DELETE FROM gang_members WHERE identifier = ?', { identifier })
        pcall(function()
            MySQL.update.await('UPDATE users SET gang = NULL, gang_grade = 0 WHERE identifier = ?', { identifier })
        end)
        return
    end
    MySQL.query.await('REPLACE INTO gang_members (identifier, gang, grade, name) VALUES (?, ?, ?, ?)', {
        identifier, gang, grade or 0, name or ''
    })
    pcall(function()
        MySQL.update.await('UPDATE users SET gang = ?, gang_grade = ? WHERE identifier = ?', { gang, grade or 0, identifier })
    end)
end

local function ensureSchema()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `gang_outfits` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `gang` VARCHAR(50) NOT NULL,
            `kind` VARCHAR(20) NOT NULL,
            `grade` INT NULL DEFAULT NULL,
            `skin` LONGTEXT NOT NULL,
            PRIMARY KEY (`id`),
            UNIQUE KEY `gang_kind_grade` (`gang`, `kind`, `grade`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `gang_player_skins` (
            `identifier` VARCHAR(80) NOT NULL,
            `skin` LONGTEXT NOT NULL,
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `gang_stash_logs` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `gang` VARCHAR(50) NOT NULL,
            `identifier` VARCHAR(80) NOT NULL,
            `player` VARCHAR(80) NOT NULL,
            `action` VARCHAR(20) NOT NULL,
            `item` VARCHAR(80) NOT NULL,
            `count` INT NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `gang_time` (`gang`, `created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    pcall(function()
        MySQL.query.await('ALTER TABLE `gang_vehicles` ADD COLUMN `props` LONGTEXT NULL')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE `gang_vehicles` ADD COLUMN `stored` TINYINT NOT NULL DEFAULT 1')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE `gang_vehicles` ADD COLUMN `impounded` TINYINT NOT NULL DEFAULT 0')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE `gang_vehicles` ADD COLUMN `last_used` INT NOT NULL DEFAULT 0')
    end)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `gang_members` (
            `identifier` VARCHAR(80) NOT NULL,
            `gang` VARCHAR(50) NOT NULL,
            `grade` INT NOT NULL DEFAULT 0,
            `name` VARCHAR(80) NOT NULL DEFAULT '',
            PRIMARY KEY (`identifier`),
            KEY `gang_idx` (`gang`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    pcall(function()
        MySQL.query.await('ALTER TABLE `users` ADD COLUMN `gang` VARCHAR(50) NULL DEFAULT NULL')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE `users` ADD COLUMN `gang_grade` INT NULL DEFAULT 0')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE `gangs` ADD COLUMN `craft` LONGTEXT NULL')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE `gangs` ADD COLUMN `access` LONGTEXT NULL')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE `gangs` ADD COLUMN `recipes` LONGTEXT NULL')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE `gangs` ADD COLUMN `renew_days` INT NOT NULL DEFAULT 30')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE `gangs` ADD COLUMN `expires_at` INT NULL DEFAULT NULL')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE `gangs` ADD COLUMN `active` TINYINT NOT NULL DEFAULT 1')
    end)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `gang_relations` (
            `gang_source` VARCHAR(50) NOT NULL,
            `gang_target` VARCHAR(50) NOT NULL,
            `status` VARCHAR(20) NOT NULL DEFAULT 'neutral',
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`gang_source`,`gang_target`),
            KEY `target_idx` (`gang_target`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `gang_chats` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `gang_from` VARCHAR(50) NOT NULL,
            `gang_to` VARCHAR(50) NOT NULL,
            `sender_identifier` VARCHAR(80) NOT NULL,
            `sender_name` VARCHAR(80) NOT NULL,
            `sender_gang` VARCHAR(50) NOT NULL,
            `message` TEXT NOT NULL,
            `type` VARCHAR(20) NOT NULL DEFAULT 'text',
            `extra` LONGTEXT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `chat_pair` (`gang_from`,`gang_to`,`created_at`),
            KEY `chat_pair2` (`gang_to`,`gang_from`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    pcall(function()
        MySQL.query.await('ALTER TABLE `gang_chats` ADD COLUMN `type` VARCHAR(20) NOT NULL DEFAULT \'text\'')
    end)
    pcall(function()
        MySQL.query.await('ALTER TABLE `gang_chats` ADD COLUMN `extra` LONGTEXT NULL')
    end)
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `gang_groups` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `name` VARCHAR(50) NOT NULL,
            `label` VARCHAR(80) NOT NULL,
            `creator_gang` VARCHAR(50) NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `name` (`name`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `gang_group_members` (
            `group_id` INT NOT NULL,
            `gang_name` VARCHAR(50) NOT NULL,
            PRIMARY KEY (`group_id`, `gang_name`),
            KEY `gang_idx` (`gang_name`),
            CONSTRAINT `fk_group` FOREIGN KEY (`group_id`) REFERENCES `gang_groups` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `gang_group_chats` (
            `id` INT NOT NULL AUTO_INCREMENT,
            `group_id` INT NOT NULL,
            `sender_identifier` VARCHAR(80) NOT NULL,
            `sender_name` VARCHAR(80) NOT NULL,
            `sender_gang` VARCHAR(50) NOT NULL,
            `message` TEXT NOT NULL,
            `type` VARCHAR(20) NOT NULL DEFAULT 'text',
            `extra` LONGTEXT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `group_time` (`group_id`, `created_at`),
            CONSTRAINT `fk_group_chat` FOREIGN KEY (`group_id`) REFERENCES `gang_groups` (`id`) ON DELETE CASCADE
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `gang_blocks` (
            `blocker_gang` VARCHAR(50) NOT NULL,
            `blocked_gang` VARCHAR(50) NOT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`blocker_gang`, `blocked_gang`),
            KEY `blocked_idx` (`blocked_gang`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end

MySQL.ready(function()
    ensureSchema()
    loadGangs()
    checkExpiries()
    broadcastGangs()
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then
            local g = xPlayer.get('gang')
            if g and g ~= '' then
                local ped = GetPlayerPed(src)
                local c = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0.0,0.0,0.0)
                Online[src] = {
                    gang = g,
                    grade = xPlayer.get('gang_grade') or 0,
                    rank = rankLabel(g, xPlayer.get('gang_grade') or 0),
                    name = playerName(xPlayer),
                    x = c.x, y = c.y, z = c.z
                }
                TriggerClientEvent('esx_gangs:setPlayerGang', src, g, xPlayer.get('gang_grade') or 0)
            end
        end
    end
end)

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    TriggerClientEvent('esx_gangs:sync', playerId, publicAll())
    local mem = MySQL.single.await('SELECT gang, grade FROM gang_members WHERE identifier = ?', { xPlayer.identifier })
    local gname, ggrade
    if mem then
        gname, ggrade = mem.gang, mem.grade or 0
    else
        local row = MySQL.single.await('SELECT gang, gang_grade FROM users WHERE identifier = ?', { xPlayer.identifier })
        if row then
            gname, ggrade = row.gang, row.gang_grade or 0
        end
    end
    if gname and gname ~= '' then
        xPlayer.set('gang', gname)
        xPlayer.set('gang_grade', ggrade or 0)
        upsertMember(xPlayer.identifier, gname, ggrade or 0, playerName(xPlayer))
        local ped = GetPlayerPed(playerId)
        local c = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0.0,0.0,0.0)
        Online[playerId] = {
            gang = gname,
            grade = ggrade or 0,
            rank = rankLabel(gname, ggrade or 0),
            name = playerName(xPlayer),
            x = c.x, y = c.y, z = c.z
        }
        TriggerClientEvent('esx_gangs:setPlayerGang', playerId, gname, ggrade or 0)
        pushGangState(playerId)
        if sendGangPlayers then sendGangPlayers() end -- بلافاصله به هم‌گنگی‌های آنلاین بفرست
    end
end)

lib.callback.register('esx_gangs:getGangs', function(source)
    if not hasPermission(source) then return nil end
    return publicAll()
end)

lib.callback.register('esx_gangs:getAllGangsPublic', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return {} end
    local gname = xPlayer.get('gang')
    if not gname or not Gangs[gname] then return {} end
    return publicAll()
end)

lib.callback.register('esx_gangs:getMyGang', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return nil end
    local name = xPlayer.get('gang')
    if not name or not Gangs[name] then return nil end
    return { gang = publicGang(Gangs[name]), grade = xPlayer.get('gang_grade') or 0 }
end)

RegisterNetEvent('esx_gangs:createGang', function(name, label, days)
    local src = source
    if not hasPermission(src) then return end
    if type(name) ~= 'string' or type(label) ~= 'string' then return end
    name = name:lower():gsub('%s+', ''):gsub('[^%w_]', '')
    label = label:gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' or #name < 2 or #name > 32 then
        return TriggerClientEvent('esx:showNotification', src, 'Invalid gang name')
    end
    if label == '' or #label < 2 or #label > 50 then
        return TriggerClientEvent('esx:showNotification', src, 'Invalid gang label')
    end
    if Gangs[name] then
        return TriggerClientEvent('esx:showNotification', src, 'This gang already exists')
    end
    local renewDays = clampRenewDays(days)
    local expiresAt = expiryFromDays(renewDays)
    MySQL.insert.await('INSERT INTO gangs (name, label, renew_days, expires_at, active) VALUES (?, ?, ?, ?, 1)', {
        name, label, renewDays, expiresAt
    })
    MySQL.insert.await('INSERT INTO gang_ranks (gang, grade, label) VALUES (?, ?, ?)', { name, 0, 'Member' })
    MySQL.insert.await('INSERT INTO gang_ranks (gang, grade, label) VALUES (?, ?, ?)', { name, 1, 'Boss' })
    Gangs[name] = {
        name = name,
        label = label,
        parking = nil,
        spawn = nil,
        stash = nil,
        wardrobe = nil,
        boss = nil,
        craft = nil,
        money = 0,
        ranks = {
            { grade = 0, label = 'Member' },
            { grade = 1, label = 'Boss' }
        },
        vehicles = {},
        outfits = { rob = false, savedGrades = {} },
        access = defaultAccess({ { grade = 0 }, { grade = 1 } }),
        recipes = {},
        renewDays = renewDays,
        expiresAt = expiresAt,
        active = true
    }
    exports.ox_inventory:RegisterStash(Config.StashPrefix .. name, label, Config.DefaultSlots, Config.DefaultWeight)
    broadcastGangs()
    TriggerClientEvent('esx:showNotification', src, 'Gang created: ' .. label .. (renewDays > 0 and (' (' .. renewDays .. ' days)') or ' (unlimited)'))
    TriggerClientEvent('esx_gangs:openPanel', src, publicAll(), name)
end)

RegisterNetEvent('esx_gangs:setLocation', function(gangName, kind, coords)
    local src = source
    if not hasPermission(src) then return end
    if not Gangs[gangName] then return end
    local allowed = { parking = true, spawn = true, stash = true, wardrobe = true, boss = true, craft = true }
    if not allowed[kind] then return end
    if type(coords) ~= 'table' or not coords.x then return end
    local c = { x = coords.x + 0.0, y = coords.y + 0.0, z = coords.z + 0.0, w = (coords.w or 0.0) + 0.0 }
    MySQL.update.await(('UPDATE gangs SET `%s` = ? WHERE name = ?'):format(kind), { encodeCoords(c), gangName })
    Gangs[gangName][kind] = c
    broadcastGangs()
    TriggerClientEvent('esx:showNotification', src, 'Location saved')
end)

RegisterNetEvent('esx_gangs:saveRanks', function(gangName, ranks)
    local src = source
    if not hasPermission(src) then return end
    if not Gangs[gangName] then return end
    if type(ranks) ~= 'table' then return end
    if #ranks > Config.MaxRanks then
        return TriggerClientEvent('esx:showNotification', src, 'Maximum 10 ranks')
    end
    local cleaned, seen = {}, {}
    for _, r in ipairs(ranks) do
        local grade = tonumber(r.grade)
        local label = tostring(r.label or ''):gsub('^%s+', ''):gsub('%s+$', '')
        if not grade or grade < 0 or grade > 99 or label == '' then
            return TriggerClientEvent('esx:showNotification', src, 'Invalid rank')
        end
        if seen[grade] then
            return TriggerClientEvent('esx:showNotification', src, 'Duplicate grade')
        end
        seen[grade] = true
        cleaned[#cleaned + 1] = { grade = grade, label = label }
    end
    table.sort(cleaned, function(a, b) return a.grade < b.grade end)
    MySQL.update.await('DELETE FROM gang_ranks WHERE gang = ?', { gangName })
    for _, r in ipairs(cleaned) do
        MySQL.insert.await('INSERT INTO gang_ranks (gang, grade, label) VALUES (?, ?, ?)', { gangName, r.grade, r.label })
    end
    Gangs[gangName].ranks = cleaned
    broadcastGangs()
    TriggerClientEvent('esx:showNotification', src, 'Ranks saved')
end)

RegisterNetEvent('esx_gangs:deleteGang', function(gangName)
    local src = source
    if not hasPermission(src) then return end
    if not Gangs[gangName] then return end
    MySQL.update.await('UPDATE users SET gang = NULL, gang_grade = 0 WHERE gang = ?', { gangName })
    MySQL.update.await('DELETE FROM gangs WHERE name = ?', { gangName })
    Gangs[gangName] = nil
    broadcastGangs()
    TriggerClientEvent('esx:showNotification', src, 'Gang deleted')
    TriggerClientEvent('esx_gangs:openPanel', src, publicAll(), nil)
end)

-- ================== سیستم تمدید / انقضای گنگ ==================

-- تمدید: یک دوره کامل جدید از همین لحظه + فعال شدن گنگ
RegisterNetEvent('esx_gangs:renewGang', function(gangName)
    local src = source
    if not hasPermission(src) then return end
    local g = Gangs[gangName]
    if not g then
        return TriggerClientEvent('esx:showNotification', src, 'Gang not found')
    end
    local days = tonumber(g.renewDays) or 0
    g.expiresAt = expiryFromDays(days)
    g.active = true
    MySQL.update.await('UPDATE gangs SET expires_at = ?, active = 1 WHERE name = ?', { g.expiresAt, gangName })
    broadcastGangs()
    TriggerClientEvent('esx:showNotification', src, days > 0
        and ('Gang renewed for ' .. days .. ' days: ' .. (g.label or gangName))
        or ('Gang renewed (unlimited): ' .. (g.label or gangName)))
    TriggerClientEvent('esx_gangs:openPanel', src, publicAll(), gangName)
end)

-- فعال / غیرفعال دستی
RegisterNetEvent('esx_gangs:setGangEnabled', function(gangName, enabled)
    local src = source
    if not hasPermission(src) then return end
    local g = Gangs[gangName]
    if not g then
        return TriggerClientEvent('esx:showNotification', src, 'Gang not found')
    end
    enabled = toBool(enabled, false)
    if enabled then
        if g.expiresAt and os.time() >= g.expiresAt then
            return TriggerClientEvent('esx:showNotification', src, 'Gang period is over - use Renew')
        end
        g.active = true
        MySQL.update.await('UPDATE gangs SET active = 1 WHERE name = ?', { gangName })
        TriggerClientEvent('esx:showNotification', src, 'Gang enabled: ' .. (g.label or gangName))
    else
        g.active = false
        MySQL.update.await('UPDATE gangs SET active = 0 WHERE name = ?', { gangName })
        TriggerClientEvent('esx:showNotification', src, 'Gang disabled: ' .. (g.label or gangName))
    end
    broadcastGangs()
    TriggerClientEvent('esx_gangs:openPanel', src, publicAll(), gangName)
end)

-- تغییر روزها: طول دوره جدید میشه و دوره جدید از همین لحظه شروع میشه
RegisterNetEvent('esx_gangs:setGangRenewDays', function(gangName, days)
    local src = source
    if not hasPermission(src) then return end
    local g = Gangs[gangName]
    if not g then
        return TriggerClientEvent('esx:showNotification', src, 'Gang not found')
    end
    local n = tonumber(days)
    if n == nil or n < 0 or n ~= math.floor(n) or n > (Config.MaxRenewDays or 365) then
        return TriggerClientEvent('esx:showNotification', src, 'Invalid days (0-' .. tostring(Config.MaxRenewDays or 365) .. ')')
    end
    g.renewDays = n
    g.expiresAt = expiryFromDays(n)
    MySQL.update.await('UPDATE gangs SET renew_days = ?, expires_at = ? WHERE name = ?', { n, g.expiresAt, gangName })
    broadcastGangs()
    TriggerClientEvent('esx:showNotification', src, n > 0
        and ('Gang period set to ' .. n .. ' days: ' .. (g.label or gangName))
        or ('Gang set to unlimited: ' .. (g.label or gangName)))
    TriggerClientEvent('esx_gangs:openPanel', src, publicAll(), gangName)
end)

RegisterNetEvent('esx_gangs:addVehicle', function(gangName, model, label, props)
    local src = source
    if not hasPermission(src) then return end
    if not Gangs[gangName] then
        return TriggerClientEvent('esx:showNotification', src, 'Gang not found')
    end
    model = tostring(model or ''):lower()
    if model == '' then return end
    for _, v in ipairs(Gangs[gangName].vehicles) do
        if v.model == model then
            return TriggerClientEvent('esx:showNotification', src, 'This vehicle is already in the gang garage')
        end
    end
    local propsJson = props and json.encode(props) or nil
    MySQL.insert.await('INSERT INTO gang_vehicles (gang, model, label, props, stored) VALUES (?, ?, ?, ?, 1)', {
        gangName, model, label or model, propsJson
    })
    Gangs[gangName].vehicles[#Gangs[gangName].vehicles + 1] = {
        model = model, label = label or model, props = props, stored = true
    }
    broadcastGangs()
    TriggerClientEvent('esx:showNotification', src, 'Vehicle saved with current mods: ' .. model)
end)

RegisterNetEvent('esx_gangs:removeVehicle', function(gangName, model)
    local src = source
    if not hasPermission(src) then return end
    if not Gangs[gangName] then return end
    MySQL.update.await('DELETE FROM gang_vehicles WHERE gang = ? AND model = ?', { gangName, model })
    local list = {}
    for _, v in ipairs(Gangs[gangName].vehicles) do
        if v.model ~= model then list[#list + 1] = v end
    end
    Gangs[gangName].vehicles = list
    broadcastGangs()
end)

RegisterNetEvent('esx_gangs:takeVehicle', function(model)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local gname = xPlayer.get('gang')
    if not gname or not Gangs[gname] then return end
    local g = Gangs[gname]
    if not gangActive(g) then
        return TriggerClientEvent('esx:showNotification', src, 'Gang is disabled')
    end
    if not g.spawn then
        return TriggerClientEvent('esx:showNotification', src, 'Spawn is not set')
    end
    local veh
    for _, v in ipairs(g.vehicles) do
        if v.model == model then veh = v break end
    end
    if not veh then return end
    if veh.impounded then
        return TriggerClientEvent('esx:showNotification', src, 'This vehicle is at impound')
    end
    if not veh.stored then
        return TriggerClientEvent('esx:showNotification', src, 'This vehicle is out')
    end
    veh.stored = false
    veh.impounded = false
    veh.lastUsed = os.time()
    MySQL.update.await('UPDATE gang_vehicles SET stored = 0, impounded = 0, last_used = ? WHERE gang = ? AND model = ?', { veh.lastUsed, gname, model })
    broadcastGangs()
    TriggerClientEvent('esx_gangs:spawnVehicle', src, model, g.spawn, veh.props)
end)

RegisterNetEvent('esx_gangs:setVehNet', function(model, netId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local gname = xPlayer.get('gang')
    if not gname or not Gangs[gname] then return end
    for _, v in ipairs(Gangs[gname].vehicles) do
        if v.model == model then
            v.netId = tonumber(netId)
            v.lastUsed = os.time()
            break
        end
    end
end)

local function findVeh(gname, model)
    if not Gangs[gname] then return nil end
    for _, v in ipairs(Gangs[gname].vehicles) do
        if v.model == model then return v end
    end
    return nil
end

local function deleteVehNet(netId)
    if not netId then return end
    local ent = NetworkGetEntityFromNetworkId(netId)
    if ent and ent ~= 0 and DoesEntityExist(ent) then
        DeleteEntity(ent)
    end
end

local function markImpound(gname, model)
    local veh = findVeh(gname, model)
    if not veh or veh.stored or veh.impounded then return false end
    deleteVehNet(veh.netId)
    veh.impounded = true
    veh.stored = false
    veh.netId = nil
    MySQL.update.await('UPDATE gang_vehicles SET impounded = 1, stored = 0 WHERE gang = ? AND model = ?', { gname, model })
    broadcastGangs()
    TriggerClientEvent('esx_gangs:vehicleStored', -1, model)
    return true
end

RegisterNetEvent('esx_gangs:touchVehicle', function(model)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local gname = xPlayer.get('gang')
    local veh = findVeh(gname, model)
    if not veh or veh.stored or veh.impounded then return end
    veh.lastUsed = os.time()
    MySQL.update.await('UPDATE gang_vehicles SET last_used = ? WHERE gang = ? AND model = ?', { veh.lastUsed, gname, model })
end)

RegisterNetEvent('esx_gangs:waterImpound', function(model)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local gname = xPlayer.get('gang')
    if markImpound(gname, model) then
        TriggerClientEvent('esx:showNotification', src, 'Vehicle sent to gang impound')
    end
end)

RegisterNetEvent('esx_gangs:missingVehicle', function(model)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    markImpound(xPlayer.get('gang'), model)
end)

lib.callback.register('esx_gangs:impoundList', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return {} end
    local gname = xPlayer.get('gang')
    if not gname or not Gangs[gname] then return {} end
    local list = {}
    for _, v in ipairs(Gangs[gname].vehicles) do
        if v.impounded then
            list[#list + 1] = { model = v.model, label = v.label }
        end
    end
    return list
end)

RegisterNetEvent('esx_gangs:retrieveImpound', function(model)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local gname = xPlayer.get('gang')
    if not gname or not Gangs[gname] then return end
    if not gangActive(Gangs[gname]) then
        return TriggerClientEvent('esx:showNotification', src, 'Gang is disabled')
    end
    local veh = findVeh(gname, model)
    if not veh or not veh.impounded then
        return TriggerClientEvent('esx:showNotification', src, 'Vehicle not at impound')
    end
    local cost = Config.ImpoundCost or 500
    if xPlayer.getMoney() < cost then
        return TriggerClientEvent('esx:showNotification', src, 'You need $500 cash')
    end
    if not Gangs[gname].parking then
        return TriggerClientEvent('esx:showNotification', src, 'Gang parking is not set')
    end
    xPlayer.removeMoney(cost)
    veh.impounded = false
    veh.stored = true
    veh.netId = nil
    MySQL.update.await('UPDATE gang_vehicles SET impounded = 0, stored = 1 WHERE gang = ? AND model = ?', { gname, model })
    broadcastGangs()
    TriggerClientEvent('esx:showNotification', src, 'Vehicle is in the gang parking')
end)

CreateThread(function()
    while true do
        Wait(10000)
        local now = os.time()
        local idle = Config.ImpoundIdle or 14400
        for gname, g in pairs(Gangs) do
            for _, v in ipairs(g.vehicles or {}) do
                if not v.stored and not v.impounded then
                    local last = tonumber(v.lastUsed) or 0
                    if last == 0 then
                        v.lastUsed = now
                    elseif (now - last) >= idle then
                        markImpound(gname, v.model)
                    elseif v.netId then
                        local ent = NetworkGetEntityFromNetworkId(v.netId)
                        if not ent or ent == 0 or not DoesEntityExist(ent) then
                            markImpound(gname, v.model)
                        end
                    end
                end
            end
        end
    end
end)

RegisterNetEvent('esx_gangs:storeVehicle', function(model, props)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local gname = xPlayer.get('gang')
    if not gname or not Gangs[gname] then return end
    if not gangActive(Gangs[gname]) then
        return TriggerClientEvent('esx:showNotification', src, 'Gang is disabled')
    end
    local veh
    for _, v in ipairs(Gangs[gname].vehicles) do
        if v.model == model then veh = v break end
    end
    if not veh then
        return TriggerClientEvent('esx:showNotification', src, 'This is not a gang vehicle')
    end
    veh.props = props
    veh.stored = true
    MySQL.update.await('UPDATE gang_vehicles SET props = ?, stored = 1 WHERE gang = ? AND model = ?', {
        json.encode(props or {}), gname, model
    })
    broadcastGangs()
    TriggerClientEvent('esx:showNotification', src, 'Vehicle stored with mods')
    TriggerClientEvent('esx_gangs:vehicleStored', src, model)
end)

local function collectMembers(gname)
    local map = {}
    local rows = MySQL.query.await('SELECT identifier, grade, name FROM gang_members WHERE gang = ?', { gname }) or {}
    for _, row in ipairs(rows) do
        map[row.identifier] = {
            identifier = row.identifier,
            name = (row.name ~= '' and row.name) or row.identifier,
            grade = tonumber(row.grade) or 0,
            rank = rankLabel(gname, tonumber(row.grade) or 0),
            online = false,
            id = nil
        }
    end
    pcall(function()
        local urows = MySQL.query.await('SELECT identifier, gang_grade FROM users WHERE gang = ?', { gname }) or {}
        for _, row in ipairs(urows) do
            if not map[row.identifier] then
                map[row.identifier] = {
                    identifier = row.identifier,
                    name = row.identifier,
                    grade = tonumber(row.gang_grade) or 0,
                    rank = rankLabel(gname, tonumber(row.gang_grade) or 0),
                    online = false,
                    id = nil
                }
            end
        end
    end)
    local xPlayers = ESX.GetExtendedPlayers and ESX.GetExtendedPlayers() or ESX.GetPlayers()
    if xPlayers then
        for _, xp in pairs(xPlayers) do
            local xPlayer = type(xp) == 'table' and xp or ESX.GetPlayerFromId(xp)
            if xPlayer and xPlayer.get('gang') == gname then
                local ident = xPlayer.identifier
                local grade = tonumber(xPlayer.get('gang_grade')) or 0
                local name = playerName(xPlayer)
                map[ident] = {
                    identifier = ident,
                    name = name,
                    grade = grade,
                    rank = rankLabel(gname, grade),
                    online = true,
                    id = xPlayer.source
                }
                upsertMember(ident, gname, grade, name)
            end
        end
    end
    local list = {}
    for _, m in pairs(map) do
        list[#list + 1] = m
    end
    table.sort(list, function(a, b) return a.grade > b.grade end)
    return list
end

-- Helpers for Sides & Negotiation & Groups
local function getGroupMembers(groupId)
    local rows = MySQL.query.await('SELECT gang_name FROM gang_group_members WHERE group_id = ?', { groupId }) or {}
    local list = {}
    for _, r in ipairs(rows) do
        list[#list+1] = r.gang_name
    end
    return list
end

local function isGangInGroup(gangName, groupId)
    local row = MySQL.single.await('SELECT 1 as ok FROM gang_group_members WHERE group_id = ? AND gang_name = ?', { groupId, gangName })
    return row ~= nil
end

local function getGroupsForGang(gangName)
    local rows = MySQL.query.await([[
        SELECT gg.id, gg.name, gg.label, gg.creator_gang, gg.created_at
        FROM gang_groups gg
        JOIN gang_group_members ggm ON gg.id = ggm.group_id
        WHERE ggm.gang_name = ?
        ORDER BY gg.created_at DESC
    ]], { gangName }) or {}
    for _, g in ipairs(rows) do
        g.members = getGroupMembers(g.id)
        g.memberLabels = {}
        for _, m in ipairs(g.members) do
            g.memberLabels[m] = Gangs[m] and Gangs[m].label or m
        end
    end
    return rows
end

-- Block helpers
local function isBlocked(blocker, blocked)
    local row = MySQL.single.await('SELECT 1 as ok FROM gang_blocks WHERE blocker_gang = ? AND blocked_gang = ?', { blocker, blocked })
    return row ~= nil
end

local function getBlockedGangs(gangName)
    local rows = MySQL.query.await('SELECT blocked_gang FROM gang_blocks WHERE blocker_gang = ?', { gangName }) or {}
    local map = {}
    for _, r in ipairs(rows) do map[r.blocked_gang] = true end
    return map
end

local function getBlockedByGangs(gangName)
    local rows = MySQL.query.await('SELECT blocker_gang FROM gang_blocks WHERE blocked_gang = ?', { gangName }) or {}
    local map = {}
    for _, r in ipairs(rows) do map[r.blocker_gang] = true end
    return map
end

local function getMyRelations(gname)
    local map = {}
    local rows = MySQL.query.await('SELECT gang_target, status FROM gang_relations WHERE gang_source = ?', { gname }) or {}
    for _, r in ipairs(rows) do
        map[r.gang_target] = r.status
    end
    return map
end

local function getTheirRelations(gname)
    local map = {}
    local rows = MySQL.query.await('SELECT gang_source, status FROM gang_relations WHERE gang_target = ?', { gname }) or {}
    for _, r in ipairs(rows) do
        map[r.gang_source] = r.status
    end
    return map
end

lib.callback.register('esx_gangs:bossData', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer or not isBoss(xPlayer) then return nil end
    local gname = xPlayer.get('gang')
    if not gname or not Gangs[gname] or not gangActive(Gangs[gname]) then return nil end
    local logs = MySQL.query.await('SELECT player, action, item, count, UNIX_TIMESTAMP(created_at) AS created_at FROM gang_stash_logs WHERE gang = ? ORDER BY id DESC LIMIT 80', { gname })
    local all = publicAll()
    local myRels = getMyRelations(gname)
    local theirRels = getTheirRelations(gname)
    local groups = getGroupsForGang(gname)
    local blocked = getBlockedGangs(gname)
    local blockedBy = getBlockedByGangs(gname)
    return {
        gang = publicGang(Gangs[gname]),
        members = collectMembers(gname),
        logs = logs or {},
        myGrade = xPlayer.get('gang_grade') or 0,
        allGangs = all,
        myRelations = myRels,
        theirRelations = theirRels,
        groups = groups,
        blocked = blocked,
        blockedBy = blockedBy
    }
end)

-- Sides relations
RegisterNetEvent('esx_gangs:setRelation', function(targetGang, status)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not isBoss(xPlayer) then return end
    local myGang = xPlayer.get('gang')
    if not myGang or not Gangs[myGang] then return end
    if not targetGang or not Gangs[targetGang] then
        return TriggerClientEvent('esx:showNotification', src, 'Gang not found')
    end
    if myGang == targetGang then
        return TriggerClientEvent('esx:showNotification', src, 'Cannot set relation to own gang')
    end
    status = tostring(status or ''):lower()
    if status == 'friend' then status = 'ally' end
    if status ~= 'ally' and status ~= 'enemy' and status ~= 'neutral' then
        return TriggerClientEvent('esx:showNotification', src, 'Invalid status')
    end
    if status == 'neutral' then
        MySQL.update.await('DELETE FROM gang_relations WHERE gang_source = ? AND gang_target = ?', { myGang, targetGang })
    else
        MySQL.query.await('REPLACE INTO gang_relations (gang_source, gang_target, status) VALUES (?, ?, ?)', { myGang, targetGang, status })
    end
    TriggerClientEvent('esx:showNotification', src, ('Relation to %s set to %s'):format(Gangs[targetGang].label or targetGang, status))
    TriggerClientEvent('esx_gangs:refreshBoss', src)
    for _, pid in ipairs(GetPlayers()) do
        local xp = ESX.GetPlayerFromId(tonumber(pid))
        if xp and xp.get('gang') == targetGang and isBoss(xp) then
            TriggerClientEvent('esx_gangs:refreshBoss', tonumber(pid))
        end
    end
end)

lib.callback.register('esx_gangs:getRelations', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return {} end
    local gname = xPlayer.get('gang')
    if not gname then return {} end
    return {
        my = getMyRelations(gname),
        their = getTheirRelations(gname),
        all = publicAll()
    }
end)

-- Negotiation chats
lib.callback.register('esx_gangs:getChats', function(source, targetGang)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return {} end
    local myGang = xPlayer.get('gang')
    if not myGang or not targetGang or not Gangs[targetGang] or not Gangs[myGang] then return {} end
    if myGang == targetGang then return {} end
    local rows = MySQL.query.await('SELECT gang_from, gang_to, sender_name, sender_gang, message, type, extra, UNIX_TIMESTAMP(created_at) as ts, created_at FROM gang_chats WHERE (gang_from = ? AND gang_to = ?) OR (gang_from = ? AND gang_to = ?) ORDER BY id ASC LIMIT 200', { myGang, targetGang, targetGang, myGang }) or {}
    for _, r in ipairs(rows) do
        if r.extra and r.extra ~= '' then
            local ok, d = pcall(json.decode, r.extra)
            if ok then r.extraDecoded = d end
        end
    end
    return rows
end)

RegisterNetEvent('esx_gangs:sendChat', function(targetGang, message)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local myGang = xPlayer.get('gang')
    if not myGang or not Gangs[myGang] then return end
    if not isBoss(xPlayer) then
        return TriggerClientEvent('esx:showNotification', src, 'Boss only')
    end
    if not targetGang or not Gangs[targetGang] or myGang == targetGang then
        return TriggerClientEvent('esx:showNotification', src, 'Invalid gang')
    end
    -- block check
    if isBlocked(targetGang, myGang) then
        return TriggerClientEvent('esx:showNotification', src, 'You are blocked by this gang')
    end
    if isBlocked(myGang, targetGang) then
        return TriggerClientEvent('esx:showNotification', src, 'You have blocked this gang. Unblock to send.')
    end
    message = tostring(message or '')
    message = message:gsub('^%s+', ''):gsub('%s+$', '')
    if #message < 1 then return end
    if #message > 500 then
        return TriggerClientEvent('esx:showNotification', src, 'Message too long')
    end
    local senderName = playerName(xPlayer)
    MySQL.insert.await('INSERT INTO gang_chats (gang_from, gang_to, sender_identifier, sender_name, sender_gang, message, type) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        myGang, targetGang, xPlayer.identifier, senderName, myGang, message, 'text'
    })
    TriggerClientEvent('esx:showNotification', src, 'Message sent')
    for _, pid in ipairs(GetPlayers()) do
        local xp = ESX.GetPlayerFromId(tonumber(pid))
        if xp then
            local g = xp.get('gang')
            if g == myGang or g == targetGang then
                TriggerClientEvent('esx_gangs:chatRefresh', tonumber(pid), myGang, targetGang)
            end
        end
    end
end)

RegisterNetEvent('esx_gangs:sendChatLocation', function(targetGang, data)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local myGang = xPlayer.get('gang')
    if not myGang or not Gangs[myGang] then return end
    if not isBoss(xPlayer) then
        return TriggerClientEvent('esx:showNotification', src, 'Boss only')
    end
    if not targetGang or not Gangs[targetGang] or myGang == targetGang then
        return TriggerClientEvent('esx:showNotification', src, 'Invalid gang')
    end
    if type(data) ~= 'table' then return end
    local x = tonumber(data.x) or 0
    local y = tonumber(data.y) or 0
    local z = tonumber(data.z) or 0
    local kind = tostring(data.kind or 'location')
    if kind ~= 'location' and kind ~= 'love' then kind = 'location' end
    local extra = json.encode({ x = x, y = y, z = z, kind = kind })
    local msg = kind == 'love' and '❤️ Love Location' or '📍 Location'
    local senderName = playerName(xPlayer)
    MySQL.insert.await('INSERT INTO gang_chats (gang_from, gang_to, sender_identifier, sender_name, sender_gang, message, type, extra) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', {
        myGang, targetGang, xPlayer.identifier, senderName, myGang, msg, kind, extra
    })
    TriggerClientEvent('esx:showNotification', src, 'Location sent')
    for _, pid in ipairs(GetPlayers()) do
        local xp = ESX.GetPlayerFromId(tonumber(pid))
        if xp then
            local g = xp.get('gang')
            if g == myGang or g == targetGang then
                TriggerClientEvent('esx_gangs:chatRefresh', tonumber(pid), myGang, targetGang)
            end
        end
    end
end)

RegisterNetEvent('esx_gangs:clearChats', function(targetGang)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not isBoss(xPlayer) then return end
    local myGang = xPlayer.get('gang')
    if not myGang or not targetGang or not Gangs[targetGang] then return end
    MySQL.update.await('DELETE FROM gang_chats WHERE (gang_from = ? AND gang_to = ?) OR (gang_from = ? AND gang_to = ?)', { myGang, targetGang, targetGang, myGang })
    TriggerClientEvent('esx:showNotification', src, 'Chat cleared')
    for _, pid in ipairs(GetPlayers()) do
        local xp = ESX.GetPlayerFromId(tonumber(pid))
        if xp then
            local g = xp.get('gang')
            if g == myGang or g == targetGang then
                TriggerClientEvent('esx_gangs:chatRefresh', tonumber(pid), myGang, targetGang)
            end
        end
    end
end)

-- ================== GANG GROUPS (Telegram style group chat) ==================
lib.callback.register('esx_gangs:getGroups', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return {} end
    local myGang = xPlayer.get('gang')
    if not myGang then return {} end
    return getGroupsForGang(myGang)
end)

lib.callback.register('esx_gangs:getGroupChats', function(source, groupId)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return {} end
    local myGang = xPlayer.get('gang')
    if not myGang then return {} end
    groupId = tonumber(groupId)
    if not groupId then return {} end
    if not isGangInGroup(myGang, groupId) then return {} end
    local rows = MySQL.query.await('SELECT sender_name, sender_gang, message, type, extra, UNIX_TIMESTAMP(created_at) as ts, created_at FROM gang_group_chats WHERE group_id = ? ORDER BY id ASC LIMIT 300', { groupId }) or {}
    for _, r in ipairs(rows) do
        if r.extra and r.extra ~= '' then
            local ok, d = pcall(json.decode, r.extra)
            if ok then r.extraDecoded = d end
        end
    end
    return rows
end)

RegisterNetEvent('esx_gangs:createGroup', function(name, label, members)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not isBoss(xPlayer) then
        return TriggerClientEvent('esx:showNotification', src, 'Boss only')
    end
    local myGang = xPlayer.get('gang')
    if not myGang then return end
    if type(name) ~= 'string' or type(label) ~= 'string' then return end
    name = name:lower():gsub('%s+', ''):gsub('[^%w_]', '')
    label = label:gsub('^%s+', ''):gsub('%s+$', '')
    if #name < 2 or #name > 32 then
        return TriggerClientEvent('esx:showNotification', src, 'Invalid group name (2-32)')
    end
    if #label < 2 or #label > 50 then
        return TriggerClientEvent('esx:showNotification', src, 'Invalid group label')
    end
    if type(members) ~= 'table' or #members == 0 then
        return TriggerClientEvent('esx:showNotification', src, 'Select at least 1 other gang')
    end
    -- validate gangs
    local uniq = {}
    uniq[myGang] = true
    for _, g in ipairs(members) do
        if Gangs[g] and g ~= myGang then
            uniq[g] = true
        end
    end
    local finalMembers = {}
    for g,_ in pairs(uniq) do finalMembers[#finalMembers+1] = g end
    if #finalMembers < 2 then
        return TriggerClientEvent('esx:showNotification', src, 'Need at least 2 gangs in group')
    end
    if #finalMembers > 10 then
        return TriggerClientEvent('esx:showNotification', src, 'Max 10 gangs per group')
    end
    -- check duplicate name
    local exists = MySQL.single.await('SELECT id FROM gang_groups WHERE name = ?', { name })
    if exists then
        return TriggerClientEvent('esx:showNotification', src, 'Group name already exists')
    end
    local groupId = MySQL.insert.await('INSERT INTO gang_groups (name, label, creator_gang) VALUES (?, ?, ?)', { name, label, myGang })
    if not groupId then
        return TriggerClientEvent('esx:showNotification', src, 'Failed to create group')
    end
    for _, g in ipairs(finalMembers) do
        MySQL.insert.await('INSERT INTO gang_group_members (group_id, gang_name) VALUES (?, ?)', { groupId, g })
    end
    TriggerClientEvent('esx:showNotification', src, 'Group created: ' .. label)
    -- notify all member gangs
    for _, pid in ipairs(GetPlayers()) do
        local xp = ESX.GetPlayerFromId(tonumber(pid))
        if xp then
            local gg = xp.get('gang')
            if uniq[gg] then
                TriggerClientEvent('esx_gangs:groupRefresh', tonumber(pid))
                if isBoss(xp) then
                    TriggerClientEvent('esx_gangs:refreshBoss', tonumber(pid))
                end
            end
        end
    end
end)

RegisterNetEvent('esx_gangs:sendGroupChat', function(groupId, message)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not isBoss(xPlayer) then return end
    local myGang = xPlayer.get('gang')
    if not myGang then return end
    groupId = tonumber(groupId)
    if not groupId then return end
    if not isGangInGroup(myGang, groupId) then
        return TriggerClientEvent('esx:showNotification', src, 'Not in group')
    end
    message = tostring(message or ''):gsub('^%s+', ''):gsub('%s+$', '')
    if #message < 1 or #message > 500 then return end
    local senderName = playerName(xPlayer)
    MySQL.insert.await('INSERT INTO gang_group_chats (group_id, sender_identifier, sender_name, sender_gang, message, type) VALUES (?, ?, ?, ?, ?, ?)', {
        groupId, xPlayer.identifier, senderName, myGang, message, 'text'
    })
    -- notify group members
    local members = getGroupMembers(groupId)
    local memberSet = {}
    for _, m in ipairs(members) do memberSet[m]=true end
    for _, pid in ipairs(GetPlayers()) do
        local xp = ESX.GetPlayerFromId(tonumber(pid))
        if xp and memberSet[xp.get('gang')] then
            TriggerClientEvent('esx_gangs:groupChatRefresh', tonumber(pid), groupId)
        end
    end
end)

RegisterNetEvent('esx_gangs:deleteGroup', function(groupId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not isBoss(xPlayer) then return end
    local myGang = xPlayer.get('gang')
    groupId = tonumber(groupId)
    if not groupId then return end
    local grp = MySQL.single.await('SELECT creator_gang FROM gang_groups WHERE id = ?', { groupId })
    if not grp then return end
    if grp.creator_gang ~= myGang and not hasPermission(src) then
        return TriggerClientEvent('esx:showNotification', src, 'Only creator can delete')
    end
    MySQL.update.await('DELETE FROM gang_groups WHERE id = ?', { groupId })
    TriggerClientEvent('esx:showNotification', src, 'Group deleted')
    for _, pid in ipairs(GetPlayers()) do
        TriggerClientEvent('esx_gangs:groupRefresh', tonumber(pid))
        TriggerClientEvent('esx_gangs:refreshBoss', tonumber(pid))
    end
end)

RegisterNetEvent('esx_gangs:leaveGroup', function(groupId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not isBoss(xPlayer) then return end
    local myGang = xPlayer.get('gang')
    groupId = tonumber(groupId)
    if not groupId then return end
    if not isGangInGroup(myGang, groupId) then
        return TriggerClientEvent('esx:showNotification', src, 'Not in group')
    end
    MySQL.update.await('DELETE FROM gang_group_members WHERE group_id = ? AND gang_name = ?', { groupId, myGang })
    TriggerClientEvent('esx:showNotification', src, 'Left group')
    -- if no members left, delete group
    local remaining = MySQL.single.await('SELECT COUNT(*) as cnt FROM gang_group_members WHERE group_id = ?', { groupId })
    if remaining and remaining.cnt == 0 then
        MySQL.update.await('DELETE FROM gang_groups WHERE id = ?', { groupId })
    end
    for _, pid in ipairs(GetPlayers()) do
        TriggerClientEvent('esx_gangs:groupRefresh', tonumber(pid))
        TriggerClientEvent('esx_gangs:refreshBoss', tonumber(pid))
    end
end)

-- Block system
lib.callback.register('esx_gangs:getBlocks', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return {} end
    local gname = xPlayer.get('gang')
    if not gname then return {} end
    return {
        blocked = getBlockedGangs(gname),
        blockedBy = getBlockedByGangs(gname)
    }
end)

RegisterNetEvent('esx_gangs:blockGang', function(targetGang)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not isBoss(xPlayer) then return end
    local myGang = xPlayer.get('gang')
    if not myGang or not targetGang or not Gangs[targetGang] or myGang == targetGang then return end
    if isBlocked(myGang, targetGang) then
        return TriggerClientEvent('esx:showNotification', src, 'Already blocked')
    end
    MySQL.insert.await('INSERT INTO gang_blocks (blocker_gang, blocked_gang) VALUES (?, ?)', { myGang, targetGang })
    TriggerClientEvent('esx:showNotification', src, 'Gang blocked: ' .. (Gangs[targetGang].label or targetGang))
    TriggerClientEvent('esx_gangs:refreshBoss', src)
    TriggerClientEvent('esx_gangs:blockRefresh', src)
end)

RegisterNetEvent('esx_gangs:unblockGang', function(targetGang)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not isBoss(xPlayer) then return end
    local myGang = xPlayer.get('gang')
    if not myGang or not targetGang then return end
    MySQL.update.await('DELETE FROM gang_blocks WHERE blocker_gang = ? AND blocked_gang = ?', { myGang, targetGang })
    TriggerClientEvent('esx:showNotification', src, 'Gang unblocked')
    TriggerClientEvent('esx_gangs:refreshBoss', src)
    TriggerClientEvent('esx_gangs:blockRefresh', src)
end)

local function manageMember(src, identifier, action)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not isBoss(xPlayer) then return false, 'no_perm' end
    local gname = xPlayer.get('gang')
    local myGrade = tonumber(xPlayer.get('gang_grade')) or 0
    if identifier == xPlayer.identifier then return false, 'self' end
    local mem = MySQL.single.await('SELECT identifier, gang, grade, name FROM gang_members WHERE identifier = ?', { identifier })
    if not mem then
        mem = MySQL.single.await('SELECT identifier, gang, gang_grade AS grade FROM users WHERE identifier = ?', { identifier })
    end
    if not mem or mem.gang ~= gname then return false, 'no_member' end
    local grade = tonumber(mem.grade) or 0
    if grade >= myGrade then return false, 'rank' end
    local t = ESX.GetPlayerFromIdentifier(identifier)
    if action == 'fire' then
        upsertMember(identifier, nil, 0, '')
        if t then
            t.set('gang', nil)
            t.set('gang_grade', 0)
            Online[t.source] = nil
            TriggerClientEvent('esx_gangs:setPlayerGang', t.source, nil, 0)
            pushGangState(t.source)
            TriggerClientEvent('esx:showNotification', t.source, 'You were fired from the gang')
            if sendGangPlayers then sendGangPlayers() end
        end
        return true
    end
    local dir = action == 'promote' and 1 or -1
    local ng = nextGrade(gname, grade, dir)
    if not ng then return false, 'limit' end
    if ng >= myGrade then return false, 'rank' end
    upsertMember(identifier, gname, ng, mem.name or '')
    if t then
        t.set('gang_grade', ng)
        if Online[t.source] then
            Online[t.source].grade = ng
            Online[t.source].rank = rankLabel(gname, ng)
        end
        TriggerClientEvent('esx_gangs:setPlayerGang', t.source, gname, ng)
        pushGangState(t.source)
        TriggerClientEvent('esx:showNotification', t.source, 'New rank: ' .. rankLabel(gname, ng))
    end
    return true
end

RegisterNetEvent('esx_gangs:memberAction', function(identifier, action)
    local src = source
    local ok, reason = manageMember(src, identifier, action)
    if not ok then
        local msg = ({
            no_perm = 'No permission',
            no_member = 'Member not found',
            self = 'You cannot do that to yourself',
            rank = 'Their rank is equal or higher',
            limit = 'No next rank'
        })[reason] or 'Error'
        return TriggerClientEvent('esx:showNotification', src, msg)
    end
    TriggerClientEvent('esx:showNotification', src, 'Done')
    TriggerClientEvent('esx_gangs:refreshBoss', src)
end)

RegisterNetEvent('esx_gangs:money', function(kind, amount)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not isBoss(xPlayer) then return end
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    local gname = xPlayer.get('gang')
    local g = Gangs[gname]
    if not g then return end
    if not gangActive(g) then
        return TriggerClientEvent('esx:showNotification', src, 'Gang is disabled')
    end
    if kind == 'deposit' then
        if xPlayer.getMoney() < amount then
            return TriggerClientEvent('esx:showNotification', src, 'Not enough cash')
        end
        xPlayer.removeMoney(amount)
        g.money = (g.money or 0) + amount
    elseif kind == 'withdraw' then
        if (g.money or 0) < amount then
            return TriggerClientEvent('esx:showNotification', src, 'Not enough in treasury')
        end
        g.money = g.money - amount
        xPlayer.addMoney(amount)
    else
        return
    end
    MySQL.update.await('UPDATE gangs SET money = ? WHERE name = ?', { g.money, gname })
    broadcastGangs()
    TriggerClientEvent('esx_gangs:refreshBoss', src)
end)

RegisterNetEvent('esx_gangs:saveRecipes', function(gangName, recipes)
    local src = source
    if not hasPermission(src) then return end
    if not Gangs[gangName] then return end
    if type(recipes) ~= 'table' then return end
    if #recipes > (Config.MaxCrafts or 10) then
        return TriggerClientEvent('esx:showNotification', src, 'Maximum 10 recipes')
    end
    local cleaned = {}
    for i, rec in ipairs(recipes) do
        local result = tostring(rec.result or ''):lower():gsub('%s+', '')
        if result == '' then
            return TriggerClientEvent('esx:showNotification', src, 'Recipe ' .. i .. ' has no result item')
        end
        local ings = {}
        for _, ing in ipairs(rec.ingredients or {}) do
            local item = tostring(ing.item or ''):lower():gsub('%s+', '')
            local count = math.floor(tonumber(ing.count) or 0)
            if item ~= '' and count > 0 then
                ings[#ings + 1] = { item = item, count = count }
            end
        end
        if #ings == 0 then
            return TriggerClientEvent('esx:showNotification', src, 'Recipe needs ingredients')
        end
        local lab = tostring(rec.label or '')
        if lab == '' then lab = result end
        cleaned[#cleaned + 1] = {
            id = i,
            result = result,
            resultCount = math.max(1, math.floor(tonumber(rec.resultCount) or 1)),
            label = lab,
            time = math.max(1, math.floor(tonumber(rec.time) or 5)),
            ingredients = ings
        }
    end
    Gangs[gangName].recipes = cleaned
    MySQL.update.await('UPDATE gangs SET recipes = ? WHERE name = ?', { json.encode(cleaned), gangName })
    broadcastGangs()
    TriggerClientEvent('esx:showNotification', src, 'Recipes saved')
    TriggerClientEvent('esx_gangs:openPanel', src, publicAll(), gangName)
end)

RegisterNetEvent('esx_gangs:craft', function(recipeId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local gname = xPlayer.get('gang')
    if not gname or not Gangs[gname] then return end
    if not gangActive(Gangs[gname]) then
        return TriggerClientEvent('esx:showNotification', src, 'Gang is disabled')
    end
    if not HasFeatureAccess(gname, xPlayer.get('gang_grade') or 0, 'craft') then
        return TriggerClientEvent('esx:showNotification', src, 'No craft access')
    end
    recipeId = tonumber(recipeId)
    local rec
    for _, r in ipairs(Gangs[gname].recipes or {}) do
        if tonumber(r.id) == recipeId then rec = r break end
    end
    if not rec then return end
    for _, ing in ipairs(rec.ingredients or {}) do
        local have = exports.ox_inventory:Search(src, 'count', ing.item) or 0
        if have < ing.count then
            return TriggerClientEvent('esx:showNotification', src, 'Missing: ' .. ing.item)
        end
    end
    if not exports.ox_inventory:CanCarryItem(src, rec.result, rec.resultCount or 1) then
        return TriggerClientEvent('esx:showNotification', src, 'Inventory full')
    end
    for _, ing in ipairs(rec.ingredients or {}) do
        exports.ox_inventory:RemoveItem(src, ing.item, ing.count)
    end
    exports.ox_inventory:AddItem(src, rec.result, rec.resultCount or 1)
    TriggerClientEvent('esx:showNotification', src, 'Crafted: ' .. (rec.label or rec.result))
end)

RegisterNetEvent('esx_gangs:setAccess', function(feature, grades)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not isBoss(xPlayer) then return end
    local allowed = { stash = true, wardrobe = true, parking = true, craft = true }
    if not allowed[feature] then return end
    local gname = xPlayer.get('gang')
    local g = Gangs[gname]
    if not g then return end
    local cleaned, seen = {}, {}
    for _, n in ipairs(grades or {}) do
        local gr = tonumber(n)
        if gr and not seen[gr] then
            seen[gr] = true
            cleaned[#cleaned + 1] = gr
        end
    end
    g.access = g.access or defaultAccess(g.ranks)
    g.access[feature] = cleaned
    MySQL.update.await('UPDATE gangs SET access = ? WHERE name = ?', { json.encode(g.access), gname })
    broadcastGangs()
    TriggerClientEvent('esx:showNotification', src, 'Access updated')
    TriggerClientEvent('esx_gangs:refreshBoss', src)
end)

RegisterNetEvent('esx_gangs:clearLogs', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not isBoss(xPlayer) then return end
    local gname = xPlayer.get('gang')
    if not gname then return end
    MySQL.update.await('DELETE FROM gang_stash_logs WHERE gang = ?', { gname })
    TriggerClientEvent('esx:showNotification', src, 'Stash history cleared')
    TriggerClientEvent('esx_gangs:refreshBoss', src)
end)

local function stashGang(inv)
    if type(inv) ~= 'string' then return nil end
    local prefix = Config.StashPrefix
    if inv:sub(1, #prefix) == prefix then
        return inv:sub(#prefix + 1)
    end
    return nil
end

local function logStash(src, gang, action, item, count)
    if not gang or not item or not count or count <= 0 then return end
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    MySQL.insert('INSERT INTO gang_stash_logs (gang, identifier, player, action, item, count) VALUES (?, ?, ?, ?, ?, ?)', {
        gang, xPlayer.identifier, xPlayer.getName() or GetPlayerName(src), action, item, count
    })
end

CreateThread(function()
    while GetResourceState('ox_inventory') ~= 'started' do Wait(200) end
    exports.ox_inventory:registerHook('swapItems', function(payload)
        local src = payload.source
        local fromG = stashGang(tostring(payload.fromInventory))
        local toG = stashGang(tostring(payload.toInventory))
        local item = payload.fromSlot and (payload.fromSlot.name or payload.fromSlot) or payload.itemName
        if type(item) == 'table' then item = item.name end
        local count = payload.count or 0
        if fromG and not toG then
            logStash(src, fromG, 'take', tostring(item), count)
        elseif toG and not fromG then
            logStash(src, toG, 'put', tostring(item), count)
        end
    end, {
        print = false
    })
end)

RegisterNetEvent('esx_gangs:saveOutfit', function(kind, grade, skin)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or not isBoss(xPlayer) then return end
    if type(skin) ~= 'table' then
        return TriggerClientEvent('esx:showNotification', src, 'Could not read outfit')
    end
    local gname = xPlayer.get('gang')
    if not gname or not Gangs[gname] then return end
    kind = tostring(kind or '')
    if kind ~= 'rank' and kind ~= 'rob' then return end
    if kind == 'rob' then
        grade = -1
    else
        grade = tonumber(grade)
        local ok = false
        for _, r in ipairs(Gangs[gname].ranks) do
            if r.grade == grade then ok = true break end
        end
        if not ok then
            return TriggerClientEvent('esx:showNotification', src, 'Rank not found')
        end
    end
    MySQL.update.await('DELETE FROM gang_outfits WHERE gang = ? AND kind = ? AND grade = ?', { gname, kind, grade })
    MySQL.insert.await('INSERT INTO gang_outfits (gang, kind, grade, skin) VALUES (?, ?, ?, ?)', {
        gname, kind, grade, json.encode(skin)
    })
    Gangs[gname].outfits = Gangs[gname].outfits or { rob = false, savedGrades = {} }
    if kind == 'rob' then
        Gangs[gname].outfits.rob = true
    else
        local list = Gangs[gname].outfits.savedGrades or {}
        local found = false
        for _, n in ipairs(list) do
            if n == grade then found = true break end
        end
        if not found then list[#list + 1] = grade end
        Gangs[gname].outfits.savedGrades = list
    end
    broadcastGangs()
    local msg = kind == 'rob' and 'Rob outfit saved' or ('Outfit saved for rank ' .. tostring(grade))
    TriggerClientEvent('esx:showNotification', src, msg)
    TriggerClientEvent('esx_gangs:refreshBoss', src)
end)

lib.callback.register('esx_gangs:getOutfit', function(source, kind)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then return nil end
    local gname = xPlayer.get('gang')
    if not gname or not Gangs[gname] then return nil end
    if kind == 'citizen' then
        local row = MySQL.single.await('SELECT skin FROM gang_player_skins WHERE identifier = ?', { xPlayer.identifier })
        if not row then return nil end
        local ok, skin = pcall(json.decode, row.skin)
        return ok and skin or nil
    end
    local grade = xPlayer.get('gang_grade') or 0
    local row
    if kind == 'rob' then
        row = MySQL.single.await('SELECT skin FROM gang_outfits WHERE gang = ? AND kind = ?', { gname, 'rob' })
    else
        row = MySQL.single.await('SELECT skin FROM gang_outfits WHERE gang = ? AND kind = ? AND grade = ?', { gname, 'rank', grade })
    end
    if not row then return nil end
    local ok, skin = pcall(json.decode, row.skin)
    return ok and skin or nil
end)

RegisterNetEvent('esx_gangs:saveCitizen', function(skin)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer or type(skin) ~= 'table' then return end
    MySQL.query.await('REPLACE INTO gang_player_skins (identifier, skin) VALUES (?, ?)', {
        xPlayer.identifier, json.encode(skin)
    })
end)

function SetPlayerGang(src, targetId, gangName, grade)
    if not hasPermission(src) then return false, 'no_perm' end
    local xTarget = ESX.GetPlayerFromId(targetId)
    if not xTarget then return false, 'no_player' end
    grade = tonumber(grade) or 0
    if gangName == 'none' or gangName == 'null' or gangName == '' then
        upsertMember(xTarget.identifier, nil, 0, '')
        xTarget.set('gang', nil)
        xTarget.set('gang_grade', 0)
        Online[targetId] = nil
        TriggerClientEvent('esx_gangs:setPlayerGang', targetId, nil, 0)
        pushGangState(targetId)
        -- broadcast removal to old gang immediately
        if sendGangPlayers then sendGangPlayers() end
        return true, 'removed'
    end
    if not Gangs[gangName] then return false, 'no_gang' end
    local valid = false
    for _, r in ipairs(Gangs[gangName].ranks) do
        if r.grade == grade then valid = true break end
    end
    if not valid then return false, 'no_rank' end
    upsertMember(xTarget.identifier, gangName, grade, playerName(xTarget))
    xTarget.set('gang', gangName)
    xTarget.set('gang_grade', grade)
    local ped = GetPlayerPed(targetId)
    local coords = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0.0, 0.0, 0.0)
    Online[targetId] = {
        gang = gangName,
        grade = grade,
        rank = rankLabel(gangName, grade),
        name = playerName(xTarget),
        x = coords.x, y = coords.y, z = coords.z
    }
    TriggerClientEvent('esx_gangs:setPlayerGang', targetId, gangName, grade)
    pushGangState(targetId)
    if sendGangPlayers then sendGangPlayers() end -- عضو جدید -> بلافاصله بلیپش برای بقیه بیاد
    return true, 'ok'
end

function GetGangs()
    return publicAll()
end

function HasAdmin(src)
    return hasPermission(src)
end

-- برای HUD ها و ریسورس‌های دیگه: دیتای گنگ پلیر (ساختار جاب) — سمت سرور
function GetPlayerGang(src)
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return nil end
    return gangStateObject(xPlayer.get('gang'), xPlayer.get('gang_grade'))
end

exports('GetGangs', GetGangs)
exports('HasAdmin', HasAdmin)
exports('GetPlayerGang', GetPlayerGang)

-- =========================================================
-- GANG LIVE BLIPS SYSTEM
-- =========================================================
-- Online = { [src] = { gang, grade, rank, name, x,y,z } }
-- Logic:
--   player joins -> imOnline -> server validates ESX gang
--   server every 1 sec updates coords and sends only same-gang list
--   client creates black blip per teammate, name = "Name | Rank"
--   remove on leave / drop / gang change
-- =========================================================

local function updateOnlineCoords()
    for src, d in pairs(Online) do
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 then
            local c = GetEntityCoords(ped)
            d.x = c.x
            d.y = c.y
            d.z = c.z
        end
    end
end

-- state آخرین چیزی که به هر کلاینت فرستادیم (برای پاکسازی یک‌باره بعد از خروج از گنگ)
local lastSentGang = {}

sendGangPlayers = function()
    -- تایید مجدد هر عضو با xPlayer سرور؛ عضو بدون گنگ = حذف از لیست بلیپ
    for src, d in pairs(Online) do
        local xp = ESX.GetPlayerFromId(src)
        local g = xp and xp.get('gang') or nil
        if not g or g == '' or not Gangs[g] then
            Online[src] = nil
        elseif g ~= d.gang then
            d.gang = g
            d.grade = tonumber(xp.get('gang_grade')) or 0
            d.rank = rankLabel(g, d.grade)
            d.name = playerName(xp)
        end
    end

    updateOnlineCoords()

    -- group players by gang (گنگ غیرفعال = بلیپی هم نداره)
    local byGang = {}
    for src, d in pairs(Online) do
        if d.gang and d.gang ~= '' and Gangs[d.gang] and gangActive(Gangs[d.gang]) then
            byGang[d.gang] = byGang[d.gang] or {}
            byGang[d.gang][#byGang[d.gang] + 1] = {
                id = src,
                gang = d.gang,
                name = d.name or GetPlayerName(src) or ('ID ' .. src),
                grade = d.grade or 0,
                gradeName = d.rank or rankLabel(d.gang, d.grade or 0),
                rank = d.rank or rankLabel(d.gang, d.grade or 0),
                x = d.x or 0.0,
                y = d.y or 0.0,
                z = d.z or 0.0
            }
        end
    end

    -- send only same-gang list to each online player
    for src, d in pairs(Online) do
        if d.gang and byGang[d.gang] then
            TriggerClientEvent('esx_gangs:updatePlayers', src, byGang[d.gang])
            lastSentGang[src] = d.gang
        else
            TriggerClientEvent('esx_gangs:updatePlayers', src, {})
            lastSentGang[src] = false
        end
    end

    -- players not registered in Online yet:
    --   has gang -> send list once | just lost gang -> send ONE empty cleanup packet
    local xPlayers = ESX.GetExtendedPlayers and ESX.GetExtendedPlayers() or {}
    if xPlayers then
        for _, xp in pairs(xPlayers) do
            local xPlayer = type(xp) == 'table' and xp or ESX.GetPlayerFromId(xp)
            if xPlayer then
                local sid = xPlayer.source
                if not Online[sid] then
                    local g = xPlayer.get('gang')
                    if g and byGang[g] then
                        TriggerClientEvent('esx_gangs:updatePlayers', sid, byGang[g])
                        lastSentGang[sid] = g
                    elseif lastSentGang[sid] ~= false then
                        TriggerClientEvent('esx_gangs:updatePlayers', sid, {})
                        lastSentGang[sid] = false
                    end
                end
            end
        end
    end
end

RegisterNetEvent('esx_gangs:imOnline', function(_gang, _grade, _rank)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then
        -- امنیتی: دیتای گنگِ ارسالی از کلاینت معتبر نیست - تا ESX آماده نشه ثبت نمیشی
        Online[src] = nil
        return
    end

    local realGang = xPlayer.get('gang')
    if not realGang or realGang == '' or not Gangs[realGang] then
        Online[src] = nil
        return
    end
    local realGrade = tonumber(xPlayer.get('gang_grade')) or tonumber(_grade) or 0
    local realRank = rankLabel(realGang, realGrade)
    local ped = GetPlayerPed(src)
    local c = (ped and ped ~= 0) and GetEntityCoords(ped) or vector3(0.0, 0.0, 0.0)
    local was = Online[src]
    Online[src] = {
        gang = realGang,
        grade = realGrade,
        rank = realRank,
        name = playerName(xPlayer),
        x = c.x, y = c.y, z = c.z
    }
    -- عضو تازه آنلاین شده یا گنگ عوض کرده -> بلافاصله لیست به همه اعضا برو
    if not was or was.gang ~= realGang then
        sendGangPlayers()
    end
end)

RegisterNetEvent('esx_gangs:requestPlayers', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local g = xPlayer.get('gang')
    if not g then return end
    updateOnlineCoords()
    local list = {}
    for s, d in pairs(Online) do
        if d.gang == g then
            list[#list + 1] = {
                id = s,
                gang = d.gang,
                name = d.name,
                grade = d.grade,
                gradeName = d.rank or rankLabel(d.gang, d.grade),
                rank = d.rank or rankLabel(d.gang, d.grade),
                x = d.x or 0.0, y = d.y or 0.0, z = d.z or 0.0
            }
        end
    end
    TriggerClientEvent('esx_gangs:updatePlayers', src, list)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local old = Online[src]
    Online[src] = nil
    lastSentGang[src] = nil
    if old and old.gang then
        -- notify remaining gang members immediately
        sendGangPlayers()
    end
end)

-- also clean when esx:playerDropped or gang removed
AddEventHandler('esx:playerDropped', function(playerId)
    Online[playerId] = nil
    lastSentGang[playerId] = nil
end)

lib.callback.register('esx_gangs:gangBlips', function(source)
    local xPlayer = ESX.GetPlayerFromId(source)
    local meGang = xPlayer and xPlayer.get('gang') or (Online[source] and Online[source].gang)
    if not meGang then return {} end
    if not Gangs[meGang] or not gangActive(Gangs[meGang]) then return {} end
    updateOnlineCoords()
    local list = {}
    for src, d in pairs(Online) do
        if d.gang == meGang and src ~= source then
            list[#list + 1] = {
                id = src,
                name = d.name,
                grade = d.grade,
                gradeName = d.rank or rankLabel(d.gang, d.grade),
                rank = d.rank or rankLabel(d.gang, d.grade),
                x = d.x or 0.0, y = d.y or 0.0, z = d.z or 0.0
            }
        end
    end
    return list
end)

CreateThread(function()
    while true do
        Wait(Config.GangBlipInterval or 1000)
        -- همیشه اجرا میشه تا پاکسازی بلیپ اعضای حذف‌شده هم تضمین بشه
        sendGangPlayers()
    end
end)
