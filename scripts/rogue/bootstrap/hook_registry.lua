--[[
    文件说明：bootstrap/hook_registry.lua
    功能：全局钩子统一注册模块。
    从runtime_system.lua独立，统一管理DST引擎的注入点：
    AddPlayerPostInit, AddPrefabPostInit, AddComponentPostInit, AddModRPCHandler等。
    提供记录-回放机制，便于调试和热更新。
]]
local M = {}

M._hooks = {}
M._player_post_inits = {}
M._prefab_post_inits = {}
M._component_actions = {}
M._rpc_handlers = {}

-- 注册一个玩家创建后处理钩子
function M.RegisterPlayerPostInit(fn, priority)
    if type(fn) ~= "function" then return false end
    table.insert(M._player_post_inits, { fn = fn, priority = priority or 50 })
    return true
end

-- 注册一个预制体创建后处理钩子
function M.RegisterPrefabPostInit(prefab_name, fn)
    if type(prefab_name) ~= "string" or type(fn) ~= "function" then return false end
    M._prefab_post_inits[prefab_name] = M._prefab_post_inits[prefab_name] or {}
    table.insert(M._prefab_post_inits[prefab_name], fn)
    return true
end

-- 注册一个组件后处理钩子
function M.RegisterComponentPostInit(component_name, fn)
    if type(component_name) ~= "string" or type(fn) ~= "function" then return false end
    M._component_actions[component_name] = M._component_actions[component_name] or {}
    table.insert(M._component_actions[component_name], fn)
    return true
end

-- 注册RPC处理器
function M.RegisterRPCHandler(namespace, name, handler)
    if type(handler) ~= "function" then return false end
    M._rpc_handlers[name] = { namespace = namespace, handler = handler }
    return true
end

-- 在DST引擎中实际应用所有已注册的钩子
function M.ApplyAllHooks(deps)
    local G = deps.GLOBAL or _G

    -- 应用玩家后处理钩子
    for _, entry in ipairs(M._player_post_inits) do
        G.AddPlayerPostInit(entry.fn)
    end

    -- 应用预制体后处理钩子
    for prefab_name, fns in pairs(M._prefab_post_inits) do
        for _, fn in ipairs(fns) do
            G.AddPrefabPostInit(prefab_name, fn)
        end
    end

    -- 应用组件后处理钩子
    for component_name, fns in pairs(M._component_actions) do
        for _, fn in ipairs(fns) do
            G.AddComponentPostInit(component_name, fn)
        end
    end

    -- 应用RPC处理器（延迟注册，namespace通过闭包注入）
    for name, entry in pairs(M._rpc_handlers) do
        G.AddModRPCHandler(entry.namespace, name, entry.handler)
    end
end

return M
