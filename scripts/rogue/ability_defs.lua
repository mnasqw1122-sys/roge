--[[
    文件说明：ability_defs.lua
    功能：装备能力（附魔）定义表。
    包含所有武器/防具/装备的附魔能力定义及其回调函数。
    从 drop_system.lua 拆分而来，作为独立的数据模块。
]]
local M = {}

-- 函数说明：在指定位置生成带缩放的视觉特效
function M.SpawnScaledFx(SpawnPrefab, prefab, pt, scale)
    if not (SpawnPrefab and pt and prefab) then
        return nil
    end
    local fx = SpawnPrefab(prefab)
    if fx and fx.Transform then
        fx.Transform:SetPosition(pt.x, pt.y, pt.z)
        if scale and fx.Transform.SetScale then
            fx.Transform:SetScale(scale, scale, scale)
        end
    end
    return fx
end

-- 函数说明：触发星陨重击能力（纯视觉陨石+延时伤害，不破坏地形）
function M.TriggerMeteorStrike(deps, attacker, target, damage)
    if not (target and target:IsValid()) then
        return
    end
    local SpawnScaledFx = M.SpawnScaledFx
    local telegraph_pt = target:GetPosition()
    SpawnScaledFx(deps.SpawnPrefab, "statue_transition_2", telegraph_pt, 0.85)

    target:DoTaskInTime(0.35, function(inst)
        if not (inst and inst:IsValid()) then
            return
        end
        local pt = inst:GetPosition()

        local meteor = deps.SpawnPrefab("shadowmeteor")
        if meteor then
            meteor.Transform:SetPosition(pt.x, pt.y, pt.z)

            if meteor.autosizetask then
                meteor.autosizetask:Cancel()
                meteor.autosizetask = nil
            end
            if meteor.striketask then
                meteor.striketask:Cancel()
                meteor.striketask = nil
            end
            if meteor.warnshadow then
                meteor.warnshadow:Remove()
                meteor.warnshadow = nil
            end

            meteor.AnimState:PlayAnimation("crash")
            meteor:ListenForEvent("animover", meteor.Remove)
            meteor:DoTaskInTime(3, meteor.Remove)

            meteor:DoTaskInTime(0.33, function(m)
                if m and m:IsValid() and m.SoundEmitter then
                    m.SoundEmitter:PlaySound("dontstarve/common/meteor_impact")
                end
                SpawnScaledFx(deps.SpawnPrefab, "explode_reskin", pt, 2.2)

                if inst and inst:IsValid() then
                    local source = attacker and attacker:IsValid() and attacker or nil
                    if inst.components and inst.components.combat then
                        inst.components.combat:GetAttacked(source, damage or 80)
                    elseif inst.components and inst.components.health then
                        inst.components.health:DoDelta(-(damage or 80), nil, "rogue_meteor")
                    end
                end
            end)
        else
            local world = deps.GetWorld and deps.GetWorld() or nil
            if world and world.PushEvent and deps.Vector3 then
                world:PushEvent("ms_sendlightningstrike", deps.Vector3(pt.x, pt.y, pt.z))
            else
                SpawnScaledFx(deps.SpawnPrefab, "lightning", pt)
            end
            SpawnScaledFx(deps.SpawnPrefab, "explode_reskin", pt, 2.2)

            if inst and inst:IsValid() then
                local source = attacker and attacker:IsValid() and attacker or nil
                if inst.components and inst.components.combat then
                    inst.components.combat:GetAttacked(source, damage or 80)
                elseif inst.components and inst.components.health then
                    inst.components.health:DoDelta(-(damage or 80), nil, "rogue_meteor")
                end
            end
        end
    end)
end

-- 函数说明：构建全部装备能力定义表，deps为外部依赖注入
function M.Build(deps)
    local SpawnScaledFx = M.SpawnScaledFx
    local TriggerMeteorStrike = function(attacker, target, damage)
        M.TriggerMeteorStrike(deps, attacker, target, damage)
    end

    return {
        -- 武器能力
        {
            id = "ignite", name = "烈焰", slot = "weapon", weight = 10, min_day = 1,
            desc = "攻击有 20% 几率点燃敌人",
            onattack = function(inst, attacker, target)
                if target and target.components.burnable and not target.components.burnable:IsBurning() and math.random() < 0.2 then
                    target.components.burnable:Ignite(true, attacker)
                end
            end
        },
        {
            id = "frost", name = "冰霜", slot = "weapon", weight = 10, min_day = 1,
            desc = "攻击有 20% 几率大幅冰冻敌人",
            onattack = function(inst, attacker, target)
                if target and target.components.freezable and math.random() < 0.2 then
                    target.components.freezable:AddColdness(2)
                    if target.components.freezable.SpawnShatterFX then
                        target.components.freezable:SpawnShatterFX()
                    end
                end
            end
        },
        {
            id = "lifesteal", name = "饮血", slot = "weapon", weight = 8, min_day = 12,
            desc = "每次攻击恢复 2 点生命值",
            onattack = function(inst, attacker, target)
                if attacker and attacker.components.health and not attacker.components.health:IsDead() then
                    attacker.components.health:DoDelta(2)
                end
            end
        },
        {
            id = "meteor", name = "星陨", slot = "weapon", weight = 5, min_day = 25,
            desc = "攻击有 10% 几率延迟召来星陨重击目标",
            onattack = function(inst, attacker, target)
                if target and target:IsValid() and math.random() < 0.1 then
                    TriggerMeteorStrike(attacker, target, 80)
                end
            end
        },
        {
            id = "lightning", name = "雷霆", slot = "weapon", weight = 8, min_day = 15,
            desc = "攻击有 15% 几率召唤闪电",
            onattack = function(inst, attacker, target)
                if target and target:IsValid() and math.random() < 0.15 then
                    local pt = target:GetPosition()
                    local world = deps.GetWorld and deps.GetWorld() or (deps.GLOBAL and deps.GLOBAL.TheWorld)
                    if world and deps.GLOBAL and deps.GLOBAL.Vector3 then
                        world:PushEvent("ms_sendlightningstrike", deps.GLOBAL.Vector3(pt.x, pt.y, pt.z))
                    elseif world and deps.Vector3 then
                        world:PushEvent("ms_sendlightningstrike", deps.Vector3(pt.x, pt.y, pt.z))
                    else
                        local lightning = deps.SpawnPrefab("lightning")
                        if lightning then
                            lightning.Transform:SetPosition(pt.x, pt.y, pt.z)
                        end
                    end
                    if target.components.combat then
                        target.components.combat:GetAttacked(attacker, 40)
                    end
                end
            end
        },
        {
            id = "chain_lightning", name = "闪电链", slot = "weapon", weight = 6, min_day = 15,
            desc = "攻击有 15% 几率释放闪电链，在周围敌人间弹射",
            onattack = function(inst, attacker, target)
                if target and target:IsValid() and math.random() < 0.15 then
                    local x, y, z = target.Transform:GetWorldPosition()
                    local ents = deps.TheSim:FindEntities(x, y, z, 8, {"_combat"}, {"player", "companion", "INLIMBO", "NOCLICK", "FX"})
                    local count = 0
                    local dmg = (inst.components.weapon and inst.components.weapon.GetDamage and inst.components.weapon:GetDamage(attacker, target) or 34) * 0.5
                    for _, ent in ipairs(ents) do
                        if ent ~= attacker and ent.components.combat and ent.components.health and not ent.components.health:IsDead() then
                            ent:DoTaskInTime(count * 0.2, function(e)
                                if e and e:IsValid() and e.components.health and not e.components.health:IsDead() then
                                    local ept = e:GetPosition()
                                    if deps.SpawnPrefab then
                                        local lfx = deps.SpawnPrefab("sparks") or deps.SpawnPrefab("lightning")
                                        if lfx then
                                            lfx.Transform:SetPosition(ept.x, ept.y, ept.z)
                                        end
                                    end
                                    e.components.combat:GetAttacked(attacker, dmg)
                                end
                            end)
                            count = count + 1
                            if count >= 4 then break end
                        end
                    end
                end
            end
        },
        {
            id = "windfury", name = "风怒", slot = "weapon", weight = 4, min_day = 18,
            desc = "每次攻击有 20% 几率触发残影连击，在 0.5 秒内对目标追加 2 次攻击（造成 60% 伤害）",
            onattack = function(inst, attacker, target)
                if target and target:IsValid() and target.components.health and not target.components.health:IsDead() then
                    if math.random() < 0.2 and not inst._windfury_triggering then
                        inst._windfury_triggering = true

                        local dmg = (inst.components.weapon and inst.components.weapon.GetDamage and inst.components.weapon:GetDamage(attacker, target) or 34) * 0.6

                        target:DoTaskInTime(0.2, function(t)
                            if t and t:IsValid() and t.components.combat and t.components.health and not t.components.health:IsDead() then
                                t.components.combat:GetAttacked(attacker, dmg)
                                if deps.SpawnPrefab then
                                    local fx = deps.SpawnPrefab("sparks") or deps.SpawnPrefab("impact")
                                    if fx then fx.Transform:SetPosition(t.Transform:GetWorldPosition()) end
                                end
                            end
                        end)

                        target:DoTaskInTime(0.4, function(t)
                            if t and t:IsValid() and t.components.combat and t.components.health and not t.components.health:IsDead() then
                                t.components.combat:GetAttacked(attacker, dmg)
                                if deps.SpawnPrefab then
                                    local fx = deps.SpawnPrefab("sparks") or deps.SpawnPrefab("impact")
                                    if fx then fx.Transform:SetPosition(t.Transform:GetWorldPosition()) end
                                end
                            end
                            if inst and inst:IsValid() then
                                inst._windfury_triggering = false
                            end
                        end)
                    end
                end
            end
        },
        {
            id = "executioner", name = "斩杀", slot = "weapon", weight = 5, min_day = 20,
            desc = "对生命值低于 20% 的非 Boss 敌人造成致命一击；对 Boss 造成双倍伤害",
            onattack = function(inst, attacker, target)
                if target and target:IsValid() and target.components.health and not target.components.health:IsDead() then
                    local hp_pct = target.components.health:GetPercent()
                    local is_boss = target:HasTag("epic")
                    if hp_pct < 0.2 then
                        if not is_boss then
                            if deps.SpawnPrefab then
                                local fx = deps.SpawnPrefab("shadowstrike") or deps.SpawnPrefab("impact")
                                if fx then fx.Transform:SetPosition(target.Transform:GetWorldPosition()) end
                            end
                            target.components.health:DoDelta(-target.components.health.currenthealth, nil, "executioner")
                        else
                            local weapon_dmg = (inst.components.weapon and inst.components.weapon.GetDamage) and inst.components.weapon:GetDamage(attacker, target) or 34
                            target.components.health:DoDelta(-weapon_dmg, nil, "executioner")
                            if deps.SpawnPrefab then
                                local fx = deps.SpawnPrefab("impact")
                                if fx then fx.Transform:SetPosition(target.Transform:GetWorldPosition()) end
                            end
                        end
                    end
                end
            end
        },
        {
            id = "void_tear", name = "虚空撕裂", slot = "weapon", weight = 5, min_day = 25,
            desc = "每次攻击施加破甲印记(每层+5%受伤，最高5层)，叠满后引爆造成小范围暗影伤害",
            onattack = function(inst, attacker, target)
                if target and target:IsValid() and target.components.combat and target.components.health and not target.components.health:IsDead() then
                    target.rogue_void_stacks = (target.rogue_void_stacks or 0) + 1

                    if target.components.combat.externaldamagetakenmultipliers then
                        target.components.combat.externaldamagetakenmultipliers:SetModifier(inst, 1 + target.rogue_void_stacks * 0.05, "void_tear_debuff")
                    end

                    if deps.SpawnPrefab then
                        local fx = deps.SpawnPrefab("shadow_despawn") or deps.SpawnPrefab("statue_transition")
                        if fx then
                            fx.Transform:SetPosition(target.Transform:GetWorldPosition())
                            fx.Transform:SetScale(0.3 + target.rogue_void_stacks * 0.1, 0.3 + target.rogue_void_stacks * 0.1, 0.3 + target.rogue_void_stacks * 0.1)
                        end
                    end

                    if target.rogue_void_task then target.rogue_void_task:Cancel() end
                    target.rogue_void_task = target:DoTaskInTime(5, function(t)
                        if t and t:IsValid() then
                            t.rogue_void_stacks = 0
                            if t.components.combat and t.components.combat.externaldamagetakenmultipliers then
                                t.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, "void_tear_debuff")
                            end
                        end
                    end)

                    if target.rogue_void_stacks >= 5 then
                        target.rogue_void_stacks = 0
                        if target.components.combat.externaldamagetakenmultipliers then
                            target.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, "void_tear_debuff")
                        end
                        if target.rogue_void_task then target.rogue_void_task:Cancel() end

                        local x, y, z = target.Transform:GetWorldPosition()
                        if deps.SpawnPrefab then
                            local blast = deps.SpawnPrefab("shadowstrike") or deps.SpawnPrefab("explode_reskin")
                            if blast then
                                blast.Transform:SetPosition(x, y, z)
                                blast.Transform:SetScale(1.5, 1.5, 1.5)
                            end
                        end

                        local ents = deps.TheSim:FindEntities(x, y, z, 5, {"_combat"}, {"player", "companion", "INLIMBO", "NOCLICK", "FX"})
                        local blast_dmg = (inst.components.weapon and inst.components.weapon.GetDamage and inst.components.weapon:GetDamage(attacker, target) or 34) * 1.5
                        for _, ent in ipairs(ents) do
                            if ent and ent:IsValid() and ent.components.combat and ent.components.health and not ent.components.health:IsDead() then
                                ent.components.combat:GetAttacked(attacker, blast_dmg)
                            end
                        end
                    end
                end
            end
        },
        {
            id = "phantom_strike", name = "幻影剑舞", slot = "weapon", weight = 3, min_day = 30,
            desc = "连续攻击时，每5次攻击触发一次幻影连斩，对目标及周围敌人造成80%武器伤害",
            onattack = function(inst, attacker, target)
                if not attacker or not attacker:IsValid() then return end
                attacker._phantom_hits = (attacker._phantom_hits or 0) + 1

                if attacker._phantom_hits >= 5 then
                    attacker._phantom_hits = 0

                    local weapon_dmg = (inst.components.weapon and inst.components.weapon.GetDamage and inst.components.weapon:GetDamage(attacker, target) or 34) * 0.8

                    if target and target:IsValid() and target.components.combat and target.components.health and not target.components.health:IsDead() then
                        target.components.combat:GetAttacked(attacker, weapon_dmg)
                    end

                    if deps.SpawnPrefab then
                        local fx = deps.SpawnPrefab("shadowstrike")
                        if fx and target and target:IsValid() then
                            fx.Transform:SetPosition(target.Transform:GetWorldPosition())
                        end
                    end

                    local x, y, z = attacker.Transform:GetWorldPosition()
                    local ents = deps.TheSim:FindEntities(x, y, z, 6, {"_combat"}, {"player", "companion", "INLIMBO", "NOCLICK", "FX"})
                    local hit_count = 0
                    for _, ent in ipairs(ents) do
                        if ent ~= target and ent:IsValid() and ent.components.combat and ent.components.health and not ent.components.health:IsDead() then
                            ent:DoTaskInTime(hit_count * 0.15, function(e)
                                if e and e:IsValid() and e.components.health and not e.components.health:IsDead() then
                                    e.components.combat:GetAttacked(attacker, weapon_dmg * 0.6)
                                    if deps.SpawnPrefab then
                                        local hit_fx = deps.SpawnPrefab("sparks")
                                        if hit_fx then hit_fx.Transform:SetPosition(e.Transform:GetWorldPosition()) end
                                    end
                                end
                            end)
                            hit_count = hit_count + 1
                            if hit_count >= 3 then break end
                        end
                    end
                end
            end
        },

        -- 防具/装备能力
        {
            id = "shield", name = "护盾", slot = "armor", weight = 8, min_day = 10,
            desc = "被攻击时有 15% 几率规避该次伤害并获得 3 秒无敌",
            onattacked = function(inst, owner, attacker, damage)
                if math.random() < 0.15 and not inst._shield_cd then
                    inst._shield_cd = true
                    inst:DoTaskInTime(10, function() inst._shield_cd = false end)
                    if owner.components.health and not owner.components.health:IsDead() then
                        owner.components.health:SetInvincible(true)
                        owner:DoTaskInTime(3, function(o)
                            if o and o.components.health then o.components.health:SetInvincible(false) end
                        end)
                    end
                    if deps.SpawnPrefab then
                        local fx = deps.SpawnPrefab("forcefieldfx")
                        if fx then
                            fx.entity:SetParent(owner.entity)
                            fx.Transform:SetPosition(0, 0.2, 0)
                            owner:DoTaskInTime(3, function() fx:Remove() end)
                        end
                    end
                end
            end
        },
        {
            id = "winter_insulation", name = "御寒", slot = "equippable", weight = 10, min_day = 1,
            desc = "提供极高的保暖效果并持续产热，无惧严寒",
            onequip = function(inst, owner)
                if inst.components.insulator then
                    inst._old_insulation = inst.components.insulator.insulation
                    inst._old_insulation_type = inst.components.insulator.type
                    inst.components.insulator:SetInsulation(9000)
                    inst.components.insulator:SetWinter()
                else
                    inst:AddComponent("insulator")
                    inst.components.insulator:SetInsulation(9000)
                    inst.components.insulator:SetWinter()
                    inst._added_insulator = true
                end

                if inst.components.heater then
                    inst._old_equippedheat = inst.components.heater.equippedheat
                    inst._old_exo = inst.components.heater:IsExothermic()
                    inst._old_endo = inst.components.heater:IsEndothermic()
                    inst.components.heater.equippedheat = 30
                    inst.components.heater:SetThermics(true, false)
                else
                    inst:AddComponent("heater")
                    inst.components.heater.equippedheat = 30
                    inst.components.heater:SetThermics(true, false)
                    inst._added_heater = true
                end
            end,
            onunequip = function(inst, owner)
                if inst._added_insulator then
                    inst:RemoveComponent("insulator")
                    inst._added_insulator = nil
                elseif inst.components.insulator then
                    inst.components.insulator:SetInsulation(inst._old_insulation or 0)
                    if inst._old_insulation_type == "summer" then
                        inst.components.insulator:SetSummer()
                    else
                        inst.components.insulator:SetWinter()
                    end
                end

                if inst._added_heater then
                    inst:RemoveComponent("heater")
                    inst._added_heater = nil
                elseif inst.components.heater then
                    inst.components.heater.equippedheat = inst._old_equippedheat
                    inst.components.heater:SetThermics(inst._old_exo, inst._old_endo)
                end
            end
        },
        {
            id = "summer_cooling", name = "避暑", slot = "equippable", weight = 10, min_day = 1,
            desc = "提供极高的防热效果并持续制冷，无惧酷暑",
            onequip = function(inst, owner)
                if inst.components.insulator then
                    inst._old_insulation = inst.components.insulator.insulation
                    inst._old_insulation_type = inst.components.insulator.type
                    inst.components.insulator:SetInsulation(9000)
                    inst.components.insulator:SetSummer()
                else
                    inst:AddComponent("insulator")
                    inst.components.insulator:SetInsulation(9000)
                    inst.components.insulator:SetSummer()
                    inst._added_insulator = true
                end

                if inst.components.heater then
                    inst._old_equippedheat = inst.components.heater.equippedheat
                    inst._old_exo = inst.components.heater:IsExothermic()
                    inst._old_endo = inst.components.heater:IsEndothermic()
                    inst.components.heater.equippedheat = 25
                    inst.components.heater:SetThermics(false, true)
                else
                    inst:AddComponent("heater")
                    inst.components.heater.equippedheat = 25
                    inst.components.heater:SetThermics(false, true)
                    inst._added_heater = true
                end
            end,
            onunequip = function(inst, owner)
                if inst._added_insulator then
                    inst:RemoveComponent("insulator")
                    inst._added_insulator = nil
                elseif inst.components.insulator then
                    inst.components.insulator:SetInsulation(inst._old_insulation or 0)
                    if inst._old_insulation_type == "winter" then
                        inst.components.insulator:SetWinter()
                    else
                        inst.components.insulator:SetSummer()
                    end
                end

                if inst._added_heater then
                    inst:RemoveComponent("heater")
                    inst._added_heater = nil
                elseif inst.components.heater then
                    inst.components.heater.equippedheat = inst._old_equippedheat
                    inst.components.heater:SetThermics(inst._old_exo, inst._old_endo)
                end
            end
        },
        {
            id = "light", name = "荧光", slot = "equippable", weight = 10, min_day = 1,
            desc = "装备时发出光芒，照亮黑夜",
            onequip = function(inst, owner)
                if deps.SpawnPrefab then
                    inst._owner_light = deps.SpawnPrefab("minerhatlight")
                    if inst._owner_light then
                        inst._owner_light.entity:SetParent(owner.entity)
                    end
                end
            end,
            onunequip = function(inst, owner)
                if inst._owner_light then
                    inst._owner_light:Remove()
                    inst._owner_light = nil
                end
            end
        },
        {
            id = "regen", name = "复苏", slot = "equippable", weight = 8, min_day = 5,
            desc = "装备时缓慢恢复生命值",
            onequip = function(inst, owner)
                if inst._regen_task then inst._regen_task:Cancel() end
                inst._regen_task = inst:DoPeriodicTask(4, function()
                    if owner and owner.components.health and not owner.components.health:IsDead() then
                        owner.components.health:DoDelta(1)
                    end
                end)
            end,
            onunequip = function(inst, owner)
                if inst._regen_task then
                    inst._regen_task:Cancel()
                    inst._regen_task = nil
                end
            end
        },
        {
            id = "greed_pact", name = "贪婪契约", slot = "equippable", weight = 5, min_day = 10,
            desc = "大幅提升击杀怪物获取的积分和高品质掉落概率，但受到的伤害增加 20%",
            onequip = function(inst, owner)
                if owner.components.combat and owner.components.combat.externaldamagetakenmultipliers then
                    owner.components.combat.externaldamagetakenmultipliers:SetModifier(inst, 1.20, "greed_pact")
                end
                if not owner:HasTag("rogue_greed_pact") then
                    owner:AddTag("rogue_greed_pact")
                end
            end,
            onunequip = function(inst, owner)
                if owner.components.combat and owner.components.combat.externaldamagetakenmultipliers then
                    owner.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, "greed_pact")
                end
                if owner:HasTag("rogue_greed_pact") then
                    owner:RemoveTag("rogue_greed_pact")
                end
            end
        },
        {
            id = "thorns", name = "荆棘", slot = "armor", weight = 8, min_day = 8,
            desc = "受到攻击时反弹 50% 伤害",
            onattacked = function(inst, owner, attacker, damage)
                if attacker and attacker.components.combat and damage and damage > 0 and not inst._thorns_cd then
                    inst._thorns_cd = true
                    inst:DoTaskInTime(0.1, function() inst._thorns_cd = false end)
                    attacker.components.combat:GetAttacked(owner, damage * 0.5)
                end
            end
        },
        {
            id = "frost_armor", name = "极寒领域", slot = "armor", weight = 5, min_day = 12,
            desc = "受到攻击时使攻击者叠加寒冷值并减速，连续攻击多次的敌人将被直接冻结",
            onattacked = function(inst, owner, attacker, damage)
                if attacker and attacker:IsValid() and not (attacker.components.health and attacker.components.health:IsDead()) then
                    if attacker.components.locomotor then
                        attacker.components.locomotor:SetExternalSpeedMultiplier(attacker, "rogue_frost_armor", 0.7)
                        attacker:DoTaskInTime(3, function(a)
                            if a and a:IsValid() and a.components.locomotor then
                                a.components.locomotor:RemoveExternalSpeedMultiplier(a, "rogue_frost_armor")
                            end
                        end)
                    end

                    if attacker.components.freezable then
                        attacker.components.freezable:AddColdness(1)
                        if attacker.components.freezable.SpawnShatterFX then
                            attacker.components.freezable:SpawnShatterFX()
                        end
                    end
                end
            end
        },
        {
            id = "kinetic_deflection", name = "动能偏转", slot = "armor", weight = 4, min_day = 20,
            desc = "每隔 10 秒获得一层偏转护盾，完全闪避下一次受到的伤害，并恢复少量精神值",
            onequip = function(inst, owner)
                if inst._kinetic_task then inst._kinetic_task:Cancel() end

                inst._kinetic_task = inst:DoPeriodicTask(10, function()
                    if not owner or not owner:IsValid() then return end

                    if not owner._kinetic_shield_active then
                        owner._kinetic_shield_active = true
                        if deps.SpawnPrefab then
                            local fx = deps.SpawnPrefab("forcefieldfx") or deps.SpawnPrefab("small_puff")
                            if fx then
                                fx.entity:SetParent(owner.entity)
                                fx.Transform:SetPosition(0, 0.2, 0)
                                owner._kinetic_fx = fx
                            end
                        end
                        if owner.components.talker then
                            owner.components.talker:Say("偏转力场就绪！")
                        end
                    end
                end)

                if not inst._on_attacked_kinetic then
                    inst._on_attacked_kinetic = function(owner_inst, data)
                        if owner_inst._kinetic_shield_active and data and data.damage and data.damage > 0 then
                            owner_inst._kinetic_shield_active = false

                            if owner_inst._kinetic_fx and owner_inst._kinetic_fx:IsValid() then
                                owner_inst._kinetic_fx:Remove()
                                owner_inst._kinetic_fx = nil
                            end

                            if owner_inst.components.sanity then
                                owner_inst.components.sanity:DoDelta(15)
                            end

                            if owner_inst.components.health and not owner_inst.components.health:IsDead() then
                                owner_inst.components.health:SetInvincible(true)
                                owner_inst:DoTaskInTime(0.1, function(o)
                                    if o and o.components.health then
                                        o.components.health:SetInvincible(false)
                                    end
                                end)
                            end
                        end
                    end
                    owner:ListenForEvent("attacked", inst._on_attacked_kinetic)
                end
            end,
            onunequip = function(inst, owner)
                if inst._kinetic_task then
                    inst._kinetic_task:Cancel()
                    inst._kinetic_task = nil
                end
                if inst._on_attacked_kinetic then
                    owner:RemoveEventCallback("attacked", inst._on_attacked_kinetic)
                    inst._on_attacked_kinetic = nil
                end
                owner._kinetic_shield_active = false
                if owner._kinetic_fx and owner._kinetic_fx:IsValid() then
                    owner._kinetic_fx:Remove()
                    owner._kinetic_fx = nil
                end
            end
        },
        {
            id = "earthquake", name = "大地践踏", slot = "armor", weight = 3, min_day = 25,
            desc = "单次受到超过最大生命值 15% 的伤害时，触发地震波，眩晕周围敌人并反震伤害",
            onattacked = function(inst, owner, attacker, damage)
                if owner and owner.components.health and damage and damage > 0 then
                    local threshold = (owner.components.health.maxhealth or 100) * 0.15
                    if damage >= threshold and not inst._earthquake_cd then
                        inst._earthquake_cd = true
                        inst:DoTaskInTime(5, function() inst._earthquake_cd = false end)

                        local x, y, z = owner.Transform:GetWorldPosition()
                        deps.GLOBAL.ShakeAllCameras(deps.GLOBAL.CAMERASHAKE.FULL, 0.7, 0.02, 1, owner, 40)

                        if deps.SpawnPrefab then
                            local ring = deps.SpawnPrefab("deer_ice_circle") or deps.SpawnPrefab("groundpoundring_fx")
                            if ring then
                                ring.Transform:SetPosition(x, y, z)
                                ring.Transform:SetScale(0.8, 0.8, 0.8)
                            end
                        end

                        local reflect_dmg = damage * 1.5

                        local ents = deps.TheSim:FindEntities(x, y, z, 6, {"_combat"}, {"player", "companion", "INLIMBO", "NOCLICK", "FX", "flying"})
                        for _, ent in ipairs(ents) do
                            if ent and ent:IsValid() and ent.components.combat and ent.components.health and not ent.components.health:IsDead() then
                                ent.components.combat:GetAttacked(owner, reflect_dmg)
                                if ent.sg and ent.sg.GoToState then
                                    if ent.components.health:IsDead() then
                                        -- 已经死了就不打断了
                                    elseif ent.sg:HasState("hit") then
                                        ent.sg:GoToState("hit")
                                    end
                                end
                                if ent.components.locomotor then
                                    ent.components.locomotor:SetExternalSpeedMultiplier(ent, "rogue_earthquake", 0.1)
                                    ent:DoTaskInTime(2, function(e)
                                        if e and e:IsValid() and e.components.locomotor then
                                            e.components.locomotor:RemoveExternalSpeedMultiplier(e, "rogue_earthquake")
                                        end
                                    end)
                                end
                            end
                        end
                    end
                end
            end
        },
        {
            id = "time_warp", name = "时空扭曲", slot = "equippable", weight = 3, min_day = 25,
            desc = "生命值低于 30% 时自动展开时空力场，大范围减缓敌人动作，持续 6 秒。冷却 1 天",
            onequip = function(inst, owner)
                if not inst._on_health_time_warp then
                    inst._on_health_time_warp = function(owner_inst, data)
                        if inst._time_warp_cd then return end

                        local hp_pct = owner_inst.components.health and owner_inst.components.health:GetPercent() or 1
                        if hp_pct < 0.3 then
                            inst._time_warp_cd = true
                            inst:DoTaskInTime(480, function() inst._time_warp_cd = false end)

                            if owner_inst.components.talker then
                                owner_inst.components.talker:Say("时空扭曲力场已展开！")
                            end

                            local x, y, z = owner_inst.Transform:GetWorldPosition()

                            if deps.SpawnPrefab then
                                local fx = deps.SpawnPrefab("staffcastfx") or deps.SpawnPrefab("deer_ice_circle")
                                if fx then
                                    fx.Transform:SetPosition(x, y, z)
                                    fx.Transform:SetScale(2, 2, 2)
                                end
                            end

                            local ents = deps.TheSim:FindEntities(x, y, z, 12, {"_combat"}, {"player", "companion", "INLIMBO", "NOCLICK", "FX"})
                            for _, ent in ipairs(ents) do
                                if ent and ent:IsValid() and ent.components.locomotor then
                                    ent.components.locomotor:SetExternalSpeedMultiplier(ent, "rogue_time_warp", 0.2)
                                    if ent.AnimState then
                                        ent.AnimState:SetDeltaTimeMultiplier(0.3)
                                    end

                                    ent:DoTaskInTime(6, function(e)
                                        if e and e:IsValid() then
                                            if e.components.locomotor then
                                                e.components.locomotor:RemoveExternalSpeedMultiplier(e, "rogue_time_warp")
                                            end
                                            if e.AnimState then
                                                e.AnimState:SetDeltaTimeMultiplier(1.0)
                                            end
                                        end
                                    end)
                                end
                            end
                        end
                    end
                    owner:ListenForEvent("healthdelta", inst._on_health_time_warp)
                end
            end,
            onunequip = function(inst, owner)
                if inst._on_health_time_warp then
                    owner:RemoveEventCallback("healthdelta", inst._on_health_time_warp)
                    inst._on_health_time_warp = nil
                end
            end
        },
        {
            id = "aura_of_decay", name = "腐朽光环", slot = "equippable", weight = 4, min_day = 18,
            desc = "对周围所有敌对生物每两秒造成相当于其最大生命值 2% 的真实伤害（对Boss有上限）",
            onequip = function(inst, owner)
                if inst._decay_task then inst._decay_task:Cancel() end
                inst._decay_task = inst:DoPeriodicTask(2, function()
                    if not owner or not owner:IsValid() or (owner.components.health and owner.components.health:IsDead()) then return end

                    local x, y, z = owner.Transform:GetWorldPosition()
                    local ents = deps.TheSim:FindEntities(x, y, z, 8, {"_combat"}, {"player", "companion", "INLIMBO", "NOCLICK", "FX", "wall", "structure"})

                    for _, ent in ipairs(ents) do
                        if ent and ent:IsValid() and ent.components.health and not ent.components.health:IsDead() then
                            local is_hostile = ent:HasTag("monster") or ent:HasTag("hostile") or (ent.components.combat and ent.components.combat.target == owner)
                            if is_hostile then
                                local max_hp = ent.components.health.maxhealth or 100
                                local dmg = max_hp * 0.02
                                if ent:HasTag("epic") then
                                    dmg = math.min(dmg, 100)
                                else
                                    dmg = math.min(dmg, 400)
                                end

                                ent.components.health:DoDelta(-dmg, nil, "aura_of_decay")

                                if deps.SpawnPrefab and math.random() < 0.3 then
                                    local fx = deps.SpawnPrefab("sporecloud") or deps.SpawnPrefab("spoiled_food")
                                    if fx then
                                        fx.Transform:SetPosition(ent.Transform:GetWorldPosition())
                                        if fx.components.timer then fx.components.timer:StartTimer("extinguish", 0.5) end
                                        fx:DoTaskInTime(0.5, fx.Remove)
                                    end
                                end
                            end
                        end
                    end
                end)
            end,
            onunequip = function(inst, owner)
                if inst._decay_task then
                    inst._decay_task:Cancel()
                    inst._decay_task = nil
                end
            end
        },
        {
            id = "phoenix_ash", name = "凤凰涅槃", slot = "armor", weight = 2, min_day = 30,
            desc = "受到致命伤害时免死并恢复 50% 生命值，向周围爆发火环。冷却 3 天",
            onequip = function(inst, owner)
                if not owner.components.health then return end

                if not inst._on_minhealth then
                    inst._on_minhealth = function(owner_inst, data)
                        if inst._phoenix_cd then return end
                        if not owner_inst.components.health then return end

                        local current = owner_inst.components.health.currenthealth or 0
                        if current > 1 then return end

                        inst._phoenix_cd = true

                        owner_inst.components.health:SetInvincible(true)

                        owner_inst.components.health:SetPercent(0.5)

                        owner_inst:DoTaskInTime(3, function(o)
                            if o and o:IsValid() and o.components.health then
                                o.components.health:SetInvincible(false)
                            end
                        end)

                        local x, y, z = owner_inst.Transform:GetWorldPosition()
                        local ents = deps.TheSim:FindEntities(x, y, z, 8, {"_combat"}, {"player", "companion", "INLIMBO", "NOCLICK", "FX"})
                        for _, ent in ipairs(ents) do
                            if ent and ent:IsValid() and ent.components.combat and ent.components.health and not ent.components.health:IsDead() then
                                ent.components.combat:GetAttacked(owner_inst, 150)
                                if ent.components.burnable and not ent.components.burnable:IsBurning() then
                                    ent.components.burnable:Ignite(true, owner_inst)
                                end
                            end
                        end

                        if deps.SpawnPrefab then
                            local fx = deps.SpawnPrefab("statue_transition_2") or deps.SpawnPrefab("explode_fire")
                            if fx then fx.Transform:SetPosition(x, y, z) end
                        end

                        inst:DoTaskInTime(480 * 3, function()
                            inst._phoenix_cd = false
                        end)
                    end
                    owner:ListenForEvent("minhealth", inst._on_minhealth)
                end

                if not inst._phoenix_cd then
                    owner.components.health.minhealth = (owner.components.health.minhealth or 0) + 1
                end
            end,
            onunequip = function(inst, owner)
                if inst._on_minhealth then
                    owner:RemoveEventCallback("minhealth", inst._on_minhealth)
                    inst._on_minhealth = nil
                end
                if not inst._phoenix_cd and owner.components.health then
                    owner.components.health.minhealth = math.max(0, (owner.components.health.minhealth or 0) - 1)
                end
                if inst._phoenix_cd then
                    inst._phoenix_cd = false
                end
            end
        },
        -- 新增装备能力
        {
            id = "arcane_shield", name = "奥能护盾", slot = "armor", weight = 4, min_day = 20,
            desc = "被攻击时有 20% 几率生成奥能护盾，吸收 50 点伤害并反弹给攻击者",
            onattacked = function(inst, owner, attacker, damage)
                if math.random() < 0.2 and not inst._arcane_cd then
                    inst._arcane_cd = true
                    inst:DoTaskInTime(8, function() inst._arcane_cd = false end)

                    local absorb = math.min(damage, 50)
                    if owner.components.health and not owner.components.health:IsDead() then
                        owner.components.health:DoDelta(absorb, nil, "arcane_shield")
                    end

                    if attacker and attacker.components.combat and damage > 0 then
                        attacker.components.combat:GetAttacked(owner, absorb * 0.75)
                    end

                    if deps.SpawnPrefab then
                        local fx = deps.SpawnPrefab("forcefieldfx")
                        if fx then
                            fx.entity:SetParent(owner.entity)
                            fx.Transform:SetPosition(0, 0.2, 0)
                            owner:DoTaskInTime(2, function() fx:Remove() end)
                        end
                    end
                end
            end
        },
        {
            id = "shadow_step", name = "暗影步", slot = "equippable", weight = 5, min_day = 25,
            desc = "攻击时有 15% 几率进入暗影形态，移动速度提升 50%，持续 3 秒",
            onattack = function(inst, attacker, target)
                if attacker and attacker:IsValid() and math.random() < 0.15 and not attacker._shadow_step_active then
                    attacker._shadow_step_active = true

                    if attacker.components.locomotor then
                        attacker.components.locomotor:SetExternalSpeedMultiplier(attacker, "shadow_step", 1.5)
                    end

                    if deps.SpawnPrefab then
                        local fx = deps.SpawnPrefab("shadow_despawn")
                        if fx then
                            fx.Transform:SetPosition(attacker.Transform:GetWorldPosition())
                        end
                    end

                    attacker:DoTaskInTime(3, function(a)
                        if a and a:IsValid() then
                            a._shadow_step_active = false
                            if a.components.locomotor then
                                a.components.locomotor:RemoveExternalSpeedMultiplier(a, "shadow_step")
                            end
                        end
                    end)
                end
            end
        },
        {
            id = "vampiric_aura", name = "吸血鬼光环", slot = "equippable", weight = 4, min_day = 18,
            desc = "攻击敌人时恢复相当于武器伤害 10% 的生命值",
            onequip = function(inst, owner)
                if not inst._on_vampiric_attack then
                    inst._on_vampiric_attack = function(owner_inst, data)
                        if not data or not data.target or not data.target:IsValid() then return end

                        local weapon = owner_inst.components.combat and owner_inst.components.combat.weapon
                        local base_dmg = 0
                        if weapon and weapon.components.weapon then
                            base_dmg = weapon.components.weapon:GetDamage(owner_inst, data.target) or 34
                        else
                            base_dmg = owner_inst.components.combat and owner_inst.components.combat.defaultdamage or 34
                        end
                        if base_dmg > 0 and owner_inst.components.health and not owner_inst.components.health:IsDead() then
                            owner_inst.components.health:DoDelta(base_dmg * 0.1, nil, "vampiric_aura")
                        end
                    end
                    owner:ListenForEvent("onattackother", inst._on_vampiric_attack)
                end
            end,
            onunequip = function(inst, owner)
                if inst._on_vampiric_attack then
                    owner:RemoveEventCallback("onattackother", inst._on_vampiric_attack)
                    inst._on_vampiric_attack = nil
                end
            end
        },
        {
            id = "elemental_ward", name = "元素守护", slot = "armor", weight = 6, min_day = 15,
            desc = "提供对火焰、冰冻和闪电伤害的 30% 抗性",
            onequip = function(inst, owner)
                if owner.components.combat and owner.components.combat.externaldamagetakenmultipliers then
                    owner.components.combat.externaldamagetakenmultipliers:SetModifier(inst, 0.7, "elemental_ward")
                end
                if owner.components.freezable then
                    inst._old_freezable_resist = owner.components.freezable.resistance or 0
                    owner.components.freezable.resistance = (owner.components.freezable.resistance or 0) + 2
                end
                if owner.components.temperature then
                    inst._elemental_temp_task = owner:DoPeriodicTask(1, function(o)
                        if not o:IsValid() then return end
                        if o.components.health and o.components.health:IsDead() then return end
                        if o.components.burnable and o.components.burnable:IsBurning() then
                            o.components.health:DoDelta(2)
                        end
                    end)
                end
            end,
            onunequip = function(inst, owner)
                if owner.components.combat and owner.components.combat.externaldamagetakenmultipliers then
                    owner.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, "elemental_ward")
                end
                if owner.components.freezable and inst._old_freezable_resist then
                    owner.components.freezable.resistance = inst._old_freezable_resist
                    inst._old_freezable_resist = nil
                end
                if inst._elemental_temp_task then
                    inst._elemental_temp_task:Cancel()
                    inst._elemental_temp_task = nil
                end
            end
        },
        {
            id = "berserker_fury", name = "狂战士之怒", slot = "weapon", weight = 5, min_day = 22,
            desc = "生命值越低，伤害越高，最高提升 50% 伤害",
            onattack = function(inst, attacker, target)
                if attacker and attacker:IsValid() and attacker.components.health then
                    local hp_pct = attacker.components.health:GetPercent()
                    local damage_bonus = (1 - hp_pct) * 0.5

                    if damage_bonus > 0 and attacker.components.combat then
                        attacker.components.combat.externaldamagemultipliers:SetModifier(inst, 1 + damage_bonus, "berserker_fury")

                        attacker:DoTaskInTime(0.1, function(a)
                            if a and a:IsValid() and a.components.combat then
                                a.components.combat.externaldamagemultipliers:RemoveModifier(inst, "berserker_fury")
                            end
                        end)
                    end
                end
            end
        },
        {
            id = "combo_strike", name = "连击", slot = "weapon", weight = 5, min_day = 8,
            desc = "连续攻击同一目标时伤害递增，每次+15%，重置后额外造成一次爆发伤害",
            onattack = function(inst, attacker, target)
                if not attacker or not attacker:IsValid() then return end
                if not target or not target:IsValid() then return end

                local target_id = target.GUID
                attacker._combo_target = target_id
                attacker._combo_count = (attacker._combo_count or 0) + 1

                if attacker._combo_count > 1 and attacker.components.combat then
                    local bonus = math.min(attacker._combo_count * 0.15, 0.9)
                    attacker.components.combat.externaldamagemultipliers:SetModifier(inst, 1 + bonus, "combo_strike")
                    attacker:DoTaskInTime(0.1, function(a)
                        if a and a:IsValid() and a.components.combat then
                            a.components.combat.externaldamagemultipliers:RemoveModifier(inst, "combo_strike")
                        end
                    end)
                end

                if attacker._combo_reset_task then
                    attacker._combo_reset_task:Cancel()
                end
                attacker._combo_reset_task = attacker:DoTaskInTime(2.5, function(a)
                    if a and a:IsValid() and a._combo_count and a._combo_count >= 4 then
                        if target and target:IsValid() and target.components.health and not target.components.health:IsDead() then
                            local burst_dmg = (inst.components.weapon and inst.components.weapon:GetDamage(a, target) or 34) * 0.5
                            target.components.combat:GetAttacked(a, burst_dmg)
                        end
                    end
                    if a then
                        a._combo_count = 0
                        a._combo_target = nil
                    end
                end)
            end
        },
        {
            id = "momentum", name = "蓄势", slot = "weapon", weight = 4, min_day = 12,
            desc = "移动时积累势能，停下后首次攻击消耗势能造成额外 60% 伤害",
            onequip = function(inst, owner)
                owner._momentum_energy = 0
                if not inst._momentum_task then
                    inst._momentum_task = owner:DoPeriodicTask(0.3, function(o)
                        if not o:IsValid() or not o.components.locomotor then return end
                        if o.components.health and o.components.health:IsDead() then return end
                        local speed = o.components.locomotor:GetSpeedMultiplier()
                        if speed and speed > 1.05 then
                            o._momentum_energy = math.min((o._momentum_energy or 0) + 0.1, 1.0)
                        else
                            o._momentum_energy = math.max((o._momentum_energy or 0) - 0.05, 0)
                        end
                    end)
                end
            end,
            onunequip = function(inst, owner)
                if inst._momentum_task then
                    inst._momentum_task:Cancel()
                    inst._momentum_task = nil
                end
                owner._momentum_energy = nil
            end,
            onattack = function(inst, attacker, target)
                if not attacker or not attacker:IsValid() then return end
                local energy = attacker._momentum_energy or 0
                if energy >= 0.5 then
                    local bonus = energy * 0.6
                    if attacker.components.combat then
                        attacker.components.combat.externaldamagemultipliers:SetModifier(inst, 1 + bonus, "momentum")
                        attacker:DoTaskInTime(0.1, function(a)
                            if a and a:IsValid() and a.components.combat then
                                a.components.combat.externaldamagemultipliers:RemoveModifier(inst, "momentum")
                            end
                        end)
                    end
                    attacker._momentum_energy = 0
                end
            end
        },
        {
            id = "blood_pact", name = "血契", slot = "weapon", weight = 3, min_day = 15,
            desc = "攻击消耗 5 点生命值，造成额外 40% 伤害。生命不足时自动停止",
            onattack = function(inst, attacker, target)
                if not attacker or not attacker:IsValid() then return end
                if not attacker.components.health then return end
                local hp = attacker.components.health.currenthealth
                if hp <= 15 then return end

                attacker.components.health:DoDelta(-5, nil, "blood_pact")

                if attacker.components.combat then
                    attacker.components.combat.externaldamagemultipliers:SetModifier(inst, 1.4, "blood_pact")
                    attacker:DoTaskInTime(0.1, function(a)
                        if a and a:IsValid() and a.components.combat then
                            a.components.combat.externaldamagemultipliers:RemoveModifier(inst, "blood_pact")
                        end
                    end)
                end
            end
        },
        {
            id = "echo_blade", name = "回响之刃", slot = "weapon", weight = 3, min_day = 20,
            desc = "攻击时 20% 几率触发回响，0.5 秒后对目标再次造成 50% 武器伤害",
            onattack = function(inst, attacker, target)
                if not attacker or not attacker:IsValid() then return end
                if not target or not target:IsValid() then return end
                if math.random() > 0.20 then return end

                local dmg = (inst.components.weapon and inst.components.weapon:GetDamage(attacker, target) or 34) * 0.5
                local t_ref = target
                local a_ref = attacker

                attacker:DoTaskInTime(0.5, function()
                    if t_ref and t_ref:IsValid() and t_ref.components.health and not t_ref.components.health:IsDead() then
                        t_ref.components.combat:GetAttacked(a_ref, dmg)
                    end
                end)
            end
        },
        {
            id = "retaliation", name = "反击", slot = "armor", weight = 5, min_day = 10,
            desc = "被攻击时 25% 几率对攻击者反击，造成相当于受到伤害 80% 的伤害",
            onattacked = function(inst, owner, attacker, damage)
                if not attacker or not attacker:IsValid() then return end
                if not attacker.components.health or attacker.components.health:IsDead() then return end
                if math.random() > 0.25 then return end

                local counter_dmg = (damage or 20) * 0.8
                if attacker.components.combat then
                    attacker.components.combat:GetAttacked(owner, counter_dmg)
                end
            end
        },
        {
            id = "last_stand", name = "背水一战", slot = "armor", weight = 3, min_day = 18,
            desc = "生命值低于 30% 时，获得 25% 伤害减免和 20% 攻击加成",
            onequip = function(inst, owner)
                if not inst._last_stand_task then
                    inst._last_stand_task = owner:DoPeriodicTask(0.5, function(o)
                        if not o:IsValid() or not o.components.health then return end
                        local hp_pct = o.components.health:GetPercent()
                        if hp_pct < 0.3 and not o._last_stand_active then
                            o._last_stand_active = true
                            if o.components.combat and o.components.combat.externaldamagetakenmultipliers then
                                o.components.combat.externaldamagetakenmultipliers:SetModifier(inst, 0.75, "last_stand")
                            end
                            if o.components.combat and o.components.combat.externaldamagemultipliers then
                                o.components.combat.externaldamagemultipliers:SetModifier(inst, 1.2, "last_stand")
                            end
                        elseif hp_pct >= 0.35 and o._last_stand_active then
                            o._last_stand_active = false
                            if o.components.combat and o.components.combat.externaldamagetakenmultipliers then
                                o.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, "last_stand")
                            end
                            if o.components.combat and o.components.combat.externaldamagemultipliers then
                                o.components.combat.externaldamagemultipliers:RemoveModifier(inst, "last_stand")
                            end
                        end
                    end)
                end
            end,
            onunequip = function(inst, owner)
                if inst._last_stand_task then
                    inst._last_stand_task:Cancel()
                    inst._last_stand_task = nil
                end
                if owner._last_stand_active then
                    owner._last_stand_active = false
                    if owner.components.combat and owner.components.combat.externaldamagetakenmultipliers then
                        owner.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, "last_stand")
                    end
                    if owner.components.combat and owner.components.combat.externaldamagemultipliers then
                        owner.components.combat.externaldamagemultipliers:RemoveModifier(inst, "last_stand")
                    end
                end
            end
        },
        {
            id = "adrenaline", name = "肾上腺素", slot = "equippable", weight = 4, min_day = 8,
            desc = "受到伤害后 5 秒内攻击速度提升 30%，移动速度提升 15%",
            onequip = function(inst, owner)
                if not inst._on_adrenaline_hit then
                    inst._on_adrenaline_hit = function(owner_inst, data)
                        if owner_inst._adrenaline_active then return end
                        owner_inst._adrenaline_active = true

                        if owner_inst.components.locomotor then
                            owner_inst.components.locomotor:SetExternalSpeedMultiplier(inst, "rogue_adrenaline", 1.15)
                        end
                        if owner_inst.components.combat and owner_inst.components.combat.externaldamagemultipliers then
                            owner_inst.components.combat.externaldamagemultipliers:SetModifier(inst, 1.3, "rogue_adrenaline")
                        end

                        owner_inst:DoTaskInTime(5, function(o)
                            if o and o:IsValid() then
                                o._adrenaline_active = false
                                if o.components.locomotor then
                                    o.components.locomotor:RemoveExternalSpeedMultiplier(inst, "rogue_adrenaline")
                                end
                                if o.components.combat and o.components.combat.externaldamagemultipliers then
                                    o.components.combat.externaldamagemultipliers:RemoveModifier(inst, "rogue_adrenaline")
                                end
                            end
                        end)
                    end
                    owner:ListenForEvent("attacked", inst._on_adrenaline_hit)
                end
            end,
            onunequip = function(inst, owner)
                if inst._on_adrenaline_hit then
                    owner:RemoveEventCallback("attacked", inst._on_adrenaline_hit)
                    inst._on_adrenaline_hit = nil
                end
                if owner._adrenaline_active then
                    owner._adrenaline_active = false
                    if owner.components.locomotor then
                        owner.components.locomotor:RemoveExternalSpeedMultiplier(inst, "rogue_adrenaline")
                    end
                    if owner.components.combat and owner.components.combat.externaldamagemultipliers then
                        owner.components.combat.externaldamagemultipliers:RemoveModifier(inst, "rogue_adrenaline")
                    end
                end
            end
        },
        {
            id = "soul_harvest", name = "灵魂收割", slot = "equippable", weight = 3, min_day = 15,
            desc = "击杀敌人时恢复 15 点生命值和 10 点理智值，并短暂提升 10% 移速",
            onequip = function(inst, owner)
                if not inst._on_soul_kill then
                    inst._on_soul_kill = function(owner_inst, data)
                        local victim = data and data.inst
                        if not victim then return end
                        if victim:HasTag("rogue_elite") or victim:HasTag("rogue_boss") then
                            if owner_inst.components.health and not owner_inst.components.health:IsDead() then
                                owner_inst.components.health:DoDelta(30, nil, "soul_harvest")
                            end
                            if owner_inst.components.sanity then
                                owner_inst.components.sanity:DoDelta(20)
                            end
                        else
                            if owner_inst.components.health and not owner_inst.components.health:IsDead() then
                                owner_inst.components.health:DoDelta(15, nil, "soul_harvest")
                            end
                            if owner_inst.components.sanity then
                                owner_inst.components.sanity:DoDelta(10)
                            end
                        end
                        if owner_inst.components.locomotor then
                            owner_inst.components.locomotor:SetExternalSpeedMultiplier(inst, "rogue_soul_harvest", 1.1)
                            owner_inst:DoTaskInTime(3, function(o)
                                if o and o:IsValid() and o.components.locomotor then
                                    o.components.locomotor:RemoveExternalSpeedMultiplier(inst, "rogue_soul_harvest")
                                end
                            end)
                        end
                    end
                    owner:ListenForEvent("killed", inst._on_soul_kill)
                end
            end,
            onunequip = function(inst, owner)
                if inst._on_soul_kill then
                    owner:RemoveEventCallback("killed", inst._on_soul_kill)
                    inst._on_soul_kill = nil
                end
            end
        },
        -- 终极附魔（min_day 35+）
        {
            id = "doom_blade", name = "毁灭之刃", slot = "weapon", weight = 2, min_day = 35,
            desc = "攻击有30%几率造成毁灭打击，对非Boss目标造成3倍伤害，对Boss造成1.5倍伤害",
            onattack = function(inst, attacker, target)
                if not target or not target:IsValid() then return end
                if math.random() >= 0.30 then return end
                local is_boss = target:HasTag("epic")
                local mult = is_boss and 0.5 or 2.0
                local weapon_dmg = (inst.components.weapon and inst.components.weapon.GetDamage and inst.components.weapon:GetDamage(attacker, target) or 34)
                if target.components.combat then
                    target.components.combat:GetAttacked(attacker, weapon_dmg * mult)
                end
                if deps.SpawnPrefab then
                    local fx = deps.SpawnPrefab("statue_transition_2")
                    if fx then fx.Transform:SetPosition(target.Transform:GetWorldPosition()) end
                end
            end
        },
        {
            id = "soul_barrier", name = "灵魂壁垒", slot = "armor", weight = 2, min_day = 35,
            desc = "每30秒获得一层灵魂屏障，最多3层，每层可完全吸收一次攻击并恢复10点生命",
            onequip = function(inst, owner)
                owner._soul_barrier_stacks = 0
                if inst._soul_barrier_task then inst._soul_barrier_task:Cancel() end
                inst._soul_barrier_task = inst:DoPeriodicTask(30, function()
                    if not owner or not owner:IsValid() then return end
                    if owner._soul_barrier_stacks < 3 then
                        owner._soul_barrier_stacks = owner._soul_barrier_stacks + 1
                    end
                end)
                if not inst._on_soul_barrier_attacked then
                    inst._on_soul_barrier_attacked = function(o, data)
                        if o._soul_barrier_stacks and o._soul_barrier_stacks > 0 and data and data.damage and data.damage > 0 then
                            o._soul_barrier_stacks = o._soul_barrier_stacks - 1
                            if o.components.health and not o.components.health:IsDead() then
                                o.components.health:SetInvincible(true)
                                o:DoTaskInTime(0.1, function(p)
                                    if p and p.components.health then p.components.health:SetInvincible(false) end
                                end)
                                o.components.health:DoDelta(10)
                            end
                            if deps.SpawnPrefab then
                                local fx = deps.SpawnPrefab("forcefieldfx")
                                if fx then fx.entity:SetParent(o.entity) fx.Transform:SetPosition(0, 0.2, 0) o:DoTaskInTime(1, function() fx:Remove() end) end
                            end
                        end
                    end
                    owner:ListenForEvent("attacked", inst._on_soul_barrier_attacked)
                end
            end,
            onunequip = function(inst, owner)
                if inst._soul_barrier_task then inst._soul_barrier_task:Cancel() inst._soul_barrier_task = nil end
                if inst._on_soul_barrier_attacked then
                    owner:RemoveEventCallback("attacked", inst._on_soul_barrier_attacked)
                    inst._on_soul_barrier_attacked = nil
                end
                owner._soul_barrier_stacks = 0
            end
        },
        {
            id = "chaos_storm", name = "混沌风暴", slot = "weapon", weight = 2, min_day = 40,
            desc = "攻击有20%几率召唤混沌风暴，对周围8格内所有敌人造成武器伤害的80%",
            onattack = function(inst, attacker, target)
                if not attacker or not attacker:IsValid() or math.random() >= 0.20 then return end
                local x, y, z = attacker.Transform:GetWorldPosition()
                local weapon_dmg = (inst.components.weapon and inst.components.weapon.GetDamage and inst.components.weapon:GetDamage(attacker, target) or 34) * 0.8
                local ents = deps.TheSim:FindEntities(x, y, z, 8, {"_combat"}, {"player", "companion", "INLIMBO", "NOCLICK", "FX"})
                for _, ent in ipairs(ents) do
                    if ent and ent:IsValid() and ent.components.combat and ent.components.health and not ent.components.health:IsDead() then
                        ent.components.combat:GetAttacked(attacker, weapon_dmg)
                    end
                end
                if deps.SpawnPrefab then
                    local fx = deps.SpawnPrefab("deer_ice_circle")
                    if fx then fx.Transform:SetPosition(x, y, z) end
                end
            end
        }
    }
end

return M
