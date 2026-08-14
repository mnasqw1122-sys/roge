--[[
    文件说明：boss_balance_defs.lua
    功能：Boss 深度机制（V2）变异概率定义。
    v3.0 之前 5 处 `math.random() < 0.25` 硬编码散落在 boss_mechanics.lua，
    本文件将其集中定义，支持按 prefab 单独调整，默认值保持原 0.25 不变以兼容既有玩法。
]]
local M = {}

-- 各类 Boss 变异为 V2 深度机制的概率（0~1）
-- boss_variant_chance 为全局兜底值；prefab_variant_chance 可对单个 Boss 覆盖
M.BOSS_BALANCE = {
    boss_variant_chance = 0.25,
    prefab_variant_chance = {
        bearger        = 0.25, -- 领域工匠
        leif           = 0.25, -- 统御军势（树精守卫）
        treeguard      = 0.25, -- 统御军势（树精守卫）
        moose          = 0.25, -- 雷暴猎场
        spiderqueen    = 0.25, -- 双相裂变
        minotaur       = 0.25, -- 压迫领域
    },
}

return M
