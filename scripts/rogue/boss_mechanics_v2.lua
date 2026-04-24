--[[
    文件说明：boss_mechanics_v2.lua
    功能：兼容包装层。
    核心实现已迁移至 boss_mechanics/state_hijack.lua 和 boss_mechanics/registry.lua。
    本文件保留以保证存量代码兼容性，所有调用透明转发到新模块。
]]
local M = {}

local Hijack = require("rogue/boss_mechanics/state_hijack")
local Registry = require("rogue/boss_mechanics/registry")

-- 兼容别名
M.DeepMechanicAffixes = Registry._affixes

-- 转发注册
function M.RegisterDeepAffix(id, def)
    return Registry.RegisterDeepAffix(id, def)
end

-- 转发应用
function M.ApplyDeepAffix(boss, affix_id, deps)
    return Registry.ApplyDeepAffix(boss, affix_id, deps, Hijack)
end

-- 直接暴露劫持API
M.HijackStateGraph = Hijack.HijackStateGraph
M.InjectNewState = Hijack.InjectNewState
M.HijackBrain = Hijack.HijackBrain

return M
