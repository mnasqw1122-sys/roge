local assets =
{
    Asset("ANIM", "anim/player_basic.zip"),
    Asset("ANIM", "anim/player_idles_shiver.zip"),
    Asset("ANIM", "anim/player_actions.zip"),
    Asset("ANIM", "anim/player_actions_axe.zip"),
    Asset("ANIM", "anim/player_actions_pickaxe.zip"),
    Asset("ANIM", "anim/player_actions_shovel.zip"),
    Asset("ANIM", "anim/player_actions_blowdart.zip"),
    Asset("ANIM", "anim/player_actions_eat.zip"),
    Asset("ANIM", "anim/player_actions_item.zip"),
    Asset("ANIM", "anim/player_actions_uniqueitem.zip"),
    Asset("ANIM", "anim/player_actions_bugnet.zip"),
    Asset("ANIM", "anim/player_actions_fishing.zip"),
    Asset("ANIM", "anim/player_actions_boomerang.zip"),
    Asset("ANIM", "anim/player_bush_hat.zip"),
    Asset("ANIM", "anim/player_attacks.zip"),
    Asset("ANIM", "anim/player_idles.zip"),
    Asset("ANIM", "anim/player_rebirth.zip"),
    Asset("ANIM", "anim/player_jump.zip"),
    Asset("ANIM", "anim/player_amulet_resurrect.zip"),
    Asset("ANIM", "anim/player_teleport.zip"),
    Asset("ANIM", "anim/wilson_fx.zip"),
    Asset("ANIM", "anim/player_one_man_band.zip"),
    Asset("ANIM", "anim/shadow_hands.zip"),
    Asset("ANIM", "anim/swap_glasscutter.zip"),
    Asset("ANIM", "anim/swap_nightmaresword.zip"),
    Asset("ANIM", "anim/swap_ruins_bat.zip"),
    Asset("ANIM", "anim/swap_tornado_stick.zip"),
    Asset("ANIM", "anim/armor_sanity.zip"),
    Asset("ANIM", "anim/eye_shield.zip"),
    Asset("ANIM", "anim/swap_eye_shield.zip"),
    Asset("ANIM", "anim/torso_dragonfly.zip"),
    Asset("ANIM", "anim/armor_ruins.zip"),
    Asset("ANIM", "anim/armor_skeleton.zip"),
    Asset("ANIM", "anim/armor_bramble.zip"),
    Asset("ANIM", "anim/armor_dreadstone.zip"),
    Asset("ANIM", "anim/armor_lunarplant.zip"),
    Asset("ANIM", "anim/armor_voidcloth.zip"),
    Asset("ANIM", "anim/armor_slurtleshell.zip"),
    Asset("ANIM", "anim/hat_ruins.zip"),
    Asset("ANIM", "anim/hat_skeleton.zip"),
    Asset("ANIM", "anim/hat_slurtle.zip"),
    Asset("ANIM", "anim/hat_dreadstone.zip"),
    Asset("ANIM", "anim/hat_voidcloth.zip"),
    Asset("ANIM", "anim/hat_lunarplant.zip"),
    Asset("SOUND", "sound/sfx.fsb"),
    Asset("SOUND", "sound/wilson.fsb"),
}

local prefabs =
{
    "panflute",
    "telestaff",
    "glasscutter",
    "nightsword",
    "ruins_bat",
    "staff_tornado",
    "armor_sanity",
    "shieldofterror",
    "armordragonfly",
    "armorruins",
    "armorskeleton",
    "armor_bramble",
    "armordreadstone",
    "armor_lunarplant",
    "armor_voidcloth",
    "armorsnurtleshell",
    "ruinshat",
    "skeletonhat",
    "slurtlehat",
    "dreadstonehat",
    "voidclothhat",
    "lunarplanthat",
    "perogies",
    "healingsalve",
    "mandrake",
}

local brain = require("brains/rogue_npcbrain")

local PERSONALITIES = {
    aggressive = { name = "狂战士", kite_chance = 0.1, retreat_threshold = 0.1, charge_chance = 0.3, combo_chance = 0.2, dodge_chance = 0.05, taunt_chance = 0.1 },
    cautious = { name = "守卫", kite_chance = 0.5, retreat_threshold = 0.35, charge_chance = 0.05, combo_chance = 0.05, dodge_chance = 0.2, taunt_chance = 0.15 },
    evasive = { name = "游侠", kite_chance = 0.7, retreat_threshold = 0.25, charge_chance = 0.05, combo_chance = 0.1, dodge_chance = 0.35, taunt_chance = 0.02 },
    balanced = { name = "战士", kite_chance = 0.3, retreat_threshold = 0.2, charge_chance = 0.15, combo_chance = 0.15, dodge_chance = 0.1, taunt_chance = 0.08 },
}

-- 函数说明：受击回调
local function OnAttacked(inst, data)
    if data.attacker then
        inst.components.combat:SetTarget(data.attacker)

        if inst._ai_perception then
            inst._ai_perception:UpdateAggro(data.attacker, data.damage or 10)
        end

        local personality = inst._ai_personality or "balanced"
        local p_data = PERSONALITIES[personality] or PERSONALITIES.balanced
        local level = inst._ai_level and inst._ai_level:value() or 1

        if not inst.sg:HasStateTag("busy") and not inst.sg:HasStateTag("dodging") then
            local dodge_chance = p_data.dodge_chance + (level - 1) * 0.02
            if math.random() < dodge_chance then
                local direction = math.random() > 0.5 and 1 or -1
                inst:PushEvent("rogue_dodge", {direction = direction})
            end
        end
    end

    local damage = data and data.damage or 0
    if damage > 0 and TheWorld and TheWorld.components.rogue_ai_npc_manager then
        TheWorld.components.rogue_ai_npc_manager:GainExp(damage * 0.05)
    end
end

-- 函数说明：命中回调
local function OnHitOther(inst, data)
    local damage = data and data.damage or 0
    if damage > 0 and TheWorld and TheWorld.components.rogue_ai_npc_manager then
        TheWorld.components.rogue_ai_npc_manager:GainExp(damage * 0.2)
    end

    local personality = inst._ai_personality or "balanced"
    local p_data = PERSONALITIES[personality] or PERSONALITIES.balanced
    local level = inst._ai_level and inst._ai_level:value() or 1

    if not inst.sg:HasStateTag("busy") then
        local combo_chance = p_data.combo_chance + (level - 1) * 0.01
        if math.random() < combo_chance then
            inst:PushEvent("rogue_combo_attack")
            return
        end

        local charge_chance = p_data.charge_chance + (level - 1) * 0.01
        if math.random() < charge_chance then
            inst:PushEvent("rogue_charge_attack")
        end
    end
end

-- 函数说明：死亡回调
local function OnDeath(inst, data)
    if inst.components.inventory then
        for k, v in pairs(inst.components.inventory.itemslots) do
            v:Remove()
        end
        local equipslots = {}
        for k, v in pairs(inst.components.inventory.equipslots) do
            equipslots[k] = v
        end
        for k, v in pairs(equipslots) do
            inst.components.inventory:Unequip(v)
            v:Remove()
        end
    end

    local weapon = inst.rogue_weapon
    local armor = inst.rogue_armor
    local hat = inst.rogue_hat

    local function SpawnLoot(prefab)
        if prefab then
            for i = 1, 2 do
                local loot = SpawnPrefab(prefab)
                if loot then
                    local pt = inst:GetPosition()
                    loot.Transform:SetPosition(pt.x, pt.y, pt.z)
                    if loot.components.inventoryitem then
                        loot.components.inventoryitem:OnDropped(true)
                    end
                end
            end
        end
    end

    SpawnLoot(weapon)
    SpawnLoot(armor)
    SpawnLoot(hat)

    if TheWorld and TheWorld.components.rogue_ai_npc_manager then
        TheWorld.components.rogue_ai_npc_manager:OnNPCKilled(inst)
    end
end

-- 函数说明：存档回调（清除背包物品，防止网络变量反序列化错误）
local function OnSave(inst, data)
    data.rogue_weapon = inst.rogue_weapon
    data.rogue_armor = inst.rogue_armor
    data.rogue_hat = inst.rogue_hat
    data.ai_personality = inst._ai_personality
    data.combat_style = inst._combat_style
    data.ai_level = inst._ai_level and inst._ai_level:value() or 1

    if inst.components.inventory then
        local items_to_remove = {}
        for k, v in pairs(inst.components.inventory.itemslots) do
            table.insert(items_to_remove, v)
        end
        for k, v in pairs(inst.components.inventory.equipslots) do
            table.insert(items_to_remove, v)
        end
        for _, item in ipairs(items_to_remove) do
            if item and item:IsValid() then
                inst.components.inventory:RemoveItem(item, true)
                item:Remove()
            end
        end
    end
end

-- 函数说明：读档回调（重新装备物品，恢复NPC状态）
local function OnLoad(inst, data)
    if data then
        inst.rogue_weapon = data.rogue_weapon
        inst.rogue_armor = data.rogue_armor
        inst.rogue_hat = data.rogue_hat
        if data.ai_personality then
            inst._ai_personality = data.ai_personality
        end
        if data.combat_style then
            inst._combat_style = data.combat_style
        end
        if data.ai_level and inst._ai_level then
            inst._ai_level:set(data.ai_level)
        end

        inst:DoTaskInTime(0, function()
            if not inst:IsValid() then return end

            local function ReEquipItem(prefab)
                if prefab then
                    local item = SpawnPrefab(prefab)
                    if item then
                        if item.components.armor then
                            item.components.armor:InitCondition(999999, item.components.armor.absorb_percent)
                        end
                        if item.components.finiteuses then
                            item.components.finiteuses:SetMaxUses(999999)
                            item.components.finiteuses:SetUses(999999)
                        end
                        if inst.components.inventory then
                            inst.components.inventory:Equip(item)
                        end
                    end
                end
            end

            ReEquipItem(inst.rogue_weapon)
            ReEquipItem(inst.rogue_armor)
            ReEquipItem(inst.rogue_hat)

            if TheWorld and TheWorld.components.rogue_ai_npc_manager then
                TheWorld.components.rogue_ai_npc_manager.active_npc = inst
            end
        end)
    end
end

-- 函数说明：AI定时决策器（扫描间隔从0.5s提升至1.0s，引入惰性评估降低CPU开销）
local function StartAITicker(inst)
    if inst._ai_ticker then return end
    inst._ai_ticker = inst:DoPeriodicTask(1.0, function()
        if not inst:IsValid() or inst.components.health:IsDead() then return end
        if inst._ai_perception then
            -- 惰性评估：战斗中仅维护当前目标，非战斗状态才执行完整感知扫描
            local in_combat = inst.components.combat
                and inst.components.combat.target
                and inst.components.combat.target:IsValid()
            if not in_combat then
                inst._ai_perception:Scan()
                inst._ai_perception:DecayAggro()
            end
        end

        local personality = inst._ai_personality or "balanced"
        local p_data = PERSONALITIES[personality] or PERSONALITIES.balanced
        local level = inst._ai_level and inst._ai_level:value() or 1
        local target = inst.components.combat and inst.components.combat.target

        if target and target:IsValid() and not inst.sg:HasStateTag("busy") then
            local hp_pct = inst.components.health:GetPercent()
            local target_hp = target.components.health and target.components.health:GetPercent() or 1

            if hp_pct > 0.5 and target_hp < 0.3 and level >= 5 then
                if math.random() < 0.05 then
                    inst:PushEvent("rogue_taunt")
                end
            end

            if hp_pct > 0.6 and level >= 3 then
                local charge_chance = p_data.charge_chance * 0.1
                if math.random() < charge_chance then
                    inst:PushEvent("rogue_charge_attack")
                end
            end
        end
    end)
end

local function fn()
    local inst = CreateEntity()

    inst.entity:AddTransform()
    inst.entity:AddAnimState()
    inst.entity:AddSoundEmitter()
    inst.entity:AddDynamicShadow()
    inst.entity:AddNetwork()

    MakeCharacterPhysics(inst, 75, .5)

    inst.DynamicShadow:SetSize(1.3, .6)

    inst.Transform:SetFourFaced()

    inst.AnimState:SetBank("wilson")
    inst.AnimState:SetBuild("wilson")
    inst.AnimState:PlayAnimation("idle")
    inst.AnimState:Hide("hat")
    inst.AnimState:Hide("hair_hat")
    inst.AnimState:Show("arm_normal")
    inst.AnimState:Hide("arm_carry")
    inst.AnimState:Show("torso")
    inst.AnimState:Show("face")

    inst:AddTag("character")
    inst:AddTag("scarytoprey")
    inst:AddTag("rogue_ai_npc")

    inst._ai_level = net_shortint(inst.GUID, "rogue_npc._ai_level", "aileveldirty")

    inst.entity:SetPristine()

    if not TheWorld.ismastersim then
        return inst
    end

    inst:AddComponent("locomotor")
    inst.components.locomotor.runspeed = 6.5
    inst.components.locomotor.walkspeed = 4.5

    inst:AddComponent("health")
    inst.components.health:SetMaxHealth(1500)
    inst.components.health.nofadeout = true

    inst:AddComponent("combat")
    inst.components.combat:SetDefaultDamage(34)
    inst.components.combat:SetAttackPeriod(0.5)
    inst.components.combat:SetRange(2)
    inst.components.combat.hiteffectsymbol = "torso"

    inst:AddComponent("inventory")

    inst:AddComponent("eater")

    inst:AddComponent("inspectable")

    inst:AddComponent("follower")

    inst._ai_personality = "balanced"
    inst._combat_style = "melee"

    inst.displaynamefn = function(inst)
        local lvl = inst._ai_level and inst._ai_level:value() or 1
        local personality = inst._ai_personality or "balanced"
        local p_data = PERSONALITIES[personality] or PERSONALITIES.balanced
        if lvl > 1 then
            return "神秘的挑战者·" .. p_data.name .. " (Lv." .. lvl .. ")"
        else
            return "神秘的挑战者·" .. p_data.name
        end
    end

    inst.name = "神秘的挑战者"

    inst:SetBrain(brain)
    inst:SetStateGraph("SGrogue_npc")

    inst:ListenForEvent("attacked", OnAttacked)
    inst:ListenForEvent("onhitother", OnHitOther)
    inst:ListenForEvent("death", OnDeath)

    inst.OnSave = OnSave
    inst.OnLoad = OnLoad

    inst:DoTaskInTime(0, function()
        if TheWorld and TheWorld.components.rogue_ai_npc_manager then
            TheWorld.components.rogue_ai_npc_manager.active_npc = inst
        end
        StartAITicker(inst)
    end)

    return inst
end

return Prefab("rogue_npc", fn, assets, prefabs)
