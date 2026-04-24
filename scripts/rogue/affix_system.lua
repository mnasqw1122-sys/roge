--[[
    文件说明：affix_system.lua
    功能：精英与Boss词缀系统。
    负责随机抽取、分配并应用词缀（如吸血、冰霜、护盾等）到敌对实体上，包含词缀属性的强化和特殊机制的事件监听绑定。
]]
local M = {}

function M.Create(deps)
    local S = {}

    -- 检查实体是否可以被赋予词缀
    local function CanApplyAffixToEntity(ent)
        if not ent or not ent:IsValid() or ent:HasTag("player") or ent:HasTag("companion") or ent:HasTag("structure") then
            return false
        end
        return true
    end

    -- 随机抽取一个未被排除的词缀
    local function PickWeightedAffix(excluded_map)
        local candidates = {}
        local total_weight = 0
        for _, affix in ipairs(deps.ELITE_AFFIX_DEFS) do
            if not excluded_map or not excluded_map[affix.id] then
                table.insert(candidates, affix)
                total_weight = total_weight + (affix.weight or 0)
            end
        end
        if total_weight <= 0 then return nil end

        local roll = math.random() * total_weight
        local acc = 0
        for _, affix in ipairs(candidates) do
            acc = acc + affix.weight
            if roll <= acc then return affix end
        end
        return candidates[#candidates]
    end

    -- 应用词缀的基础属性加成（血量、攻击、移速、体型等）
    local function ApplyAffixStats(ent, affix)
        if ent.components.health then
            local max = ent.components.health.maxhealth or 100
            ent.components.health:SetMaxHealth(max * (affix.hp_mult or 1))
            ent.components.health:SetPercent(1)
        end
        if ent.components.combat then
            if ent.components.combat.defaultdamage then
                ent.components.combat:SetDefaultDamage(ent.components.combat.defaultdamage * (affix.dmg_mult or 1))
            end
            if affix.range_mult then
                local old_range = ent.components.combat.hitrange or 3
                ent.components.combat:SetRange(old_range * affix.range_mult)
            end
        end
        if ent.components.locomotor then
            local mult = affix.speed_mult or 1
            if ent.components.locomotor.walkspeed then
                ent.components.locomotor.walkspeed = ent.components.locomotor.walkspeed * mult
            end
            if ent.components.locomotor.runspeed then
                ent.components.locomotor.runspeed = ent.components.locomotor.runspeed * mult
            end
        end
        if affix.size_mult then
            local s = ent.Transform:GetScale()
            ent.Transform:SetScale(s * affix.size_mult, s * affix.size_mult, s * affix.size_mult)
        end
    end

    local function SpawnAffixAdds(source, count)
        local players = deps.CollectAlivePlayers()
        if #players == 0 then return end
        for _ = 1, count do
            local prefab = deps.PickRandom({ "hound", "spider", "spider_warrior", "merm" })
            local add = deps.SpawnPrefab(prefab)
            if add then
                local pt = source:GetPosition()
                local offset = deps.FindWalkableOffset(pt, math.random() * 2 * deps.PI, 3, 8, true, false)
                add.Transform:SetPosition((offset and (pt + offset) or pt):Get())
                if add.components and add.components.combat then
                    add.components.combat:SetTarget(deps.PickRandom(players))
                end
                local fx = deps.SpawnPrefab("spawn_fx_medium")
                if fx then
                    fx.Transform:SetPosition(add.Transform:GetWorldPosition())
                end
            end
        end
    end

    -- 根据特定的词缀类型绑定特殊行为（如吸血、冰冻、分裂等）
    local function ApplyAffixBehavior(ent, affix_id, day)
        if affix_id == "vampire" then
            if not ent.rogue_lifesteal_hooked then
                ent.rogue_lifesteal_hooked = true
                ent:ListenForEvent("onhitother", function(inst, data)
                    if inst:IsValid() and inst.components.health and not inst.components.health:IsDead() then
                        local target = data and data.target
                        if target and target.components.health then
                            local heal = math.max(1, (target.components.health.maxhealth or 50) * 0.1)
                            inst.components.health:DoDelta(heal)
                        end
                    end
                end)
            end
        elseif affix_id == "frozen" then
            if not ent.rogue_frozen_hooked then
                ent.rogue_frozen_hooked = true
                ent:ListenForEvent("onhitother", function(inst, data)
                    local target = data and data.target
                    if target and target:IsValid() and target.components.freezable then
                        target.components.freezable:AddColdness(1)
                        target.components.freezable:SpawnShatterFX()
                    end
                end)
            end
        elseif affix_id == "thorns" then
            if not ent.rogue_thorns_hooked then
                ent.rogue_thorns_hooked = true
                ent:ListenForEvent("attacked", function(inst, data)
                    local attacker = data and data.attacker
                    local damage = data and data.damage or 0
                    if attacker and attacker:IsValid() and attacker.components.combat and damage > 0 then
                        attacker.components.combat:GetAttacked(inst, damage * 0.25)
                    end
                end)
            end
        elseif affix_id == "split" then
            if not ent.rogue_split_hooked then
                ent.rogue_split_hooked = true
                ent.rogue_split_once = false
                ent:ListenForEvent("attacked", function(inst)
                    if inst.rogue_split_once or not inst.components or not inst.components.health then return end
                    if inst.components.health:GetPercent() <= 0.45 then
                        inst.rogue_split_once = true
                        SpawnAffixAdds(inst, 2 + math.min(1, math.floor((day - 1) / 30)))
                    end
                end)
            end
        elseif affix_id == "shield" then
            if not ent.rogue_shield_hooked then
                ent.rogue_shield_hooked = true
                ent.rogue_shield_dead = false
                ent:ListenForEvent("death", function(inst)
                    inst.rogue_shield_dead = true
                end)
                ent:ListenForEvent("attacked", function(inst, data)
                    if not inst.components or not inst.components.health then return end
                    if inst.rogue_shield_dead or inst.components.health:IsDead() then return end
                    local dmg = data and data.damage or 0
                    if dmg > 0 then
                        local maxhp = inst.components.health.maxhealth or 100
                        local current = inst.components.health.currenthealth or 0
                        local missing = math.max(0, maxhp - current)
                        if missing > 0 then
                            local absorb = math.min(missing, math.min(maxhp * 0.03, dmg * 0.55))
                            if absorb > 0 then
                                inst.components.health:DoDelta(absorb)
                                local fx = deps.SpawnPrefab("small_puff")
                                if fx then
                                    fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
                                end
                            end
                        end
                    end
                end)
            end
        elseif affix_id == "hunter" then
            if not ent.rogue_hunter_task then
                ent.rogue_hunter_task = ent:DoPeriodicTask(6, function(inst)
                    if not inst:IsValid() then return end
                    local target = deps.PickRandom(deps.CollectAlivePlayers())
                    if target and inst.components and inst.components.combat then
                        inst.components.combat:SetTarget(target)
                    end
                    if inst.components and inst.components.locomotor then
                        local base = inst.rogue_hunter_base_run or inst.components.locomotor.runspeed
                        inst.rogue_hunter_base_run = base
                        inst.components.locomotor.runspeed = base * 1.2
                        inst:DoTaskInTime(1.2, function(inst2)
                            if inst2 and inst2:IsValid() and inst2.components and inst2.components.locomotor then
                                inst2.components.locomotor.runspeed = base
                            end
                        end)
                    end
                end)
            end
        elseif affix_id == "sacrifice" then
            if not ent.rogue_sacrifice_hooked then
                ent.rogue_sacrifice_hooked = true
                ent:ListenForEvent("death", function(inst)
                    local fx = deps.SpawnPrefab("statue_transition_2")
                    if fx then
                        fx.Transform:SetPosition(inst.Transform:GetWorldPosition())
                    end
                    SpawnAffixAdds(inst, 2 + math.min(2, math.floor((day - 1) / 35)))
                end)
            end
        elseif affix_id == "resonance" then
            if not ent.rogue_resonance_task then
                ent.rogue_resonance_task = ent:DoPeriodicTask(7, function(inst)
                    if not inst:IsValid() or not inst.components or not inst.components.combat then return end
                    local base = inst.rogue_resonance_base_damage or inst.components.combat.defaultdamage or 0
                    inst.rogue_resonance_base_damage = base
                    inst.components.combat:SetDefaultDamage(base * 1.12)
                    inst:DoTaskInTime(2.5, function(inst2)
                        if inst2 and inst2:IsValid() and inst2.components and inst2.components.combat and inst2.rogue_resonance_base_damage then
                            inst2.components.combat:SetDefaultDamage(inst2.rogue_resonance_base_damage)
                        end
                    end)
                end)
            end
        elseif affix_id == "corrupt" then
            if not ent.rogue_corrupt_hooked then
                ent.rogue_corrupt_hooked = true
                ent:ListenForEvent("onhitother", function(inst, data)
                    local target = data and data.target
                    if target and target:IsValid() then
                        if target.components and target.components.sanity then
                            target.components.sanity:DoDelta(-2)
                        end
                        if target.components and target.components.hunger then
                            target.components.hunger:DoDelta(-1.2)
                        end
                    end
                end)
            end
        elseif affix_id == "drain" then
            if not ent.rogue_drain_hooked then
                ent.rogue_drain_hooked = true
                ent:ListenForEvent("onhitother", function(inst, data)
                    local target = data and data.target
                    if target and target:IsValid() and inst.components and inst.components.health then
                        local heal = 3 + math.min(5, math.floor(day / 20))
                        inst.components.health:DoDelta(heal)
                        if target.components and target.components.sanity then
                            target.components.sanity:DoDelta(-1.5)
                        end
                    end
                end)
            end
        elseif affix_id == "execute" then
            if not ent.rogue_execute_hooked then
                ent.rogue_execute_hooked = true
                ent:ListenForEvent("onhitother", function(inst, data)
                    local target = data and data.target
                    if target and target:IsValid() and target.components and target.components.health and target.components.combat and target.components.health:GetPercent() <= 0.3 then
                        if target.rogue_execute_lock then return end
                        target.rogue_execute_lock = true
                        local bonus = (inst.components and inst.components.combat and inst.components.combat.defaultdamage or 20) * 0.45
                        target.components.health:DoDelta(-bonus, nil, inst.prefab, nil, inst, true)
                        target:DoTaskInTime(0, function(t)
                            if t and t:IsValid() then
                                t.rogue_execute_lock = nil
                            end
                        end)
                    end
                end)
            end
        elseif affix_id == "phantom" then
            if not ent.rogue_phantom_hooked then
                ent.rogue_phantom_hooked = true
                ent.rogue_phantom_dodge_cd = false
                ent:ListenForEvent("attacked", function(inst, data)
                    if inst.rogue_phantom_dodge_cd then return end
                    if math.random() < 0.25 then
                        inst.rogue_phantom_dodge_cd = true
                        inst:DoTaskInTime(3, function() inst.rogue_phantom_dodge_cd = false end)
                        if inst.components.health then
                            inst.components.health:DoDelta(0, nil, "phantom_dodge")
                        end
                        if inst.components.locomotor then
                            local orig_speed = inst.components.locomotor:GetSpeedMultiplier()
                            inst.components.locomotor:SetExternalSpeedMultiplier(inst, "rogue_phantom_dodge", 2.0)
                            inst:DoTaskInTime(1.5, function()
                                if inst and inst:IsValid() and inst.components.locomotor then
                                    inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "rogue_phantom_dodge")
                                end
                            end)
                        end
                    end
                end)
            end
        elseif affix_id == "enrage" then
            if not ent.rogue_enrage_hooked then
                ent.rogue_enrage_hooked = true
                ent:ListenForEvent("attacked", function(inst, data)
                    if not inst.components.combat or not inst.components.health then return end
                    local hp_pct = inst.components.health:GetPercent()
                    if hp_pct < 0.5 and not inst.rogue_enraged then
                        inst.rogue_enraged = true
                        if inst.components.combat.externaldamagemultipliers then
                            inst.components.combat.externaldamagemultipliers:SetModifier(inst, 1.6, "rogue_enrage")
                        end
                        if inst.components.locomotor then
                            inst.components.locomotor:SetExternalSpeedMultiplier(inst, "rogue_enrage", 1.3)
                        end
                        inst:DoTaskInTime(8, function()
                            if inst and inst:IsValid() then
                                inst.rogue_enraged = false
                                if inst.components.combat and inst.components.combat.externaldamagemultipliers then
                                    inst.components.combat.externaldamagemultipliers:RemoveModifier(inst, "rogue_enrage")
                                end
                                if inst.components.locomotor then
                                    inst.components.locomotor:RemoveExternalSpeedMultiplier(inst, "rogue_enrage")
                                end
                            end
                        end)
                    end
                end)
            end
        elseif affix_id == "toxic" then
            if not ent.rogue_toxic_hooked then
                ent.rogue_toxic_hooked = true
                ent:ListenForEvent("onhitother", function(inst, data)
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    if target.rogue_toxic_cd then return end
                    target.rogue_toxic_cd = true
                    target:DoTaskInTime(2, function(t)
                        if t and t:IsValid() then t.rogue_toxic_cd = nil end
                    end)
                    local tick_count = 0
                    target:DoPeriodicTask(1, function(t)
                        tick_count = tick_count + 1
                        if t and t:IsValid() and t.components.health and not t.components.health:IsDead() and tick_count <= 4 then
                            t.components.health:DoDelta(-8, nil, "rogue_toxic")
                        else
                            if t and t:IsValid() then t.rogue_toxic_cd = nil end
                        end
                    end)
                end)
            end
        elseif affix_id == "mirror" then
            if not ent.rogue_mirror_hooked then
                ent.rogue_mirror_hooked = true
                ent:ListenForEvent("attacked", function(inst, data)
                    if not data or not data.attacker then return end
                    if math.random() < 0.2 then
                        local attacker = data.attacker
                        if attacker and attacker:IsValid() and attacker.components.combat and attacker.components.health and not attacker.components.health:IsDead() then
                            local reflect_dmg = (data.damage or 20) * 0.5
                            attacker.components.health:DoDelta(-reflect_dmg, nil, "rogue_mirror", nil, inst, true)
                        end
                    end
                end)
            end
        elseif affix_id == "soul_link" then
            if not ent.rogue_soul_link_hooked then
                ent.rogue_soul_link_hooked = true
                ent:ListenForEvent("onhitother", function(inst, data)
                    local target = data and data.target
                    if not target or not target:IsValid() then return end
                    if not target.components.combat or not target.components.health then return end
                    local x, y, z = inst.Transform:GetWorldPosition()
                    local ents = TheSim:FindEntities(x, y, z, 12, {"_combat"}, {"player", "companion", "INLIMBO", "NOCLICK", "FX"})
                    local allies = {}
                    for _, e in ipairs(ents) do
                        if e ~= inst and e:IsValid() and e.components.health and not e.components.health:IsDead() and e:HasTag("rogue_affix") then
                            table.insert(allies, e)
                        end
                    end
                    if #allies > 0 then
                        local heal = (data.damage or 10) * 0.15
                        for _, ally in ipairs(allies) do
                            if ally.components.health then
                                ally.components.health:DoDelta(heal, nil, "rogue_soul_link")
                            end
                        end
                    end
                end)
            end
        end
    end

    local function ApplyEliteAffix(ent, day, force)
        if not CanApplyAffixToEntity(ent) or ent:HasTag("rogue_affix") then return false end

        local base_chance = deps.Config.ELITE_AFFIX_CHANCE + math.floor((day - 1) / 25) * 0.03
        local chance = math.min(deps.CONST.MAX_ELITE_AFFIX_CHANCE, base_chance)
        if not force and math.random() > chance then return false end

        local affix1 = PickWeightedAffix()
        if not affix1 then return false end

        local affixes = { affix1 }
        local second_chance = math.min(deps.CONST.MAX_SECOND_AFFIX_CHANCE, deps.Config.SECOND_AFFIX_CHANCE + math.floor((day - 1) / 35) * 0.03)
        if math.random() < second_chance then
            local excluded = { [affix1.id] = true }
            if deps.AFFIX_CONFLICTS[affix1.id] then
                for k, _ in pairs(deps.AFFIX_CONFLICTS[affix1.id]) do excluded[k] = true end
            end
            local affix2 = PickWeightedAffix(excluded)
            if affix2 then table.insert(affixes, affix2) end
        end

        local names = {}
        for _, affix in ipairs(affixes) do
            ApplyAffixStats(ent, affix)
            ApplyAffixBehavior(ent, affix.id, day)
            table.insert(names, affix.name)
            ent:AddTag("rogue_affix_" .. affix.id)
        end

        ent:AddTag("rogue_affix")
        ent.rogue_affix_name = table.concat(names, "、")
        ent.rogue_affix_count = #affixes

        if not ent.rogue_size_mod then
            ent.Transform:SetScale(1.35, 1.35, 1.35)
        end

        if ent.components.colouradder then
            ent.components.colouradder:PushColour("elite", 0.3, 0, 0, 0)
        else
            ent.AnimState:SetMultColour(1, 0.5, 0.5, 1)
        end

        local fx = deps.SpawnPrefab("statue_transition_2")
        if fx then
            fx.Transform:SetPosition(ent.Transform:GetWorldPosition())
            fx.Transform:SetScale(0.8, 0.8, 0.8)
        end

        return true
    end

    local function SpawnBossMinions(boss, count)
        local players = deps.CollectAlivePlayers()
        if #players == 0 then return end
        for _ = 1, count do
            local prefab = deps.PickRandom({ "hound", "spider_warrior", "merm", "pigman" })
            local minion = deps.SpawnPrefab(prefab)
            if minion then
                local pt = boss:GetPosition()
                local offset = deps.FindWalkableOffset(pt, math.random() * 2 * deps.PI, 4, 8, true, false)
                minion.Transform:SetPosition((offset and (pt + offset) or pt):Get())
                if minion.components.combat then
                    minion.components.combat:SetTarget(deps.PickRandom(players))
                end
                deps.SpawnPrefab("spawn_fx_medium").Transform:SetPosition(minion.Transform:GetWorldPosition())
            end
        end
    end

    local function ApplyBossPhaseVisual(inst, phase)
        if deps.Config.BOSS_PHASE_FX_MODE <= 0 or not inst:IsValid() then return end
        if inst.Light then
            if phase == 60 then
                inst.Light:SetIntensity(0.45); inst.Light:SetRadius(1.6); inst.Light:SetColour(1, 0.35, 0.2)
            else
                inst.Light:SetIntensity(0.58); inst.Light:SetRadius(2.2); inst.Light:SetColour(0.9, 0.15, 0.15)
            end
            inst.Light:Enable(true)
        end
    end

    local function SetupBossPhases(ent, day)
        if not ent or not ent:IsValid() or deps.Config.BOSS_PHASE_MODE <= 0 or not ent.components.health then return end
        if deps.BossMechanics then
            local tpl = deps.BossMechanics.AttachBossTemplate(ent, day)
            if tpl and deps.Config.AFFIX_ANNOUNCE_MODE >= 1 then
                deps.Announce(deps.GetEntityName(ent) .. " 机制模板：" .. tpl.name)
            end
        end

        ent.rogue_phase_60 = false
        ent.rogue_phase_30 = false

        ent:ListenForEvent("healthdelta", function(inst)
            if not inst:IsValid() or not inst.components.health or inst.components.health:IsDead() then return end
            local pct = inst.components.health:GetPercent()

            if not inst.rogue_phase_60 and pct <= 0.6 then
                inst.rogue_phase_60 = true
                local mult = (deps.Config.BOSS_PHASE_MODE == 2) and 1.4 or 1.25
                if inst.rogue_set_damage_mult then
                    inst:rogue_set_damage_mult("rogue_phase_60", mult)
                elseif inst.components.combat then
                    inst.components.combat:SetDefaultDamage(inst.components.combat.defaultdamage * mult)
                end
                if inst.rogue_set_speed_mult then
                    inst:rogue_set_speed_mult("rogue_phase_60", 1.1)
                elseif inst.components.locomotor then
                    inst.components.locomotor.runspeed = inst.components.locomotor.runspeed * 1.1
                end
                ApplyBossPhaseVisual(inst, 60)
                deps.Announce(deps.GetEntityName(inst) .. " 进入狂暴阶段！攻击大幅提升！")
            end

            if not inst.rogue_phase_30 and pct <= 0.3 then
                inst.rogue_phase_30 = true
                local count = math.max(1, deps.Config.BOSS_PHASE_MINION_COUNT + math.floor((day - 1) / 40))
                ApplyBossPhaseVisual(inst, 30)
                SpawnBossMinions(inst, count)
                deps.Announce(deps.GetEntityName(inst) .. " 濒死狂怒！召唤了援军！")
            end
        end)
    end

    S.ApplyEliteAffix = ApplyEliteAffix
    S.SetupBossPhases = SetupBossPhases
    return S
end

return M
