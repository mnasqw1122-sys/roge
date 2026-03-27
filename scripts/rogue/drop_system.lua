--[[
    文件说明：drop_system.lua
    功能：掉落与装备能力系统。
    负责控制怪物击杀后的战利品掉落（基础物资、Boss装备、稀有材料）、保底机制以及为掉落装备附加随机特殊能力（如烈焰、荆棘）。
]]
local M = {}

function M.Create(deps)
    local state = {}
    state.boss_loot_pity = {}
    state.gear_quality_pity = { boss_gear = 0, trial_gear = 0 }
    local function IsAbilityEligibleItem(item)
        return item ~= nil and item.components ~= nil and (item.components.weapon ~= nil or item.components.equippable ~= nil)
    end

    local function CloneList(src)
        if not src then return nil end
        local out = {}
        for _, v in ipairs(src) do
            table.insert(out, v)
        end
        return out
    end

    local function CloneMap(src)
        if not src then return nil end
        local out = {}
        for k, v in pairs(src) do
            out[k] = v
        end
        return out
    end

    local function CloneNumberMap(src)
        local out = {}
        if type(src) ~= "table" then
            return out
        end
        for k, v in pairs(src) do
            local n = tonumber(v)
            if n ~= nil then
                out[k] = n
            end
        end
        return out
    end

    local function SpawnScaledFx(prefab, pt, scale)
        if not (deps.SpawnPrefab and pt and prefab) then
            return nil
        end
        local fx = deps.SpawnPrefab(prefab)
        if fx and fx.Transform then
            fx.Transform:SetPosition(pt.x, pt.y, pt.z)
            if scale and fx.Transform.SetScale then
                fx.Transform:SetScale(scale, scale, scale)
            end
        end
        return fx
    end

    -- 函数说明：触发星陨重击能力（纯视觉陨石+延时伤害，不破坏地形）
    local function TriggerMeteorStrike(attacker, target, damage)
        if not (target and target:IsValid()) then
            return
        end
        local telegraph_pt = target:GetPosition()
        SpawnScaledFx("statue_transition_2", telegraph_pt, 0.85)
        
        target:DoTaskInTime(0.35, function(inst)
            if not (inst and inst:IsValid()) then
                return
            end
            local pt = inst:GetPosition()
            
            local meteor = deps.SpawnPrefab("shadowmeteor")
            if meteor then
                meteor.Transform:SetPosition(pt.x, pt.y, pt.z)
                
                -- 取消原生陨石的随机大小和破坏任务
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
                
                -- 陨石砸地动画约在0.33秒处触地
                meteor:DoTaskInTime(0.33, function(m)
                    if m and m:IsValid() and m.SoundEmitter then
                        m.SoundEmitter:PlaySound("dontstarve/common/meteor_impact")
                    end
                    SpawnScaledFx("explode_reskin", pt, 2.2)
                    
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
                -- 兼容降级方案
                local world = deps.GetWorld and deps.GetWorld() or nil
                if world and world.PushEvent and deps.Vector3 then
                    world:PushEvent("ms_sendlightningstrike", deps.Vector3(pt.x, pt.y, pt.z))
                else
                    SpawnScaledFx("lightning", pt)
                end
                SpawnScaledFx("explode_reskin", pt, 2.2)
                
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

    -- [全新装备能力系统 (Enchantments)] --
    local ABILITY_DEFS = {
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
                    -- 寻找附近的敌人进行弹射
                    local ents = deps.TheSim:FindEntities(x, y, z, 8, {"_combat"}, {"player", "companion", "INLIMBO", "NOCLICK", "FX"})
                    local count = 0
                    local dmg = (inst.components.weapon and inst.components.weapon.GetDamage and inst.components.weapon:GetDamage(attacker, target) or 34) * 0.5 -- 50%武器伤害
                    for _, ent in ipairs(ents) do
                        if ent ~= attacker and ent.components.combat and ent.components.health and not ent.components.health:IsDead() then
                            ent:DoTaskInTime(count * 0.2, function(e)
                                if e and e:IsValid() and e.components.health and not e.components.health:IsDead() then
                                    local pt = e:GetPosition()
                                    if deps.SpawnPrefab then
                                        local lightning = deps.SpawnPrefab("sparks") or deps.SpawnPrefab("lightning")
                                        if lightning then
                                            lightning.Transform:SetPosition(pt.x, pt.y, pt.z)
                                        end
                                    end
                                    e.components.combat:GetAttacked(attacker, dmg)
                                end
                            end)
                            count = count + 1
                            if count >= 4 then break end -- 最多弹射 4 个目标
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
                        
                        -- 计算追加伤害 (60% 武器伤害)
                        local dmg = (inst.components.weapon and inst.components.weapon.GetDamage and inst.components.weapon:GetDamage(attacker, target) or 34) * 0.6
                        
                        -- 第一次追加攻击
                        target:DoTaskInTime(0.2, function(t)
                            if t and t:IsValid() and t.components.combat and t.components.health and not t.components.health:IsDead() then
                                t.components.combat:GetAttacked(attacker, dmg)
                                if deps.SpawnPrefab then
                                    local fx = deps.SpawnPrefab("sparks") or deps.SpawnPrefab("impact")
                                    if fx then fx.Transform:SetPosition(t.Transform:GetWorldPosition()) end
                                end
                            end
                        end)
                        
                        -- 第二次追加攻击
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
                            -- 对非 Boss 直接斩杀
                            if deps.SpawnPrefab then
                                local fx = deps.SpawnPrefab("shadowstrike") or deps.SpawnPrefab("impact")
                                if fx then fx.Transform:SetPosition(target.Transform:GetWorldPosition()) end
                            end
                            target.components.health:DoDelta(-target.components.health.currenthealth, nil, "executioner")
                        else
                            -- 对 Boss 造成额外的一倍武器伤害（实现双倍效果）
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
                    
                    -- 刷新或挂载破甲修饰
                    if target.components.combat.externaldamagetakenmultipliers then
                        target.components.combat.externaldamagetakenmultipliers:SetModifier(inst, 1 + target.rogue_void_stacks * 0.05, "void_tear_debuff")
                    end
                    
                    -- 播放叠加特效
                    if deps.SpawnPrefab then
                        local fx = deps.SpawnPrefab("shadow_despawn") or deps.SpawnPrefab("statue_transition")
                        if fx then
                            fx.Transform:SetPosition(target.Transform:GetWorldPosition())
                            fx.Transform:SetScale(0.3 + target.rogue_void_stacks * 0.1, 0.3 + target.rogue_void_stacks * 0.1, 0.3 + target.rogue_void_stacks * 0.1)
                        end
                    end
                    
                    -- 定时器重置层数
                    if target.rogue_void_task then target.rogue_void_task:Cancel() end
                    target.rogue_void_task = target:DoTaskInTime(5, function(t)
                        if t and t:IsValid() then
                            t.rogue_void_stacks = 0
                            if t.components.combat and t.components.combat.externaldamagetakenmultipliers then
                                t.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, "void_tear_debuff")
                            end
                        end
                    end)
                    
                    -- 叠满5层引爆
                    if target.rogue_void_stacks >= 5 then
                        target.rogue_void_stacks = 0
                        if target.components.combat.externaldamagetakenmultipliers then
                            target.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, "void_tear_debuff")
                        end
                        if target.rogue_void_task then target.rogue_void_task:Cancel() end
                        
                        -- 引爆伤害
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
            desc = "连续攻击时，召唤一个持续 5 秒的暗影分身，模仿玩家攻击周围敌人",
            onattack = function(inst, attacker, target)
                if not attacker or not attacker:IsValid() then return end
                attacker._phantom_hits = (attacker._phantom_hits or 0) + 1
                
                -- 5 次攻击触发一次分身
                if attacker._phantom_hits >= 5 then
                    attacker._phantom_hits = 0
                    
                    if deps.SpawnPrefab then
                        local x, y, z = attacker.Transform:GetWorldPosition()
                        local clone = deps.SpawnPrefab("shadowprotector") or deps.SpawnPrefab("shadowduelist")
                        if clone then
                            clone.Transform:SetPosition(x, y, z)
                            -- 让分身持续时间变短 (5秒)
                            if clone.components.health then
                                clone.components.health:DoDelta(9999) -- 满血
                                clone:DoTaskInTime(5, function(c)
                                    if c.components.health then c.components.health:Kill() else c:Remove() end
                                end)
                            else
                                clone:DoTaskInTime(5, clone.Remove)
                            end
                            
                            -- 设置攻击力与目标
                            if clone.components.combat then
                                local dmg = (inst.components.weapon and inst.components.weapon.GetDamage and inst.components.weapon:GetDamage(attacker, target) or 34) * 0.8
                                clone.components.combat:SetDefaultDamage(dmg)
                                clone.components.combat:SetTarget(target)
                            end
                            -- 绑定到玩家
                            if clone.components.follower then
                                clone.components.follower:SetLeader(attacker)
                            end
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
                    if owner.components.health and not owner.components.health:IsDead() and damage and damage > 0 then
                        owner.components.health:DoDelta(damage, nil, "rogue_shield")
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
                -- 极高保暖
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

                -- 主动产热
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
                -- 恢复保暖
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

                -- 恢复产热
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
                -- 极高防热
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

                -- 主动制冷
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
                -- 恢复防热
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

                -- 恢复制冷
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
                -- 增加玩家受到的伤害 20%
                if owner.components.combat and owner.components.combat.externaldamagetakenmultipliers then
                    owner.components.combat.externaldamagetakenmultipliers:SetModifier(inst, 1.20, "greed_pact")
                end
                
                -- 给玩家打上贪婪标签，供掉落系统和积分系统读取
                if not owner:HasTag("rogue_greed_pact") then
                    owner:AddTag("rogue_greed_pact")
                end
            end,
            onunequip = function(inst, owner)
                if owner.components.combat and owner.components.combat.externaldamagetakenmultipliers then
                    owner.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, "greed_pact")
                end
                
                -- 移除贪婪标签
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
                    -- 减速效果
                    if attacker.components.locomotor then
                        attacker.components.locomotor:SetExternalSpeedMultiplier(attacker, "rogue_frost_armor", 0.7) -- 减速30%
                        attacker:DoTaskInTime(3, function(a)
                            if a and a:IsValid() and a.components.locomotor then
                                a.components.locomotor:RemoveExternalSpeedMultiplier(a, "rogue_frost_armor")
                            end
                        end)
                    end
                    
                    -- 增加寒冷值
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
                
                -- 核心循环：每 10 秒尝试补充护盾
                inst._kinetic_task = inst:DoPeriodicTask(10, function()
                    if not owner or not owner:IsValid() then return end
                    
                    if not owner._kinetic_shield_active then
                        owner._kinetic_shield_active = true
                        -- 播放护盾生成特效
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

                -- 拦截受击事件
                if not inst._on_attacked_kinetic then
                    inst._on_attacked_kinetic = function(owner_inst, data)
                        if owner_inst._kinetic_shield_active and data and data.damage and data.damage > 0 then
                            -- 触发偏转
                            owner_inst._kinetic_shield_active = false
                            
                            -- 清除护盾特效
                            if owner_inst._kinetic_fx and owner_inst._kinetic_fx:IsValid() then
                                owner_inst._kinetic_fx:Remove()
                                owner_inst._kinetic_fx = nil
                            end
                            
                            -- 恢复精神值
                            if owner_inst.components.sanity then
                                owner_inst.components.sanity:DoDelta(15)
                            end
                            
                            -- 拦截伤害：返还本次造成的伤害
                            if owner_inst.components.health and not owner_inst.components.health:IsDead() then
                                owner_inst.components.health:DoDelta(data.damage, nil, "kinetic_deflection", true)
                                if deps.SpawnPrefab then
                                    local block_fx = deps.SpawnPrefab("impact")
                                    if block_fx then block_fx.Transform:SetPosition(owner_inst.Transform:GetWorldPosition()) end
                                end
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
                        inst:DoTaskInTime(5, function() inst._earthquake_cd = false end) -- 5秒冷却
                        
                        -- 触发地震特效
                        local x, y, z = owner.Transform:GetWorldPosition()
                        deps.GLOBAL.ShakeAllCameras(deps.GLOBAL.CAMERASHAKE.FULL, 0.7, 0.02, 1, owner, 40)
                        
                        if deps.SpawnPrefab then
                            local ring = deps.SpawnPrefab("deer_ice_circle") or deps.SpawnPrefab("groundpoundring_fx")
                            if ring then
                                ring.Transform:SetPosition(x, y, z)
                                ring.Transform:SetScale(0.8, 0.8, 0.8)
                            end
                        end
                        
                        -- 计算反震伤害 (受到伤害的 1.5 倍)
                        local reflect_dmg = damage * 1.5
                        
                        -- 寻找范围内的敌人并眩晕+伤害
                        local ents = deps.TheSim:FindEntities(x, y, z, 6, {"_combat"}, {"player", "companion", "INLIMBO", "NOCLICK", "FX", "flying"})
                        for _, ent in ipairs(ents) do
                            if ent and ent:IsValid() and ent.components.combat and ent.components.health and not ent.components.health:IsDead() then
                                ent.components.combat:GetAttacked(owner, reflect_dmg)
                                -- 打断动作（如果可以的话）
                                if ent.sg and ent.sg.GoToState then
                                    if ent.components.health:IsDead() then
                                        -- 已经死了就不打断了
                                    elseif ent.sg:HasState("hit") then
                                        ent.sg:GoToState("hit")
                                    end
                                end
                                -- 附加冰冻/减速实现“眩晕”效果
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
                            -- 冷却1天 (480秒)
                            inst:DoTaskInTime(480, function() inst._time_warp_cd = false end)
                            
                            if owner_inst.components.talker then
                                owner_inst.components.talker:Say("时空扭曲力场已展开！")
                            end
                            
                            local x, y, z = owner_inst.Transform:GetWorldPosition()
                            
                            -- 播放大范围特效
                            if deps.SpawnPrefab then
                                local fx = deps.SpawnPrefab("staffcastfx") or deps.SpawnPrefab("deer_ice_circle")
                                if fx then
                                    fx.Transform:SetPosition(x, y, z)
                                    fx.Transform:SetScale(2, 2, 2)
                                end
                            end
                            
                            -- 寻找周围敌人并减速
                            local ents = deps.TheSim:FindEntities(x, y, z, 12, {"_combat"}, {"player", "companion", "INLIMBO", "NOCLICK", "FX"})
                            for _, ent in ipairs(ents) do
                                if ent and ent:IsValid() and ent.components.locomotor then
                                    ent.components.locomotor:SetExternalSpeedMultiplier(ent, "rogue_time_warp", 0.2) -- 极度减速
                                    if ent.AnimState then
                                        ent.AnimState:SetDeltaTimeMultiplier(0.3) -- 动画极度变慢
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
            desc = "对周围所有敌对生物每秒造成相当于其最大生命值 1% 的真实伤害（对Boss有上限）",
            onequip = function(inst, owner)
                if inst._decay_task then inst._decay_task:Cancel() end
                inst._decay_task = inst:DoPeriodicTask(1, function()
                    if not owner or not owner:IsValid() or (owner.components.health and owner.components.health:IsDead()) then return end
                    
                    local x, y, z = owner.Transform:GetWorldPosition()
                    local ents = deps.TheSim:FindEntities(x, y, z, 8, {"_combat"}, {"player", "companion", "INLIMBO", "NOCLICK", "FX", "wall", "structure"})
                    
                    for _, ent in ipairs(ents) do
                        if ent and ent:IsValid() and ent.components.health and not ent.components.health:IsDead() then
                            -- 判断是否是敌对目标 (通过能否攻击或者是否有怪物标签)
                            local is_hostile = ent:HasTag("monster") or ent:HasTag("hostile") or (ent.components.combat and ent.components.combat.target == owner)
                            if is_hostile then
                                local max_hp = ent.components.health.maxhealth or 100
                                local dmg = max_hp * 0.01
                                -- 对 Boss 伤害上限控制
                                if ent:HasTag("epic") then
                                    dmg = math.min(dmg, 50)
                                else
                                    dmg = math.min(dmg, 200)
                                end
                                
                                ent.components.health:DoDelta(-dmg, nil, "aura_of_decay")
                                
                                -- 播放微小特效
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
                
                -- 如果不在冷却中，提供最小生命值保护（免死）
                if not inst._phoenix_cd then
                    owner.components.health.minhealth = (owner.components.health.minhealth or 0) + 1
                end
                
                if not inst._on_minhealth then
                    inst._on_minhealth = function(owner_inst, data)
                        if inst._phoenix_cd then return end
                        
                        -- 触发涅槃
                        inst._phoenix_cd = true
                        
                        -- 触发时暂时移除保护，进入冷却
                        owner_inst.components.health.minhealth = math.max(0, (owner_inst.components.health.minhealth or 1) - 1)
                        
                        -- 冷却时间 3 天 (480秒/天)
                        inst:DoTaskInTime(480 * 3, function() 
                            inst._phoenix_cd = false 
                            -- 冷却结束如果依然装备着，则恢复保护
                            if owner_inst and owner_inst:IsValid() and owner_inst.components.inventory and owner_inst.components.inventory:IsItemEquipped(inst) then
                                owner_inst.components.health.minhealth = (owner_inst.components.health.minhealth or 0) + 1
                            end
                        end)
                        
                        -- 恢复 50% 生命值
                        owner_inst.components.health:SetPercent(0.5)
                        
                        -- 短暂无敌
                        if owner_inst.components.health.SetInvincible then
                            owner_inst.components.health:SetInvincible(true)
                            owner_inst:DoTaskInTime(3, function(o) 
                                if o and o:IsValid() and o.components.health then o.components.health:SetInvincible(false) end 
                            end)
                        end
                        
                        -- 爆发火环伤害
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
                        
                        -- 播放特效
                        if deps.SpawnPrefab then
                            local fx = deps.SpawnPrefab("statue_transition_2") or deps.SpawnPrefab("explode_fire")
                            if fx then fx.Transform:SetPosition(x, y, z) end
                        end
                    end
                    owner:ListenForEvent("minhealth", inst._on_minhealth)
                end
            end,
            onunequip = function(inst, owner)
                if inst._on_minhealth then
                    owner:RemoveEventCallback("minhealth", inst._on_minhealth)
                    inst._on_minhealth = nil
                end
                -- 脱下装备时移除保护
                if not inst._phoenix_cd and owner.components.health then
                    owner.components.health.minhealth = math.max(0, (owner.components.health.minhealth or 1) - 1)
                end
            end
        }
    }

    local function ApplyRogueAbilities(item, ability_ids, meta, refill_durability)
        if not item or not item:IsValid() or not ability_ids then return false end
        if not IsAbilityEligibleItem(item) then return false end
        
        item.rogue_abilities = CloneList(ability_ids)
        item.rogue_affix_meta = meta and CloneMap(meta) or nil
        
        local lines = {}
        if meta and meta.rarity_name then
            table.insert(lines, meta.rarity_name .. "品质")
        end

        local has_onattack = false
        local has_onattacked = false
        local has_onequip = false

        for _, id in ipairs(item.rogue_abilities) do
            local def = nil
            for _, d in ipairs(ABILITY_DEFS) do
                if d.id == id then def = d; break end
            end
            if def then
                table.insert(lines, "【" .. def.name .. "】" .. def.desc)
                if def.onattack then has_onattack = true end
                if def.onattacked then has_onattacked = true end
                if def.onequip or def.onunequip then has_onequip = true end
            end
        end

        item.rogue_affix_text = (#lines > 0) and ("\n" .. table.concat(lines, "\n")) or ""
        if item._rogue_affix_nettext then
            item._rogue_affix_nettext:set(item.rogue_affix_text)
        end

        -- 挂载事件和组件
        if has_onattack and item.components.weapon and not item._rogue_onattack_hooked then
            item._rogue_onattack_hooked = true
            local old_onattack = item.components.weapon.onattack
            item.components.weapon:SetOnAttack(function(inst, attacker, target)
                if old_onattack then
                    old_onattack(inst, attacker, target)
                end
                for _, id in ipairs(inst.rogue_abilities or {}) do
                    local def = nil
                    for _, d in ipairs(ABILITY_DEFS) do if d.id == id then def = d; break end end
                    if def and def.onattack then
                        def.onattack(inst, attacker, target)
                    end
                end
            end)
        end

        if has_onattacked and item.components.armor and not item._rogue_onattacked_hooked then
            item._rogue_onattacked_hooked = true
            item._rogue_onattacked = function(owner, data)
                local attacker = data and data.attacker
                local damage = data and data.damage or 0
                for _, id in ipairs(item.rogue_abilities or {}) do
                    local def = nil
                    for _, d in ipairs(ABILITY_DEFS) do if d.id == id then def = d; break end end
                    if def and def.onattacked then
                        def.onattacked(item, owner, attacker, damage)
                    end
                end
            end
        end

        if (has_onequip or has_onattacked) and item.components.equippable and not item._rogue_onequip_hooked then
            item._rogue_onequip_hooked = true
            local old_onequip = item.components.equippable.onequipfn
            local old_onunequip = item.components.equippable.onunequipfn

            item.components.equippable:SetOnEquip(function(inst, owner)
                if old_onequip then old_onequip(inst, owner) end
                for _, id in ipairs(inst.rogue_abilities or {}) do
                    local def = nil
                    for _, d in ipairs(ABILITY_DEFS) do if d.id == id then def = d; break end end
                    if def and def.onequip then
                        def.onequip(inst, owner)
                    end
                end
                if inst._rogue_onattacked then
                    inst._rogue_attacked_handler = function(o, data) inst._rogue_onattacked(o, data) end
                    owner:ListenForEvent("attacked", inst._rogue_attacked_handler)
                end
            end)

            item.components.equippable:SetOnUnequip(function(inst, owner)
                if old_onunequip then old_onunequip(inst, owner) end
                for _, id in ipairs(inst.rogue_abilities or {}) do
                    local def = nil
                    for _, d in ipairs(ABILITY_DEFS) do if d.id == id then def = d; break end end
                    if def and def.onunequip then
                        def.onunequip(inst, owner)
                    end
                end
                if inst._rogue_attacked_handler then
                    owner:RemoveEventCallback("attacked", inst._rogue_attacked_handler)
                    inst._rogue_attacked_handler = nil
                end
            end)
        end

        if refill_durability then
            if item.components.finiteuses then
                item.components.finiteuses:SetPercent(1)
            elseif item.components.armor then
                item.components.armor:SetPercent(1)
            end
        end

        -- 更新UI描述
        if item.rogue_affix_text ~= "" and item.components.inspectable then
            if not item._rogue_desc_base then
                item._rogue_desc_base = item.components.inspectable.GetDescription
                item.components.inspectable.GetDescription = function(self, viewer)
                    local inst = self.inst
                    local base_text = inst._rogue_desc_base and inst._rogue_desc_base(self, viewer) or ""
                    return base_text .. (inst.rogue_affix_text or "")
                end
            end
        end
        
        -- 品质发光效果
        if item.Light then
            local count = #(item.rogue_abilities or {})
            local level = math.min(1, count / 4)
            item.Light:SetIntensity(0.35 + 0.25 * level)
            item.Light:SetRadius(0.35 + 0.25 * level)
            local r, g, b = 1, 0.88, 0.55
            local rarity = meta and meta.rarity or nil
            if rarity == "rare" then
                r, g, b = 0.45, 0.75, 1
            elseif rarity == "epic" then
                r, g, b = 0.72, 0.48, 1
            elseif rarity == "legendary" then
                r, g, b = 1, 0.62, 0.15
            end
            item.Light:SetColour(r, g, b)
            item.Light:Enable(true)
        end

        return true
    end

    -- 挂载物品的持久化钩子，保存与加载其能力属性
    local function HookRogueItemPersistence(item)
        if not item or item._rogue_persist_hooked then return end
        item._rogue_persist_hooked = true

        local _OnSave = item.OnSave
        item.OnSave = function(inst, data)
            local refs
            if _OnSave then 
                refs = _OnSave(inst, data) 
            end
            if inst.rogue_abilities then
                data.rogue_abilities = CloneList(inst.rogue_abilities)
            end
            if inst.rogue_affix_meta then
                data.rogue_affix_meta = CloneMap(inst.rogue_affix_meta)
            end
            return refs
        end

        local _OnLoad = item.OnLoad
        item.OnLoad = function(inst, data)
            if _OnLoad then _OnLoad(inst, data) end
            if not data then return end
            if data.rogue_abilities then
                inst.rogue_abilities = CloneList(data.rogue_abilities)
                inst.rogue_affix_meta = data.rogue_affix_meta and CloneMap(data.rogue_affix_meta) or nil
                inst:DoTaskInTime(0, function()
                    if inst:IsValid() and inst.rogue_abilities then
                        ApplyRogueAbilities(inst, inst.rogue_abilities, inst.rogue_affix_meta, false)
                    end
                end)
            end
        end
    end

    state.RegisterItemPersistenceHook = function()
        deps.AddPrefabPostInitAny(function(inst)
            if not deps.IsMasterSim() then return end
            if not inst.components or not inst.components.inventoryitem then return end
            -- 注意：_rogue_affix_nettext 和 displaynamefn 已经在 modmain.lua 中全局注册
            -- 必须保证客户端和服务器网络变量对齐
            if not deps.IsRogueAffixCandidatePrefab(inst.prefab) then return end
            HookRogueItemPersistence(inst)
        end)
    end

    -- 在实体死亡位置附近生成掉落物，并可选择应用附魔
    state.SpawnDrop = function(victim, prefab, abilities)
        local actual_prefab = deps.ResolveRuntimePrefab(prefab)
        if not actual_prefab then
            if deps.IsPrefabRegistered(prefab) then
                actual_prefab = prefab
            else
                if deps.Config.DEBUG_MODE then
                    print("SpawnDrop: Invalid prefab or alias for " .. tostring(prefab))
                end
                return
            end
        end

        local item = deps.SpawnPrefab(actual_prefab)
        if not item then
            print("SpawnDrop Error: Failed to spawn prefab '" .. tostring(actual_prefab) .. "' (original: '" .. tostring(prefab) .. "')")
            if deps.Config.DEBUG_MODE then
                print("SpawnDrop: Failed to spawn prefab " .. tostring(actual_prefab))
            end
            return
        end

        local pt = victim:GetPosition()
        local offset = deps.FindWalkableOffset(pt, math.random() * 2 * deps.PI, 2, 8, true, false)
        item.Transform:SetPosition((offset and (pt + offset) or pt):Get())

        HookRogueItemPersistence(item)
        if abilities then
            local applied = ApplyRogueAbilities(item, abilities, { refill_durability = true })
            if not applied then
                item.rogue_abilities = nil
                item.rogue_affix_text = nil
                if item._rogue_affix_nettext then
                    item._rogue_affix_nettext:set("")
                end
                if item.Light then item.Light:Enable(false) end
            end
        end
        return item
    end

    local function CalculateDiminishingReturn(current_val, add_val)
        if current_val > 3.0 then return add_val * 0.1 end
        if current_val > 1.5 then return add_val * 0.5 end
        return add_val
    end

    local RARITY_DEFS = {
        common = { rarity_name = "普通", mult = 0.9, min_affix = 1, max_affix = 1 },
        rare = { rarity_name = "精良", mult = 1.08, min_affix = 1, max_affix = 2 },
        epic = { rarity_name = "史诗", mult = 1.26, min_affix = 2, max_affix = 2 },
        legendary = { rarity_name = "传说", mult = 1.5, min_affix = 2, max_affix = 3 },
    }

    local function GetSeasonRotation(day)
        local defs = deps.SEASON_AFFIX_ROTATION_DEFS
        if not defs or #defs == 0 then return nil end
        local idx = ((math.max(1, day) - 1) % #defs) + 1
        return defs[idx]
    end

    local function BuildSet(list)
        local set = {}
        for _, v in ipairs(list or {}) do
            set[v] = true
        end
        return set
    end

    local function IsAbilitySlotMatch(item, slot)
        if slot == "all" then
            return true
        end
        if slot == "weapon" then
            return item.components and item.components.weapon ~= nil
        end
        if slot == "armor" then
            return item.components and item.components.armor ~= nil
        end
        if slot == "equippable" then
            return item.components and item.components.equippable ~= nil
        end
        return false
    end

    local function BuildAbilityPool(item, day)
        local out = {}
        local rotation = GetSeasonRotation(day)
        local enabled = BuildSet(rotation and rotation.enable or nil)
        local disabled = BuildSet(rotation and rotation.disable or nil)
        for _, def in ipairs(ABILITY_DEFS) do
            if day >= (def.min_day or 0) and IsAbilitySlotMatch(item, def.slot) and not disabled[def.id] then
                local node = def
                if next(enabled) ~= nil and enabled[def.id] then
                    node = {
                        id = def.id, name = def.name, slot = def.slot,
                        weight = (def.weight or 1) * 1.45, min_day = def.min_day,
                    }
                end
                table.insert(out, node)
            end
        end
        return out
    end

    local function PickAbilityOnce(pool, used)
        local total = 0
        for _, v in ipairs(pool) do
            if not used[v.id] then
                total = total + (v.weight or 1)
            end
        end
        if total <= 0 then
            return nil
        end
        local roll = math.random() * total
        for _, v in ipairs(pool) do
            if not used[v.id] then
                roll = roll - (v.weight or 1)
                if roll <= 0 then
                    return v
                end
            end
        end
        return nil
    end

    local function GetProgressTier(day)
        if day >= 90 then return 4 end
        if day >= 60 then return 3 end
        if day >= 30 then return 2 end
        return 1
    end

    local function ApplyRarityPity(common, rare, epic, legendary, pity_key)
        local rules = deps.DROP_PITY_RULES and deps.DROP_PITY_RULES[pity_key] or nil
        if not rules then
            return common, rare, epic, legendary
        end
        local stacks = state.gear_quality_pity[pity_key] or 0
        if stacks <= (rules.start_after or 99) then
            return common, rare, epic, legendary
        end
        local active = math.min((rules.max_stacks or stacks), stacks) - (rules.start_after or 0)
        if active <= 0 then
            return common, rare, epic, legendary
        end
        local add_rare = (rules.per_stack_rare or 0) * active
        local add_epic = (rules.per_stack_epic or 0) * active
        local add_legendary = (rules.per_stack_legendary or 0) * active
        local common_cut = add_rare + add_epic + add_legendary
        common = math.max(0, common - common_cut * 100)
        rare = rare + add_rare * 100
        epic = epic + add_epic * 100
        legendary = legendary + add_legendary * 100
        return common, rare, epic, legendary
    end

    local function PickRarity(day, ctx)
        ctx = ctx or {}
        local tier = GetProgressTier(day)
        local w = {
            [1] = { common = 62, rare = 30, epic = 8, legendary = 0 },
            [2] = { common = 42, rare = 36, epic = 18, legendary = 4 },
            [3] = { common = 26, rare = 38, epic = 24, legendary = 12 },
            [4] = { common = 14, rare = 34, epic = 32, legendary = 20 },
        }
        local row = w[tier] or w[2]
        local common = row.common
        local rare = row.rare
        local epic = row.epic
        local legendary = row.legendary
        if ctx.is_trial then
            common = math.max(5, common - 10)
            rare = rare + 3
            epic = epic + 5
            legendary = legendary + 2
        end
        if ctx.is_special then
            common = math.max(0, common - 18)
            rare = math.max(0, rare - 4)
            epic = epic + 10
            legendary = legendary + 12
        end
        local rotation = GetSeasonRotation(day)
        if rotation and rotation.rarity_bonus then
            rare = rare + (rotation.rarity_bonus.rare or 0) * 100
            epic = epic + (rotation.rarity_bonus.epic or 0) * 100
            legendary = legendary + (rotation.rarity_bonus.legendary or 0) * 100
            common = math.max(0, common - ((rotation.rarity_bonus.rare or 0) + (rotation.rarity_bonus.epic or 0) + (rotation.rarity_bonus.legendary or 0)) * 100)
        end
        if ctx.objective_bonus and ctx.objective_bonus > 0 then
            rare = rare + ctx.objective_bonus
            epic = epic + ctx.objective_bonus * 0.75
            legendary = legendary + ctx.objective_bonus * 0.45
            common = math.max(0, common - ctx.objective_bonus * 2.2)
        end
        common, rare, epic, legendary = ApplyRarityPity(common, rare, epic, legendary, ctx.pity_key)
        local total = common + rare + epic + legendary
        if total <= 0 then
            return "common"
        end
        local roll = math.random() * total
        if roll <= common then return "common" end
        roll = roll - common
        if roll <= rare then return "rare" end
        roll = roll - rare
        if roll <= epic then return "epic" end
        return "legendary"
    end

    local function CommitRarityPity(pity_key, rarity_key, killer)
        if not pity_key then return end
        state.gear_quality_pity[pity_key] = state.gear_quality_pity[pity_key] or 0
        local rules = deps.DROP_PITY_RULES and deps.DROP_PITY_RULES[pity_key] or nil
        local reset_on_epic = rules and rules.reset_on_epic
        if rarity_key == "legendary" or (reset_on_epic and rarity_key == "epic") then
            state.gear_quality_pity[pity_key] = 0
        else
            state.gear_quality_pity[pity_key] = math.min((rules and rules.max_stacks) or 9, state.gear_quality_pity[pity_key] + 1)
        end
        if killer and deps.IsValidPlayer and deps.IsValidPlayer(killer) and deps.EnsurePlayerData then
            local data = deps.EnsurePlayerData(killer)
            data.loot_pity_stack = state.gear_quality_pity[pity_key] or 0
            if deps.SyncGrowthNetvars then
                deps.SyncGrowthNetvars(killer, data)
            end
        end
    end

    local function RecordBuildStats(killer, meta, abilities)
        if not killer or not deps.IsValidPlayer or not deps.IsValidPlayer(killer) or not deps.EnsurePlayerData then
            return
        end
        local data = deps.EnsurePlayerData(killer)
        data.build_affix_counts = data.build_affix_counts or {}
        data.build_rarity_counts = data.build_rarity_counts or { common = 0, rare = 0, epic = 0, legendary = 0 }
        if meta and meta.rarity then
            data.build_rarity_counts[meta.rarity] = (data.build_rarity_counts[meta.rarity] or 0) + 1
        end
        for _, ab in ipairs(abilities or {}) do
            data.build_affix_counts[ab] = (data.build_affix_counts[ab] or 0) + 1
        end
        local score =
            (data.build_rarity_counts.common or 0) * 1 +
            (data.build_rarity_counts.rare or 0) * 3 +
            (data.build_rarity_counts.epic or 0) * 6 +
            (data.build_rarity_counts.legendary or 0) * 10
        data.build_score = score
        if deps.SyncGrowthNetvars then
            deps.SyncGrowthNetvars(killer, data)
        end
    end

    local function RollAbilitiesForItem(item, day, ctx)
        if not item or not item:IsValid() then return nil, nil end
        local rarity_key = PickRarity(day, ctx)
        local rarity = RARITY_DEFS[rarity_key] or RARITY_DEFS.common
        local pool = BuildAbilityPool(item, day)
        if #pool == 0 then return nil, nil end
        local count = math.random(rarity.min_affix, rarity.max_affix)
        local used = {}
        local abilities = {}
        local names = {}
        for _ = 1, count do
            local picked = PickAbilityOnce(pool, used)
            if not picked then break end
            used[picked.id] = true
            table.insert(abilities, picked.id)
            table.insert(names, picked.name)
        end
        
        local signature = ctx and ctx.boss_signature or nil
        if signature and signature.bonus_affix then
            for k, _ in pairs(signature.bonus_affix) do
                if not used[k] then
                    local is_valid = false
                    for _, d in ipairs(ABILITY_DEFS) do
                        if d.id == k and IsAbilitySlotMatch(item, d.slot) then
                            is_valid = true
                            table.insert(names, d.name)
                            break
                        end
                    end
                    if is_valid then
                        table.insert(abilities, k)
                        used[k] = true
                    end
                end
            end
        end

        if #abilities == 0 then
            return nil, nil
        end
        local meta = {
            rarity = rarity_key,
            rarity_name = rarity.rarity_name,
            affix_names = table.concat(names, "、"),
            season_rotation = (GetSeasonRotation(day) and GetSeasonRotation(day).id) or nil,
        }
        CommitRarityPity(ctx and ctx.pity_key or nil, rarity_key, ctx and ctx.killer or nil)
        RecordBuildStats(ctx and ctx.killer or nil, meta, abilities)
        return abilities, meta
    end

    local function SpawnBossGearDrop(victim, prefab, day, ctx)
        local item = state.SpawnDrop(victim, prefab, nil)
        if not item then return false, nil end
        local abilities, meta = RollAbilitiesForItem(item, day, ctx)
        if abilities then
            ApplyRogueAbilities(item, abilities, meta, true)
        end
        return true, meta
    end

    local function PickBossSpecificGear(victim, day)
        if not deps.BossLoot then return nil, false, nil end
        local raw_key = (victim and victim.rogue_boss_loot_key) or (victim and victim.prefab) or nil
        local pool, key = deps.BossLoot.GetPool(raw_key)
        if not pool or #pool == 0 then return nil, false, nil end
        local pity = state.boss_loot_pity[key] or 0
        local chance = math.min(0.95, 0.65 + pity * 0.1)
        if math.random() <= chance then
            local total = 0
            for _, v in ipairs(pool) do
                total = total + (v.weight or 1)
            end
            local picked = deps.PickWeightedCandidate(pool, total)
            if picked then
                state.boss_loot_pity[key] = 0
                return picked.prefab, true, key
            end
        end
        state.boss_loot_pity[key] = math.min(6, pity + 1)
        return nil, false, key
    end

    local function GetBossSignature(victim)
        local defs = deps.BOSS_LOOT_SIGNATURE_DEFS
        if not defs then return nil end
        local key = (victim and victim.rogue_boss_loot_key) or (victim and victim.prefab) or "default"
        return defs[key] or defs.default
    end

    local function GetObjectiveBoost(killer)
        if not killer or not deps.EnsurePlayerData then
            return { done = 0, grade = 0, gear_weight_mult = 1, rarity_bonus = 0 }
        end
        local data = deps.EnsurePlayerData(killer)
        local done = math.max(0, math.min(4, data.season_objective_done or 0))
        local grade = math.max(0, math.min(3, data.season_objective_grade or 0))
        local gear_weight_mult = 1 + done * 0.05 + grade * 0.03
        local rarity_bonus = done * 0.8 + grade * 1.2
        return {
            done = done,
            grade = grade,
            gear_weight_mult = gear_weight_mult,
            rarity_bonus = rarity_bonus,
        }
    end

    local function PickBossGearBySignature(pool, victim, objective_boost)
        if not pool or #pool == 0 then return nil end
        local signature = GetBossSignature(victim)
        local sig_tags = BuildSet(signature and signature.tags or nil)
        local boost_mult = (objective_boost and objective_boost.gear_weight_mult) or 1
        local total = 0
        local weighted = {}
        for _, it in ipairs(pool) do
            local w = it.weight or 1
            if next(sig_tags) ~= nil then
                local match = 0
                for _, t in ipairs(it.tags or {}) do
                    if sig_tags[t] then
                        match = match + 1
                    end
                end
                if match > 0 then
                    w = w * (1 + 0.28 * match)
                end
            end
            w = w * boost_mult
            total = total + w
            weighted[#weighted + 1] = { item = it, w = w }
        end
        if total <= 0 then return pool[math.random(#pool)] end
        local roll = math.random() * total
        for _, node in ipairs(weighted) do
            roll = roll - node.w
            if roll <= 0 then
                return node.item
            end
        end
        return weighted[#weighted].item
    end

    state.ApplyBuff = function(player, is_boss)
        if not deps.IsValidPlayer(player) then return end
        local data = deps.EnsurePlayerData(player)

        local fx = deps.SpawnPrefab("explode_reskin")
        if fx then
            fx.Transform:SetPosition(player.Transform:GetWorldPosition())
            fx.Transform:SetScale(0.5, 0.5, 0.5)
        end

        if math.random() < 0.5 then
            local mult = is_boss and deps.BUFF_TYPES.HEALTH.boss_mult or 1
            local val = math.random(deps.BUFF_TYPES.HEALTH.min, deps.BUFF_TYPES.HEALTH.max) * mult
            if player.components.health and player.components.health.maxhealth > 500 then
                val = val * 0.5
            end
            if player.components.health then
                player.components.health:SetMaxHealth(player.components.health.maxhealth + val)
                player.components.health:DoDelta(val)
                data.hp_bonus = (data.hp_bonus or 0) + val
                player.rogue_applied_hp_bonus = data.hp_bonus
                if player.rogue_hp_bonus then player.rogue_hp_bonus:set(data.hp_bonus) end
                deps.Announce(player:GetDisplayName() .. " 获得了 " .. math.floor(val) .. " 点生命上限！")
            end
        else
            local mult = is_boss and deps.BUFF_TYPES.DAMAGE.boss_mult or 1
            local val = deps.RollRange(deps.BUFF_TYPES.DAMAGE) * mult
            val = CalculateDiminishingReturn(data.damage_bonus, val)
            data.damage_bonus = data.damage_bonus + val
            if player.components.combat then
                player.components.combat.externaldamagemultipliers:SetModifier(deps.CONST.DAMAGE_MODIFIER_KEY, 1 + data.damage_bonus)
            end
            if player.rogue_dmg_bonus then player.rogue_dmg_bonus:set(data.damage_bonus) end
            deps.Announce(player:GetDisplayName() .. " 获得了 " .. string.format("%.1f", val * 100) .. "% 伤害加成！")
        end
    end

    state.DropLoot = function(victim, is_boss, day, killer)
        if not victim or not victim:IsValid() then return end
        if victim._rogue_drop_done then return end
        victim._rogue_drop_done = true
        
        -- 判断击杀者是否拥有贪婪契约
        local has_greed = killer and killer:HasTag("rogue_greed_pact")
        
        local objective_boost = GetObjectiveBoost(killer)
        if is_boss then
            local is_trial_boss = victim:HasTag("rogue_trial_boss")
            local tier = GetProgressTier(day)
            local bal = deps.VNEXT_DROP_BALANCE or {}
            local gear_pool, gear_w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_GEAR", day)
            local mat_pool, mat_w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_MATS", day)
            local main_meta = nil
            local boss_signature = GetBossSignature(victim)
            if is_trial_boss then
                if gear_pool then
                    local item = PickBossGearBySignature(gear_pool, victim, objective_boost) or deps.PickWeightedCandidate(gear_pool, gear_w)
                    if item then
                        local _, meta = SpawnBossGearDrop(victim, item.prefab, day, { is_trial = true, pity_key = "trial_gear", boss_signature = boss_signature, killer = killer, objective_bonus = objective_boost.rarity_bonus })
                        main_meta = meta or main_meta
                    end
                    local trial_extra_base = bal.trial_extra_base or 0.25
                    local trial_extra_step = bal.trial_extra_tier_step or 0.12
                    local trial_extra_cap = bal.trial_extra_cap or 0.72
                    local extra_chance = math.min(trial_extra_cap, trial_extra_base + trial_extra_step * tier)
                    if has_greed then extra_chance = extra_chance + 0.3 end -- 贪婪契约提升掉率
                    if math.random() < extra_chance then
                        local extra = PickBossGearBySignature(gear_pool, victim, objective_boost) or deps.PickWeightedCandidate(gear_pool, gear_w)
                        if extra then
                            SpawnBossGearDrop(victim, extra.prefab, day, { is_trial = true, pity_key = "trial_gear", boss_signature = boss_signature, killer = killer, objective_bonus = objective_boost.rarity_bonus })
                        end
                    end
                end
                if mat_pool then
                    local trial_mat_base = bal.trial_mat_base or 1
                    local trial_mat_tier_bonus = bal.trial_mat_tier_bonus or 1
                    local trial_min = trial_mat_base + trial_mat_tier_bonus * tier
                    local count = math.random(trial_min, trial_min + 1)
                    for _ = 1, count do
                        local item = deps.PickWeightedCandidate(mat_pool, mat_w)
                        if item then state.SpawnDrop(victim, item.prefab) end
                    end
                end
                if main_meta and main_meta.rarity_name then
                    deps.Announce("挑战房试炼Boss被击败！掉落了" .. main_meta.rarity_name .. "战利品！")
                else
                    deps.Announce("挑战房试炼Boss被击败！掉落了试炼战利品！")
                end
                return
            end
            local special_prefab, used_special, special_key = PickBossSpecificGear(victim, day)
            if special_prefab then
                local _, meta = SpawnBossGearDrop(victim, special_prefab, day, { is_special = true, pity_key = "boss_gear", boss_signature = boss_signature, killer = killer, objective_bonus = objective_boost.rarity_bonus })
                main_meta = meta or main_meta
            elseif gear_pool then
                local item = PickBossGearBySignature(gear_pool, victim, objective_boost) or deps.PickWeightedCandidate(gear_pool, gear_w)
                if item then
                    local _, meta = SpawnBossGearDrop(victim, item.prefab, day, { pity_key = "boss_gear", boss_signature = boss_signature, killer = killer, objective_bonus = objective_boost.rarity_bonus })
                    main_meta = meta or main_meta
                end
            end
            if gear_pool then
                local boss_extra_base = bal.boss_extra_base or 0.12
                local boss_extra_step = bal.boss_extra_tier_step or 0.1
                local boss_extra_cap = bal.boss_extra_cap or 0.6
                local extra_chance = math.min(boss_extra_cap, boss_extra_base + boss_extra_step * tier)
                if has_greed then extra_chance = extra_chance + 0.3 end -- 贪婪契约提升掉率
                if math.random() < extra_chance then
                    local extra = PickBossGearBySignature(gear_pool, victim, objective_boost) or deps.PickWeightedCandidate(gear_pool, gear_w)
                    if extra then
                        SpawnBossGearDrop(victim, extra.prefab, day, { pity_key = "boss_gear", boss_signature = boss_signature, killer = killer, objective_bonus = objective_boost.rarity_bonus })
                    end
                end
            end
            if mat_pool then
                local boss_mat_base = bal.boss_mat_base or 2
                local boss_mat_tier_bonus = bal.boss_mat_tier_bonus or 1
                local boss_min = boss_mat_base + boss_mat_tier_bonus * tier
                local count = math.random(boss_min, boss_min + 1)
                for _ = 1, count do
                    local item = deps.PickWeightedCandidate(mat_pool, mat_w)
                    if item then state.SpawnDrop(victim, item.prefab) end
                end
            end
            if used_special and special_key then
                if main_meta and main_meta.rarity_name then
                    deps.Announce("BOSS 被击败！掉落了专属" .. main_meta.rarity_name .. "战利品！")
                else
                    deps.Announce("BOSS 被击败！掉落了专属战利品！")
                end
            else
                if main_meta and main_meta.rarity_name then
                    deps.Announce("BOSS 被击败！掉落了" .. main_meta.rarity_name .. "稀有战利品！")
                else
                    deps.Announce("BOSS 被击败！掉落了稀有战利品！")
                end
            end
            return
        end

        if victim:HasTag("rogue_elite") then
            local drop_pool, drop_w = deps.PoolCatalog.GetRuntimePool("DROPS_NORMAL", day)
            local rare_pool, rare_w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_MATS", day)
            local gear_pool, gear_w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_GEAR", day)
            local bal = deps.VNEXT_DROP_BALANCE or {}
            local elite_gear_chance = bal.elite_gear_chance or 0.14
            if has_greed then elite_gear_chance = elite_gear_chance + 0.15 end -- 贪婪契约提升精英掉率
            for _ = 1, math.random(1, 2) do
                local roll = math.random()
                if roll < elite_gear_chance and gear_pool then
                    local item = deps.PickWeightedCandidate(gear_pool, gear_w)
                    if item then
                        SpawnBossGearDrop(victim, item.prefab, day, { elite_bonus = true, pity_key = "boss_gear", killer = killer, objective_bonus = objective_boost.rarity_bonus * 0.6 })
                    end
                elseif roll < (elite_gear_chance + 0.18) and rare_pool then
                    local item = deps.PickWeightedCandidate(rare_pool, rare_w)
                    if item then state.SpawnDrop(victim, item.prefab) end
                elseif drop_pool then
                    local item = deps.PickWeightedCandidate(drop_pool, drop_w)
                    if item then state.SpawnDrop(victim, item.prefab) end
                end
            end
            return
        end

        local killer_data = killer and deps.EnsurePlayerData(killer) or nil
        local drop_bonus = killer_data and killer_data.drop_bonus or 0
        local ws = deps.GetWaveState()
        local wave_drop_bonus = (ws and ws.current_rule and ws.current_rule.drop_bonus) or 0
        local route_drop_bonus = (ws and ws.route_drop_bonus) or 0
        local threat_drop_bonus = (ws and ws.threat_drop_bonus) or 0
        local catastrophe_drop_bonus = (ws and ws.catastrophe and ws.catastrophe.drop_bonus) or 0
        local chance = deps.Config.NORMAL_DROP_CHANCE + math.floor((day - 1) / 15) * 0.02 + drop_bonus + wave_drop_bonus + route_drop_bonus + threat_drop_bonus + catastrophe_drop_bonus
        if has_greed then chance = chance + 0.15 end -- 贪婪契约提升普通怪掉率
        if math.random() < math.min(deps.CONST.MAX_NORMAL_DROP_CHANCE, chance) then
            local pool, w = deps.PoolCatalog.GetRuntimePool("DROPS_NORMAL", day)
            local item = deps.PickWeightedCandidate(pool, w)
            if item then state.SpawnDrop(victim, item.prefab) end
        end
    end

    state.ExportState = function()
        return {
            boss_loot_pity = CloneNumberMap(state.boss_loot_pity),
            gear_quality_pity = CloneNumberMap(state.gear_quality_pity),
        }
    end

    state.ImportState = function(saved)
        if type(saved) ~= "table" then
            return
        end
        state.boss_loot_pity = CloneNumberMap(saved.boss_loot_pity)
        local pity = CloneNumberMap(saved.gear_quality_pity)
        state.gear_quality_pity = {
            boss_gear = math.max(0, pity.boss_gear or 0),
            trial_gear = math.max(0, pity.trial_gear or 0),
        }
    end

    return state
end

return M
