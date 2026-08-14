--[[
    文件说明：set_bonus_defs.lua
    功能：套装效果定义数据，从config.lua拆分而来。
]]
local M = {}

M.SET_BONUS_DEFS = {
    {
        set_tag = "ruins_set",
        name = "远古守护",
        pieces = { body = "armorruins", head = "ruinshat" },
        threshold = 2,
        bonuses = {
            [2] = { desc = "2件：受到伤害降低15%", dmg_taken_mult = 0.85 },
        }
    },
    {
        set_tag = "dragon_set",
        name = "龙焰之心",
        pieces = { body = "armordragonfly", hand = "nightsword" },
        threshold = 2,
        bonuses = {
            [2] = { desc = "2件：攻击有25%几率点燃敌人", ignite_chance = 0.25 },
        }
    },
    {
        set_tag = "shadow_set",
        name = "暗影契约",
        pieces = { body = "armor_sanity", hand = "nightsword" },
        threshold = 2,
        bonuses = {
            [2] = { desc = "2件：暗影伤害+20%，理智消耗减半", shadow_dmg_bonus = 0.20, sanity_cost_mult = 0.5 },
        }
    },
    {
        set_tag = "dreadstone_set",
        name = "绝望壁垒",
        pieces = { body = "armordreadstone", head = "dreadstonehat" },
        threshold = 2,
        bonuses = {
            [2] = { desc = "2件：每秒恢复2点生命值", regen_per_sec = 2 },
        }
    },
    {
        set_tag = "void_set",
        name = "虚空行者",
        pieces = { body = "armor_voidcloth", head = "voidclothhat" },
        threshold = 2,
        bonuses = {
            [2] = { desc = "2件：移动速度+15%，攻击速度+10%", speed_bonus = 0.15, atk_speed_bonus = 0.10 },
        }
    },
    {
        set_tag = "lunar_set",
        name = "月光庇佑",
        pieces = { body = "armor_lunarplant", head = "lunarplanthat" },
        threshold = 2,
        bonuses = {
            [2] = { desc = "2件：受到的月光伤害免疫，理智恢复+30%", lunar_immune = true, sanity_regen_bonus = 0.30 },
        }
    },
    {
        set_tag = "battle_set",
        name = "战神武装",
        pieces = { body = "armorwood", head = "footballhat", hand = "hambat" },
        threshold = 2,
        bonuses = {
            [2] = { desc = "2件：伤害+10%", dmg_bonus = 0.10 },
            [3] = { desc = "3件：伤害+10%，连杀窗口+1秒", dmg_bonus = 0.10, combo_window = 1.0 },
        }
    },
    {
        set_tag = "survival_set",
        name = "求生本能",
        pieces = { body = "armormarble", head = "beefalohat" },
        threshold = 2,
        bonuses = {
            [2] = { desc = "2件：最大生命+50，饥饿消耗-20%", hp_bonus = 50, hunger_drain_mult = 0.80 },
        }
    },
}

return M
