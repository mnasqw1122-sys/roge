--[[
    文件说明：progression_defs.lua
    功能：进度/日常/掉落/协作系统定义数据，从config.lua拆分而来。
    V2扩展：日常任务从6种扩展到15+种，增加条件组合和连锁任务。
]]
local M = {}

M.DAILY_KIND_NAMES = {
    [1] = "击杀怪物",
    [2] = "击杀精英",
    [3] = "击杀Boss",
    [4] = "完成波次",
    [5] = "完成挑战",
    [6] = "完成悬赏",
    [7] = "连杀达标",
    [8] = "收集资源",
    [9] = "存活天数",
    [10] = "无伤战斗",
    [11] = "遗物收集",
    [12] = "天赋觉醒",
    [13] = "使用连击技能",
    [14] = "击杀特定生物",
    [15] = "多目标组合",
}

M.DAILY_TASK_KIND_WEIGHTS = {
    [1] = 22, [2] = 16, [3] = 10, [4] = 12, [5] = 8,
    [6] = 8, [7] = 6, [8] = 8, [9] = 4, [10] = 4,
    [11] = 5, [12] = 4, [13] = 5, [14] = 6, [15] = 2,
}

M.DAILY_TASK_TARGETS = {
    [1] = { 30, 50, 80 },
    [2] = { 5, 8, 12 },
    [3] = { 1, 2, 3 },
    [4] = { 3, 5, 8 },
    [5] = { 1, 2, 3 },
    [6] = { 1, 2, 3 },
    [7] = { 15, 25, 40 },
    [8] = { 10, 20, 30 },
    [9] = { 3, 5, 7 },
    [10] = { 5, 10, 15 },
    [11] = { 2, 4, 6 },
    [12] = { 1, 2, 3 },
    [13] = { 1, 2, 3 },
    [14] = { 3, 5, 8 },
    [15] = { 1, 1, 1 },
}

M.DAILY_TASK_REWARDS = {
    [1] = { gold = 10, xp = 20 },
    [2] = { gold = 20, xp = 40 },
    [3] = { gold = 50, xp = 80 },
    [4] = { gold = 15, xp = 30 },
    [5] = { gold = 30, xp = 50 },
    [6] = { gold = 25, xp = 45 },
    [7] = { gold = 15, xp = 35 },
    [8] = { gold = 10, xp = 25 },
    [9] = { gold = 20, xp = 30 },
    [10] = { gold = 30, xp = 60 },
    [11] = { gold = 20, xp = 40 },
    [12] = { gold = 15, xp = 35 },
    [13] = { gold = 15, xp = 30 },
    [14] = { gold = 20, xp = 35 },
    [15] = { gold = 50, xp = 100 },
}

M.DAILY_CHAIN_DEFS = {
    {
        id = "hunter_chain",
        name = "猎人之道",
        steps = {
            { kind = 1, target = 30, desc = "击杀30只怪物" },
            { kind = 2, target = 5, desc = "击杀5只精英" },
            { kind = 3, target = 1, desc = "击杀1个Boss" },
        },
        chain_reward = { gold = 100, xp = 200, bonus_relic = true },
    },
    {
        id = "survivor_chain",
        name = "生存之道",
        steps = {
            { kind = 9, target = 3, desc = "存活3天" },
            { kind = 10, target = 5, desc = "完成5次无伤战斗" },
            { kind = 8, target = 20, desc = "收集20个资源" },
        },
        chain_reward = { gold = 80, xp = 150, bonus_talent = true },
    },
    {
        id = "combo_chain",
        name = "连击之道",
        steps = {
            { kind = 7, target = 15, desc = "达成15连杀" },
            { kind = 13, target = 1, desc = "使用1次连击技能" },
            { kind = 7, target = 40, desc = "达成40连杀" },
        },
        chain_reward = { gold = 90, xp = 180, bonus_combo_skill = true },
    },
    {
        id = "collector_chain",
        name = "收藏之道",
        steps = {
            { kind = 11, target = 2, desc = "收集2件遗物" },
            { kind = 12, target = 1, desc = "觉醒1次天赋" },
            { kind = 11, target = 5, desc = "收集5件遗物" },
        },
        chain_reward = { gold = 120, xp = 250, bonus_synergy = true },
    },
}

M.DAILY_SPECIFIC_TARGET_DEFS = {
    { id = "spider", name = "蜘蛛", prefab = "spider" },
    { id = "hound", name = "猎犬", prefab = "hound" },
    { id = "pig", name = "猪人", prefab = "pigman" },
    { id = "merm", name = "鱼人", prefab = "merm" },
    { id = "bat", name = "蝙蝠", prefab = "bat" },
    { id = "tentacle", name = "触手", prefab = "tentacle" },
    { id = "treeguard", name = "树精", prefab = "leif" },
    { id = "koalefant", name = "考拉象", prefab = "koalefant" },
}

M.DAILY_TASK_ROTATION_MODS = {
    [1] = { kill_mult = 1.0, elite_mult = 1.1, boss_mult = 1.0, combo_mult = 0.9 },
    [2] = { kill_mult = 1.1, elite_mult = 0.9, boss_mult = 1.2, combo_mult = 1.0 },
    [3] = { kill_mult = 0.9, elite_mult = 1.0, boss_mult = 0.8, combo_mult = 1.3 },
    [4] = { kill_mult = 1.0, elite_mult = 1.0, boss_mult = 1.0, combo_mult = 1.0 },
}

M.DROP_TABLE_NORMAL = {
    { prefab = "meat", weight = 30 },
    { prefab = "drumstick", weight = 25 },
    { prefab = "monstermeat", weight = 15 },
    { prefab = "silk", weight = 8 },
    { prefab = "spidergland", weight = 5 },
    { prefab = "stinger", weight = 3 },
    { prefab = "honey", weight = 4 },
    { prefab = "rocks", weight = 5 },
    { prefab = "flint", weight = 5 },
}

M.DROP_TABLE_ELITE = {
    { prefab = "goldnugget", weight = 20 },
    { prefab = "gears", weight = 8 },
    { prefab = "redgem", weight = 5 },
    { prefab = "bluegem", weight = 5 },
    { prefab = "greengem", weight = 2 },
    { prefab = "thulecite", weight = 3 },
    { prefab = "nightmarefuel", weight = 8 },
    { prefab = "livinglog", weight = 6 },
    { prefab = "silk", weight = 10 },
    { prefab = "spidergland", weight = 8 },
    { prefab = "honeycomb", weight = 5 },
    { prefab = "tentaclespike", weight = 3 },
    { prefab = "armorwood", weight = 2 },
    { prefab = "spear", weight = 5 },
    { prefab = "amulet", weight = 2 },
}

M.COOP_DEFS = {
    { id = "shared_kill", name = "协力击杀", desc = "多人同时攻击同一目标时伤害+5%", bonus = 0.05 },
    { id = "proximity_buff", name = "近距增益", desc = "附近有队友时防御+3%", bonus = 0.03 },
    { id = "revive_bonus", name = "复活加成", desc = "复活队友后双方获得10秒无敌", duration = 10 },
}

return M
