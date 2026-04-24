local M = {}
local catalog = require("pool_catalog")
local helpers = require("rogue/helpers")

local dynamic_recycle_values = nil
local dynamic_shop_pool = nil
local dynamic_black_market_pool = nil

-- 函数说明：黑市服务定义，不再出售商品，改为提供能力重铸和属性升级服务。
-- 玩家将武器/装备放入黑市场景格子，消耗积分+生命/理智来随机更换能力或升级属性。
local BLACK_MARKET_DEFS = {
    { id = "bm_reforge", service = "reforge", cost = 15, hp_cost = 0.05, sanity_cost = 0.05, desc = "重铸：消耗资源随机更换武器/装备的能力" },
    { id = "bm_upgrade", service = "upgrade", cost = 20, hp_cost = 0.08, sanity_cost = 0, desc = "强化：消耗资源随机升级武器/装备的属性" },
}

-- 函数说明：黑市属性升级定义表，定义可升级的属性类型和数值范围。
local BLACK_MARKET_UPGRADE_DEFS = {
    weapon = {
        { id = "damage_bonus", name = "攻击力", min_val = 2, max_val = 5, weight = 30, desc = "提升武器基础伤害" },
        { id = "attack_speed", name = "攻速", min_val = 0.02, max_val = 0.05, weight = 20, desc = "提升攻击速度" },
        { id = "crit_chance", name = "暴击率", min_val = 0.02, max_val = 0.05, weight = 15, desc = "提升暴击概率" },
        { id = "lifesteal", name = "吸血", min_val = 1, max_val = 3, weight = 10, desc = "攻击时恢复生命值" },
    },
    armor = {
        { id = "defense_bonus", name = "防御力", min_val = 0.02, max_val = 0.05, weight = 30, desc = "提升护甲减伤比例" },
        { id = "max_hp_bonus", name = "生命加成", min_val = 5, max_val = 15, weight = 25, desc = "装备时增加最大生命值" },
        { id = "regen_bonus", name = "回复", min_val = 0.5, max_val = 1.5, weight = 15, desc = "装备时持续恢复生命" },
        { id = "thorns", name = "反伤", min_val = 0.02, max_val = 0.05, weight = 10, desc = "受击时反弹伤害" },
    },
    equippable = {
        { id = "speed_bonus", name = "移速", min_val = 0.03, max_val = 0.08, weight = 25, desc = "装备时提升移动速度" },
        { id = "sanity_regen", name = "理智回复", min_val = 1, max_val = 3, weight = 20, desc = "装备时持续恢复理智" },
        { id = "insulation_bonus", name = "保温", min_val = 30, max_val = 60, weight = 20, desc = "提升保暖/隔热值" },
        { id = "dodge_chance", name = "闪避", min_val = 0.02, max_val = 0.04, weight = 10, desc = "有概率闪避攻击" },
    },
}

-- 函数说明：获取黑市属性升级定义表。
function M.GetBlackMarketUpgradeDefs()
    return BLACK_MARKET_UPGRADE_DEFS
end

-- 函数说明：季节限定商品，仅在对应季节出现。所有商品均不在普通商店掉落池中。
local SEASONAL_SHOP_DEFS = {
    { id = "ss_heatrock", prefab = "heatrock", cost = 8, season = "winter", weight = 15, count = 2, desc = "暖石（冬季限定）" },
    { id = "ss_winterhat", prefab = "winterhat", cost = 12, season = "winter", weight = 12, count = 1, desc = "冬帽（冬季限定）" },
    { id = "ss_ice", prefab = "ice", cost = 5, season = "summer", weight = 15, count = 3, desc = "冰块（夏季限定）" },
    { id = "ss_floralshirt", prefab = "floralshirt", cost = 14, season = "summer", weight = 10, count = 1, desc = "花衬衫（夏季限定）" },
    { id = "ss_rainhat", prefab = "rainhat", cost = 10, season = "spring", weight = 14, count = 1, desc = "雨帽（春季限定）" },
}

-- 函数说明：每种商品的每日限购数量配置。
local PURCHASE_LIMITS = {
    default = 3,
    hambat = 2,
    armorwood = 2,
    armorgrass = 3,
    spear = 3,
    torch = 5,
    healingsalve = 4,
    bandage = 3,
    meatballs = 5,
    spidergland = 3,
}

-- 函数说明：获取指定商品的每日限购数量。
function M.GetPurchaseLimit(prefab)
    return PURCHASE_LIMITS[prefab] or PURCHASE_LIMITS.default
end

-- 函数说明：获取黑市服务列表（重铸和强化）。
function M.GetBlackMarketItems()
    if not dynamic_black_market_pool then
        dynamic_black_market_pool = {}
        for _, def in ipairs(BLACK_MARKET_DEFS) do
            table.insert(dynamic_black_market_pool, def)
        end
    end
    return dynamic_black_market_pool
end

-- 函数说明：获取当天折扣信息，返回折扣商品id和折扣比例的映射表。
-- 使用 PRNG_Uniform 替代 math.randomseed，不污染全局 RNG 状态。
function M.GetDailyDiscounts()
    local day = (TheWorld and TheWorld.state and TheWorld.state.cycles) or 1
    local prng = helpers.CreateDailyPRNG(day, 2048)

    local discounts = {}
    local shop_items = M.GetDailyShopItems()
    local discount_count = prng:RandInt(1, 3)
    local candidates = {}
    for _, item in ipairs(shop_items) do
        table.insert(candidates, item.id)
    end

    for _ = 1, discount_count do
        if #candidates == 0 then break end
        local idx = prng:RandInt(1, #candidates)
        local id = candidates[idx]
        local pct = prng:RandInt(2, 4) * 0.1
        discounts[id] = pct
        table.remove(candidates, idx)
    end

    return discounts
end

-- 函数说明：获取当前季节对应的限定商品列表。
-- 使用 PRNG_Uniform 替代 math.randomseed，不污染全局 RNG 状态。
function M.GetSeasonalItems()
    local season = (TheWorld and TheWorld.state and TheWorld.state.season) or "autumn"
    local day = (TheWorld and TheWorld.state and TheWorld.state.cycles) or 1

    local items = {}
    for _, def in ipairs(SEASONAL_SHOP_DEFS) do
        if def.season == season then
            table.insert(items, def)
        end
    end

    if #items <= 2 then return items end

    local prng = helpers.CreateDailyPRNG(day, 7777)
    return helpers.PickNWeightedWithPRNG(prng, items, 2)
end

local function InitDynamicData(variant)
    dynamic_recycle_values = {}
    dynamic_shop_pool = {}
    dynamic_black_market_pool = nil

    local function AddToPools(drop_type, default_val)
        local target_type = drop_type
        if variant == "shipwrecked" then
            target_type = drop_type .. "_SHIPWRECKED"
        elseif variant == "hamlet" then
            target_type = drop_type .. "_HAMLET"
        end

        local list = catalog.POOLS[target_type] or catalog.POOLS[drop_type]
        if list then
            for _, item in ipairs(list) do
                local prefab = item.prefab

                if not dynamic_recycle_values[prefab] then
                    local val = default_val
                    if item.tier_hint == "endgame" then val = 25
                    elseif item.tier_hint == "late" then val = 15
                    elseif item.tier_hint == "mid" then val = 8
                    elseif item.tier_hint == "early" then val = 3
                    end
                    dynamic_recycle_values[prefab] = val
                end

                local cost = dynamic_recycle_values[prefab] * 2
                if cost < 5 then cost = 5 end

                table.insert(dynamic_shop_pool, {
                    id = prefab,
                    prefab = prefab,
                    cost = cost,
                    weight = item.weight or 10,
                    count = item.count and item.count[1] or 1
                })
            end
        end
    end

    AddToPools("DROPS_NORMAL", 1)
    AddToPools("DROPS_BOSS_MATS", 5)
    AddToPools("DROPS_BOSS_GEAR", 10)
end

-- 函数说明：获取当天的商店列表（最多15个），含季节商品。
-- 使用 PRNG_Uniform 替代 math.randomseed，不污染全局 RNG 状态。
function M.GetDailyShopItems()
    local day = (TheWorld and TheWorld.state and TheWorld.state.cycles) or 1
    local variant = catalog.GetWorldVariant()

    if not dynamic_shop_pool then
        InitDynamicData(variant)
    end

    local prng = helpers.CreateDailyPRNG(day, 9527)
    local items = helpers.PickNWeightedWithPRNG(prng, dynamic_shop_pool, 15)

    local seasonal = M.GetSeasonalItems()
    for _, s in ipairs(seasonal) do
        local already = false
        for _, existing in ipairs(items) do
            if existing.id == s.id then already = true; break end
        end
        if not already then
            table.insert(items, s)
        end
    end

    return items
end

function M.InitVariant(variant)
    catalog.SetWorldVariant(variant)
    InitDynamicData(variant)
end

function M.GetRecycleValue(prefab)
    if not dynamic_recycle_values then
        InitDynamicData(catalog.GetWorldVariant())
    end
    return dynamic_recycle_values[prefab] or 0
end

-- 函数说明：根据游戏天数对基础价格应用日增长系数，实现渐进式经济系统
-- day=1 时倍率 1.0，每天增长 0.3%，即 day=30 时约 +9%、day=60 时约 +18%
function M.GetDayAdjustedCost(base_cost, day)
    day = day or 1
    local day_factor = 1 + (day - 1) * 0.003
    return math.max(1, math.ceil(base_cost * day_factor))
end

return M
