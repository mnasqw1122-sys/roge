--[[
    文件说明：wave_boss_compat.lua
    功能：Boss兼容性模块。
    用于修复或调整部分原版Boss（如克劳斯、熊獾、蚁狮等）在肉鸽波次生成时的仇恨丢失、休眠等问题，并管理试炼Boss的超时消散机制。
]]
local M = {}

function M.Create(deps)
    local S = {}

    -- 函数说明：为试炼 Boss 添加超时回收，避免长期占用战场资源。
    S.AttachTrialBossTimeout = function(ent)
        if not ent or not ent:IsValid() then return end
        local now = (deps.GetTime and deps.GetTime() or 0)
        ent.rogue_trial_last_player_hit = now
        if not ent.rogue_trial_hit_listener then
            ent.rogue_trial_hit_listener = true
            ent:ListenForEvent("attacked", function(inst, data)
                local attacker = data and data.attacker
                if deps.IsValidPlayer(attacker) then
                    inst.rogue_trial_last_player_hit = (deps.GetTime and deps.GetTime() or 0)
                end
            end)
        end
        if not ent.rogue_trial_timeout_task then
            ent.rogue_trial_timeout_task = ent:DoPeriodicTask(5, function(inst)
                if not inst:IsValid() or (inst.components.health and inst.components.health:IsDead()) then return end
                if not inst:HasTag("rogue_trial_boss") then return end
                local t = deps.GetTime and deps.GetTime() or 0
                local last = inst.rogue_trial_last_player_hit or t
                if t - last >= 60 then
                    deps.Announce("挑战房试炼Boss因无人攻击已消散。")
                    inst:Remove()
                end
            end)
            ent:ListenForEvent("onremove", function(inst)
                if inst.rogue_trial_timeout_task then
                    inst.rogue_trial_timeout_task:Cancel()
                    inst.rogue_trial_timeout_task = nil
                end
            end)
        end
    end

    -- 函数说明：持续强制 Boss 保持仇恨，避免脱战或休眠导致流程中断。
    local function AttachForcedAggro(ent)
        if not ent or not ent:IsValid() or ent.rogue_forced_aggro_task then return end
        ent.rogue_forced_aggro_task = ent:DoPeriodicTask(2, function(inst)
            if not inst:IsValid() or (inst.components.health and inst.components.health:IsDead()) then return end
            local p = deps.PickRandom(deps.CollectAlivePlayers())
            if p and p:IsValid() and inst.components and inst.components.combat then
                inst.components.combat:SetTarget(p)
            end
            if inst.prefab == "moose" then
                inst.shouldGoAway = false
            end
            if inst.prefab == "bearger" then
                inst:RemoveTag("hibernation")
                if inst.components and inst.components.sleeper then
                    inst.components.sleeper:WakeUp()
                end
            end
            if inst.prefab == "antqueen" then
                if inst.components and inst.components.sleeper then
                    inst.components.sleeper:SetSleepTest(function() return false end)
                    inst.components.sleeper:SetWakeTest(function() return true end)
                    inst.components.sleeper:WakeUp()
                end
                if inst.sg and (inst.sg:HasStateTag("sleeping") or inst.sg.currentstate and inst.sg.currentstate.name == "sleep") then
                    inst.sg:GoToState("wake")
                end
            end
        end)
        ent:ListenForEvent("onremove", function(inst)
            if inst.rogue_forced_aggro_task then
                inst.rogue_forced_aggro_task:Cancel()
                inst.rogue_forced_aggro_task = nil
            end
        end)
    end

    -- 函数说明：应用 Boss 兼容性修补，保证特殊 Boss 在波次里正常战斗。
    S.ApplyBossCompatibility = function(ent, is_trial_boss)
        if not ent or not ent:IsValid() then return end
        if ent.prefab == "moose" then
            ent.shouldGoAway = false
            AttachForcedAggro(ent)
        elseif ent.prefab == "klaus" then
            if not ent.rogue_klaus_deer_spawned and ent.SpawnDeer then
                ent.rogue_klaus_deer_spawned = true
                ent:DoTaskInTime(0.2, function(inst)
                    if inst:IsValid() and inst.SpawnDeer and not (inst.components.health and inst.components.health:IsDead()) then
                        inst:SpawnDeer()
                    end
                end)
            end
        elseif ent.prefab == "bearger" then
            if ent.components and ent.components.sleeper then
                ent.components.sleeper:SetSleepTest(function() return false end)
                ent.components.sleeper:SetWakeTest(function() return true end)
                ent.components.sleeper:WakeUp()
            end
            ent:RemoveTag("hibernation")
            AttachForcedAggro(ent)
        elseif ent.prefab == "antqueen" then
            if ent.components and ent.components.sleeper then
                ent.components.sleeper:SetSleepTest(function() return false end)
                ent.components.sleeper:SetWakeTest(function() return true end)
                ent.components.sleeper:WakeUp()
            end
            if ent.sg and (ent.sg:HasStateTag("sleeping") or ent.sg.currentstate and ent.sg.currentstate.name == "sleep") then
                ent.sg:GoToState("wake")
            end
            AttachForcedAggro(ent)
        end
        if is_trial_boss and ent.prefab == "klaus" and ent.SpawnDeer then
            ent.rogue_klaus_deer_spawned = true
        end
    end

    return S
end

return M
