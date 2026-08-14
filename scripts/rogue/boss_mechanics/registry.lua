--[[
    文件说明：boss_mechanics/registry.lua
    功能：Boss深度机制词缀注册表。
    提供O(1)查找的注册与分发，替代boss_mechanics_v2.lua中的线性表查找。
    同时管理词缀的生命周期回调链(on_attach / on_health_delta / on_death)。
]]
local M = {}

-- 使用字典替代线性表，实现O(1)查找
M._affixes = {}
-- 按实例追踪已应用的词缀
M._active_instances = {}

-- 注册深度机制词缀
function M.RegisterDeepAffix(id, def)
    if type(id) ~= "string" or type(def) ~= "table" then
        print("[RogueBossRegistry] Invalid registration for id=" .. tostring(id))
        return false
    end
    M._affixes[id] = def
    return true
end

-- O(1)查找词缀定义
function M.GetAffix(id)
    return M._affixes[id]
end

-- 检查词缀是否已注册
function M.IsAffixRegistered(id)
    return M._affixes[id] ~= nil
end

-- 获取所有已注册词缀ID
function M.GetAllAffixIds()
    local ids = {}
    for id, _ in pairs(M._affixes) do
        table.insert(ids, id)
    end
    return ids
end

-- 应用深度词缀到Boss实例
function M.ApplyDeepAffix(boss, affix_id, deps, hijack_api)
    local affix_def = M._affixes[affix_id]
    if not affix_def then
        print("[RogueBossRegistry] Affix not found: " .. tostring(affix_id))
        return false
    end

    if boss._active_deep_affix then
        print("[RogueBossRegistry] Boss already has a deep affix: " .. tostring(boss._active_deep_affix))
        return false
    end

    boss._active_deep_affix = affix_id
    boss._rogue_deps = deps

    local SH = hijack_api or require("rogue/boss_mechanics/state_hijack")

    if affix_def.OnAttach then
        affix_def.OnAttach(boss, SH.HijackStateGraph, SH.InjectNewState, SH.HijackBrain)
    end

    if affix_def.OnHealthDelta then
        boss:ListenForEvent("healthdelta", function(inst, data)
            affix_def.OnHealthDelta(inst, data)
        end)
    end

    if affix_def.OnDeath then
        boss:ListenForEvent("death", function(inst, data)
            affix_def.OnDeath(inst, data)
        end)
    end

    M._active_instances[boss] = { affix_id = affix_id, callbacks = { affix_def.OnHealthDelta, affix_def.OnDeath } }

    return true
end

-- 清理实例追踪
function M.ClearInstance(boss)
    M._active_instances[boss] = nil
end

return M
