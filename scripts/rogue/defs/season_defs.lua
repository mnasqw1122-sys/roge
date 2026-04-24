--[[
    文件说明：season_defs.lua
    功能：赛季系统定义数据，从config.lua拆分而来。
]]
local M = {}

M.SEASON_PHASE_NAMES = {
    [1] = "准备期",
    [2] = "进行中",
    [3] = "终局日",
    [4] = "终局夜",
    [5] = "结算中",
    [6] = "重置中",
}

M.SEASON_AFFIX_ROTATION_DEFS = {
    { id = "wild_hunt", name = "狂猎赛季", enable = { "ignite", "meteor" }, disable = { "shield" }, rarity_bonus = { epic = 0.04, legendary = 0.02 } },
    { id = "iron_wall", name = "铁壁赛季", enable = { "shield", "thorns", "regen" }, disable = { "lightning" }, rarity_bonus = { rare = 0.03, epic = 0.03 } },
    { id = "blood_moon", name = "血月赛季", enable = { "lifesteal", "frost" }, disable = {}, rarity_bonus = { epic = 0.05, legendary = 0.03 } },
    { id = "storm_front", name = "风暴赛季", enable = { "lightning", "light" }, disable = { "lifesteal" }, rarity_bonus = { rare = 0.04, epic = 0.02 } },
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

M.SEASON_STYLE_NAMES = {
    [1] = "全能统筹",
    [2] = "试炼主导",
    [3] = "赏金主导",
    [4] = "灾厄韧性",
    [5] = "稳健推进",
    [6] = "均衡推进",
}

M.SEASON_ROTATION_NAMES = {}
for i, def in ipairs(M.SEASON_AFFIX_ROTATION_DEFS) do
    M.SEASON_ROTATION_NAMES[i] = def.name
end

M.SEASON_OBJECTIVE_NAMES = {}
for i, def in ipairs(M.SEASON_OBJECTIVE_DEFS) do
    M.SEASON_OBJECTIVE_NAMES[i] = def.name
end

M.SEASON_MILESTONE_DEFS = {
    { id = 1, name = "初露锋芒", day = 15, desc = "赛季初期里程碑", rewards = { mat_count = 3, gear_chance = 0.30, relic_chance = 0.10 } },
    { id = 2, name = "渐入佳境", day = 30, desc = "赛季中期里程碑", rewards = { mat_count = 5, gear_chance = 0.45, relic_chance = 0.20 } },
    { id = 3, name = "巅峰时刻", day = 50, desc = "赛季后期里程碑", rewards = { mat_count = 8, gear_chance = 0.60, relic_chance = 0.35 } },
    { id = 4, name = "传奇终章", day = 70, desc = "赛季终局里程碑", rewards = { mat_count = 12, gear_chance = 0.80, relic_chance = 0.50 } },
}

M.SEASON_MILESTONE_UNLOCK_METRICS = {
    { id = 1, min_kills = 50, min_bosses = 0, min_elites = 5 },
    { id = 2, min_kills = 150, min_bosses = 2, min_elites = 20 },
    { id = 3, min_kills = 350, min_bosses = 5, min_elites = 50 },
    { id = 4, min_kills = 600, min_bosses = 8, min_elites = 80 },
}

return M
