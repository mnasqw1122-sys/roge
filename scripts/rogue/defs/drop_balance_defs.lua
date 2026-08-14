--[[
    文件说明：drop_balance_defs.lua
    功能：掉落平衡参数定义，从 drop_system.lua 的 `or 默认值` 兜底中抽取而来。
    v2.2 之前 VNEXT_DROP_BALANCE 被引用但从未定义，所有值靠硬编码兜底；
    本文件将其集中暴露，便于后续在 modinfo/CONST 调参，且保持原默认值不变以兼容存档行为。
]]
local M = {}

-- VNEXT 掉落平衡参数表
-- trial_*   : 挑战房试炼 Boss 额外掉落相关
-- boss_*    : 普通Boss额外掉落相关
-- elite_*   : 精英怪掉装备相关
M.VNEXT_DROP_BALANCE = {
    -- 试炼Boss 额外装备掉落概率：base + step * tier，上限 cap
    trial_extra_base       = 0.25,
    trial_extra_tier_step  = 0.12,
    trial_extra_cap        = 0.72,
    -- 试炼Boss 材料掉落数量基数 + tier 加成
    trial_mat_base         = 1,
    trial_mat_tier_bonus   = 1,
    -- 普通Boss 额外装备掉落概率：base + step * tier，上限 cap
    boss_extra_base        = 0.12,
    boss_extra_tier_step   = 0.10,
    boss_extra_cap         = 0.60,
    -- 普通Boss 材料掉落数量基数 + tier 加成
    boss_mat_base          = 2,
    boss_mat_tier_bonus    = 1,
    -- 精英怪掉落装备的基础概率
    elite_gear_chance      = 0.14,
}

return M
