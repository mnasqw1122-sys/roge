--[[
    文件说明：boss_mechanics.lua
    功能：Boss强化与模板机制模块。
    在生成Boss时随机附加特定的战斗模板（如召唤型、场地压制型、狂暴领域型等），增加Boss战的多样性与挑战难度。
]]
local M = {}

function M.Create(deps)
    local S = {}

    local function GetThreatTier()
        local ws = deps.GetWaveState and deps.GetWaveState() or nil
        local tier = ws and ws.threat_tier or 1
        if tier < 1 then tier = 1 end
        if tier > 3 then tier = 3 end
        return tier
    end

    local function GetRotationId()
        for _, p in ipairs(deps.CollectAlivePlayers()) do
            if p and p:IsValid() and deps.EnsurePlayerData then
                local data = deps.EnsurePlayerData(p)
                return data.season_rotation_id or data.season_rotation or 1
            end
        end
        return 1
    end

    local function GetAlivePlayers()
        return deps.CollectAlivePlayers and deps.CollectAlivePlayers() or {}
    end

    local function GetPlayerCount()
        local count = #GetAlivePlayers()
        return count > 0 and count or 1
    end

    -- 获取玩家数量分级的 Boss 技能伤害缩放系数
    -- 优化：从旧版 0.88/1.0/1.12/1.22 升级为更显著的多人难度弹性曲线
    local function GetPlayerDamageScale()
        local count = GetPlayerCount()
        if count <= 1 then return 1.0
        elseif count == 2 then return 1.15
        elseif count == 3 then return 1.25
        elseif count == 4 then return 1.35
        end
        return 1.40
    end

    -- 获取玩家数量分级的 Boss HP 缩放系数(供 wave_system 生成 Boss 时使用)
    local function GetPlayerHPScale()
        local count = GetPlayerCount()
        if count <= 1 then return 1.0
        elseif count == 2 then return 1.6
        elseif count == 3 then return 2.2
        elseif count == 4 then return 2.8
        end
        return 3.3
    end

    local function GetTargetCount(base, max_count)
        local players = GetAlivePlayers()
        if #players <= 0 then
            return 0
        end
        local count = (base or 1) + math.floor((#players - 1) / 2)
        if max_count and count > max_count then
            count = max_count
        end
        if count < 1 then
            count = 1
        end
        if count > #players then
            count = #players
        end
        return count
    end

    local function MultiplyValues(map)
        local value = 1
        for _, mult in pairs(map) do
            value = value * mult
        end
        return value
    end

    local function SpawnFxAt(prefab, x, y, z)
        if not prefab then return nil end
        local fx = deps.SpawnPrefab(prefab)
        if fx then
            fx.Transform:SetPosition(x, y or 0, z)
        end
        return fx
    end

    local function EnsureBossRuntime(inst)
        if inst.rogue_boss_runtime then
            return inst.rogue_boss_runtime
        end
        local runtime = {
            tasks = {},
            damage_mults = {},
            speed_mults = {},
            base_damage = inst.components and inst.components.combat and inst.components.combat.defaultdamage or nil,
            base_speed = inst.components and inst.components.locomotor and inst.components.locomotor.runspeed or nil,
        }

        local function RebuildDamage()
            if inst.components and inst.components.combat and runtime.base_damage then
                inst.components.combat:SetDefaultDamage(runtime.base_damage * MultiplyValues(runtime.damage_mults))
            end
        end

        local function RebuildSpeed()
            if inst.components and inst.components.locomotor and runtime.base_speed then
                inst.components.locomotor.runspeed = runtime.base_speed * MultiplyValues(runtime.speed_mults)
            end
        end

        inst.rogue_set_damage_mult = function(_, key, mult)
            if not key then return end
            if mult and mult ~= 1 then
                runtime.damage_mults[key] = mult
            else
                runtime.damage_mults[key] = nil
            end
            RebuildDamage()
        end

        inst.rogue_set_speed_mult = function(_, key, mult)
            if not key then return end
            if mult and mult ~= 1 then
                runtime.speed_mults[key] = mult
            else
                runtime.speed_mults[key] = nil
            end
            RebuildSpeed()
        end

        inst.rogue_set_managed_task = function(_, key, task)
            if not key then return end
            local old = runtime.tasks[key]
            if old then
                old:Cancel()
            end
            runtime.tasks[key] = task
        end

        inst.rogue_cancel_managed_task = function(_, key)
            local old = runtime.tasks[key]
            if old then
                old:Cancel()
                runtime.tasks[key] = nil
            end
        end

        inst:ListenForEvent("onremove", function(ent)
            for key, task in pairs(runtime.tasks) do
                if task then
                    task:Cancel()
                end
                runtime.tasks[key] = nil
            end
            if ent.components and ent.components.colouradder then
                ent.components.colouradder:PopColour("rogue_template_phase")
            end
        end)

        inst.rogue_boss_runtime = runtime
        return runtime
    end

    local function PickTemplate(day)
        local pool = {}
        local total = 0
        local rotation_id = GetRotationId()
        local mods = deps.BOSS_TEMPLATE_ROTATION_MODS and deps.BOSS_TEMPLATE_ROTATION_MODS[rotation_id] or {}
        for _, def in ipairs(deps.BOSS_TEMPLATE_DEFS or {}) do
            if day >= (def.min_day or 1) then
                local threat_mult = 1
                if def.id == "berserk_aura" then
                    local tt = GetThreatTier()
                    threat_mult = tt == 1 and 0.9 or (tt == 2 and 1.0 or 1.25)
                elseif def.id == "phase_shift" and GetThreatTier() >= 3 then
                    threat_mult = 1.15
                end
                table.insert(pool, def)
                total = total + (def.weight or 1) * (mods[def.id] or 1) * threat_mult
            end
        end
        if #pool == 0 then
            return nil
        end
        local roll = math.random() * total
        local acc = 0
        for _, def in ipairs(pool) do
            local threat_mult = 1
            if def.id == "berserk_aura" then
                local tt = GetThreatTier()
                threat_mult = tt == 1 and 0.9 or (tt == 2 and 1.0 or 1.25)
            elseif def.id == "phase_shift" and GetThreatTier() >= 3 then
                threat_mult = 1.15
            end
            acc = acc + (def.weight or 1) * (mods[def.id] or 1) * threat_mult
            if roll <= acc then
                return def
            end
        end
        return pool[#pool]
    end

    local function PickTargets(limit, preferred)
        local players = GetAlivePlayers()
        if #players <= 0 or limit <= 0 then
            return {}
        end
        local picked = {}
        local pool = {}
        if preferred then
            for _, p in ipairs(players) do
                if p == preferred then
                    table.insert(picked, p)
                    break
                end
            end
        end
        for _, p in ipairs(players) do
            local exists = false
            for _, picked_player in ipairs(picked) do
                if picked_player == p then
                    exists = true
                    break
                end
            end
            if not exists then
                table.insert(pool, p)
            end
        end
        while #picked < limit and #pool > 0 do
            local idx = math.random(#pool)
            table.insert(picked, pool[idx])
            table.remove(pool, idx)
        end
        return picked
    end

    local function GetCurrentTarget(inst)
        if not inst.components or not inst.components.combat then
            return nil
        end
        local target = inst.components.combat.target
        if not target then
            return nil
        end
        for _, p in ipairs(GetAlivePlayers()) do
            if p == target then
                return p
            end
        end
        return nil
    end

    local function GetSkillDamage(inst, factor, min_damage, max_damage)
        local runtime = EnsureBossRuntime(inst)
        local base = runtime.base_damage or (inst.components and inst.components.combat and inst.components.combat.defaultdamage) or 45
        local damage = base * (factor or 0.4) * GetPlayerDamageScale() * (1 + (GetThreatTier() - 1) * 0.08)
        if min_damage and damage < min_damage then
            damage = min_damage
        end
        if max_damage and damage > max_damage then
            damage = max_damage
        end
        return damage
    end

    local function DamagePlayersNearPoint(inst, pos, radius, damage_factor, min_damage, max_damage, sanity_delta, cause, on_hit)
        if not pos then return 0 end
        local x, y, z = pos:Get()
        local count = 0
        local damage = GetSkillDamage(inst, damage_factor, min_damage, max_damage)
        for _, p in ipairs(GetAlivePlayers()) do
            if p and p:IsValid() and p:GetDistanceSqToPoint(x, y, z) <= radius * radius then
                count = count + 1
                if p.components and p.components.combat then
                    p.components.combat:GetAttacked(inst, damage)
                elseif p.components and p.components.health then
                    p.components.health:DoDelta(-damage, nil, cause or "rogue_boss_skill")
                end
                if sanity_delta and sanity_delta ~= 0 and p.components and p.components.sanity then
                    p.components.sanity:DoDelta(-math.abs(sanity_delta))
                end
                if on_hit then
                    on_hit(p, damage)
                end
            end
        end
        return count
    end

    local function PlayStrikeFx(pos, telegraph_prefab)
        if not pos then return end
        local x, y, z = pos:Get()
        local world = deps.GetWorld and deps.GetWorld() or nil
        local use_moonstorm_fx = world and world.components and world.components.moonstorms ~= nil
        SpawnFxAt(telegraph_prefab or (use_moonstorm_fx and "moonstorm_ground_lightning_fx" or "statue_transition_2"), x, y, z)
        if world and world.PushEvent and deps.Vector3 then
            world:PushEvent("ms_sendlightningstrike", deps.Vector3(x, y, z))
        end
    end

    local function ScheduleBurst(inst, pos, opts)
        if not pos then return end
        opts = opts or {}
        local x, y, z = pos:Get()
        SpawnFxAt(opts.telegraph_prefab or "statue_transition_2", x, y, z)
        inst:DoTaskInTime(opts.delay or 0.9, function(ent)
            if not ent or not ent:IsValid() or not ent.components or not ent.components.health or ent.components.health:IsDead() then
                return
            end
            PlayStrikeFx(pos, opts.impact_prefab)
            DamagePlayersNearPoint(ent, pos, opts.radius or 2.5, opts.damage_factor or 0.36, opts.min_damage or 10, opts.max_damage or 90, opts.sanity_delta or 0, opts.cause, opts.on_hit)
        end)
    end

    local function SpawnMinionsAround(inst, count, target_hint)
        local players = GetAlivePlayers()
        if #players == 0 then return 0 end
        local spawned = 0
        local center = target_hint and target_hint:IsValid() and target_hint:GetPosition() or inst:GetPosition()
        for _ = 1, count do
            local prefab = deps.PickRandom({ "hound", "spider_warrior", "merm", "pigman" })
            local minion = deps.SpawnPrefab(prefab)
            if minion then
                local offset = deps.FindWalkableOffset(center, math.random() * 2 * deps.PI, 3 + math.random() * 3, 8, true, false)
                minion.Transform:SetPosition((offset and (center + offset) or center):Get())
                if minion.components and minion.components.combat then
                    minion.components.combat:SetTarget(target_hint or deps.PickRandom(players))
                end
                SpawnFxAt("spawn_fx_medium", minion.Transform:GetWorldPosition())
                spawned = spawned + 1
            end
        end
        return spawned
    end

    local function ApplyTint(inst, key, r, g, b)
        if inst.components and inst.components.colouradder then
            inst.components.colouradder:PushColour(key, r, g, b, 0)
        end
    end

    local function ClearTint(inst, key)
        if inst.components and inst.components.colouradder then
            inst.components.colouradder:PopColour(key)
        end
    end

    local function ApplyTimedBuff(inst, key, damage_mult, speed_mult, duration)
        EnsureBossRuntime(inst)
        if inst.rogue_set_damage_mult then
            inst:rogue_set_damage_mult(key .. "_dmg", damage_mult)
        end
        if inst.rogue_set_speed_mult then
            inst:rogue_set_speed_mult(key .. "_spd", speed_mult)
        end
        inst:DoTaskInTime(duration or 3, function(ent)
            if ent and ent:IsValid() then
                if ent.rogue_set_damage_mult then
                    ent:rogue_set_damage_mult(key .. "_dmg", 1)
                end
                if ent.rogue_set_speed_mult then
                    ent:rogue_set_speed_mult(key .. "_spd", 1)
                end
            end
        end)
    end

    local function CastZoneVolley(inst, day)
        local primary = GetCurrentTarget(inst)
        local targets = PickTargets(GetTargetCount(1, 3), primary)
        if #targets == 0 then
            return
        end
        local extra = math.min(2, math.floor(day / 18))
        for _, target in ipairs(targets) do
            local base_pos = target:GetPosition()
            ScheduleBurst(inst, base_pos, {
                radius = 2.6,
                damage_factor = 0.34,
                min_damage = 12,
                max_damage = 75,
                sanity_delta = 0,
                cause = "rogue_zone_strike",
            })
            for _ = 1, extra do
                local offset = deps.FindWalkableOffset(base_pos, math.random() * 2 * deps.PI, 2.5 + math.random() * 2.5, 8, true, false)
                if offset then
                    ScheduleBurst(inst, base_pos + offset, {
                        radius = 2.3,
                        damage_factor = 0.28,
                        min_damage = 10,
                        max_damage = 65,
                        cause = "rogue_zone_strike",
                    })
                end
            end
        end
        deps.Announce(deps.GetEntityName(inst) .. " 封锁战场，雷暴将连续落下！")
    end

    local function CastChargeRush(inst)
        local target = GetCurrentTarget(inst)
        if not target then
            local picks = PickTargets(1, nil)
            target = picks[1]
        end
        if not target then
            return
        end
        local boss_pos = inst:GetPosition()
        local target_pos = target:GetPosition()
        local bx, by, bz = boss_pos:Get()
        local tx, ty, tz = target_pos:Get()
        local positions = {}
        for i = 1, 3 do
            local t = i / 4
            table.insert(positions, deps.Vector3(bx + (tx - bx) * t, by + (ty - by) * t, bz + (tz - bz) * t))
        end
        table.insert(positions, target_pos)

        if inst.components and inst.components.combat then
            inst.components.combat:SetTarget(target)
        end
        ApplyTimedBuff(inst, "rogue_charge_rush", 1.12 + (GetPlayerCount() > 2 and 0.04 or 0), 1.24 + math.min(0.12, (GetPlayerCount() - 1) * 0.04), 3)
        for index, pos in ipairs(positions) do
            ScheduleBurst(inst, pos, {
                delay = 0.75,
                radius = index == #positions and 3.2 or 2.3,
                damage_factor = index == #positions and 0.5 or 0.28,
                min_damage = index == #positions and 16 or 10,
                max_damage = index == #positions and 110 or 70,
                cause = "rogue_charge_rush",
            })
        end
        deps.Announce(deps.GetEntityName(inst) .. " 锁定猎物，发起贯穿冲锋！")
    end

    local function StartPhaseShiftCycle(inst, day)
        local function EnterForm(ent, form)
            if not ent or not ent:IsValid() or not ent.components or not ent.components.health or ent.components.health:IsDead() then
                return
            end
            local stage = ent.rogue_phase_shift_stage or 1
            ent.rogue_phase_shift_form = form
            ClearTint(ent, "rogue_template_phase")
            if form == "assault" then
                ApplyTint(ent, "rogue_template_phase", 0.18, 0.06, 0.02)
                if ent.rogue_set_damage_mult then
                    ent:rogue_set_damage_mult("rogue_phase_shift_form", 1.08 + stage * 0.04)
                end
                if ent.rogue_set_speed_mult then
                    ent:rogue_set_speed_mult("rogue_phase_shift_form", 1.06 + stage * 0.07)
                end
                CastChargeRush(ent)
                deps.Announce(deps.GetEntityName(ent) .. " 切换为裂战相，开始强压追击！")
            else
                ApplyTint(ent, "rogue_template_phase", 0.08, 0.02, 0.18)
                if ent.rogue_set_damage_mult then
                    ent:rogue_set_damage_mult("rogue_phase_shift_form", 1.02 + stage * 0.03)
                end
                if ent.rogue_set_speed_mult then
                    ent:rogue_set_speed_mult("rogue_phase_shift_form", 0.96)
                end
                local heal_total = 0
                for _, target in ipairs(PickTargets(GetTargetCount(1, 2), GetCurrentTarget(ent))) do
                    ScheduleBurst(ent, target:GetPosition(), {
                        delay = 1.0,
                        telegraph_prefab = "shadow_puff_large_front",
                        impact_prefab = "shadow_puff_large_front",
                        radius = 3.0,
                        damage_factor = 0.33 + stage * 0.05,
                        min_damage = 12,
                        max_damage = 80,
                        sanity_delta = 5 + stage,
                        cause = "rogue_phase_shift",
                        on_hit = function()
                            if ent.components and ent.components.health and not ent.components.health:IsDead() then
                                local per_hit = (ent.components.health.maxhealth or 0) * (stage >= 3 and 0.018 or 0.012)
                                heal_total = heal_total + per_hit
                            end
                        end,
                    })
                end
                if stage >= 3 then
                    SpawnMinionsAround(ent, math.max(1, math.floor(GetPlayerCount() / 2)), GetCurrentTarget(ent))
                end
                ent:DoTaskInTime(1.25, function(inst2)
                    if inst2 and inst2:IsValid() and inst2.components and inst2.components.health and not inst2.components.health:IsDead() and heal_total > 0 then
                        inst2.components.health:DoDelta(heal_total)
                    end
                end)
                deps.Announce(deps.GetEntityName(ent) .. " 切换为吞灵相，开始抽取战场生命！")
            end
        end

        EnsureBossRuntime(inst)
        inst.rogue_phase_shift_stage = 1
        EnterForm(inst, "assault")
        local period = math.max(7, 11 - math.floor(day / 28))
        inst:rogue_set_managed_task("rogue_phase_shift_cycle", inst:DoPeriodicTask(period, function(ent)
            local next_form = ent.rogue_phase_shift_form == "assault" and "siphon" or "assault"
            EnterForm(ent, next_form)
        end))
        inst:ListenForEvent("healthdelta", function(ent)
            if not ent:IsValid() or not ent.components or not ent.components.health or ent.components.health:IsDead() then
                return
            end
            local pct = ent.components.health:GetPercent()
            if (ent.rogue_phase_shift_stage or 1) < 2 and pct <= 0.7 then
                ent.rogue_phase_shift_stage = 2
                period = math.max(6, period - 1)
                ent:rogue_set_managed_task("rogue_phase_shift_cycle", ent:DoPeriodicTask(period, function(inst2)
                    local next_form = inst2.rogue_phase_shift_form == "assault" and "siphon" or "assault"
                    EnterForm(inst2, next_form)
                end))
                deps.Announce(deps.GetEntityName(ent) .. " 裂变加速，形态切换频率提升！")
            end
            if (ent.rogue_phase_shift_stage or 1) < 3 and pct <= 0.35 then
                ent.rogue_phase_shift_stage = 3
                if ent.components.health then
                    ent.components.health:DoDelta((ent.components.health.maxhealth or 0) * 0.06)
                end
                period = math.max(5, period - 1)
                ent:rogue_set_managed_task("rogue_phase_shift_cycle", ent:DoPeriodicTask(period, function(inst2)
                    local next_form = inst2.rogue_phase_shift_form == "assault" and "siphon" or "assault"
                    EnterForm(inst2, next_form)
                end))
                SpawnFxAt("shadow_puff_large_front", ent.Transform:GetWorldPosition())
                deps.Announce(deps.GetEntityName(ent) .. " 进入终末裂变，吞灵与裂战同步增强！")
            end
        end)
    end

    local function AttachSummoner(inst, day)
        EnsureBossRuntime(inst)
        local function TriggerWave(ent, threshold, count_mult)
            local target = GetCurrentTarget(ent)
            local count = math.max(1, math.floor(day / 18) + count_mult + math.floor(GetPlayerCount() / 2))
            SpawnMinionsAround(ent, count, target)
            ApplyTimedBuff(ent, "rogue_summon_wave", 1.08 + math.min(0.08, count * 0.01), 1.04, 6)
            deps.Announce(deps.GetEntityName(ent) .. " 号令援军压上！")
            ent["rogue_template_summon_" .. threshold] = true
        end

        inst:ListenForEvent("healthdelta", function(ent)
            if not ent:IsValid() or not ent.components or not ent.components.health or ent.components.health:IsDead() then return end
            local pct = ent.components.health:GetPercent()
            if not ent.rogue_template_summon_80 and pct <= 0.8 then
                TriggerWave(ent, 80, 1)
            end
            if not ent.rogue_template_summon_55 and pct <= 0.55 then
                TriggerWave(ent, 55, 2)
            end
            if not ent.rogue_template_summon_30 and pct <= 0.3 then
                TriggerWave(ent, 30, 3)
            end
        end)

        local period = math.max(9, 16 - math.floor(day / 20) - math.floor((GetPlayerCount() - 1) / 2))
        inst:rogue_set_managed_task("rogue_template_summoner", inst:DoPeriodicTask(period, function(ent)
            if not ent:IsValid() or not ent.components or not ent.components.health or ent.components.health:IsDead() then return end
            if ent.components.health:GetPercent() > 0.85 and GetPlayerCount() <= 1 then return end
            local targets = PickTargets(GetTargetCount(1, 2), GetCurrentTarget(ent))
            for _, target in ipairs(targets) do
                SpawnMinionsAround(ent, 1 + math.floor(day / 35), target)
            end
            deps.Announce(deps.GetEntityName(ent) .. " 调兵分压，战场正在扩散！")
        end))
    end

    local function AttachZone(inst, day)
        EnsureBossRuntime(inst)
        local period = math.max(6, 11 - math.floor(day / 18) - math.floor((GetPlayerCount() - 1) / 2))
        inst:rogue_set_managed_task("rogue_template_zone", inst:DoPeriodicTask(period, function(ent)
            if not ent:IsValid() or not ent.components or not ent.components.health or ent.components.health:IsDead() then return end
            CastZoneVolley(ent, day)
        end))
    end

    local function AttachCharger(inst, day)
        if not inst.components or not inst.components.locomotor then return end
        EnsureBossRuntime(inst)
        local period = math.max(7, 13 - math.floor(day / 22) - math.floor((GetPlayerCount() - 1) / 2))
        inst:rogue_set_managed_task("rogue_template_charger", inst:DoPeriodicTask(period, function(ent)
            if not ent:IsValid() or not ent.components or not ent.components.health or ent.components.health:IsDead() then return end
            CastChargeRush(ent)
        end))
    end

    local function AttachPhaseShift(inst, day)
        EnsureBossRuntime(inst)
        StartPhaseShiftCycle(inst, day)
    end

    local function AttachBerserkAura(inst, day)
        EnsureBossRuntime(inst)
        local period = math.max(6, 11 - math.floor(day / 22) - (GetThreatTier() - 1))
        inst:rogue_set_managed_task("rogue_template_berserk", inst:DoPeriodicTask(period, function(ent)
            if not ent:IsValid() or not ent.components or not ent.components.health or ent.components.health:IsDead() then return end
            local tier = GetThreatTier()
            local center = ent:GetPosition()
            local inner_hits = DamagePlayersNearPoint(ent, center, 5.5 + math.min(2, GetPlayerCount() - 1), 0.22 + tier * 0.04, 8, 55, 4 + tier, "rogue_berserk_aura")
            local far_targets = {}
            for _, p in ipairs(GetAlivePlayers()) do
                if p:GetDistanceSqToPoint(center:Get()) > 49 then
                    table.insert(far_targets, p)
                end
            end
            if #far_targets > 0 then
                local strike_count = math.min(#far_targets, GetTargetCount(1, 3))
                for i = 1, strike_count do
                    local idx = math.random(#far_targets)
                    local target = far_targets[idx]
                    ScheduleBurst(ent, target:GetPosition(), {
                        delay = 0.75,
                        telegraph_prefab = "shadow_puff_large_front",
                        impact_prefab = "shadow_puff_large_front",
                        radius = 2.8,
                        damage_factor = 0.32 + tier * 0.03,
                        min_damage = 12,
                        max_damage = 78,
                        sanity_delta = 5 + tier,
                        cause = "rogue_berserk_pursuit",
                    })
                    table.remove(far_targets, idx)
                end
            end
            ApplyTimedBuff(ent, "rogue_berserk_aura", 1.08 + tier * 0.03 + math.min(0.05, GetPlayerCount() * 0.01), inner_hits <= 0 and 1.12 or 1.04, 4.5)
            SpawnFxAt("shadow_puff_large_front", ent.Transform:GetWorldPosition())
            deps.Announce(deps.GetEntityName(ent) .. " 展开压迫领域，逼迫全队重新站位！")
        end))
    end

    S.AttachBossTemplate = function(inst, day)
        if not inst or not inst:IsValid() or inst.rogue_boss_template_id then return nil end
        EnsureBossRuntime(inst)
        
        -- [V2 深度机制集成]
        if deps and deps.RogueBossMechanicsV2 then
            -- 如果是熊獾，有 25% 概率变异为 V2 领域工匠机制
            if inst.prefab == "bearger" and math.random() < 0.25 then
                local success = deps.RogueBossMechanicsV2.ApplyDeepAffix(inst, "arena_forge_bearger", deps)
                if success then
                    inst.rogue_boss_template_id = "arena_forge_bearger"
                    inst.rogue_boss_template_name = "领域工匠"
                    return { id = "arena_forge_bearger", name = "领域工匠" }
                end
            end
            -- 如果是树精守卫，有 25% 概率变异为 V2 统御军势机制
            if (inst.prefab == "leif" or inst.prefab == "treeguard") and math.random() < 0.25 then
                local success = deps.RogueBossMechanicsV2.ApplyDeepAffix(inst, "summoner_legion_treeguard", deps)
                if success then
                    inst.rogue_boss_template_id = "summoner_legion_treeguard"
                    inst.rogue_boss_template_name = "统御军势"
                    return { id = "summoner_legion_treeguard", name = "统御军势" }
                end
            end
            -- 如果是鹿角鹅，有 25% 概率变异为 V2 雷暴猎场机制
            if inst.prefab == "moose" and math.random() < 0.25 then
                local success = deps.RogueBossMechanicsV2.ApplyDeepAffix(inst, "thunder_hunt_moose", deps)
                if success then
                    inst.rogue_boss_template_id = "thunder_hunt_moose"
                    inst.rogue_boss_template_name = "雷暴猎场"
                    return { id = "thunder_hunt_moose", name = "雷暴猎场" }
                end
            end
            -- 如果是蜘蛛女王，有 25% 概率变异为 V2 双相裂变机制
            if inst.prefab == "spiderqueen" and math.random() < 0.25 then
                local success = deps.RogueBossMechanicsV2.ApplyDeepAffix(inst, "phase_shift_spiderqueen", deps)
                if success then
                    inst.rogue_boss_template_id = "phase_shift_spiderqueen"
                    inst.rogue_boss_template_name = "双相裂变"
                    return { id = "phase_shift_spiderqueen", name = "双相裂变" }
                end
            end
            -- 如果是远古犀牛，有 25% 概率变异为 V2 压迫领域机制
            if inst.prefab == "minotaur" and math.random() < 0.25 then
                local success = deps.RogueBossMechanicsV2.ApplyDeepAffix(inst, "oppressive_domain_minotaur", deps)
                if success then
                    inst.rogue_boss_template_id = "oppressive_domain_minotaur"
                    inst.rogue_boss_template_name = "压迫领域"
                    return { id = "oppressive_domain_minotaur", name = "压迫领域" }
                end
            end
        end
        
        -- [回退到 V1 机制]
        local template = PickTemplate(day)
        if not template then return nil end
        
        inst.rogue_boss_template_id = template.id
        inst.rogue_boss_template_name = template.name
        if template.id == "summoner" then
            AttachSummoner(inst, day)
        elseif template.id == "zone" then
            AttachZone(inst, day)
        elseif template.id == "charger" then
            AttachCharger(inst, day)
        elseif template.id == "phase_shift" then
            AttachPhaseShift(inst, day)
        elseif template.id == "berserk_aura" then
            AttachBerserkAura(inst, day)
        end
        return template
    end

    return S
end

return M
