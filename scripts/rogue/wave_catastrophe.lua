--[[
    文件说明：wave_catastrophe.lua
    功能：异变天灾机制模块。
    负责在波次中生成和管理天灾环境（如酸雨、暗影扰动、猩红月蚀），对玩家施加持续负面效果（掉血、掉理智、雷击），并强化波次内敌人。
]]
local M = {}

-- 函数说明：按天数计算天灾阶段，并据此构建运行时参数。
local function BuildCatastropheRuntime(catastrophe, day)
    local tier = 1
    if day >= 40 then
        tier = 3
    elseif day >= 18 then
        tier = 2
    end
    return {
        tier = tier,
        tier_name = (tier == 1 and "初阶") or (tier == 2 and "中阶") or "末阶",
        sanity_drain = (catastrophe and catastrophe.sanity_drain or 0) * (tier == 1 and 0.9 or (tier == 2 and 1.15 or 1.4)),
        enemy_hp_mult = tier == 1 and 1.00 or (tier == 2 and 1.07 or 1.14),
        enemy_dmg_mult = tier == 1 and 1.00 or (tier == 2 and 1.06 or 1.12),
        moisture_scale = tier == 1 and 1.8 or (tier == 2 and 2.4 or 3.1),
        acid_period = tier == 1 and 8 or (tier == 2 and 6.5 or 5.5),
        moisture_delta = tier == 1 and 6 or (tier == 2 and 8 or 10),
        acid_threshold = tier == 1 and 35 or (tier == 2 and 30 or 26),
        acid_damage = tier == 1 and 1 or (tier == 2 and 1.5 or 2),
        shadow_period = tier == 1 and 4 or (tier == 2 and 3.2 or 2.6),
        lightning_period = tier == 1 and 10 or (tier == 2 and 8 or 6.5),
        lightning_near = tier == 1 and 4 or (tier == 2 and 3 or 2),
        lightning_far = tier == 1 and 8 or (tier == 2 and 9 or 10),
        moon_tint = tier == 1 and 0.22 or (tier == 2 and 0.30 or 0.38),
    }
end

function M.Create(deps)
    local S = {}

    -- 函数说明：按配置概率决定当天是否触发天灾。
    S.Roll = function(day)
        local chance = math.min(deps.CONST.CATASTROPHE_MAX_CHANCE, deps.CONST.CATASTROPHE_BASE_CHANCE + math.floor((day - 1) / 25) * 0.03)
        if math.random() > chance then
            return nil
        end
        return deps.CATASTROPHE_DEFS[math.random(#deps.CATASTROPHE_DEFS)]
    end

    S.BuildRuntime = function(catastrophe, day)
        return BuildCatastropheRuntime(catastrophe, day)
    end

    -- 函数说明：清理天灾环境任务与玩家视觉效果。
    S.ClearEnvironment = function(world, wave_state)
        if wave_state.catastrophe_env_task then
            wave_state.catastrophe_env_task:Cancel()
            wave_state.catastrophe_env_task = nil
        end
        for _, p in ipairs(deps.CollectAlivePlayers()) do
            if p.components and p.components.colouradder then
                p.components.colouradder:PopColour("rogue_catastrophe")
            end
        end
        if world then
            world:PushEvent("ms_setmoisturescale", 1)
            world:PushEvent("ms_forceprecipitation", false)
        end
    end

    -- 函数说明：根据当前天灾应用环境效果并创建周期任务。
    S.ApplyEnvironment = function(world, wave_state, is_wave_active)
        local c = wave_state.catastrophe
        local rt = wave_state.catastrophe_runtime
        if not world or not c or not rt then
            return
        end
        if c.id == 1 then
            world:PushEvent("ms_setmoisturescale", rt.moisture_scale)
            world:PushEvent("ms_forceprecipitation", true)
            wave_state.catastrophe_env_task = world:DoPeriodicTask(rt.acid_period, function()
                if not is_wave_active() or not wave_state.catastrophe or wave_state.catastrophe.id ~= 1 then return end
                for _, p in ipairs(deps.CollectAlivePlayers()) do
                    if p.components and p.components.moisture then
                        p.components.moisture:DoDelta(rt.moisture_delta)
                        if p.components.health and p.components.moisture:GetMoisture() >= rt.acid_threshold then
                            p.components.health:DoDelta(-rt.acid_damage, nil, "rogue_acidrain")
                        end
                    end
                    local fx = deps.SpawnPrefab("splash")
                    if fx then
                        local x, y, z = p.Transform:GetWorldPosition()
                        fx.Transform:SetPosition(x + (math.random() * 3 - 1.5), y, z + (math.random() * 3 - 1.5))
                    end
                end
            end)
        elseif c.id == 2 then
            for _, p in ipairs(deps.CollectAlivePlayers()) do
                if p.components and p.components.colouradder then
                    p.components.colouradder:PushColour("rogue_catastrophe", -0.08, -0.08, -0.02, 0)
                end
            end
            wave_state.catastrophe_env_task = world:DoPeriodicTask(rt.shadow_period, function()
                if not is_wave_active() or not wave_state.catastrophe or wave_state.catastrophe.id ~= 2 then return end
                for _, p in ipairs(deps.CollectAlivePlayers()) do
                    local fx = deps.SpawnPrefab("shadow_puff_large_front")
                    if fx then
                        local x, y, z = p.Transform:GetWorldPosition()
                        fx.Transform:SetPosition(x + (math.random() * 2 - 1), y, z + (math.random() * 2 - 1))
                    end
                end
            end)
        elseif c.id == 3 then
            for _, p in ipairs(deps.CollectAlivePlayers()) do
                if p.components and p.components.colouradder then
                    p.components.colouradder:PushColour("rogue_catastrophe", rt.moon_tint, -0.05, -0.05, 0)
                end
            end
            wave_state.catastrophe_env_task = world:DoPeriodicTask(rt.lightning_period, function()
                if not is_wave_active() or not wave_state.catastrophe or wave_state.catastrophe.id ~= 3 then return end
                local players = deps.CollectAlivePlayers()
                local target = deps.PickRandom(players)
                if target then
                    local pt = target:GetPosition()
                    local offset = deps.FindWalkableOffset(pt, math.random() * 2 * deps.PI, rt.lightning_near + math.random() * rt.lightning_far, 8, true, false)
                    world:PushEvent("ms_sendlightningstrike", offset and (pt + offset) or pt)
                end
            end)
        end
    end

    -- 函数说明：为天灾期间的敌人附加额外行为。
    S.ApplyEnemyBehavior = function(ent, wave_state, is_wave_active)
        local c = wave_state.catastrophe
        local rt = wave_state.catastrophe_runtime
        if not ent or not ent:IsValid() or not c or not rt then
            return
        end
        if c.id == 1 then
            if ent.components and ent.components.locomotor then
                local mult = 1 + 0.03 * rt.tier
                if ent.components.locomotor.walkspeed then
                    ent.components.locomotor.walkspeed = ent.components.locomotor.walkspeed * mult
                end
                if ent.components.locomotor.runspeed then
                    ent.components.locomotor.runspeed = ent.components.locomotor.runspeed * mult
                end
            end
            if not ent.rogue_catastrophe_onhit_moisture then
                ent.rogue_catastrophe_onhit_moisture = true
                ent:ListenForEvent("onhitother", function(inst, data)
                    if not inst:IsValid() or (inst.components.health and inst.components.health:IsDead()) then return end
                    if not is_wave_active() or not wave_state.catastrophe or wave_state.catastrophe.id ~= 1 then return end
                    local target = data and data.target
                    if target and target.components and target.components.moisture then
                        target.components.moisture:DoDelta(1 + rt.tier)
                    end
                end)
            end
        elseif c.id == 2 then
            if not ent.rogue_catastrophe_shadow_task then
                ent.rogue_catastrophe_shadow_task = ent:DoPeriodicTask(math.max(4, 7 - rt.tier), function(inst)
                    if not inst:IsValid() or not is_wave_active() or not wave_state.catastrophe or wave_state.catastrophe.id ~= 2 then return end
                    local target = deps.PickRandom(deps.CollectAlivePlayers())
                    if target and inst.components and inst.components.combat then
                        inst.components.combat:SetTarget(target)
                    end
                    local fx = deps.SpawnPrefab("shadow_puff_large_front")
                    if fx then
                        local x, y, z = inst.Transform:GetWorldPosition()
                        fx.Transform:SetPosition(x, y, z)
                    end
                end)
            end
        elseif c.id == 3 then
            if ent.components and ent.components.locomotor and not ent.rogue_catastrophe_crimson_task then
                ent.rogue_catastrophe_crimson_base_run = ent.components.locomotor.runspeed
                ent.rogue_catastrophe_crimson_task = ent:DoPeriodicTask(math.max(5, 9 - rt.tier), function(inst)
                    if not inst:IsValid() or not is_wave_active() or not wave_state.catastrophe or wave_state.catastrophe.id ~= 3 then return end
                    if inst.components and inst.components.locomotor then
                        local base = inst.rogue_catastrophe_crimson_base_run or inst.components.locomotor.runspeed
                        inst.components.locomotor.runspeed = base * (1.12 + rt.tier * 0.05)
                        inst:DoTaskInTime(1.6, function(inst2)
                            if inst2 and inst2:IsValid() and inst2.components and inst2.components.locomotor then
                                inst2.components.locomotor.runspeed = base
                            end
                        end)
                    end
                    local fx = deps.SpawnPrefab("statue_transition_2")
                    if fx then
                        local x, y, z = inst.Transform:GetWorldPosition()
                        fx.Transform:SetPosition(x, y, z)
                    end
                end)
            end
        end
    end

    return S
end

return M
