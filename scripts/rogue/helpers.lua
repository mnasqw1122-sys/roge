--[[
    文件说明：helpers.lua
    功能：提供一组通用辅助函数。
    包含预制体名称清理、验证、别名解析、实体过滤、加权随机选择等基础工具方法。
]]
local M = {}

-- 清理并格式化预制体名称，去除首尾空格
function M.SanitizePrefabName(prefab)
    if type(prefab) ~= "string" then return nil end
    local cleaned = prefab:gsub("^%s+", ""):gsub("%s+$", "")
    return cleaned ~= "" and cleaned or nil
end

-- 检查预制体是否已在全局注册（容错处理）
function M.IsPrefabRegistered(prefab, prefabs)
    return type(prefab) == "string" and prefab ~= "" and (prefabs == nil or prefabs[prefab] ~= nil)
end

-- 解析运行时的真实预制体名称（处理配置中的别名映射）
function M.ResolveRuntimePrefab(prefab, aliases, prefabs)
    if not M.IsPrefabRegistered(prefab, prefabs) then
        local alias = aliases and aliases[prefab] or nil
        if alias and M.IsPrefabRegistered(alias, prefabs) then return alias end
        return nil
    end
    return prefab
end

-- 根据权重从奖池中随机抽取一个候选项
function M.PickWeightedCandidate(pool, total_weight)
    if not pool or #pool == 0 or total_weight <= 0 then return nil end
    local roll = math.random() * total_weight
    local current = 0
    for _, item in ipairs(pool) do
        current = current + (item.weight or 10)
        if roll <= current then
            return item
        end
    end
    return pool[#pool]
end

-- 检查玩家是否是合法存活状态
function M.IsValidPlayer(player)
    return player ~= nil and player:IsValid() and player.components ~= nil and player.components.health ~= nil and not player.components.health:IsDead()
end

-- 收集当前世界中所有存活的玩家
function M.CollectAlivePlayers(all_players)
    local players = {}
    for _, player in ipairs(all_players or {}) do
        if M.IsValidPlayer(player) then
            table.insert(players, player)
        end
    end
    return players
end

-- 从列表中随机挑选一个元素
function M.PickRandom(list)
    if not list or #list == 0 then return nil end
    return list[math.random(#list)]
end

-- 根据范围对象 {min, max} 随机生成一个数值
function M.RollRange(range)
    return range.min + math.random() * (range.max - range.min)
end

-- 获取实体的本地化显示名称，如果没有则回退到 prefab 名字
function M.GetEntityName(ent)
    if not ent or not ent.prefab then return "未知目标" end
    if ent.GetDisplayName then
        local name = ent:GetDisplayName()
        if name and name ~= "" then return name end
    end
    if ent.name and ent.name ~= "" then return ent.name end
    return ent.prefab
end

return M
