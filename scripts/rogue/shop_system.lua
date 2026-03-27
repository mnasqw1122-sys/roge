--[[
    文件说明：shop_system.lua
    功能：肉鸽模式的商店系统。
    处理玩家在商店中购买物品以及回收掉落物的服务端逻辑。
]]
local M = {}
local ShopConfig = require("rogue/shop_config")

function M.Create(deps)
    local S = {}

    -- 玩家请求购买物品
    S.BuyItem = function(player, item_id)
        if not player or not player:IsValid() then return end
        local d = deps.EnsurePlayerData(player)
        
        -- 查找商品配置
        local item_def = nil
        for _, v in ipairs(ShopConfig.GetDailyShopItems()) do
            if v.id == item_id then
                item_def = v
                break
            end
        end

        if not item_def then
            deps.Announce(player.name .. " 尝试购买未知的商品。")
            return
        end

        local current_points = d.points or 0
        if current_points < item_def.cost then
            if player.components.talker then
                player.components.talker:Say("积分不足，需要 " .. item_def.cost .. " 积分。")
            end
            return
        end

        -- 扣除积分
        d.points = current_points - item_def.cost
        if player.rogue_points then
            player.rogue_points:set(d.points)
        end

        -- 给予物品
        local count = item_def.count or 1
        if player.components.inventory then
            for i = 1, count do
                local item = deps.SpawnPrefab(item_def.prefab)
                if item then
                    player.components.inventory:GiveItem(item)
                end
            end
        end

        if player.components.talker then
            player.components.talker:Say("购买成功！剩余积分: " .. d.points)
        end
    end

    -- 玩家请求回收物品
    S.RecycleItem = function(player, prefab)
        if not player or not player:IsValid() or not player.components.inventory then return end
        
        local value = ShopConfig.GetRecycleValue(prefab)
        if value <= 0 then
            if player.components.talker then
                player.components.talker:Say("这个物品无法回收获取积分。")
            end
            return
        end

        -- 在玩家背包中查找该物品并移除
        if not player.components.inventory:Has(prefab, 1) then
            if player.components.talker then
                player.components.talker:Say("背包中没有找到该物品。")
            end
            return
        end

        player.components.inventory:ConsumeByName(prefab, 1)

        -- 增加积分
        local d = deps.EnsurePlayerData(player)
        d.points = (d.points or 0) + value
        if player.rogue_points then
            player.rogue_points:set(d.points)
        end

        if player.components.talker then
            player.components.talker:Say("回收成功！获得 " .. value .. " 积分。当前积分: " .. d.points)
        end
    end

    return S
end

return M
