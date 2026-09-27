Config = {}

Config.Locale = 'en'

Config.AllowedGroups = {
    headadmin = true,
    developer = true,
    management = true,
    gamemaster = true
}

Config.MaxRanks = 10
Config.DefaultSlots = 50
Config.DefaultWeight = 200000

Config.Marker = {
    type = 1,
    size = vec3(1.5, 1.5, 0.6),
    color = { r = 20, g = 160, b = 150, a = 120 },
    drawDistance = 25.0
}

Config.Blip = {
    enabled = true,
    sprite = 437,
    color = 1,
    scale = 0.8
}

Config.Commands = {
    create = 'creategang',
    setgang = 'setgang',
    addcar = 'addcargang'
}

Config.StashPrefix = 'gangstash_'
Config.RecallCost = 500
Config.ImpoundCost = 500
Config.ImpoundIdle = 4 * 60 * 60
Config.ImpoundDelay = 10
-- شرط ۳: ریستارت سرور -> ماشین‌هایی که بیرون بودن (stored=0) برن ایمپاند گنگ
-- ماشین‌های داخل پارکینگ گنگ (stored=1) هیچوقت ایمپاند نمیشن
Config.ImpoundOnRestart = true
Config.Impound = {
    coords = vec4(2879.72, 4490.65, 48.16, 161.62),
    model = 's_m_y_xmech_02'
}

Config.MemberBlip = {
    sprite = 1,      -- 1 = circle, 280 = user, 1 is cleanest for live
    color = 40,      -- 40 = black (gang blip)
    scale = 0.85,
    display = 4,     -- 4 = both map + minimap
    shortRange = false,
    category = 7,    -- 7 = "Other Players" legend (nil = skip)
    showSelf = true  -- بلیپ خودت هم روی مپ دیده بشه (false = فقط هم‌گنگی‌ها)
}
Config.GangBlipInterval = 1000 -- ms - GPS update هر یک ثانیه
Config.MaxCraftIngredients = 6
Config.MaxCrafts = 10

-- ================== سیستم تمدید / انقضای گنگ ==================
Config.DefaultRenewDays = 30      -- روز تمدید پیش‌فرض هنگام ساخت گنگ (۰ = بدون انقضا)
Config.MaxRenewDays = 365         -- حداکثر روز قابل تنظیم برای هر گنگ
Config.ExpiryCheckInterval = 60000 -- ms - هر چند وقت چک بشه گنگ‌های منقضی خودکار غیرفعال بشن
