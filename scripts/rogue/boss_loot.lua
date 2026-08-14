--[[
    文件说明：boss_loot.lua
    功能：定义各类Boss的专属战利品掉落池。
    提供Boss到战利品权重表的映射与查询接口，并处理不同形态Boss（如变异巨鹿）的掉落别名转换。
]]
local M = {}

local BOSS_LOOT = {
    deerclops = {
        { prefab = "eyebrellahat", weight = 50 },
        { prefab = "blueamulet", weight = 35 },
        { prefab = "icestaff", weight = 15 },
    },
    bearger = {
        { prefab = "armorskeleton", weight = 40 },
        { prefab = "hambat", weight = 35 },
        { prefab = "beargervest", weight = 25 },
    },
    moose = {
        { prefab = "goose_feather", weight = 45 },
        { prefab = "waterballoon", weight = 35 },
        { prefab = "weatherpain", weight = 20 },
    },
    dragonfly = {
        { prefab = "armordragonfly", weight = 45 },
        { prefab = "lavae_egg", weight = 30 },
        { prefab = "yellowstaff", weight = 25 },
    },
    klaus = {
        { prefab = "krampus_sack", weight = 25 },
        { prefab = "orangeamulet", weight = 35 },
        { prefab = "nightsword", weight = 40 },
    },
    beequeen = {
        { prefab = "hivehat", weight = 45 },
        { prefab = "royal_jelly", weight = 35 },
        { prefab = "bundlewrap_blueprint", weight = 20 },
    },
    eyeofterror = {
        { prefab = "shieldofterror", weight = 40 },
        { prefab = "eyemaskhat", weight = 35 },
        { prefab = "yellowamulet", weight = 25 },
    },
    daywalker = {
        { prefab = "voidclothhat", weight = 35 },
        { prefab = "armor_voidcloth", weight = 35 },
        { prefab = "dreadstonehat", weight = 30 },
    },
    daywalker2 = {
        { prefab = "dreadstonehat", weight = 35 },
        { prefab = "armordreadstone", weight = 35 },
        { prefab = "armor_voidcloth", weight = 30 },
    },
    alterguardian = {
        { prefab = "opalstaff", weight = 35 },
        { prefab = "moonstorm_goggleshat", weight = 35 },
        { prefab = "alterguardianhat", weight = 30 },
    },
}

local ALIAS = {
    mutateddeerclops = "deerclops",
    mutatedbearger = "bearger",
    alterguardian_phase1 = "alterguardian",
    alterguardian_phase2 = "alterguardian",
    alterguardian_phase3 = "alterguardian",
}

function M.ResolveKey(raw_key)
    local key = raw_key or ""
    return ALIAS[key] or key
end

function M.GetPool(raw_key)
    local key = M.ResolveKey(raw_key)
    return BOSS_LOOT[key], key
end

return M
