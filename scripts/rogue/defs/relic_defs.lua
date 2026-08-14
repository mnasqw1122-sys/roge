--[[
    文件说明：relic_defs.lua
    功能：遗物系统定义数据，从config.lua拆分而来。
    V2扩展：36种遗物，增加Build组合定义和更多协同效果。
]]
local M = {}

M.RELIC_DEFS = {
    -- ========== 攻击组 ==========
    { id = 1, name = "狂战纹章", desc = "永久伤害+5%", rarity = "rare", rarity_name = "稀有", weight = 18, group = "atk", max_stack = 1 },
    { id = 6, name = "锋锐核心", desc = "永久伤害+3%", rarity = "common", rarity_name = "普通", weight = 22, group = "atk", max_stack = 1 },
    { id = 19, name = "灭世之刃", desc = "暴击伤害+25%", rarity = "epic", rarity_name = "史诗", weight = 6, group = "atk", max_stack = 1 },
    { id = 20, name = "嗜血獠牙", desc = "击杀后5秒内伤害+10%", rarity = "rare", rarity_name = "稀有", weight = 14, group = "atk", max_stack = 1 },
    { id = 21, name = "破甲锥", desc = "攻击无视12%护甲", rarity = "rare", rarity_name = "稀有", weight = 14, group = "atk", max_stack = 1 },
    { id = 22, name = "炎龙之心", desc = "攻击附带5点火伤", rarity = "epic", rarity_name = "史诗", weight = 7, group = "atk", max_stack = 1 },
    { id = 23, name = "雷神之锤", desc = "攻击有8%几率触发闪电", rarity = "epic", rarity_name = "史诗", weight = 6, group = "atk", max_stack = 1 },
    { id = 24, name = "深渊之触", desc = "对Boss伤害+8%", rarity = "rare", rarity_name = "稀有", weight = 12, group = "atk", max_stack = 1 },

    -- ========== 生命组 ==========
    { id = 2, name = "生命护符", desc = "立即生命上限+20", rarity = "rare", rarity_name = "稀有", weight = 18, group = "hp", max_stack = 1 },
    { id = 7, name = "韧性符节", desc = "立即生命上限+15", rarity = "common", rarity_name = "普通", weight = 22, group = "hp", max_stack = 1 },
    { id = 25, name = "不朽铠甲", desc = "受到伤害减少8%", rarity = "epic", rarity_name = "史诗", weight = 6, group = "hp", max_stack = 1 },
    { id = 26, name = "再生之环", desc = "每3秒恢复1点生命", rarity = "rare", rarity_name = "稀有", weight = 14, group = "hp", max_stack = 1 },
    { id = 27, name = "铁壁护盾", desc = "生命值满时，受到首次攻击伤害减半", rarity = "rare", rarity_name = "稀有", weight = 12, group = "hp", max_stack = 1 },
    { id = 28, name = "生命虹吸石", desc = "击杀敌人恢复3点生命", rarity = "common", rarity_name = "普通", weight = 20, group = "hp", max_stack = 1 },

    -- ========== 掉落组 ==========
    { id = 3, name = "拾荒齿轮", desc = "普通掉落率+3%", rarity = "common", rarity_name = "普通", weight = 24, group = "drop", max_stack = 1 },
    { id = 8, name = "猎运骰子", desc = "普通掉落率+2%", rarity = "common", rarity_name = "普通", weight = 24, group = "drop", max_stack = 1 },
    { id = 29, name = "黄金罗盘", desc = "稀有物品掉落率+6%", rarity = "rare", rarity_name = "稀有", weight = 12, group = "drop", max_stack = 1 },
    { id = 30, name = "聚宝盆", desc = "精英掉落额外+1件", rarity = "epic", rarity_name = "史诗", weight = 5, group = "drop", max_stack = 1 },
    { id = 31, name = "命运骰子", desc = "所有掉落率+1%，但受到伤害+3%", rarity = "rare", rarity_name = "稀有", weight = 10, group = "drop", max_stack = 1 },

    -- ========== 连击组 ==========
    { id = 4, name = "连击刻印", desc = "连杀时窗+0.5秒", rarity = "common", rarity_name = "普通", weight = 24, group = "combo", max_stack = 1 },
    { id = 9, name = "战律铭牌", desc = "连杀时窗+0.5秒", rarity = "rare", rarity_name = "稀有", weight = 14, group = "combo", max_stack = 1 },
    { id = 32, name = "狂怒之链", desc = "连杀每达10次，伤害+3%（可叠加）", rarity = "rare", rarity_name = "稀有", weight = 12, group = "combo", max_stack = 1 },
    { id = 33, name = "节奏之心", desc = "连杀时窗+1秒，连杀倍率上限+0.2", rarity = "epic", rarity_name = "史诗", weight = 6, group = "combo", max_stack = 1 },

    -- ========== 日常组 ==========
    { id = 5, name = "赏金火漆", desc = "每日奖励+25%", rarity = "epic", rarity_name = "史诗", weight = 8, group = "daily", max_stack = 1 },
    { id = 10, name = "悬赏徽记", desc = "每日奖励+25%", rarity = "epic", rarity_name = "史诗", weight = 7, group = "daily", max_stack = 1 },
    { id = 34, name = "勤勉之印", desc = "每日任务目标-20%", rarity = "rare", rarity_name = "稀有", weight = 12, group = "daily", max_stack = 1 },

    -- ========== 元素组 ==========
    { id = 11, name = "元素宝珠", desc = "元素伤害提升10%", rarity = "rare", rarity_name = "稀有", weight = 16, group = "elemental", max_stack = 1 },
    { id = 35, name = "冰霜之心", desc = "冰元素伤害+12%，冰抗+15%", rarity = "rare", rarity_name = "稀有", weight = 12, group = "elemental", max_stack = 1 },
    { id = 36, name = "烈焰之核", desc = "火元素伤害+12%，火抗+15%", rarity = "rare", rarity_name = "稀有", weight = 12, group = "elemental", max_stack = 1 },

    -- ========== 速度组 ==========
    { id = 12, name = "暗影护符", desc = "移动速度提升8%", rarity = "common", rarity_name = "普通", weight = 20, group = "speed", max_stack = 1 },
    { id = 37, name = "疾风之靴", desc = "移动速度+12%，闪避率+5%", rarity = "rare", rarity_name = "稀有", weight = 10, group = "speed", max_stack = 1 },

    -- ========== 恢复组 ==========
    { id = 13, name = "生命之树", desc = "每秒恢复0.5点生命值", rarity = "epic", rarity_name = "史诗", weight = 6, group = "regen", max_stack = 1 },
    { id = 38, name = "治愈圣杯", desc = "使用治疗物品效果+30%", rarity = "rare", rarity_name = "稀有", weight = 14, group = "regen", max_stack = 1 },

    -- ========== 幸运组 ==========
    { id = 14, name = "幸运金币", desc = "稀有物品掉落率提升4%", rarity = "rare", rarity_name = "稀有", weight = 15, group = "luck", max_stack = 1 },
    { id = 39, name = "四叶草", desc = "所有随机事件好运率+5%", rarity = "common", rarity_name = "普通", weight = 20, group = "luck", max_stack = 1 },

    -- ========== 冷却组 ==========
    { id = 15, name = "时间沙漏", desc = "技能冷却时间减少10%", rarity = "epic", rarity_name = "史诗", weight = 7, group = "cooldown", max_stack = 1 },
    { id = 40, name = "永恒之钟", desc = "技能冷却时间-15%，连杀窗口+0.5秒", rarity = "legendary", rarity_name = "传说", weight = 2, group = "cooldown", max_stack = 1 },

    -- ========== 生存组 ==========
    { id = 16, name = "守护天使", desc = "受到致命伤害时有10%几率免死", rarity = "legendary", rarity_name = "传说", weight = 3, group = "survival", max_stack = 1 },
    { id = 41, name = "不死鸟羽", desc = "死亡后以30%生命复活（每赛季1次）", rarity = "legendary", rarity_name = "传说", weight = 2, group = "survival", max_stack = 1 },

    -- ========== 理智组 ==========
    { id = 17, name = "魔力源泉", desc = "理智恢复速度提升20%", rarity = "rare", rarity_name = "稀有", weight = 14, group = "sanity", max_stack = 1 },
    { id = 42, name = "清明之冠", desc = "理智值低于30%时自动恢复至50%（冷却180秒）", rarity = "epic", rarity_name = "史诗", weight = 5, group = "sanity", max_stack = 1 },

    -- ========== 暴击组 ==========
    { id = 18, name = "力量之戒", desc = "攻击时有5%几率造成双倍伤害", rarity = "epic", rarity_name = "史诗", weight = 6, group = "crit", max_stack = 1 },
    { id = 43, name = "致命印记", desc = "暴击率+4%，暴击后2秒内伤害+8%", rarity = "rare", rarity_name = "稀有", weight = 10, group = "crit", max_stack = 1 },

    -- ========== 传说组 ==========
    { id = 44, name = "混沌之眼", desc = "所有属性+2%，但随机负面效果+5%", rarity = "legendary", rarity_name = "传说", weight = 2, group = "legendary", max_stack = 1 },
    { id = 45, name = "创世之书", desc = "每拥有5件遗物，所有属性+1%", rarity = "legendary", rarity_name = "传说", weight = 2, group = "legendary", max_stack = 1 },
    { id = 46, name = "虚空之镜", desc = "受到攻击时有5%几率反弹100%伤害", rarity = "legendary", rarity_name = "传说", weight = 2, group = "legendary", max_stack = 1 },
}

M.RELIC_SYNERGY_DEFS = {
    { key = "atk_combo", need = { 1, 4 }, desc = "战意共鸣：额外伤害+2%" },
    { key = "hp_drop", need = { 2, 8 }, desc = "稳健拾荒：掉率+2%" },
    { key = "combo_daily", need = { 9, 5 }, desc = "连战红利：每日奖励+15%" },
    { key = "core_guard", need = { 6, 7 }, desc = "核心守护：生命上限+10" },
    { key = "elemental_speed", need = { 11, 12 }, desc = "元素之风：元素伤害额外+5%，移动速度+5%" },
    { key = "regen_sanity", need = { 13, 17 }, desc = "生命与理智：生命恢复速度+20%，理智恢复速度+10%" },
    { key = "luck_crit", need = { 14, 18 }, desc = "幸运暴击：暴击率+3%，稀有掉落率+2%" },
    { key = "cooldown_elemental", need = { 15, 11 }, desc = "元素冷却：技能冷却时间额外-5%，元素伤害+3%" },
    { key = "survival_hp", need = { 16, 2 }, desc = "守护生命：免死几率+5%，生命上限+10" },
    { key = "berserk_fang", need = { 1, 20 }, desc = "狂战獠牙：击杀后伤害+15%（持续5秒）" },
    { key = "armor_pen_crit", need = { 21, 18 }, desc = "破甲暴击：暴击时无视额外10%护甲" },
    { key = "fire_ice", need = { 22, 35 }, desc = "冰火交融：元素伤害+8%，元素抗性+10%" },
    { key = "thunder_combo", need = { 23, 32 }, desc = "雷霆连击：连杀达10次时触发范围闪电" },
    { key = "boss_depths", need = { 24, 19 }, desc = "深渊灭世：对Boss暴击伤害+30%" },
    { key = "immortal_regen", need = { 25, 26 }, desc = "不朽再生：减伤+3%，生命恢复+0.5/秒" },
    { key = "shield_first", need = { 27, 25 }, desc = "首击铁壁：首次攻击减伤提升至75%" },
    { key = "gold_luck", need = { 29, 39 }, desc = "金运双全：稀有掉落率+4%，好运率+3%" },
    { key = "rhythm_fury", need = { 33, 32 }, desc = "节奏狂怒：连杀倍率上限+0.3，连杀窗口+0.5秒" },
    { key = "phoenix_angel", need = { 41, 16 }, desc = "不死守护：免死后恢复至50%生命" },
    { key = "void_mirror", need = { 46, 25 }, desc = "虚空之壁：反弹几率+3%，减伤+3%" },
    { key = "genesis_tome", need = { 45, 44 }, desc = "创世混沌：每4件遗物+1.5%全属性" },
    { key = "diligence_bounty", need = { 34, 5 }, desc = "勤勉赏金：每日任务目标-30%，奖励+10%" },
    { key = "heal_saint", need = { 38, 26 }, desc = "圣愈之环：治疗效果+15%，生命恢复+0.3/秒" },
    { key = "eternal_clock", need = { 40, 15 }, desc = "永恒时光：冷却-20%，连杀窗口+1秒" },
    { key = "deadly_mark", need = { 43, 19 }, desc = "致命印记：暴击率+3%，暴击伤害+15%" },
}

M.RELIC_BUILD_DEFS = {
    {
        key = "berserker",
        name = "狂战士",
        desc = "极致输出，以攻代守",
        core_relics = { 1, 20, 19 },
        bonus = { damage_bonus = 0.05, crit_chance = 0.03 },
        bonus_desc = "额外伤害+5%，暴击率+3%"
    },
    {
        key = "fortress",
        name = "堡垒",
        desc = "坚不可摧，持久生存",
        core_relics = { 25, 27, 16 },
        bonus = { damage_reduction = 0.05, hp_bonus = 15 },
        bonus_desc = "减伤+5%，生命上限+15"
    },
    {
        key = "combo_master",
        name = "连击大师",
        desc = "连杀不断，越战越强",
        core_relics = { 4, 33, 32 },
        bonus = { combo_window_bonus = 1.0, combo_max_mult_bonus = 0.2 },
        bonus_desc = "连杀窗口+1秒，连杀倍率上限+0.2"
    },
    {
        key = "treasure_hunter",
        name = "寻宝猎人",
        desc = "遍地黄金，收获满满",
        core_relics = { 3, 29, 30 },
        bonus = { drop_bonus = 0.04, luck_bonus = 0.03 },
        bonus_desc = "掉率+4%，幸运+3%"
    },
    {
        key = "elementalist",
        name = "元素师",
        desc = "冰火雷三系精通",
        core_relics = { 11, 35, 36 },
        bonus = { elemental_bonus = 0.08, elemental_resist = 0.10 },
        bonus_desc = "元素伤害+8%，元素抗性+10%"
    },
    {
        key = "undying",
        name = "不灭者",
        desc = "死亡只是暂时的",
        core_relics = { 16, 41, 26 },
        bonus = { death_defy_chance = 0.05, regen_bonus = 0.3 },
        bonus_desc = "免死几率+5%，生命恢复+0.3/秒"
    },
}

M.RELIC_SOURCE_PROFILE = {
    init = { common = 0.55, rare = 0.32, epic = 0.10, legendary = 0.03 },
    kill = { common = 0.48, rare = 0.35, epic = 0.13, legendary = 0.04 },
    challenge = { common = 0.40, rare = 0.38, epic = 0.17, legendary = 0.05 },
    risk = { common = 0.35, rare = 0.38, epic = 0.20, legendary = 0.07 },
}

M.RELIC_SOURCE_NAME = {
    init = "开局遗物",
    kill = "击杀遗物",
    challenge = "挑战遗物",
    risk = "风险遗物",
}

return M
