local M = {}
local catalog = require("pool_catalog")

-- 动态获取回收价值
local dynamic_recycle_values = nil
local dynamic_shop_pool = nil

local function InitDynamicData(variant)
    dynamic_recycle_values = {}
    dynamic_shop_pool = {}
    
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
                
                -- 设置回收价值
                if not dynamic_recycle_values[prefab] then
                    local val = default_val
                    if item.tier_hint == "endgame" then val = 25
                    elseif item.tier_hint == "late" then val = 15
                    elseif item.tier_hint == "mid" then val = 8
                    elseif item.tier_hint == "early" then val = 3
                    end
                    dynamic_recycle_values[prefab] = val
                end
                
                -- 加入商店备选池 (成本大致为回收价值的2-3倍)
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

-- 获取当天的商店列表 (最多15个)
function M.GetDailyShopItems()
    -- 修复：客户端无法获取 TheWorld.components.worldstate，导致天数始终为 1
    -- 改用 TheWorld.state.cycles 确保多端获取到的天数一致，从而保证商店池和随机数一致
    local day = (TheWorld and TheWorld.state and TheWorld.state.cycles) or 1
    local variant = catalog.GetWorldVariant()
    
    if not dynamic_shop_pool then
        InitDynamicData(variant)
    end
    
    -- 使用天数作为随机种子，保证所有玩家/服务端看到的商品一致
    math.randomseed(day + 9527)
    
    local items = {}
    local pool_copy = {}
    for _, v in ipairs(dynamic_shop_pool) do
        table.insert(pool_copy, v)
    end
    
    -- 随机抽取15个
    for i = 1, 15 do
        if #pool_copy == 0 then break end
        local total_weight = 0
        for _, v in ipairs(pool_copy) do
            total_weight = total_weight + v.weight
        end
        
        local r = math.random() * total_weight
        local cur = 0
        local selected_idx = 1
        for idx, v in ipairs(pool_copy) do
            cur = cur + v.weight
            if r <= cur then
                selected_idx = idx
                break
            end
        end
        
        table.insert(items, pool_copy[selected_idx])
        table.remove(pool_copy, selected_idx)
    end
    
    -- 恢复随机种子
    math.randomseed(os.time())
    
    return items
end

-- 初始化商店物品配置，根据变体重新生成
function M.InitVariant(variant)
    catalog.SetWorldVariant(variant)
    InitDynamicData(variant)
end

-- 获取物品的回收积分
function M.GetRecycleValue(prefab)
    if not dynamic_recycle_values then
        InitDynamicData(catalog.GetWorldVariant())
    end
    return dynamic_recycle_values[prefab] or 0
end

return M
