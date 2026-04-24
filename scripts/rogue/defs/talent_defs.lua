--[[
    文件说明：talent_defs.lua
    功能：天赋系统定义数据，从config.lua拆分而来。
    天赋树分为4大分支：攻击(Offense)、防御(Defense)、辅助(Support)、特殊(Special)。
    每个天赋可设置 prereq（前置天赋ID）和 prereq_level（前置天赋所需等级）。
]]
local M = {}

M.TALENT_BRANCH_NAMES = {
    offense = "攻击",
    defense = "防御",
    support = "辅助",
    special = "特殊",
}

M.TALENT_BRANCH_COLORS = {
    offense = { 0.9, 0.3, 0.2, 1 },
    defense = { 0.2, 0.5, 0.9, 1 },
    support = { 0.2, 0.9, 0.4, 1 },
    special = { 0.7, 0.3, 0.9, 1 },
}

M.TALENT_DEFS = {
    -- ========== 攻击分支 ==========
    { id = 1, name = "铁壁体魄", desc = "立即获得+25生命上限", branch = "defense", max_level = 5, prereq = nil, prereq_level = nil },
    { id = 2, name = "破军技巧", desc = "永久获得+8%伤害", branch = "offense", max_level = 5, prereq = nil, prereq_level = nil },
    { id = 3, name = "连战专精", desc = "连杀持续时间+1.5秒", branch = "offense", max_level = 5, prereq = nil, prereq_level = nil },
    { id = 4, name = "猎手本能", desc = "普通掉落率额外+4%", branch = "support", max_level = 5, prereq = nil, prereq_level = nil },
    { id = 5, name = "赏金契约", desc = "每日奖励额外+50%", branch = "support", max_level = 3, prereq = nil, prereq_level = nil },
    { id = 6, name = "元素亲和", desc = "元素伤害提升15%，元素抗性提升20%", branch = "offense", max_level = 3, prereq = nil, prereq_level = nil },
    { id = 7, name = "暗影行者", desc = "移动速度提升10%，攻击速度提升5%", branch = "special", max_level = 3, prereq = nil, prereq_level = nil },
    { id = 8, name = "生命虹吸", desc = "攻击时有10%几率恢复5点生命值", branch = "offense", max_level = 3, prereq = 2, prereq_level = 2 },
    { id = 9, name = "幸运眷顾", desc = "稀有物品掉落率提升5%", branch = "support", max_level = 3, prereq = 4, prereq_level = 1 },
    { id = 10, name = "战术大师", desc = "技能冷却时间减少15%", branch = "support", max_level = 3, prereq = nil, prereq_level = nil },

    -- ========== 攻击分支进阶 ==========
    { id = 11, name = "暴击本能", desc = "暴击率+5%，暴击伤害+15%", branch = "offense", max_level = 3, prereq = 2, prereq_level = 1 },
    { id = 12, name = "穿透之刃", desc = "攻击无视目标8%护甲", branch = "offense", max_level = 3, prereq = 11, prereq_level = 1 },
    { id = 13, name = "狂怒连斩", desc = "连杀每达10次，下次攻击造成150%伤害", branch = "offense", max_level = 3, prereq = 3, prereq_level = 2 },
    { id = 14, name = "元素爆发", desc = "元素攻击有15%几率触发范围伤害", branch = "offense", max_level = 2, prereq = 6, prereq_level = 1 },
    { id = 15, name = "致命节奏", desc = "连续攻击同一目标时，每次攻击伤害+3%（最多叠加5层）", branch = "offense", max_level = 3, prereq = 11, prereq_level = 2 },
    { id = 16, name = "嗜血狂战", desc = "生命值低于30%时，伤害额外+20%", branch = "offense", max_level = 2, prereq = 8, prereq_level = 1 },
    { id = 17, name = "毁灭之力", desc = "对Boss伤害+12%", branch = "offense", max_level = 2, prereq = 12, prereq_level = 2 },

    -- ========== 防御分支进阶 ==========
    { id = 18, name = "坚壁之心", desc = "受到的所有伤害减少6%", branch = "defense", max_level = 3, prereq = 1, prereq_level = 1 },
    { id = 19, name = "再生之血", desc = "每3秒恢复1点生命值", branch = "defense", max_level = 3, prereq = 1, prereq_level = 2 },
    { id = 20, name = "铁壁领域", desc = "站立不动2秒后，获得15%减伤护盾", branch = "defense", max_level = 2, prereq = 18, prereq_level = 2 },
    { id = 21, name = "不屈意志", desc = "受到致命伤害时，保留1点生命（冷却120秒）", branch = "defense", max_level = 1, prereq = 19, prereq_level = 1 },
    { id = 22, name = "寒冰护甲", desc = "被攻击时有10%几率冻结攻击者1秒", branch = "defense", max_level = 2, prereq = 18, prereq_level = 1 },
    { id = 23, name = "生命涌泉", desc = "生命上限额外+15%，生命回复效果+20%", branch = "defense", max_level = 2, prereq = 19, prereq_level = 2 },
    { id = 24, name = "守护之魂", desc = "附近队友受到的伤害减少4%", branch = "defense", max_level = 2, prereq = 20, prereq_level = 1 },

    -- ========== 辅助分支进阶 ==========
    { id = 25, name = "疾风步法", desc = "闪避率+8%", branch = "support", max_level = 3, prereq = 10, prereq_level = 1 },
    { id = 26, name = "战利品猎人", desc = "击杀精英时额外掉落1件物品", branch = "support", max_level = 2, prereq = 9, prereq_level = 1 },
    { id = 27, name = "时光回溯", desc = "技能冷却时间额外-10%，连杀窗口+0.8秒", branch = "support", max_level = 2, prereq = 10, prereq_level = 2 },
    { id = 28, name = "财富之眼", desc = "金币/宝石类物品掉落率+10%", branch = "support", max_level = 2, prereq = 26, prereq_level = 1 },
    { id = 29, name = "团队增益", desc = "附近队友伤害+4%，移速+3%", branch = "support", max_level = 2, prereq = 5, prereq_level = 2 },
    { id = 30, name = "命运编织", desc = "所有随机事件的好运率+8%", branch = "support", max_level = 2, prereq = 28, prereq_level = 1 },

    -- ========== 特殊分支进阶 ==========
    { id = 31, name = "暗影闪避", desc = "受到攻击时有6%几率瞬移至安全位置", branch = "special", max_level = 2, prereq = 7, prereq_level = 1 },
    { id = 32, name = "灵魂收割", desc = "击杀敌人时恢复2点理智值", branch = "special", max_level = 3, prereq = 7, prereq_level = 2 },
    { id = 33, name = "混沌之力", desc = "所有属性+3%，但受到伤害+5%", branch = "special", max_level = 2, prereq = nil, prereq_level = nil },
    { id = 34, name = "时空裂隙", desc = "每120秒可触发一次3秒无敌", branch = "special", max_level = 1, prereq = 31, prereq_level = 2 },
    { id = 35, name = "暗影分身", desc = "攻击时有5%几率召唤暗影分身协助战斗（持续5秒）", branch = "special", max_level = 2, prereq = 32, prereq_level = 1 },
    { id = 36, name = "命运逆转", desc = "受到的负面效果持续时间减少25%", branch = "special", max_level = 2, prereq = 33, prereq_level = 1 },
}

return M
