--[[
    文件说明：bootstrap/lifecycle.lua
    功能：生命周期管理模块。
    从runtime_system.lua独立，管理模组的 OnStart / OnServerStart / OnClientStart / OnStop 阶段调度。
    支持启动阶段之间的依赖检查和错误恢复。
]]
local M = {}

M._phases = {}
M._started = false
M._server_started = false
M._client_started = false

-- 注册生命周期阶段回调
function M.RegisterPhase(phase_name, callback, dependencies)
    if type(callback) ~= "function" then return false end
    M._phases[phase_name] = {
        callback = callback,
        dependencies = dependencies or {},
        executed = false,
    }
    return true
end

-- 执行某个生命周期阶段（带依赖检查）
function M.ExecutePhase(phase_name, deps)
    local phase = M._phases[phase_name]
    if not phase then
        print("[Lifecycle] Unknown phase: " .. tostring(phase_name))
        return false
    end
    for _, dep_name in ipairs(phase.dependencies) do
        local dep = M._phases[dep_name]
        if not dep or not dep.executed then
            print("[Lifecycle] Phase " .. tostring(phase_name) .. " skipped: dependency " .. tostring(dep_name) .. " not ready")
            return false
        end
    end
    local ok, err = pcall(phase.callback, deps)
    if not ok then
        print("[Lifecycle] Phase " .. tostring(phase_name) .. " failed: " .. tostring(err))
        return false
    end
    phase.executed = true
    return true
end

-- 模组启动（OnStart）
function M.OnStart(deps)
    if M._started then return end
    M._started = true
    for phase_name, _ in pairs(M._phases) do
        if not M._phases[phase_name].executed then
            M.ExecutePhase(phase_name, deps)
        end
    end
end

-- 服务端启动
function M.OnServerStart(deps)
    if M._server_started then return end
    M._server_started = true
end

-- 客户端启动
function M.OnClientStart(deps)
    if M._client_started then return end
    M._client_started = true
end

-- 模组停止（OnStop）
function M.OnStop(deps)
    M._started = false
    M._server_started = false
    M._client_started = false
    for _, phase in pairs(M._phases) do
        phase.executed = false
    end
end

return M
