--[[
    文件说明：config.lua
    功能：肉鸽模式的核心数据和配置表。
    包含了天赋、补给、遗物、日常任务、赛季目标、天灾事件等各类静态定义数据。
]]
local M = {}

function M.LoadConfig(get_mod_config)
    local Get = type(get_mod_config) == "function" and get_mod_config or function()
        return nil
    end
    local cfg = {
        WORLD_VARIANT = Get("WORLD_VARIANT") or "standard",
        START_DAY = Get("STARTING_DAY") or 2,
        BOSS_INTERVAL = Get("BOSS_INTERVAL") or 6,
        NORMAL_DROP_CHANCE = Get("NORMAL_DROP_CHANCE") or 0.45,
        ELITE_CHANCE = Get("ELITE_CHANCE") or 0.2,
        WAVE_START_DELAY = Get("WAVE_START_DELAY") or 5,
        WAVE_END_DELAY = Get("WAVE_END_DELAY") or 5,
        MAX_HOSTILES_NEAR_PLAYER = Get("MAX_HOSTILES_NEAR_PLAYER") or 24,
        ELITE_AFFIX_CHANCE = Get("ELITE_AFFIX_CHANCE") or 0.65,
        BOSS_PHASE_MODE = Get("BOSS_PHASE_MODE") or 1,
        BOSS_PHASE_MINION_COUNT = Get("BOSS_PHASE_MINION_COUNT") or 2,
        DEBUG_MODE = Get("DEBUG_MODE") or false,
        AFFIX_ANNOUNCE_MODE = Get("AFFIX_ANNOUNCE_MODE") or 1,
        SECOND_AFFIX_CHANCE = Get("SECOND_AFFIX_CHANCE") or 0.15,
        BOSS_PHASE_FX_MODE = Get("BOSS_PHASE_FX_MODE") or 1,
        GROUND_LOOT_CLEAN_ENABLED = Get("GROUND_LOOT_CLEAN_ENABLED") ~= false,
        GROUND_LOOT_CLEAN_INTERVAL_DAYS = Get("GROUND_LOOT_CLEAN_INTERVAL_DAYS") or 2,
        GROUND_LOOT_CLEAN_DELAY_NIGHT = Get("GROUND_LOOT_CLEAN_DELAY_NIGHT") or 25,
        GROUND_LOOT_CLEAN_BATCH_SIZE = Get("GROUND_LOOT_CLEAN_BATCH_SIZE") or 60,
        GROUND_LOOT_CLEAN_SEARCH_RADIUS = Get("GROUND_LOOT_CLEAN_SEARCH_RADIUS") or 70,
        SEASON_PROFILE = Get("SEASON_PROFILE") or "standard",
        SEASON_DAY_LIMIT = Get("SEASON_DAY_LIMIT") or 80,
        SEASON_RESET_DELAY = Get("SEASON_RESET_DELAY") or 18,
        SEASON_GRACE_DAYS = Get("SEASON_GRACE_DAYS") or 0,
    }
    local profile = cfg.SEASON_PROFILE
    if profile ~= "custom" then
        local presets = {
            short = { season_day_limit = 60, boss_interval = 4, season_reset_delay = 12, season_grace_days = 0 },
            standard = { season_day_limit = 80, boss_interval = 6, season_reset_delay = 18, season_grace_days = 0 },
            long = { season_day_limit = 100, boss_interval = 8, season_reset_delay = 22, season_grace_days = 0 },
        }
        local p = presets[profile] or presets.standard
        cfg.SEASON_DAY_LIMIT = p.season_day_limit
        cfg.BOSS_INTERVAL = p.boss_interval
        cfg.SEASON_RESET_DELAY = p.season_reset_delay
        cfg.SEASON_GRACE_DAYS = p.season_grace_days
    end
    return cfg
end

M.CONST = {
    BUFF_KILL_INTERVAL = 100,
    DAMAGE_MODIFIER_KEY = "rogue_mode_damage_buff",
    COMBO_DAMAGE_MODIFIER_KEY = "rogue_mode_combo_buff",
    HOSTILE_SCAN_RADIUS = 20,
    MAX_ELITE_CHANCE = 0.45,
    MAX_NORMAL_DROP_CHANCE = 0.85,
    MAX_ELITE_AFFIX_CHANCE = 0.95,
    MAX_SECOND_AFFIX_CHANCE = 0.45,
    COMBO_BASE_WINDOW = 6,
    COMBO_STEP_KILLS = 5,
    COMBO_STEP_MULT = 0.05,
    COMBO_MAX_MULT = 1.6,
    TALENT_TRIGGER_KILLS = 120,
    TALENT_AUTO_PICK_DELAY = 20,
    SUPPLY_AUTO_PICK_DELAY = 15,
    V2_MAX_DROP_BONUS = 0.22,
    V2_MAX_DAMAGE_BONUS_FROM_SUPPLY = 1.0,
    WAVE_RULE_BASE_CHANCE = 0.35,
    WAVE_RULE_MAX_CHANCE = 0.6,
    SUPPLY_GROUND_PROTECT_TIME = 90,
    CATASTROPHE_BASE_CHANCE = 0.18,
    CATASTROPHE_MAX_CHANCE = 0.38,
    CHALLENGE_BASE_CHANCE = 0.38,
    TRIAL_BOSS_HP_MULT = 0.78,
    TRIAL_BOSS_HP_STEP_DAYS = 20,
    TRIAL_BOSS_HP_STEP_MULT = 0.12,
    TRIAL_BOSS_DMG_MULT = 0.92,
    TRIAL_BOSS_AFFIX_CHANCE = 0.58,
}

M.BUFF_TYPES = {
    HEALTH = { min = 10, max = 20, boss_mult = 3 },
    DAMAGE = { min = 0.05, max = 0.1, boss_mult = 3 },
}

M.TALENT_DEFS = {
    { id = 1, name = "铁壁体魄", desc = "立即获得+25生命上限" },
    { id = 2, name = "破军技巧", desc = "永久获得+8%伤害" },
    { id = 3, name = "连战专精", desc = "连杀持续时间+1.5秒" },
    { id = 4, name = "猎手本能", desc = "普通掉落率额外+4%" },
    { id = 5, name = "赏金契约", desc = "每日奖励额外+50%" },
}

M.DAILY_KIND_NAMES = {
    [1] = "击杀怪物",
    [2] = "击杀精英",
    [3] = "击杀Boss",
    [4] = "完成波次",
    [5] = "完成挑战",
    [6] = "完成悬赏",
}

M.DAILY_TASK_KIND_WEIGHTS = {
    [1] = 28,
    [2] = 22,
    [3] = 14,
    [4] = 16,
    [5] = 10,
    [6] = 10,
}

M.DAILY_TASK_ROTATION_MODS = {
    [1] = {
        weight_mult = { [1] = 1.2, [2] = 1.15, [3] = 1.1, [4] = 0.85, [5] = 0.95, [6] = 0.95 },
        target_mult = { [1] = 1.05, [2] = 1.05, [3] = 1.0, [4] = 0.9, [5] = 1.0, [6] = 1.0 },
    },
    [2] = {
        weight_mult = { [1] = 0.95, [2] = 1.0, [3] = 1.0, [4] = 1.3, [5] = 1.0, [6] = 1.0 },
        target_mult = { [1] = 0.95, [2] = 1.0, [3] = 1.0, [4] = 1.15, [5] = 1.0, [6] = 1.0 },
    },
    [3] = {
        weight_mult = { [1] = 1.05, [2] = 1.0, [3] = 1.0, [4] = 0.95, [5] = 1.2, [6] = 1.2 },
        target_mult = { [1] = 1.0, [2] = 1.0, [3] = 1.0, [4] = 0.95, [5] = 1.1, [6] = 1.1 },
    },
    [4] = {
        weight_mult = { [1] = 1.0, [2] = 1.0, [3] = 1.05, [4] = 1.0, [5] = 1.05, [6] = 1.05 },
        target_mult = { [1] = 1.0, [2] = 1.0, [3] = 1.05, [4] = 1.0, [5] = 1.05, [6] = 1.05 },
    },
}

M.DAILY_REWARD_RULES = {
    [1] = { mat_base = 1, gear_rolls = 0, gear_chance = 0 },
    [2] = { mat_base = 1, gear_rolls = 1, gear_chance = 0.25 },
    [3] = { mat_base = 2, gear_rolls = 1, gear_chance = 0.45 },
    [4] = { mat_base = 1, gear_rolls = 1, gear_chance = 0.18 },
    [5] = { mat_base = 1, gear_rolls = 2, gear_chance = 0.45 },
    [6] = { mat_base = 2, gear_rolls = 2, gear_chance = 0.4 },
}

M.WAVE_RULE_DEFS = {
    { id = 1, name = "嗜血之潮", desc = "敌人伤害提升，掉落小幅提升", dmg_mult = 1.10, hp_mult = 1.0, elite_bonus = 0, drop_bonus = 0.04, spawn_period_mult = 1.0, weight = 2 },
    { id = 2, name = "钢铁兽群", desc = "敌人血量提升，精英略增", dmg_mult = 1.0, hp_mult = 1.12, elite_bonus = 0.04, drop_bonus = 0.02, spawn_period_mult = 1.0, weight = 2 },
    { id = 3, name = "疾风突袭", desc = "刷怪更快，精英略增", dmg_mult = 1.0, hp_mult = 1.0, elite_bonus = 0.02, drop_bonus = 0.03, spawn_period_mult = 0.92, weight = 2 },
    { id = 4, name = "赏金狂欢", desc = "敌人略强，战利品显著提升", dmg_mult = 1.04, hp_mult = 1.04, elite_bonus = 0.02, drop_bonus = 0.07, spawn_period_mult = 1.0, weight = 1 },
}

M.REGION_ROUTE_DEFS = {
    { id = 1, name = "激战群岛", desc = "敌压更强，掉落更好", weight = 1, enemy_hp_mult = 1.10, enemy_dmg_mult = 1.08, elite_bonus = 0.04, drop_bonus = 0.05, gear_roll_bonus = 1 },
    { id = 2, name = "精英试炼", desc = "精英更密集，材料提升", weight = 1, enemy_hp_mult = 1.06, enemy_dmg_mult = 1.04, elite_bonus = 0.08, drop_bonus = 0.03, mat_bonus = 1 },
    { id = 3, name = "宁静绿洲", desc = "敌压减轻，收益偏稳", weight = 1, enemy_hp_mult = 0.94, enemy_dmg_mult = 0.92, elite_bonus = -0.03, drop_bonus = -0.01, heal_pct = 0.10, sanity_bonus = 10 },
    { id = 4, name = "贪婪遗迹", desc = "掉落更高，但生命受压", weight = 1, enemy_hp_mult = 1.05, enemy_dmg_mult = 1.06, elite_bonus = 0.02, drop_bonus = 0.08, hp_cost_pct = 0.08 },
}

M.REGION_ROUTE_NAMES = {}
for _, def in ipairs(M.REGION_ROUTE_DEFS) do
    M.REGION_ROUTE_NAMES[def.id] = def.name
end

M.PLAYER_BADGE_BITS = {
    ["清剿先锋"] = 1,
    ["王者终结"] = 2,
    ["试炼征服"] = 4,
    ["无伤统帅"] = 8,
}

M.PLAYER_BADGE_NAMES = {
    [1] = "清剿先锋",
    [2] = "王者终结",
    [4] = "试炼征服",
    [8] = "无伤统帅",
}

M.TEAM_BADGE_BITS = {
    ["铁壁远征"] = 1,
    ["稳健推进"] = 2,
    ["试炼征服团"] = 4,
    ["王庭破军"] = 8,
    ["极致构筑"] = 16,
    ["成型构筑"] = 32,
    ["风暴清图"] = 64,
}

M.TEAM_BADGE_NAMES = {
    [1] = "铁壁远征",
    [2] = "稳健推进",
    [4] = "试炼征服团",
    [8] = "王庭破军",
    [16] = "极致构筑",
    [32] = "成型构筑",
    [64] = "风暴清图",
}

M.SUPPLY_DEFS = {
    { id = 1, name = "急救物资", desc = "恢复30%生命与15点理智；代价：饥饿-20" },
    { id = 2, name = "战备补给", desc = "立即获得1-2件随机战利品；代价：理智-18" },
    { id = 3, name = "贪婪赌注", desc = "小幅永久增伤与掉落（有上限）；代价：生命-8%" },
    { id = 4, name = "战术重整", desc = "连杀时窗+0.8秒与理智+8；代价：饥饿-10、生命-4%" },
}

M.RELIC_DEFS = {
    { id = 1, name = "狂战纹章", desc = "永久伤害+5%", rarity = "rare", rarity_name = "稀有", weight = 18, group = "atk", max_stack = 1 },
    { id = 2, name = "生命护符", desc = "立即生命上限+20", rarity = "rare", rarity_name = "稀有", weight = 18, group = "hp", max_stack = 1 },
    { id = 3, name = "拾荒齿轮", desc = "普通掉落率+3%", rarity = "common", rarity_name = "普通", weight = 24, group = "drop", max_stack = 1 },
    { id = 4, name = "连击刻印", desc = "连杀时窗+0.5秒", rarity = "common", rarity_name = "普通", weight = 24, group = "combo", max_stack = 1 },
    { id = 5, name = "赏金火漆", desc = "每日奖励+25%", rarity = "epic", rarity_name = "史诗", weight = 8, group = "daily", max_stack = 1 },
    { id = 6, name = "锋锐核心", desc = "永久伤害+3%", rarity = "common", rarity_name = "普通", weight = 22, group = "atk", max_stack = 1 },
    { id = 7, name = "韧性符节", desc = "立即生命上限+15", rarity = "common", rarity_name = "普通", weight = 22, group = "hp", max_stack = 1 },
    { id = 8, name = "猎运骰子", desc = "普通掉落率+2%", rarity = "common", rarity_name = "普通", weight = 24, group = "drop", max_stack = 1 },
    { id = 9, name = "战律铭牌", desc = "连杀时窗+0.5秒", rarity = "rare", rarity_name = "稀有", weight = 14, group = "combo", max_stack = 1 },
    { id = 10, name = "悬赏徽记", desc = "每日奖励+25%", rarity = "epic", rarity_name = "史诗", weight = 7, group = "daily", max_stack = 1 },
}

M.RELIC_SYNERGY_DEFS = {
    { key = "atk_combo", need = { 1, 4 }, desc = "战意共鸣：额外伤害+2%" },
    { key = "hp_drop", need = { 2, 8 }, desc = "稳健拾荒：掉率+2%" },
    { key = "combo_daily", need = { 9, 5 }, desc = "连战红利：每日奖励+15%" },
    { key = "core_guard", need = { 6, 7 }, desc = "核心守护：生命上限+10" },
}

M.RELIC_SOURCE_PROFILE = {
    init = { common = 0.62, rare = 0.30, epic = 0.08 },
    kill = { common = 0.55, rare = 0.34, epic = 0.11 },
    challenge = { common = 0.48, rare = 0.37, epic = 0.15 },
    risk = { common = 0.42, rare = 0.39, epic = 0.19 },
}

M.RELIC_SOURCE_NAME = {
    init = "开局遗物",
    kill = "击杀遗物",
    challenge = "挑战遗物",
    risk = "风险遗物",
}

M.CATASTROPHE_DEFS = {
    { id = 1, name = "酸雨侵袭", desc = "敌人更硬更痛，掉落提升", hp_mult = 1.12, dmg_mult = 1.1, spawn_period_mult = 1.0, drop_bonus = 0.03, sanity_drain = 0 },
    { id = 2, name = "噩梦低语", desc = "刷怪更快并持续掉理智", hp_mult = 1.03, dmg_mult = 1.03, spawn_period_mult = 0.9, drop_bonus = 0.02, sanity_drain = 2 },
    { id = 3, name = "猩红月蚀", desc = "敌人偏强但奖励更高", hp_mult = 1.08, dmg_mult = 1.09, spawn_period_mult = 0.94, drop_bonus = 0.05, sanity_drain = 0 },
}

M.CHALLENGE_KIND_NAMES = {
    [1] = "歼灭试炼",
    [2] = "精英试炼",
    [3] = "Boss试炼",
}

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
}

M.SEASON_AFFIX_ROTATION_DEFS = {
    { id = "wild_hunt", name = "狂猎赛季", enable = { "ignite", "meteor" }, disable = { "shield" }, rarity_bonus = { epic = 0.04, legendary = 0.02 } },
    { id = "iron_wall", name = "铁壁赛季", enable = { "shield", "thorns", "regen" }, disable = { "lightning" }, rarity_bonus = { rare = 0.03, epic = 0.03 } },
    { id = "blood_moon", name = "血月赛季", enable = { "lifesteal", "frost" }, disable = {}, rarity_bonus = { epic = 0.05, legendary = 0.03 } },
    { id = "storm_front", name = "风暴赛季", enable = { "lightning", "light" }, disable = { "lifesteal" }, rarity_bonus = { rare = 0.04, epic = 0.02 } },
}

M.BOSS_LOOT_SIGNATURE_DEFS = {
    default = { tags = { "balanced" }, bonus_affix = { regen = true } },
    deerclops = { tags = { "burst", "frozen" }, bonus_affix = { frost = true } },
    bearger = { tags = { "tank", "sustain" }, bonus_affix = { shield = true, winter_insulation = true } },
    moose = { tags = { "tempo", "storm" }, bonus_affix = { lightning = true } },
    dragonfly = { tags = { "fire", "burst" }, bonus_affix = { ignite = true, summer_cooling = true } },
    klaus = { tags = { "ritual", "balanced" }, bonus_affix = { meteor = true } },
    daywalker = { tags = { "nightmare", "sustain" }, bonus_affix = { lifesteal = true, thorns = true } },
}

M.SEASON_OBJECTIVE_DEFS = {
    { id = "boss_hunter", name = "王者狩猎", metric = "boss_kills", target = 7, grade = { s = 11, a = 9, b = 7 }, weight = 1.3 },
    { id = "trial_master", name = "试炼征服", metric = "trial_wins", target = 4, grade = { s = 7, a = 5, b = 4 }, weight = 1.1 },
    { id = "deathless", name = "无伤统帅", metric = "deathless_days", target = 68, grade = { s = 80, a = 74, b = 68 }, weight = 1.0 },
    { id = "elite_slayer", name = "精英清剿", metric = "elite_kills", target = 28, grade = { s = 40, a = 34, b = 28 }, weight = 0.9 },
}

M.SEASON_OBJECTIVE_BALANCE = {
    grade_avg_s = 2.35,
    grade_avg_a = 1.45,
    grade_avg_b = 0.75,
    detail_lines_per_player = 2,
}

M.DROP_PITY_RULES = {
    boss_gear = {
        start_after = 3,
        max_stacks = 6,
        per_stack_rare = 0.05,
        per_stack_epic = 0.04,
        per_stack_legendary = 0.03,
        reset_on_epic = true,
    },
    trial_gear = {
        start_after = 2,
        max_stacks = 5,
        per_stack_rare = 0.04,
        per_stack_epic = 0.05,
        per_stack_legendary = 0.035,
        reset_on_epic = true,
    },
}

M.VNEXT_DROP_BALANCE = {
    trial_extra_base = 0.3,
    trial_extra_tier_step = 0.15,
    trial_extra_cap = 0.8,
    boss_extra_base = 0.2,
    boss_extra_tier_step = 0.1,
    boss_extra_cap = 0.7,
    elite_gear_chance = 0.25,
    trial_mat_base = 2,
    trial_mat_tier_bonus = 1,
    boss_mat_base = 3,
    boss_mat_tier_bonus = 1,
}

M.BOSS_TEMPLATE_DEFS = {
    { id = "summoner", name = "统御军势型", min_day = 21, weight = 3 },
    { id = "zone", name = "雷暴猎场型", min_day = 25, weight = 2 },
    { id = "charger", name = "点名猎杀型", min_day = 30, weight = 2 },
    { id = "phase_shift", name = "双相裂变型", min_day = 35, weight = 2 },
    { id = "berserk_aura", name = "压迫领域型", min_day = 41, weight = 1 },
}

M.BOSS_TEMPLATE_ROTATION_MODS = {
    [1] = { summoner = 1.25, zone = 1.0, charger = 1.1, phase_shift = 0.95, berserk_aura = 1.1 },
    [2] = { summoner = 0.95, zone = 1.25, charger = 1.0, phase_shift = 1.05, berserk_aura = 0.9 },
    [3] = { summoner = 1.0, zone = 0.9, charger = 1.2, phase_shift = 1.15, berserk_aura = 1.35 },
    [4] = { summoner = 1.05, zone = 1.1, charger = 1.05, phase_shift = 1.0, berserk_aura = 1.0 },
}

M.SEASON_PHASE_NAMES = {
    [1] = "准备期",
    [2] = "进行中",
    [3] = "终局日",
    [4] = "终局夜",
    [5] = "结算中",
    [6] = "重置中",
}

M.WAVE_RULE_NAMES = {}
for _, def in ipairs(M.WAVE_RULE_DEFS) do
    M.WAVE_RULE_NAMES[def.id] = def.name
end

M.THREAT_TIER_NAMES = {
    [1] = "稳态",
    [2] = "高压",
    [3] = "灾厄",
}

M.THREAT_ROTATION_MODS = {
    [1] = { base_shift = 0.10, hp_shift = 0.05, reward_shift = 1, floor_tier = 1, ceil_tier = 3 },
    [2] = { base_shift = -0.08, hp_shift = -0.04, reward_shift = -1, floor_tier = 1, ceil_tier = 3 },
    [3] = { base_shift = 0.14, hp_shift = 0.03, reward_shift = 2, floor_tier = 1, ceil_tier = 3 },
    [4] = { base_shift = 0.05, hp_shift = 0.0, reward_shift = 1, floor_tier = 1, ceil_tier = 3 },
}

M.SEASON_STYLE_NAMES = {
    [1] = "全能统筹",
    [2] = "试炼主导",
    [3] = "赏金主导",
    [4] = "灾厄韧性",
    [5] = "稳健推进",
    [6] = "均衡推进",
}

M.CATASTROPHE_NAMES = {}
for _, def in ipairs(M.CATASTROPHE_DEFS) do
    M.CATASTROPHE_NAMES[def.id] = def.name
end

M.SEASON_ROTATION_NAMES = {}
for i, def in ipairs(M.SEASON_AFFIX_ROTATION_DEFS) do
    M.SEASON_ROTATION_NAMES[i] = def.name
end

M.SEASON_OBJECTIVE_NAMES = {}
for i, def in ipairs(M.SEASON_OBJECTIVE_DEFS) do
    M.SEASON_OBJECTIVE_NAMES[i] = def.name
end

M.PREFAB_RUNTIME_ALIASES = {
    armor_wood = "armorwood", armor_grass = "armorgrass", armor_marble = "armormarble",
    armor_snurtleshell = "armorsnurtleshell", armor_ruins = "armorruins",
    armor_dragonfly = "armordragonfly", armor_skeleton = "armorskeleton",
    armor_void = "armorvoid", armor_dreadstone = "armordreadstone",
    hat_void = "voidclothhat", hat_dreadstone = "dreadstonehat",
    health_booster = "booster_shot", toothtrap = "traptooth", manure = "poop",
    pierogi = "perogies", cookedfish = "fishmeat_cooked", flair = "flare",
    powdermonkey = "monkey", bunny_puff = "rabbit", telltale_heart = "reviver",
    shield_of_terror = "armor_sanity", armor_lunar = "armor_lunarplant",
    bonearmor = "armorskeleton",
}

return M
