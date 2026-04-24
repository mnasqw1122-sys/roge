--[[
    文件说明：config.lua
    功能：肉鸽模式的核心配置入口。
    数据定义已拆分至 defs/ 子模块，本文件负责加载、合并并提供向后兼容接口。
    仅保留运行时配置加载逻辑（LoadConfig）和常量定义（CONST）。
]]
local M = {}

-- 函数说明：加载运行时配置（从modinfo选项读取）
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
        AI_NPC_ENABLED = Get("AI_NPC_ENABLED") ~= false,
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

-- 函数说明：从defs子模块合并数据定义到当前模块，保持向后兼容
local function MergeDefs(def_module)
    if type(def_module) ~= "table" then return end
    for k, v in pairs(def_module) do
        if M[k] == nil then
            M[k] = v
        end
    end
end

-- 加载拆分后的数据定义模块
MergeDefs(require("rogue/defs/talent_defs"))
MergeDefs(require("rogue/defs/supply_defs"))
MergeDefs(require("rogue/defs/relic_defs"))
MergeDefs(require("rogue/defs/wave_defs"))
MergeDefs(require("rogue/defs/season_defs"))
MergeDefs(require("rogue/defs/affix_defs"))
MergeDefs(require("rogue/defs/progression_defs"))
MergeDefs(require("rogue/defs/badge_defs"))
MergeDefs(require("rogue/defs/set_bonus_defs"))

-- 运行时常量（不拆分，与逻辑紧密耦合）
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
    CHALLENGE_BASE_CHANCE = 0.38,
    SHOP_DAILY_ITEM_COUNT = 15,
    SHOP_BLACK_MARKET_COUNT = 5,
    SHOP_SEASONAL_COUNT = 2,
    SHOP_DISCOUNT_MIN = 1,
    SHOP_DISCOUNT_MAX = 3,
    SHOP_BLACK_MARKET_HP_SAFETY = 1,
    SHOP_BLACK_MARKET_SANITY_SAFETY = 1,
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

M.PREFAB_RUNTIME_ALIASES = {
    armor_wood = "armorwood", armor_grass = "armorgrass", armor_marble = "armormarble",
    armor_snurtleshell = "armorsnurtleshell", armor_ruins = "armorruins",
    armor_dragonfly = "armordragonfly", armor_skeleton = "armorskeleton",
    armor_void = "armor_voidcloth", armor_dreadstone = "armordreadstone",
    hat_void = "voidclothhat", hat_dreadstone = "dreadstonehat",
    health_booster = "booster_shot", toothtrap = "traptooth", manure = "poop",
    pierogi = "perogies", cookedfish = "fishmeat_cooked", flair = "flare",
    powdermonkey = "monkey", bunny_puff = "rabbit", telltale_heart = "reviver",
    shield_of_terror = "armor_sanity", armor_lunar = "armor_lunarplant",
    bonearmor = "armorskeleton",
}

return M
