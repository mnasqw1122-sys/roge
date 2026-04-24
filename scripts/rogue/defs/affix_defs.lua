--[[
    文件说明：affix_defs.lua
    功能：词缀系统定义数据，从config.lua拆分而来。
    V3扩展：增加更多Boss词缀、环境词缀和全局词缀。
]]
local M = {}

M.ELITE_AFFIX_DEFS = {
    { id = "berserk", name = "狂暴", hp_mult = 1.15, dmg_mult = 1.35, speed_mult = 1.05, lifesteal = 0, weight = 2 },
    { id = "guardian", name = "壁垒", hp_mult = 1.45, dmg_mult = 1.1, speed_mult = 0.9, lifesteal = 0, weight = 2 },
    { id = "swift", name = "疾风", hp_mult = 1.0, dmg_mult = 1.15, speed_mult = 1.3, lifesteal = 0, weight = 2 },
    { id = "vampire", name = "嗜血", hp_mult = 1.2, dmg_mult = 1.2, speed_mult = 1.0, lifesteal = 0.1, weight = 2 },
    { id = "frozen", name = "冰霜", hp_mult = 1.2, dmg_mult = 1.0, speed_mult = 0.9, lifesteal = 0, weight = 2 },
    { id = "thorns", name = "荆棘", hp_mult = 1.3, dmg_mult = 1.0, speed_mult = 1.0, lifesteal = 0, weight = 2 },
    { id = "giant", name = "巨化", hp_mult = 2.0, dmg_mult = 1.2, speed_mult = 0.8, lifesteal = 0, weight = 1, size_mult = 1.8, range_mult = 1.5 },
    { id = "split", name = "分裂", hp_mult = 1.2, dmg_mult = 1.0, speed_mult = 1.0, lifesteal = 0, weight = 2 },
    { id = "shield", name = "护盾", hp_mult = 1.35, dmg_mult = 1.0, speed_mult = 0.95, lifesteal = 0, weight = 2 },
    { id = "hunter", name = "追猎", hp_mult = 1.0, dmg_mult = 1.2, speed_mult = 1.15, lifesteal = 0, weight = 2 },
    { id = "sacrifice", name = "献祭", hp_mult = 1.25, dmg_mult = 1.1, speed_mult = 1.0, lifesteal = 0, weight = 1 },
    { id = "resonance", name = "共振", hp_mult = 1.2, dmg_mult = 1.1, speed_mult = 1.0, lifesteal = 0, weight = 2 },
    { id = "corrupt", name = "腐化", hp_mult = 1.15, dmg_mult = 1.12, speed_mult = 1.0, lifesteal = 0, weight = 2 },
    { id = "drain", name = "汲能", hp_mult = 1.1, dmg_mult = 1.08, speed_mult = 1.05, lifesteal = 0, weight = 2 },
    { id = "execute", name = "处决", hp_mult = 1.05, dmg_mult = 1.2, speed_mult = 1.05, lifesteal = 0, weight = 2 },
    { id = "phantom", name = "幻影", hp_mult = 0.85, dmg_mult = 1.15, speed_mult = 1.2, lifesteal = 0, weight = 1 },
    { id = "enrage", name = "激怒", hp_mult = 1.0, dmg_mult = 1.0, speed_mult = 1.0, lifesteal = 0, weight = 1 },
    { id = "toxic", name = "剧毒", hp_mult = 1.1, dmg_mult = 1.0, speed_mult = 0.95, lifesteal = 0, weight = 1 },
    { id = "mirror", name = "镜面", hp_mult = 1.0, dmg_mult = 1.0, speed_mult = 1.0, lifesteal = 0, weight = 1 },
    { id = "soul_link", name = "魂链", hp_mult = 1.1, dmg_mult = 1.05, speed_mult = 1.0, lifesteal = 0, weight = 1 },
    { id = "inferno", name = "炼狱", hp_mult = 1.15, dmg_mult = 1.25, speed_mult = 1.0, lifesteal = 0, weight = 1 },
    { id = "gravity", name = "引力", hp_mult = 1.3, dmg_mult = 1.1, speed_mult = 0.85, lifesteal = 0, weight = 1 },
    { id = "temporal", name = "时空", hp_mult = 1.0, dmg_mult = 1.15, speed_mult = 1.1, lifesteal = 0, weight = 1 },
    { id = "plague", name = "瘟疫", hp_mult = 1.1, dmg_mult = 1.05, speed_mult = 0.95, lifesteal = 0, weight = 1 },
    { id = "fortify", name = "固守", hp_mult = 1.6, dmg_mult = 0.9, speed_mult = 0.8, lifesteal = 0, weight = 1 },
    { id = "assassin", name = "暗杀", hp_mult = 0.8, dmg_mult = 1.4, speed_mult = 1.25, lifesteal = 0, weight = 1 },
}

M.AFFIX_CONFLICTS = {
    berserk = { guardian = true, thorns = true },
    guardian = { berserk = true, swift = true },
    swift = { guardian = true, giant = true },
    vampire = { thorns = true },
    giant = { swift = true },
    split = { giant = true },
    shield = { berserk = true, execute = true },
    hunter = { guardian = true },
    sacrifice = { vampire = true, drain = true },
    resonance = { split = true },
    corrupt = { frozen = true },
    drain = { sacrifice = true },
    execute = { shield = true, giant = true },
    phantom = { giant = true, mirror = true },
    enrage = { berserk = true, guardian = true },
    toxic = { frozen = true, corrupt = true },
    mirror = { phantom = true, thorns = true },
    soul_link = { split = true, sacrifice = true },
    inferno = { frozen = true },
    gravity = { swift = true },
    temporal = { phantom = true },
    plague = { toxic = true, vampire = true },
    fortify = { berserk = true, swift = true, assassin = true },
    assassin = { guardian = true, fortify = true, giant = true },
}

M.BOSS_TEMPLATE_DEFS = {
    { id = "summoner", name = "统御军势型", min_day = 21, weight = 3 },
    { id = "zone", name = "雷暴猎场型", min_day = 25, weight = 2 },
    { id = "charger", name = "点名猎杀型", min_day = 30, weight = 2 },
    { id = "phase_shift", name = "双相裂变型", min_day = 35, weight = 2 },
    { id = "berserk_aura", name = "压迫领域型", min_day = 41, weight = 1 },
    { id = "elemental_storm", name = "元素风暴型", min_day = 28, weight = 2 },
    { id = "time_warp", name = "时空扭曲型", min_day = 38, weight = 1 },
    { id = "death_mark", name = "死亡印记型", min_day = 32, weight = 2 },
}

M.BOSS_TEMPLATE_ROTATION_MODS = {
    [1] = { summoner = 1.25, zone = 1.0, charger = 1.1, phase_shift = 0.95, berserk_aura = 1.1, elemental_storm = 1.0, time_warp = 0.9, death_mark = 1.0 },
    [2] = { summoner = 0.95, zone = 1.25, charger = 1.0, phase_shift = 1.05, berserk_aura = 0.9, elemental_storm = 1.1, time_warp = 1.0, death_mark = 0.95 },
    [3] = { summoner = 1.0, zone = 0.9, charger = 1.2, phase_shift = 1.15, berserk_aura = 1.35, elemental_storm = 0.95, time_warp = 1.1, death_mark = 1.2 },
    [4] = { summoner = 1.05, zone = 1.1, charger = 1.05, phase_shift = 1.0, berserk_aura = 1.0, elemental_storm = 1.15, time_warp = 1.2, death_mark = 1.1 },
}

M.BOSS_LOOT_SIGNATURE_DEFS = {
    default = { tags = { "balanced" }, bonus_affix = { regen = true } },
    deerclops = { tags = { "burst", "frozen" }, bonus_affix = { frost = true } },
    bearger = { tags = { "tank", "sustain" }, bonus_affix = { shield = true, winter_insulation = true } },
    moose = { tags = { "tempo", "storm" }, bonus_affix = { lightning = true } },
    dragonfly = { tags = { "fire", "burst" }, bonus_affix = { ignite = true, summer_cooling = true } },
    klaus = { tags = { "ritual", "balanced" }, bonus_affix = { meteor = true } },
    daywalker = { tags = { "nightmare", "sustain" }, bonus_affix = { lifesteal = true, thorns = true } },
    antlion = { tags = { "earthquake", "zone" }, bonus_affix = { quake = true } },
    crabking = { tags = { "water", "defense" }, bonus_affix = { shield = true, frost = true } },
    malbatross = { tags = { "wind", "storm" }, bonus_affix = { lightning = true, wind = true } },
    celestial_champion = { tags = { "divine", "phase" }, bonus_affix = { divine = true } },
}

M.ENVIRONMENT_AFFIX_DEFS = {
    { id = "fog", name = "浓雾", desc = "视野范围减少40%", weight = 3, min_day = 10, duration = 120 },
    { id = "rain_acid", name = "酸雨", desc = "每10秒对全体玩家造成3点伤害", weight = 2, min_day = 15, duration = 90 },
    { id = "wind_gale", name = "狂风", desc = "移动速度降低20%，攻击间隔增加10%", weight = 2, min_day = 12, duration = 100 },
    { id = "darkness", name = "黑暗潮汐", desc = "理智值每秒下降0.3", weight = 2, min_day = 20, duration = 80 },
    { id = "heat_wave", name = "热浪", desc = "体温持续上升，每5秒+2度", weight = 2, min_day = 18, duration = 90 },
    { id = "frost_bite", name = "寒潮", desc = "体温持续下降，每5秒-2度", weight = 2, min_day = 18, duration = 90 },
    { id = "earthquake", name = "地震", desc = "每15秒随机掉落岩石，造成范围伤害", weight = 1, min_day = 25, duration = 60 },
    { id = "blood_moon", name = "血月", desc = "所有敌人伤害+15%，生命+10%", weight = 1, min_day = 30, duration = 120 },
    { id = "static_field", name = "静电场", desc = "每20秒在随机位置释放闪电", weight = 2, min_day = 22, duration = 90 },
    { id = "spore_cloud", name = "孢子云", desc = "区域内食物腐烂速度x3", weight = 2, min_day = 14, duration = 100 },
}

M.GLOBAL_AFFIX_DEFS = {
    { id = "elite_surge", name = "精英潮涌", desc = "精英出现概率+15%", weight = 3, min_day = 15 },
    { id = "boss_empower", name = "Boss强化", desc = "Boss生命+20%，伤害+10%", weight = 2, min_day = 25 },
    { id = "loot_famine", name = "掉落饥荒", desc = "物品掉落率-15%", weight = 2, min_day = 10 },
    { id = "heal_suppress", name = "治疗压制", desc = "治疗效果-25%", weight = 2, min_day = 20 },
    { id = "speed_demon", name = "极速恶魔", desc = "所有敌人移动速度+20%", weight = 2, min_day = 18 },
    { id = "iron_skin", name = "铁皮", desc = "所有敌人受到伤害-10%", weight = 2, min_day = 15 },
    { id = "berserk_world", name = "狂暴世界", desc = "所有敌人伤害+10%，但生命-5%", weight = 1, min_day = 30 },
    { id = "double_affix", name = "双词缀", desc = "精英有更高概率获得双词缀", weight = 1, min_day = 25 },
    { id = "night_terror", name = "暗夜恐惧", desc = "夜晚时敌人额外+15%伤害", weight = 2, min_day = 20 },
    { id = "resource_scarce", name = "资源匮乏", desc = "可采集资源刷新速度-30%", weight = 2, min_day = 12 },
}

return M
