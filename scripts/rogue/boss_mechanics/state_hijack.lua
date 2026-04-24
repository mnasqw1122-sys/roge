--[[
    文件说明：boss_mechanics/state_hijack.lua
    功能：深层次StateGraph/Brain劫持工具模块。
    从boss_mechanics_v2.lua提取，提供HijackStateGraph、InjectNewState、HijackBrain三个核心API。
    这是Boss机制深度侵入的基础设施。
]]
local GLOBAL = _G or GLOBAL

local M = {}

-- 拦截StateGraph —— 在Boss原有的状态动画中插入自定义Timeline帧事件，或重写状态的OnEnter/OnExit
function M.HijackStateGraph(inst, state_name, injection_fns)
    if not inst.sg or not inst.sg.sg or not inst.sg.sg.states[state_name] then
        print("[RogueBossV2] Failed to hijack SG state: " .. tostring(state_name) .. " on " .. tostring(inst.prefab))
        return false
    end

    local target_state = inst.sg.sg.states[state_name]

    if injection_fns.onenter then
        local old_onenter = target_state.onenter
        target_state.onenter = function(self_inst, data)
            if old_onenter then old_onenter(self_inst, data) end
            injection_fns.onenter(self_inst, data)
        end
    end

    if injection_fns.onexit then
        local old_onexit = target_state.onexit
        target_state.onexit = function(self_inst)
            if old_onexit then old_onexit(self_inst) end
            injection_fns.onexit(self_inst)
        end
    end

    if injection_fns.timeline_injections then
        for _, frame_data in ipairs(injection_fns.timeline_injections) do
            table.insert(target_state.timeline, GLOBAL.TimeEvent(frame_data.time, frame_data.fn))
        end
        table.sort(target_state.timeline, function(a, b) return a.time < b.time end)
    end

    return true
end

-- 注入新动作节点 —— 动态为Boss的StateGraph添加一个全新的State
function M.InjectNewState(inst, new_state_def)
    if not inst.sg or not inst.sg.sg then return false end
    inst.sg.sg.states[new_state_def.name] = new_state_def
    return true
end

-- 劫持行为树(Brain) —— 拦截Boss的行为树逻辑，挂载高优先级强制行为节点
function M.HijackBrain(inst, new_action_fn, priority_name)
    if not inst._rogue_brain_hijacks then inst._rogue_brain_hijacks = {} end
    inst._rogue_brain_hijacks[priority_name] = new_action_fn
end

return M
