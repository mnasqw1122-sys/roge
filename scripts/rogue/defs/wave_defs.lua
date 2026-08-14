--[[
    文件说明：wave_defs.lua
    功能：波次系统定义数据，从config.lua拆分而来。
]]
local M = {}

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
    { id = 5, name = "元素领域", desc = "元素伤害提升，元素敌人增多", weight = 1, enemy_hp_mult = 1.08, enemy_dmg_mult = 1.05, elite_bonus = 0.03, drop_bonus = 0.04, elemental_bonus = 0.15 },
    { id = 6, name = "暗影迷宫", desc = "移动速度提升，敌人攻击速度加快", weight = 1, enemy_hp_mult = 1.02, enemy_dmg_mult = 1.10, elite_bonus = 0.05, drop_bonus = 0.06, speed_bonus = 0.12, enemy_speed_bonus = 0.15 },
    { id = 7, name = "生命之泉", desc = "生命恢复速度提升，敌人生命值增加", weight = 1, enemy_hp_mult = 1.15, enemy_dmg_mult = 0.95, elite_bonus = 0.02, drop_bonus = 0.03, regen_bonus = 0.2 },
    { id = 8, name = "幸运圣地", desc = "稀有物品掉落率提升，敌人数量增加", weight = 1, enemy_hp_mult = 1.0, enemy_dmg_mult = 1.0, elite_bonus = 0.06, drop_bonus = 0.02, luck_bonus = 0.1, enemy_count_bonus = 0.2 },
}

M.REGION_ROUTE_DEFS_SHIPWRECKED = {
    { id = 1, name = "珊瑚礁群", desc = "海洋生物增多，海难材料提升", weight = 1, enemy_hp_mult = 1.04, enemy_dmg_mult = 1.04, elite_bonus = 0.03, drop_bonus = 0.04, mat_bonus = 1 },
    { id = 2, name = "海盗港湾", desc = "海盗出没，金币与装备掉落提升", weight = 1, enemy_hp_mult = 1.08, enemy_dmg_mult = 1.06, elite_bonus = 0.05, drop_bonus = 0.06, gear_roll_bonus = 1 },
    { id = 3, name = "深海领域", desc = "深海怪物更强，Boss材料掉落提升", weight = 1, enemy_hp_mult = 1.12, enemy_dmg_mult = 1.10, elite_bonus = 0.04, drop_bonus = 0.05, mat_bonus = 2 },
    { id = 4, name = "火山地带", desc = "火山威胁，黑曜石资源丰富", weight = 1, enemy_hp_mult = 1.10, enemy_dmg_mult = 1.08, elite_bonus = 0.03, drop_bonus = 0.07, hp_cost_pct = 0.06 },
}

M.REGION_ROUTE_DEFS_HAMLET = {
    { id = 1, name = "雨林深处", desc = "丛林生物增多，草药资源丰富", weight = 1, enemy_hp_mult = 1.06, enemy_dmg_mult = 1.04, elite_bonus = 0.04, drop_bonus = 0.04, mat_bonus = 1 },
    { id = 2, name = "猪城集市", desc = "猪人交易频繁，呼噜币收益提升", weight = 1, enemy_hp_mult = 1.02, enemy_dmg_mult = 1.02, elite_bonus = 0.02, drop_bonus = 0.05, currency_bonus = 0.3 },
    { id = 3, name = "蚁穴迷宫", desc = "蚁群密集，甲壳材料掉落提升", weight = 1, enemy_hp_mult = 1.10, enemy_dmg_mult = 1.08, elite_bonus = 0.06, drop_bonus = 0.04, mat_bonus = 2 },
    { id = 4, name = "远古遗迹", desc = "远古力量涌动，稀有遗物掉落提升", weight = 1, enemy_hp_mult = 1.12, enemy_dmg_mult = 1.10, elite_bonus = 0.04, drop_bonus = 0.08, sanity_drain = 1 },
}

M.REGION_ROUTE_NAMES = {}
for _, def in ipairs(M.REGION_ROUTE_DEFS) do
    M.REGION_ROUTE_NAMES[def.id] = def.name
end

M.WAVE_RULE_NAMES = {}
for _, def in ipairs(M.WAVE_RULE_DEFS) do
    M.WAVE_RULE_NAMES[def.id] = def.name
end

M.CHALLENGE_KIND_NAMES = {
    [1] = "击杀挑战",
    [2] = "Boss挑战",
    [3] = "紫晶试炼",
}

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

return M
