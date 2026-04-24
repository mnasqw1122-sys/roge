--[[
    文件说明：coop_system.lua
    功能：多人协作机制模块。
    包含近距离协作增益、复活互助、协作事件三大子系统。
    当队友在附近时自动触发增益效果，支持复活互助和协作挑战事件。
]]
local M = {}

function M.Create(deps)
    local S = {}
    local coop_buffs = deps.COOP_BUFF_DEFS
    local revive_cost = deps.COOP_REVIVE_COST
    local active_coop_events = {}

    -- 预构建buff查表：buff_id → buff_def，将O(n)线性查找优化为O(1)
    local BUFF_LOOKUP = {}
    if coop_buffs and coop_buffs.buffs then
        for _, b in ipairs(coop_buffs.buffs) do
            BUFF_LOOKUP[b.id] = b
        end
    end

    -- 函数说明：获取指定玩家附近的存活队友数量和列表。
    local function GetNearbyAllies(player, range)
        if not player or not player:IsValid() then return 0, {} end
        local px, py, pz = player.Transform:GetWorldPosition()
        local nearby = deps.GLOBAL.TheSim:FindEntities(px, py, pz, range, {"player"}, {"playerghost", "INLIMBO"})
        local allies = {}
        for _, ent in ipairs(nearby) do
            if ent ~= player and ent:IsValid() and not ent:HasTag("playerghost") then
                table.insert(allies, ent)
            end
        end
        return #allies, allies
    end

    -- 函数说明：为玩家应用协作增益效果（BUFF_LOOKUP O(1)查表）
    local function ApplyCoopBuff(player, buff_id, stack_count)
        if not player or not player:IsValid() then return end
        local buff_def = BUFF_LOOKUP[buff_id]
        if not buff_def then return end

        local actual_stacks = math.min(stack_count, buff_def.max_stack)
        local key = "rogue_coop_" .. buff_id

        if buff_id == "damage" then
            if player.components.combat then
                player.components.combat.externaldamagemultipliers:SetModifier(key, 1 + buff_def.bonus * actual_stacks)
            end
        elseif buff_id == "defense" then
            if player.components.health then
                player.components.health.externalabsorbmultiplier = (player.components.health.externalabsorbmultiplier or 1) + buff_def.bonus * actual_stacks
            end
        elseif buff_id == "speed" then
            if player.components.locomotor then
                player.components.locomotor:SetExternalSpeedMultiplier(player, key, 1 + buff_def.bonus * actual_stacks)
            end
        elseif buff_id == "regen" then
            player.rogue_coop_regen_rate = buff_def.bonus * actual_stacks
            if not player.rogue_coop_regen_task then
                player.rogue_coop_regen_task = player:DoPeriodicTask(1, function(inst)
                    if inst.components.health and not inst.components.health:IsDead() and inst.rogue_coop_regen_rate then
                        inst.components.health:DoDelta(inst.rogue_coop_regen_rate, nil, "rogue_coop_regen")
                    end
                end)
            end
        end
        player.rogue_coop_stacks = player.rogue_coop_stacks or {}
        player.rogue_coop_stacks[buff_id] = actual_stacks
    end

    -- 函数说明：移除玩家的协作增益效果。
    local function RemoveCoopBuff(player, buff_id)
        if not player or not player:IsValid() then return end
        local key = "rogue_coop_" .. buff_id

        if buff_id == "damage" then
            if player.components.combat then
                player.components.combat.externaldamagemultipliers:RemoveModifier(key)
            end
        elseif buff_id == "defense" then
            if player.components.health then
                player.components.health.externalabsorbmultiplier = (player.components.health.externalabsorbmultiplier or 1) - (player.rogue_coop_stacks and player.rogue_coop_stacks[buff_id] or 0) * 0.05
            end
        elseif buff_id == "speed" then
            if player.components.locomotor then
                player.components.locomotor:RemoveExternalSpeedMultiplier(player, key)
            end
        elseif buff_id == "regen" then
            player.rogue_coop_regen_rate = 0
            if player.rogue_coop_regen_task then
                player.rogue_coop_regen_task:Cancel()
                player.rogue_coop_regen_task = nil
            end
        end
        if player.rogue_coop_stacks then
            player.rogue_coop_stacks[buff_id] = 0
        end
    end

    -- 函数说明：周期性检查并更新所有玩家的协作增益。
    S.RefreshCoopBuffs = function()
        local players = deps.CollectAlivePlayers()
        for _, p in ipairs(players) do
            if p:IsValid() and not p:HasTag("playerghost") then
                local ally_count, _ = GetNearbyAllies(p, coop_buffs.proximity_range)
                for _, buff_def in ipairs(coop_buffs.buffs) do
                    local old_stacks = (p.rogue_coop_stacks and p.rogue_coop_stacks[buff_def.id]) or 0
                    local new_stacks = ally_count >= buff_def.min_allies and ally_count or 0
                    if new_stacks ~= old_stacks then
                        if new_stacks > 0 then
                            ApplyCoopBuff(p, buff_def.id, new_stacks)
                        else
                            RemoveCoopBuff(p, buff_def.id)
                        end
                    end
                end
            end
        end
    end

    -- 函数说明：清理指定玩家的所有协作增益。
    S.CleanupPlayerCoopBuffs = function(player)
        if not player then return end
        for _, buff_def in ipairs(coop_buffs.buffs) do
            RemoveCoopBuff(player, buff_def.id)
        end
        player.rogue_coop_stacks = nil
    end

    -- 函数说明：玩家请求复活队友（消耗自身生命和理智）。
    S.TryReviveAlly = function(reviver, target)
        if not reviver or not target then return false end
        if not target:HasTag("playerghost") then return false end
        if reviver:HasTag("playerghost") then return false end

        local hp_cost = math.ceil(reviver.components.health.maxhealth * revive_cost.health_pct)
        if reviver.components.health.currenthealth <= hp_cost then
            if reviver.components.talker then
                reviver.components.talker:Say("生命值不足以复活队友！")
            end
            return false
        end

        reviver.components.health:DoDelta(-hp_cost, nil, "rogue_coop_revive")
        if reviver.components.sanity then
            reviver.components.sanity:DoDelta(-revive_cost.sanity_cost)
        end

        if target:HasTag("playerghost") then
            local pt = reviver:GetPosition()
            target:PushEvent("respawnfromghost", { source = reviver, user = target.userid })
            target.Transform:SetPosition(pt:Get())
        end

        return true
    end

    -- 函数说明：触发协作事件（守护据点）。
    S.TriggerGuardPointEvent = function(day)
        local players = deps.CollectAlivePlayers()
        if #players < 2 then return nil end

        local target = deps.PickRandom(players)
        if not target then return nil end

        local pt = target:GetPosition()
        local event_state = {
            type = "guard_point",
            center = pt,
            remaining = 30,
            wave_count = 0,
            day = day,
        }

        local marker = deps.SpawnPrefab("spawn_fx_medium")
        if marker then
            marker.Transform:SetPosition(pt:Get())
            marker.rogue_guard_marker = true
            marker.persists = false
            event_state.marker = marker
        end

        -- 函数说明：周期性刷新据点视觉标记（纯FX，无碰撞无交互）
        event_state.marker_refresh_task = nil
        local function RefreshGuardMarker()
            local evt = active_coop_events["guard_point"]
            if not evt then return end
            if evt.marker and evt.marker:IsValid() then
                evt.marker:Remove()
            end
            local new_marker = deps.SpawnPrefab("spawn_fx_medium")
            if new_marker then
                new_marker.Transform:SetPosition(evt.center.x, evt.center.y, evt.center.z)
                new_marker.rogue_guard_marker = true
                new_marker.persists = false
                evt.marker = new_marker
            end
            evt.marker_refresh_task = deps.GLOBAL.TheWorld:DoTaskInTime(3, RefreshGuardMarker)
        end
        RefreshGuardMarker()

        active_coop_events["guard_point"] = event_state
        return event_state
    end

    -- 函数说明：更新协作事件状态。
    S.UpdateCoopEvents = function(world, is_wave_active)
        for id, evt in pairs(active_coop_events) do
            if evt.type == "guard_point" then
                evt.remaining = evt.remaining - 2
                evt.wave_count = evt.wave_count + 1
                if evt.wave_count % 6 == 0 then
                    local cx, cy, cz = evt.center.x, evt.center.y, evt.center.z
                    local enemies = deps.GLOBAL.TheSim:FindEntities(cx, cy, cz, 15, {"hostile"}, {"INLIMBO", "player"})
                    if #enemies < 5 then
                        local pool, w = deps.PoolCatalog.GetRuntimePool("ENEMIES_NORMAL", evt.day)
                        if pool and w > 0 then
                            for i = 1, 3 do
                                local picked = deps.PickWeightedCandidate(pool, w)
                                if picked then
                                    local offset = deps.FindWalkableOffset(evt.center, math.random() * 2 * deps.PI, math.random() * 8 + 4, 8, true, false)
                                    if offset then
                                        local spawn_pt = evt.center + offset
                                        deps.SpawnPrefab(picked.prefab, spawn_pt)
                                    end
                                end
                            end
                        end
                    end
                end
                if evt.remaining <= 0 then
                    for _, p in ipairs(deps.CollectAlivePlayers()) do
                        local dist = p:GetDistanceSqToPoint(evt.center.x, evt.center.y, evt.center.z)
                        if dist < 20 * 20 then
                            local mat_pool, mat_w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_MATS", evt.day)
                            if mat_pool and mat_w > 0 then
                                for i = 1, 2 do
                                    local picked = deps.PickWeightedCandidate(mat_pool, mat_w)
                                    if picked then
                                        deps.SpawnDrop(p, picked.prefab, picked.count or 1)
                                    end
                                end
                            end
                            local gear_pool, gear_w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_GEAR", evt.day)
                            if gear_pool and gear_w > 0 and math.random() < 0.5 then
                                local picked = deps.PickWeightedCandidate(gear_pool, gear_w)
                                if picked then
                                    deps.SpawnDrop(p, picked.prefab, 1)
                                end
                            end
                        end
                    end
                    if evt.marker and evt.marker:IsValid() then
                        evt.marker:Remove()
                    end
                    if evt.marker_refresh_task then
                        evt.marker_refresh_task:Cancel()
                        evt.marker_refresh_task = nil
                    end
                    active_coop_events[id] = nil
                end
            end
        end
    end

    -- 函数说明：清理所有协作事件。
    S.CleanupCoopEvents = function()
        for id, evt in pairs(active_coop_events) do
            if evt.marker and evt.marker:IsValid() then
                evt.marker:Remove()
            end
            if evt.marker_refresh_task then
                evt.marker_refresh_task:Cancel()
                evt.marker_refresh_task = nil
            end
        end
        active_coop_events = {}
    end

    return S
end

return M
