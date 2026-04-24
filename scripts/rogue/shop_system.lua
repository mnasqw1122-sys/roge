--[[
    文件说明：shop_system.lua
    功能：肉鸽模式的商店系统。
    处理玩家在商店中购买物品、黑市交易（能力重铸/属性升级）、每日限购、折扣计算以及回收掉落物的服务端逻辑。
]]
local M = {}
local ShopConfig = require("rogue/shop_config")

function M.Create(deps)
    local S = {}

    -- 函数说明：获取玩家今日对指定商品的已购数量。
    local function GetPurchasedCount(data, item_id)
        local daily = data.daily or {}
        local purchases = daily.shop_purchases or {}
        return purchases[item_id] or 0
    end

    -- 函数说明：记录玩家今日购买商品的数量。
    local function RecordPurchase(data, item_id, count)
        if not data.daily then data.daily = {} end
        if not data.daily.shop_purchases then data.daily.shop_purchases = {} end
        data.daily.shop_purchases[item_id] = (data.daily.shop_purchases[item_id] or 0) + (count or 1)
    end

    -- 函数说明：计算折扣后的价格，先应用日增长系数再计算折扣。
    local function GetDiscountedCost(item_id, base_cost)
        local day = deps.GetCurrentDay and deps.GetCurrentDay() or 1
        local adjusted = ShopConfig.GetDayAdjustedCost(base_cost, day)
        local discounts = ShopConfig.GetDailyDiscounts()
        local discount_pct = discounts[item_id]
        if discount_pct and discount_pct > 0 then
            return math.ceil(adjusted * (1 - discount_pct))
        end
        return adjusted
    end

    -- 函数说明：检查并扣除黑市服务的资源代价（积分+生命+理智）。
    local function PayBlackMarketCost(player, service_def, d)
        local current_points = d.points or 0
        if current_points < service_def.cost then
            if player.components.talker then
                player.components.talker:Say("积分不足，需要 " .. service_def.cost .. " 积分。")
            end
            return false
        end

        local hp_cost_pct = service_def.hp_cost or 0
        if hp_cost_pct > 0 and player.components.health then
            local current_hp = player.components.health.currenthealth
            local hp_cost_val = player.components.health.maxhealth * hp_cost_pct
            if current_hp <= hp_cost_val + 1 then
                if player.components.talker then
                    player.components.talker:Say("生命值不足以支付代价！")
                end
                return false
            end
        end

        local sanity_cost_pct = service_def.sanity_cost or 0
        if sanity_cost_pct > 0 and player.components.sanity then
            local current_sanity = player.components.sanity.current
            local sanity_cost_val = player.components.sanity.max * sanity_cost_pct
            if current_sanity <= sanity_cost_val + 1 then
                if player.components.talker then
                    player.components.talker:Say("理智不足以支付代价！")
                end
                return false
            end
        end

        d.points = current_points - service_def.cost
        if player.rogue_points then
            player.rogue_points:set(d.points)
        end

        if hp_cost_pct > 0 and player.components.health then
            local hp_cost_val = player.components.health.maxhealth * hp_cost_pct
            player.components.health:DoDelta(-hp_cost_val, nil, "rogue_black_market")
        end

        if sanity_cost_pct > 0 and player.components.sanity then
            local sanity_cost_val = player.components.sanity.max * sanity_cost_pct
            player.components.sanity:DoDelta(-sanity_cost_val)
        end

        return true
    end

    -- 函数说明：判断物品是否可以放入黑市场景格子（武器或可装备物品）。
    local function IsBlackMarketEligible(item)
        return item ~= nil and item.components ~= nil
            and (item.components.weapon ~= nil or item.components.equippable ~= nil)
    end

    -- 函数说明：获取物品的装备类型分类（weapon/armor/equippable）。
    local function GetItemEquipCategory(item)
        if not item or not item.components then return nil end
        if item.components.weapon then return "weapon" end
        if item.components.armor then return "armor" end
        if item.components.equippable then return "equippable" end
        return nil
    end

    -- 函数说明：从指定类型的升级池中按权重随机抽取一个属性。
    local function PickRandomUpgrade(category)
        local upgrade_defs = ShopConfig.GetBlackMarketUpgradeDefs()
        local pool = upgrade_defs[category]
        if not pool or #pool == 0 then return nil end

        local total_weight = 0
        for _, def in ipairs(pool) do
            total_weight = total_weight + (def.weight or 1)
        end

        local roll = math.random() * total_weight
        local acc = 0
        for _, def in ipairs(pool) do
            acc = acc + (def.weight or 1)
            if roll <= acc then
                return def
            end
        end
        return pool[#pool]
    end

    -- 函数说明：根据当前 rogue_upgrade_stats 重建物品的升级描述文本，并劫持 inspectable.GetDescription 以显示强化属性。
    -- 供 RestoreUpgradesFromSave 和 ApplyUpgradeToItem 共用，消除代码重复和不一致风险。
    local function RebuildItemDescription(item, category)
        if not item or not item:IsValid() then return end
        if not item.rogue_upgrade_stats then return end

        -- 第一遍遍历：生成升级文本（只包含正值属性）
        local upgrade_lines = {}
        local upgrade_defs_table = ShopConfig.GetBlackMarketUpgradeDefs()[category] or {}
        for stat_id, stat_val in pairs(item.rogue_upgrade_stats) do
            if type(stat_val) == "number" and stat_val > 0 then
                for _, udef in ipairs(upgrade_defs_table) do
                    if udef.id == stat_id then
                        table.insert(upgrade_lines, udef.name .. "+" .. string.format("%.1f", stat_val))
                        break
                    end
                end
            end
        end
        item.rogue_upgrade_text = (#upgrade_lines > 0) and ("\n强化: " .. table.concat(upgrade_lines, ", ")) or ""

        -- 总是重新设置 inspectable 描述钩子（读档后是新实体，旧钩子已销毁；多次强化叠加也需更新文本）
        if item.components.inspectable then
            local old_desc = item._rogue_upgrade_base_desc or item.components.inspectable.GetDescription
            item._rogue_upgrade_base_desc = old_desc
            item.components.inspectable.GetDescription = function(self, viewer)
                local inst = self.inst
                local base_text = inst._rogue_upgrade_base_desc and inst._rogue_upgrade_base_desc(self, viewer) or ""
                return base_text .. (inst.rogue_upgrade_text or "")
            end
        end
    end

    -- 函数说明：从存档恢复黑市强化属性（在物品OnLoad时调用，重新应用所有组件修改和事件钩子）。
    local function RestoreUpgradesFromSave(item)
        if not item or not item:IsValid() then return end
        if not item.rogue_upgrade_stats then return end

        local category = GetItemEquipCategory(item)
        if not category then return end

        for stat_id, stat_val in pairs(item.rogue_upgrade_stats) do
            if stat_val <= 0 then
                -- 跳过无效数值
            elseif stat_id == "damage_bonus" and item.components.weapon then
                local base_dmg = item._rogue_original_damage or item.components.weapon.damage or 0
                item._rogue_original_damage = base_dmg
                item.components.weapon:SetDamage(base_dmg + stat_val)
            elseif stat_id == "defense_bonus" and item.components.armor then
                local base_absorb = item._rogue_original_absorb or item.components.armor.absorb_percent or 0
                item._rogue_original_absorb = base_absorb
                item.components.armor.absorb_percent = math.min(0.95, base_absorb + stat_val)
            elseif stat_id == "max_hp_bonus" then
                if item.components.equippable and not item._rogue_upgrade_hp_hooked then
                    item._rogue_upgrade_hp_hooked = true
                    local old_onequip = item.components.equippable.onequipfn
                    local old_onunequip = item.components.equippable.onunequipfn
                    item.components.equippable:SetOnEquip(function(inst, owner)
                        if old_onequip then old_onequip(inst, owner) end
                        local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.max_hp_bonus or 0
                        if bonus > 0 and owner.components.health then
                            owner.components.health:SetMaxHealth(owner.components.health.maxhealth + bonus)
                        end
                    end)
                    item.components.equippable:SetOnUnequip(function(inst, owner)
                        if old_onunequip then old_onunequip(inst, owner) end
                        local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.max_hp_bonus or 0
                        if bonus > 0 and owner.components.health then
                            owner.components.health:SetMaxHealth(math.max(1, owner.components.health.maxhealth - bonus))
                        end
                    end)
                end
            elseif stat_id == "speed_bonus" then
                if item.components.equippable and not item._rogue_upgrade_speed_hooked then
                    item._rogue_upgrade_speed_hooked = true
                    local old_onequip = item.components.equippable.onequipfn
                    local old_onunequip = item.components.equippable.onunequipfn
                    item.components.equippable:SetOnEquip(function(inst, owner)
                        if old_onequip then old_onequip(inst, owner) end
                        local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.speed_bonus or 0
                        if bonus > 0 and owner.components.locomotor then
                            owner.components.locomotor:SetExternalSpeedMultiplier(inst, "rogue_upgrade_speed", 1 + bonus)
                        end
                    end)
                    item.components.equippable:SetOnUnequip(function(inst, owner)
                        if old_onunequip then old_onunequip(inst, owner) end
                        if owner.components.locomotor then
                            owner.components.locomotor:RemoveExternalSpeedMultiplier(inst, "rogue_upgrade_speed")
                        end
                    end)
                end
            elseif stat_id == "regen_bonus" then
                if item.components.equippable and not item._rogue_upgrade_regen_hooked then
                    item._rogue_upgrade_regen_hooked = true
                    local old_onequip = item.components.equippable.onequipfn
                    local old_onunequip = item.components.equippable.onunequipfn
                    item.components.equippable:SetOnEquip(function(inst, owner)
                        if old_onequip then old_onequip(inst, owner) end
                        local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.regen_bonus or 0
                        if bonus > 0 then
                            inst._regen_task = inst:DoPeriodicTask(3, function()
                                if owner and owner:IsValid() and owner.components.health and not owner.components.health:IsDead() then
                                    owner.components.health:DoDelta(bonus)
                                end
                            end)
                        end
                    end)
                    item.components.equippable:SetOnUnequip(function(inst, owner)
                        if old_onunequip then old_onunequip(inst, owner) end
                        if inst._regen_task then
                            inst._regen_task:Cancel()
                            inst._regen_task = nil
                        end
                    end)
                end
            elseif stat_id == "sanity_regen" then
                if item.components.equippable and not item._rogue_upgrade_sanity_hooked then
                    item._rogue_upgrade_sanity_hooked = true
                    local old_onequip = item.components.equippable.onequipfn
                    local old_onunequip = item.components.equippable.onunequipfn
                    item.components.equippable:SetOnEquip(function(inst, owner)
                        if old_onequip then old_onequip(inst, owner) end
                        local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.sanity_regen or 0
                        if bonus > 0 then
                            inst._sanity_task = inst:DoPeriodicTask(3, function()
                                if owner and owner:IsValid() and owner.components.sanity then
                                    owner.components.sanity:DoDelta(bonus)
                                end
                            end)
                        end
                    end)
                    item.components.equippable:SetOnUnequip(function(inst, owner)
                        if old_onunequip then old_onunequip(inst, owner) end
                        if inst._sanity_task then
                            inst._sanity_task:Cancel()
                            inst._sanity_task = nil
                        end
                    end)
                end
            elseif stat_id == "lifesteal" then
                if item.components.weapon and not item._rogue_upgrade_lifesteal_hooked then
                    item._rogue_upgrade_lifesteal_hooked = true
                    local old_onattack = item.components.weapon.onattack
                    item.components.weapon:SetOnAttack(function(inst, attacker, target)
                        if old_onattack then old_onattack(inst, attacker, target) end
                        local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.lifesteal or 0
                        if bonus > 0 and attacker and attacker.components.health and not attacker.components.health:IsDead() then
                            attacker.components.health:DoDelta(bonus)
                        end
                    end)
                end
            elseif stat_id == "thorns" then
                if item.components.equippable and not item._rogue_upgrade_thorns_hooked then
                    item._rogue_upgrade_thorns_hooked = true
                    local old_onequip = item.components.equippable.onequipfn
                    local old_onunequip = item.components.equippable.onunequipfn
                    item.components.equippable:SetOnEquip(function(inst, owner)
                        if old_onequip then old_onequip(inst, owner) end
                        local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.thorns or 0
                        if bonus > 0 and not inst._rogue_thorns_handler then
                            inst._rogue_thorns_handler = function(o, data)
                                local attacker_data = data and data.attacker
                                local damage = data and data.damage or 0
                                if attacker_data and attacker_data:IsValid() and attacker_data.components.combat and damage > 0 then
                                    attacker_data.components.combat:GetAttacked(o, damage * bonus)
                                end
                            end
                            owner:ListenForEvent("attacked", inst._rogue_thorns_handler)
                        end
                    end)
                    item.components.equippable:SetOnUnequip(function(inst, owner)
                        if old_onunequip then old_onunequip(inst, owner) end
                        if inst._rogue_thorns_handler then
                            owner:RemoveEventCallback("attacked", inst._rogue_thorns_handler)
                            inst._rogue_thorns_handler = nil
                        end
                    end)
                end
            elseif stat_id == "crit_chance" then
                if item.components.weapon and not item._rogue_upgrade_crit_hooked then
                    item._rogue_upgrade_crit_hooked = true
                    local old_onattack = item.components.weapon.onattack
                    item.components.weapon:SetOnAttack(function(inst, attacker, target)
                        if old_onattack then old_onattack(inst, attacker, target) end
                        local chance = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.crit_chance or 0
                        if chance > 0 and math.random() < chance and target and target.components.health and not target.components.health:IsDead() then
                            local base_dmg = inst.components.weapon and inst.components.weapon.damage or 34
                            target.components.health:DoDelta(-base_dmg, nil, "rogue_crit")
                            if deps.SpawnPrefab then
                                local fx = deps.SpawnPrefab("sparks")
                                if fx then fx.Transform:SetPosition(target.Transform:GetWorldPosition()) end
                            end
                        end
                    end)
                end
            elseif stat_id == "attack_speed" then
                if item.components.weapon and not item._rogue_upgrade_atkspd_hooked then
                    item._rogue_upgrade_atkspd_hooked = true
                    local old_onattack = item.components.weapon.onattack
                    item.components.weapon:SetOnAttack(function(inst, attacker, target)
                        if old_onattack then old_onattack(inst, attacker, target) end
                        local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.attack_speed or 0
                        if bonus > 0 and attacker and attacker.components.combat then
                            local base_dmg = inst.components.weapon and inst.components.weapon.damage or 34
                            if math.random() < bonus then
                                if target and target.components.health and not target.components.health:IsDead() then
                                    target.components.health:DoDelta(-base_dmg * 0.3, nil, "rogue_atkspd")
                                end
                            end
                        end
                    end)
                end
            elseif stat_id == "insulation_bonus" then
                if item.components.equippable then
                    if item.components.insulator then
                        local base_insul = item._rogue_original_insulation or item.components.insulator.insulation or 0
                        item._rogue_original_insulation = base_insul
                        item.components.insulator:SetInsulation(base_insul + stat_val)
                    else
                        item:AddComponent("insulator")
                        item.components.insulator:SetInsulation(stat_val)
                        item.components.insulator:SetWinter()
                        item._rogue_added_insulator = true
                    end
                end
            elseif stat_id == "dodge_chance" then
                if item.components.equippable and not item._rogue_upgrade_dodge_hooked then
                    item._rogue_upgrade_dodge_hooked = true
                    local old_onequip = item.components.equippable.onequipfn
                    local old_onunequip = item.components.equippable.onunequipfn
                    item.components.equippable:SetOnEquip(function(inst, owner)
                        if old_onequip then old_onequip(inst, owner) end
                        local chance = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.dodge_chance or 0
                        if chance > 0 and not inst._rogue_dodge_handler then
                            inst._rogue_dodge_handler = function(o, data)
                                if math.random() < chance and data and data.damage and data.damage > 0 then
                                    if o.components.health and not o.components.health:IsDead() then
                                        o.components.health:SetInvincible(true)
                                        o:DoTaskInTime(0.1, function(p)
                                            if p and p.components.health then p.components.health:SetInvincible(false) end
                                        end)
                                        if deps.SpawnPrefab then
                                            local fx = deps.SpawnPrefab("small_puff")
                                            if fx then fx.Transform:SetPosition(o.Transform:GetWorldPosition()) end
                                        end
                                    end
                                end
                            end
                            owner:ListenForEvent("attacked", inst._rogue_dodge_handler)
                        end
                    end)
                    item.components.equippable:SetOnUnequip(function(inst, owner)
                        if old_onunequip then old_onunequip(inst, owner) end
                        if inst._rogue_dodge_handler then
                            owner:RemoveEventCallback("attacked", inst._rogue_dodge_handler)
                            inst._rogue_dodge_handler = nil
                        end
                    end)
                end
            end
        end

        -- 重建物品描述文本（调用公共函数）
        RebuildItemDescription(item, category)
    end

    -- 函数说明：挂载物品的强化属性持久化钩子OnSave/OnLoad（首次强化时调用一次，或由 InitPersistence 批量挂载）。
    local function HookItemUpgradePersistence(item)
        if not item or item._rogue_upgrade_persist_hooked then return end
        item._rogue_upgrade_persist_hooked = true
        local item_prefab = item.prefab or "unknown"

        local _OnSave = item.OnSave
        item.OnSave = function(inst, data)
            local refs
            if _OnSave then refs = _OnSave(inst, data) end
            if inst.rogue_upgrade_stats then
                data.rogue_shop_upgrade_stats = {}
                for k, v in pairs(inst.rogue_upgrade_stats) do
                    data.rogue_shop_upgrade_stats[k] = v
                end
                print("[rogue_shop] OnSave persisted upgrades for " .. tostring(inst.prefab or inst) .. " -> " .. (inst.rogue_upgrade_text or ""))
            end
            if inst._rogue_original_damage then
                data.rogue_shop_original_damage = inst._rogue_original_damage
            end
            if inst._rogue_original_absorb then
                data.rogue_shop_original_absorb = inst._rogue_original_absorb
            end
            if inst._rogue_original_insulation then
                data.rogue_shop_original_insulation = inst._rogue_original_insulation
            end
            if inst.rogue_upgrade_text then
                data.rogue_shop_upgrade_text = inst.rogue_upgrade_text
            end
            return refs
        end

        local _OnLoad = item.OnLoad
        item.OnLoad = function(inst, data)
            if _OnLoad then _OnLoad(inst, data) end
            if not data or not data.rogue_shop_upgrade_stats then return end
            print("[rogue_shop] OnLoad detected upgrade data for " .. tostring(inst.prefab or inst) .. " -> " .. tostring(data.rogue_shop_upgrade_text))
            inst.rogue_upgrade_stats = {}
            for k, v in pairs(data.rogue_shop_upgrade_stats) do
                inst.rogue_upgrade_stats[k] = v
            end
            inst._rogue_original_damage = data.rogue_shop_original_damage
            inst._rogue_original_absorb = data.rogue_shop_original_absorb
            inst._rogue_original_insulation = data.rogue_shop_original_insulation
            inst.rogue_upgrade_text = data.rogue_shop_upgrade_text
            inst:DoTaskInTime(0, function()
                if inst:IsValid() and inst.rogue_upgrade_stats then
                    print("[rogue_shop] RestoreUpgradesFromSave scheduled for " .. tostring(inst.prefab or inst))
                    RestoreUpgradesFromSave(inst)
                else
                    print("[rogue_shop] RestoreUpgradesFromSave ABORTED: invalid=" .. tostring(not inst:IsValid()) .. " no_stats=" .. tostring(not inst.rogue_upgrade_stats))
                end
            end)
        end
    end

    -- 函数说明：将升级属性应用到物品上，通过装备回调在游戏内生效。
    local function ApplyUpgradeToItem(item, upgrade_def, value)
        if not item or not item:IsValid() then return end

        -- 首次强化时挂载持久化钩子
        HookItemUpgradePersistence(item)

        item.rogue_upgrade_stats = item.rogue_upgrade_stats or {}

        local existing = item.rogue_upgrade_stats[upgrade_def.id] or 0
        local new_val = existing + value
        item.rogue_upgrade_stats[upgrade_def.id] = new_val

        -- 根据升级类型应用实际效果
        local category = GetItemEquipCategory(item)
        if upgrade_def.id == "damage_bonus" and item.components.weapon then
            local base_dmg = item._rogue_original_damage or item.components.weapon.damage or 0
            item._rogue_original_damage = base_dmg
            local total_bonus = item.rogue_upgrade_stats.damage_bonus or 0
            item.components.weapon:SetDamage(base_dmg + total_bonus)
        elseif upgrade_def.id == "defense_bonus" and item.components.armor then
            local base_absorb = item._rogue_original_absorb or item.components.armor.absorb_percent or 0
            item._rogue_original_absorb = base_absorb
            local total_bonus = item.rogue_upgrade_stats.defense_bonus or 0
            item.components.armor.absorb_percent = math.min(0.95, base_absorb + total_bonus)
        elseif upgrade_def.id == "max_hp_bonus" then
            -- 在装备时通过onequip回调应用
            if item.components.equippable and not item._rogue_upgrade_hp_hooked then
                item._rogue_upgrade_hp_hooked = true
                local old_onequip = item.components.equippable.onequipfn
                local old_onunequip = item.components.equippable.onunequipfn
                item.components.equippable:SetOnEquip(function(inst, owner)
                    if old_onequip then old_onequip(inst, owner) end
                    local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.max_hp_bonus or 0
                    if bonus > 0 and owner.components.health then
                        owner.components.health:SetMaxHealth(owner.components.health.maxhealth + bonus)
                    end
                end)
                item.components.equippable:SetOnUnequip(function(inst, owner)
                    if old_onunequip then old_onunequip(inst, owner) end
                    local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.max_hp_bonus or 0
                    if bonus > 0 and owner.components.health then
                        owner.components.health:SetMaxHealth(math.max(1, owner.components.health.maxhealth - bonus))
                    end
                end)
            end
        elseif upgrade_def.id == "speed_bonus" then
            if item.components.equippable and not item._rogue_upgrade_speed_hooked then
                item._rogue_upgrade_speed_hooked = true
                local old_onequip = item.components.equippable.onequipfn
                local old_onunequip = item.components.equippable.onunequipfn
                item.components.equippable:SetOnEquip(function(inst, owner)
                    if old_onequip then old_onequip(inst, owner) end
                    local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.speed_bonus or 0
                    if bonus > 0 and owner.components.locomotor then
                        owner.components.locomotor:SetExternalSpeedMultiplier(inst, "rogue_upgrade_speed", 1 + bonus)
                    end
                end)
                item.components.equippable:SetOnUnequip(function(inst, owner)
                    if old_onunequip then old_onunequip(inst, owner) end
                    if owner.components.locomotor then
                        owner.components.locomotor:RemoveExternalSpeedMultiplier(inst, "rogue_upgrade_speed")
                    end
                end)
            end
        elseif upgrade_def.id == "regen_bonus" then
            if item.components.equippable and not item._rogue_upgrade_regen_hooked then
                item._rogue_upgrade_regen_hooked = true
                local old_onequip = item.components.equippable.onequipfn
                local old_onunequip = item.components.equippable.onunequipfn
                item.components.equippable:SetOnEquip(function(inst, owner)
                    if old_onequip then old_onequip(inst, owner) end
                    local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.regen_bonus or 0
                    if bonus > 0 then
                        inst._regen_task = inst:DoPeriodicTask(3, function()
                            if owner and owner:IsValid() and owner.components.health and not owner.components.health:IsDead() then
                                owner.components.health:DoDelta(bonus)
                            end
                        end)
                    end
                end)
                item.components.equippable:SetOnUnequip(function(inst, owner)
                    if old_onunequip then old_onunequip(inst, owner) end
                    if inst._regen_task then
                        inst._regen_task:Cancel()
                        inst._regen_task = nil
                    end
                end)
            end
        elseif upgrade_def.id == "sanity_regen" then
            if item.components.equippable and not item._rogue_upgrade_sanity_hooked then
                item._rogue_upgrade_sanity_hooked = true
                local old_onequip = item.components.equippable.onequipfn
                local old_onunequip = item.components.equippable.onunequipfn
                item.components.equippable:SetOnEquip(function(inst, owner)
                    if old_onequip then old_onequip(inst, owner) end
                    local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.sanity_regen or 0
                    if bonus > 0 then
                        inst._sanity_task = inst:DoPeriodicTask(3, function()
                            if owner and owner:IsValid() and owner.components.sanity then
                                owner.components.sanity:DoDelta(bonus)
                            end
                        end)
                    end
                end)
                item.components.equippable:SetOnUnequip(function(inst, owner)
                    if old_onunequip then old_onunequip(inst, owner) end
                    if inst._sanity_task then
                        inst._sanity_task:Cancel()
                        inst._sanity_task = nil
                    end
                end)
            end
        elseif upgrade_def.id == "lifesteal" then
            if item.components.weapon and not item._rogue_upgrade_lifesteal_hooked then
                item._rogue_upgrade_lifesteal_hooked = true
                local old_onattack = item.components.weapon.onattack
                item.components.weapon:SetOnAttack(function(inst, attacker, target)
                    if old_onattack then old_onattack(inst, attacker, target) end
                    local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.lifesteal or 0
                    if bonus > 0 and attacker and attacker.components.health and not attacker.components.health:IsDead() then
                        attacker.components.health:DoDelta(bonus)
                    end
                end)
            end
        elseif upgrade_def.id == "thorns" then
            if item.components.equippable and not item._rogue_upgrade_thorns_hooked then
                item._rogue_upgrade_thorns_hooked = true
                local old_onequip = item.components.equippable.onequipfn
                local old_onunequip = item.components.equippable.onunequipfn
                item.components.equippable:SetOnEquip(function(inst, owner)
                    if old_onequip then old_onequip(inst, owner) end
                    local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.thorns or 0
                    if bonus > 0 and not inst._rogue_thorns_handler then
                        inst._rogue_thorns_handler = function(o, data)
                            local attacker = data and data.attacker
                            local damage = data and data.damage or 0
                            if attacker and attacker:IsValid() and attacker.components.combat and damage > 0 then
                                attacker.components.combat:GetAttacked(o, damage * bonus)
                            end
                        end
                        owner:ListenForEvent("attacked", inst._rogue_thorns_handler)
                    end
                end)
                item.components.equippable:SetOnUnequip(function(inst, owner)
                    if old_onunequip then old_onunequip(inst, owner) end
                    if inst._rogue_thorns_handler then
                        owner:RemoveEventCallback("attacked", inst._rogue_thorns_handler)
                        inst._rogue_thorns_handler = nil
                    end
                end)
            end
        elseif upgrade_def.id == "crit_chance" then
            if item.components.weapon and not item._rogue_upgrade_crit_hooked then
                item._rogue_upgrade_crit_hooked = true
                local old_onattack = item.components.weapon.onattack
                item.components.weapon:SetOnAttack(function(inst, attacker, target)
                    if old_onattack then old_onattack(inst, attacker, target) end
                    local chance = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.crit_chance or 0
                    if chance > 0 and math.random() < chance and target and target.components.health and not target.components.health:IsDead() then
                        local base_dmg = inst.components.weapon and inst.components.weapon.damage or 34
                        target.components.health:DoDelta(-base_dmg, nil, "rogue_crit")
                        if deps.SpawnPrefab then
                            local fx = deps.SpawnPrefab("sparks")
                            if fx then fx.Transform:SetPosition(target.Transform:GetWorldPosition()) end
                        end
                    end
                end)
            end
        elseif upgrade_def.id == "attack_speed" then
            -- 攻速通过伤害修正器实现（DST没有直接的攻速属性）
            if item.components.weapon and not item._rogue_upgrade_atkspd_hooked then
                item._rogue_upgrade_atkspd_hooked = true
                local old_onattack = item.components.weapon.onattack
                item.components.weapon:SetOnAttack(function(inst, attacker, target)
                    if old_onattack then old_onattack(inst, attacker, target) end
                    local bonus = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.attack_speed or 0
                    if bonus > 0 and attacker and attacker.components.combat then
                        local base_dmg = inst.components.weapon and inst.components.weapon.damage or 34
                        -- 攻速提升通过概率触发额外一次低伤害攻击来模拟
                        if math.random() < bonus then
                            if target and target.components.health and not target.components.health:IsDead() then
                                target.components.health:DoDelta(-base_dmg * 0.3, nil, "rogue_atkspd")
                            end
                        end
                    end
                end)
            end
        elseif upgrade_def.id == "insulation_bonus" then
            if item.components.equippable then
                if item.components.insulator then
                    local base_insul = item._rogue_original_insulation or item.components.insulator.insulation or 0
                    item._rogue_original_insulation = base_insul
                    local total_bonus = item.rogue_upgrade_stats.insulation_bonus or 0
                    item.components.insulator:SetInsulation(base_insul + total_bonus)
                else
                    item:AddComponent("insulator")
                    local total_bonus = item.rogue_upgrade_stats.insulation_bonus or 0
                    item.components.insulator:SetInsulation(total_bonus)
                    item.components.insulator:SetWinter()
                    item._rogue_added_insulator = true
                end
            end
        elseif upgrade_def.id == "dodge_chance" then
            if item.components.equippable and not item._rogue_upgrade_dodge_hooked then
                item._rogue_upgrade_dodge_hooked = true
                local old_onequip = item.components.equippable.onequipfn
                local old_onunequip = item.components.equippable.onunequipfn
                item.components.equippable:SetOnEquip(function(inst, owner)
                    if old_onequip then old_onequip(inst, owner) end
                    local chance = inst.rogue_upgrade_stats and inst.rogue_upgrade_stats.dodge_chance or 0
                    if chance > 0 and not inst._rogue_dodge_handler then
                        inst._rogue_dodge_handler = function(o, data)
                            if math.random() < chance and data and data.damage and data.damage > 0 then
                                if o.components.health and not o.components.health:IsDead() then
                                    o.components.health:SetInvincible(true)
                                    o:DoTaskInTime(0.1, function(p)
                                        if p and p.components.health then p.components.health:SetInvincible(false) end
                                    end)
                                    if deps.SpawnPrefab then
                                        local fx = deps.SpawnPrefab("small_puff")
                                        if fx then fx.Transform:SetPosition(o.Transform:GetWorldPosition()) end
                                    end
                                end
                            end
                        end
                        owner:ListenForEvent("attacked", inst._rogue_dodge_handler)
                    end
                end)
                item.components.equippable:SetOnUnequip(function(inst, owner)
                    if old_onunequip then old_onunequip(inst, owner) end
                    if inst._rogue_dodge_handler then
                        owner:RemoveEventCallback("attacked", inst._rogue_dodge_handler)
                        inst._rogue_dodge_handler = nil
                    end
                end)
            end
        end

        -- 重建物品描述文本（调用公共函数）
        RebuildItemDescription(item, category)
    end

    -- 函数说明：玩家请求购买普通商品（含限购和折扣逻辑）。
    S.BuyItem = function(player, item_id)
        if not player or not player:IsValid() then return end
        local d = deps.EnsurePlayerData(player)

        local item_def = nil
        for _, v in ipairs(ShopConfig.GetDailyShopItems()) do
            if v.id == item_id then
                item_def = v
                break
            end
        end

        if not item_def then
            deps.Announce(player.name .. " 尝试购买未知的商品。")
            return
        end

        local limit = ShopConfig.GetPurchaseLimit(item_def.prefab)
        local purchased = GetPurchasedCount(d, item_id)
        if purchased >= limit then
            if player.components.talker then
                player.components.talker:Say("今日已达到该商品限购数量（" .. limit .. "）。")
            end
            return
        end

        local final_cost = GetDiscountedCost(item_id, item_def.cost)

        local current_points = d.points or 0
        if current_points < final_cost then
            if player.components.talker then
                player.components.talker:Say("积分不足，需要 " .. final_cost .. " 积分。")
            end
            return
        end

        d.points = current_points - final_cost
        if player.rogue_points then
            player.rogue_points:set(d.points)
        end

        local count = item_def.count or 1
        if player.components.inventory then
            for i = 1, count do
                local item = deps.SpawnPrefab(item_def.prefab)
                if item then
                    player.components.inventory:GiveItem(item)
                end
            end
        end

        RecordPurchase(d, item_id, 1)

        if player.components.talker then
            local discount_msg = final_cost < item_def.cost and "（折扣价！）" or ""
            player.components.talker:Say("购买成功！" .. discount_msg .. " 剩余积分: " .. d.points)
        end
    end

    -- 函数说明：获取玩家手持的物品（active item），用于黑市重铸/强化。
    local function GetActiveItem(player)
        if not player or not player:IsValid() then return nil end
        if not player.components.inventory then return nil end
        return player.components.inventory:GetActiveItem()
    end

    -- 函数说明：玩家请求黑市重铸服务（随机更换武器/装备的能力）。
    -- 从玩家手持物品读取，替换最后一个能力并重新应用。
    S.BlackMarketReforge = function(player)
        if not player or not player:IsValid() then return end
        local d = deps.EnsurePlayerData(player)

        local service_def = nil
        for _, v in ipairs(ShopConfig.GetBlackMarketItems()) do
            if v.service == "reforge" then
                service_def = v
                break
            end
        end
        if not service_def then return end

        local target_item = GetActiveItem(player)
        if not target_item or not IsBlackMarketEligible(target_item) then
            if player.components.talker then
                player.components.talker:Say("请先从背包中拿起武器或装备！")
            end
            return
        end

        if not target_item.rogue_abilities or #target_item.rogue_abilities == 0 then
            if player.components.talker then
                player.components.talker:Say("该物品没有可重铸的能力！")
            end
            return
        end

        if not PayBlackMarketCost(player, service_def, d) then return end

        local day = (TheWorld and TheWorld.state and TheWorld.state.cycles) or 1

        local available = {}
        if deps.DropSystem and deps.DropSystem.GetAvailableAbilitiesForItem then
            available = deps.DropSystem.GetAvailableAbilitiesForItem(target_item, day)
        end

        local current = target_item.rogue_abilities
        local existing_ids = {}
        for _, id in ipairs(current) do
            existing_ids[id] = true
        end

        local candidates = {}
        for _, ab in ipairs(available) do
            if not existing_ids[ab.id] then
                table.insert(candidates, ab)
            end
        end

        if #candidates == 0 then
            if player.components.talker then
                player.components.talker:Say("没有可替换的新能力！")
            end
            return
        end

        local new_ability = candidates[math.random(#candidates)]

        if deps.DropSystem and deps.DropSystem.ReforgeItemAbility then
            deps.DropSystem.ReforgeItemAbility(target_item, new_ability.id)
        end

        local fx = deps.SpawnPrefab("statue_transition_2")
        if fx then
            local x, y, z = player.Transform:GetWorldPosition()
            fx.Transform:SetPosition(x, y, z)
        end

        if player.components.talker then
            player.components.talker:Say("重铸成功！获得新能力：" .. (new_ability.name or new_ability.id) .. "！剩余积分: " .. d.points)
        end
    end

    -- 函数说明：玩家请求黑市强化服务（随机升级武器/装备的属性）。
    -- 从锻造容器格子中读取物品，随机抽取一个属性并提升数值。
    S.BlackMarketUpgrade = function(player)
        if not player or not player:IsValid() then return end
        local d = deps.EnsurePlayerData(player)

        local service_def = nil
        for _, v in ipairs(ShopConfig.GetBlackMarketItems()) do
            if v.service == "upgrade" then
                service_def = v
                break
            end
        end
        if not service_def then return end

        local target_item = GetActiveItem(player)
        if not target_item or not IsBlackMarketEligible(target_item) then
            if player.components.talker then
                player.components.talker:Say("请先从背包中拿起武器或装备！")
            end
            return
        end

        local total_upgrades = 0
        for _, val in pairs(target_item.rogue_upgrade_stats or {}) do
            total_upgrades = total_upgrades + 1
        end
        if total_upgrades >= 4 then
            if player.components.talker then
                player.components.talker:Say("该物品已达最大强化次数！")
            end
            return
        end

        if not PayBlackMarketCost(player, service_def, d) then return end

        local category = GetItemEquipCategory(target_item)
        local upgrade_def = PickRandomUpgrade(category)

        if not upgrade_def then
            if player.components.talker then
                player.components.talker:Say("无法强化该类型的物品！")
            end
            return
        end

        local min_v = upgrade_def.min_val or 0
        local max_v = upgrade_def.max_val or min_v
        local value = min_v + math.random() * (max_v - min_v)
        value = math.floor(value * 100) / 100

        ApplyUpgradeToItem(target_item, upgrade_def, value)

        local fx = deps.SpawnPrefab("explode_reskin")
        if fx then
            local x, y, z = player.Transform:GetWorldPosition()
            fx.Transform:SetPosition(x, y, z)
            fx.Transform:SetScale(0.5, 0.5, 0.5)
        end

        if player.components.talker then
            player.components.talker:Say("强化成功！获得 " .. upgrade_def.name .. " +" .. string.format("%.1f", value) .. "！剩余积分: " .. d.points)
        end
    end

    -- 函数说明：保留旧接口兼容性，重定向到重铸服务。
    S.BuyBlackMarketItem = function(player, item_id)
        if item_id == "bm_reforge" then
            S.BlackMarketReforge(player)
        elseif item_id == "bm_upgrade" then
            S.BlackMarketUpgrade(player)
        end
    end

    -- 函数说明：玩家请求回收物品（兼容老的单个回收）。
    S.RecycleItem = function(player, prefab)
        if not player or not player:IsValid() or not player.components.inventory then return end

        local value = ShopConfig.GetRecycleValue(prefab)
        if value <= 0 then
            if player.components.talker then
                player.components.talker:Say("这个物品无法回收获取积分。")
            end
            return
        end

        if not player.components.inventory:Has(prefab, 1) then
            if player.components.talker then
                player.components.talker:Say("背包中没有找到该物品。")
            end
            return
        end

        player.components.inventory:ConsumeByName(prefab, 1)

        local d = deps.EnsurePlayerData(player)
        d.points = (d.points or 0) + value
        if player.rogue_points then
            player.rogue_points:set(d.points)
        end

        if player.components.talker then
            player.components.talker:Say("回收成功！获得 " .. value .. " 积分。当前积分: " .. d.points)
        end
    end

    -- 函数说明：打开回收容器。
    S.OpenRecycleBin = function(player)
        if not player or not player:IsValid() then return end

        if not player.rogue_recycle_bin then
            player.rogue_recycle_bin = deps.SpawnPrefab("rogue_recycle_bin")
            if player.rogue_recycle_bin then
                player.rogue_recycle_bin.entity:SetParent(player.entity)
            end
        end

        local bin = player.rogue_recycle_bin
        if bin and bin.components.container then
            bin.components.container:Open(player)
        end
    end

    -- 函数说明：关闭回收容器。
    S.CloseRecycleBin = function(player)
        if not player or not player:IsValid() then return end
        local bin = player.rogue_recycle_bin
        if bin and bin.components.container then
            bin.components.container:Close()
        end
    end

    -- 函数说明：一键回收容器内的物品。
    S.RecycleAllItems = function(player)
        if not player or not player:IsValid() then return end
        local bin = player.rogue_recycle_bin
        if not bin or not bin.components.container then return end

        local total_value = 0
        local container = bin.components.container

        local to_remove = {}
        for k, v in pairs(container.slots) do
            if v and v.prefab then
                local value = ShopConfig.GetRecycleValue(v.prefab)
                if value > 0 then
                    local count = (v.components and v.components.stackable) and v.components.stackable:StackSize() or 1
                    total_value = total_value + (value * count)
                    table.insert(to_remove, k)
                end
            end
        end

        table.sort(to_remove, function(a, b) return a > b end)
        for _, slot_idx in ipairs(to_remove) do
            local item = container:RemoveItemBySlot(slot_idx)
            if item then
                item:Remove()
            end
        end

        if total_value > 0 then
            local d = deps.EnsurePlayerData(player)
            d.points = (d.points or 0) + total_value
            if player.rogue_points then
                player.rogue_points:set(d.points)
            end
            if player.components.talker then
                player.components.talker:Say("一键回收成功！获得 " .. total_value .. " 积分。")
            end
        else
            if player.components.talker then
                player.components.talker:Say("容器中没有可回收的物品。")
            end
        end
    end

    -- 函数说明：注册所有物品的升级属性持久化钩子。
    -- 同时使用两个途径确保数据一定被恢复：
    --   路径1（主）：inventoryitem 组件的 OnSave/OnLoad — DST 核心一定调用，最可靠
    --   路径2（备）：实体的 OnSave/OnLoad — 额外保护
    -- 双路径写入，任意路径读取成功即可恢复。
    S.InitPersistence = function()
        print("[rogue_shop] InitPersistence: registering inventoryitem PostInit hook for upgrade persistence")

        -- AddComponentPostInit 回调签名: fn(component, inst) — 组件在前，实体在后！
        deps.AddComponentPostInit("inventoryitem", function(comp, inst)
            if not comp or not inst then return end

            -- 主模拟端检查延迟到实际存储操作时（OnSave/OnLoad 由 DST 引擎保证只在正确端调用）
            -- 此处不检查 IsMasterSim，避免存档加载时 TheWorld 未就绪导致回调提前退出而错过挂载

            -- === 路径1：组件级持久化（主路径，DST 引擎必然调用） ===
            if not comp._rogue_upgrade_persist_hooked then
                comp._rogue_upgrade_persist_hooked = true

                local _compOnSave = comp.OnSave
                comp.OnSave = function(self)
                    local data = _compOnSave and _compOnSave(self) or {}
                    if type(data) ~= "table" then data = {} end
                    local target = self.inst
                    if target and target.rogue_upgrade_stats then
                        data.rogue_shop_upgrade_stats = {}
                        for k, v in pairs(target.rogue_upgrade_stats) do
                            data.rogue_shop_upgrade_stats[k] = v
                        end
                        data.rogue_shop_original_damage = target._rogue_original_damage
                        data.rogue_shop_original_absorb = target._rogue_original_absorb
                        data.rogue_shop_original_insulation = target._rogue_original_insulation
                        data.rogue_shop_upgrade_text = target.rogue_upgrade_text
                        print("[rogue_shop] COMP OnSave persisted upgrades for " .. tostring(target.prefab or target) .. " -> " .. tostring(target.rogue_upgrade_text or ""))
                    end
                    return data
                end

                local _compOnLoad = comp.OnLoad
                comp.OnLoad = function(self, data)
                    local target = self.inst
                    if not target then
                        if _compOnLoad then _compOnLoad(self, data) end
                        return
                    end
                    if _compOnLoad then _compOnLoad(self, data) end
                    if data and data.rogue_shop_upgrade_stats then
                        print("[rogue_shop] COMP OnLoad found upgrade data for " .. tostring(target.prefab) .. " -> " .. tostring(data.rogue_shop_upgrade_text))
                        target.rogue_upgrade_stats = {}
                        for k, v in pairs(data.rogue_shop_upgrade_stats) do
                            target.rogue_upgrade_stats[k] = v
                        end
                        target._rogue_original_damage = data.rogue_shop_original_damage
                        target._rogue_original_absorb = data.rogue_shop_original_absorb
                        target._rogue_original_insulation = data.rogue_shop_original_insulation
                        target.rogue_upgrade_text = data.rogue_shop_upgrade_text
                        target:DoTaskInTime(0, function()
                            if target:IsValid() and target.rogue_upgrade_stats then
                                print("[rogue_shop] COMP RestoreUpgradesFromSave scheduled for " .. tostring(target.prefab))
                                RestoreUpgradesFromSave(target)
                            end
                        end)
                    end
                end
            end

            -- === 路径2：实体级持久化（备用双保险，只要 Inst 存在就挂载） ===
            if not inst._rogue_upgrade_persist_hooked then
                HookItemUpgradePersistence(inst)
            end
        end)
    end

    return S
end

return M
