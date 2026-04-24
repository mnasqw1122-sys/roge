--[[
    文件说明：drop_system.lua
    功能：掉落与装备能力系统的主调度入口。
    负责控制怪物击杀后的战利品掉落（基础物资、Boss装备、稀有材料）、
    能力应用与持久化、Buff系统以及附魔升级。
    v2.2.0: 将能力定义表拆分至 ability_defs.lua，
    品质与保底系统拆分至 rarity_system.lua，
    Boss掉落系统拆分至 boss_drop_system.lua。
]]
local RogueAbilityDefs = require("rogue/ability_defs")
local RogueRaritySystem = require("rogue/rarity_system")
local RogueBossDropSystem = require("rogue/boss_drop_system")

local M = {}

function M.Create(deps)
    local state = {}

    -- 构建能力定义表（注入deps以支持回调中的外部依赖）
    local ABILITY_DEFS = RogueAbilityDefs.Build(deps)

    -- 函数说明：构建能力ID到定义的哈希索引表，将查找从O(n)优化为O(1)
    local ABILITY_MAP = {}
    for _, def in ipairs(ABILITY_DEFS) do
        ABILITY_MAP[def.id] = def
    end

    -- 创建品质与保底子系统
    local RaritySystem = RogueRaritySystem.Create({
        SEASON_AFFIX_ROTATION_DEFS = deps.SEASON_AFFIX_ROTATION_DEFS,
        DROP_PITY_RULES = deps.DROP_PITY_RULES,
        IsValidPlayer = deps.IsValidPlayer,
        EnsurePlayerData = deps.EnsurePlayerData,
        SyncGrowthNetvars = deps.SyncGrowthNetvars,
    })

    -- 创建Boss掉落子系统
    local BossDropSystem = RogueBossDropSystem.Create({
        BOSS_LOOT_SIGNATURE_DEFS = deps.BOSS_LOOT_SIGNATURE_DEFS,
        BossLoot = deps.BossLoot,
        PickWeightedCandidate = deps.PickWeightedCandidate,
        EnsurePlayerData = deps.EnsurePlayerData,
    })

    -- 函数说明：判断物品是否可以附加能力（武器或可装备物品）
    local function IsAbilityEligibleItem(item)
        return item ~= nil and item.components ~= nil and (item.components.weapon ~= nil or item.components.equippable ~= nil)
    end

    -- 函数说明：深拷贝列表
    local function CloneList(src)
        if not src then return nil end
        local out = {}
        for _, v in ipairs(src) do
            table.insert(out, v)
        end
        return out
    end

    -- 函数说明：深拷贝映射表
    local function CloneMap(src)
        if not src then return nil end
        local out = {}
        for k, v in pairs(src) do
            out[k] = v
        end
        return out
    end

    -- 函数说明：为物品应用附魔能力，挂载事件回调，更新UI描述和品质发光
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
            local def = ABILITY_MAP[id]
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

        if has_onattack and item.components.weapon and not item._rogue_onattack_hooked then
            item._rogue_onattack_hooked = true
            local old_onattack = item.components.weapon.onattack
            item.components.weapon:SetOnAttack(function(inst, attacker, target)
                if old_onattack then
                    old_onattack(inst, attacker, target)
                end
                for _, id in ipairs(inst.rogue_abilities or {}) do
                    local def = ABILITY_MAP[id]
                    if def and def.onattack then
                        def.onattack(inst, attacker, target)
                    end
                end
            end)
        end

        if has_onattacked and item.components.equippable and not item._rogue_onattacked_hooked then
            item._rogue_onattacked_hooked = true
            item._rogue_onattacked = function(owner, data)
                local attacker = data and data.attacker
                local damage = data and data.damage or 0
                for _, id in ipairs(item.rogue_abilities or {}) do
                    local def = ABILITY_MAP[id]
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
                    local def = ABILITY_MAP[id]
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
                    local def = ABILITY_MAP[id]
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

    -- 函数说明：挂载物品的持久化钩子，保存与加载其能力属性
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

    -- 函数说明：注册所有附魔白名单物品的持久化钩子
    state.RegisterItemPersistenceHook = function()
        for prefab_name, _ in pairs(deps.ROGUE_AFFIX_PREFAB_WHITELIST) do
            deps.AddPrefabPostInit(prefab_name, function(inst)
                if not deps.IsMasterSim() then return end
                if not inst.components or not inst.components.inventoryitem then return end
                HookRogueItemPersistence(inst)
            end)
        end
    end

    -- 函数说明：在实体死亡位置附近生成掉落物，并可选择应用附魔
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

    -- 函数说明：计算递减收益（供Buff系统使用）
    local function CalculateDiminishingReturn(current_val, add_val)
        if current_val > 3.0 then return add_val * 0.1 end
        if current_val > 1.5 then return add_val * 0.5 end
        return add_val
    end

    -- 函数说明：为玩家应用击杀Buff（生命上限或伤害加成）
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
            data.damage_bonus = (data.damage_bonus or 0) + val
            if player.components.combat then
                player.components.combat.externaldamagemultipliers:SetModifier(deps.CONST.DAMAGE_MODIFIER_KEY, 1 + data.damage_bonus)
            end
            if player.rogue_dmg_bonus then player.rogue_dmg_bonus:set(data.damage_bonus) end
            deps.Announce(player:GetDisplayName() .. " 获得了 " .. string.format("%.1f", val * 100) .. "% 伤害加成！")
        end
    end

    -- 函数说明：主掉落逻辑，根据击杀目标类型分发掉落
    state.DropLoot = function(victim, is_boss, day, killer)
        if not victim or not victim:IsValid() then return end
        if victim._rogue_drop_done then return end
        victim._rogue_drop_done = true

        local has_greed = killer and killer:HasTag("rogue_greed_pact")

        local objective_boost = BossDropSystem.GetObjectiveBoost(killer)
        if is_boss then
            local is_trial_boss = victim:HasTag("rogue_trial_boss")
            local tier = RaritySystem.GetProgressTier(day)
            local bal = deps.VNEXT_DROP_BALANCE or {}
            local gear_pool, gear_w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_GEAR", day)
            local mat_pool, mat_w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_MATS", day)
            local main_meta = nil
            local boss_signature = BossDropSystem.GetBossSignature(victim)
            if is_trial_boss then
                if gear_pool then
                    local item = BossDropSystem.PickBossGearBySignature(gear_pool, victim, objective_boost) or deps.PickWeightedCandidate(gear_pool, gear_w)
                    if item then
                        local _, meta = BossDropSystem.SpawnBossGearDrop(victim, item.prefab, day, { is_trial = true, pity_key = "trial_gear", boss_signature = boss_signature, killer = killer, objective_bonus = objective_boost.rarity_bonus }, state.SpawnDrop, ApplyRogueAbilities, function(i, d, c) return RaritySystem.RollAbilitiesForItem(i, d, c, ABILITY_DEFS) end)
                        main_meta = meta or main_meta
                    end
                    local trial_extra_base = bal.trial_extra_base or 0.25
                    local trial_extra_step = bal.trial_extra_tier_step or 0.12
                    local trial_extra_cap = bal.trial_extra_cap or 0.72
                    local extra_chance = math.min(trial_extra_cap, trial_extra_base + trial_extra_step * tier)
                    if has_greed then extra_chance = extra_chance + 0.3 end
                    if math.random() < extra_chance then
                        local extra = BossDropSystem.PickBossGearBySignature(gear_pool, victim, objective_boost) or deps.PickWeightedCandidate(gear_pool, gear_w)
                        if extra then
                            BossDropSystem.SpawnBossGearDrop(victim, extra.prefab, day, { is_trial = true, pity_key = "trial_gear", boss_signature = boss_signature, killer = killer, objective_bonus = objective_boost.rarity_bonus }, state.SpawnDrop, ApplyRogueAbilities, function(i, d, c) return RaritySystem.RollAbilitiesForItem(i, d, c, ABILITY_DEFS) end)
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
            local special_prefab, used_special, special_key = BossDropSystem.PickBossSpecificGear(victim, day)
            if special_prefab then
                local _, meta = BossDropSystem.SpawnBossGearDrop(victim, special_prefab, day, { is_special = true, pity_key = "boss_gear", boss_signature = boss_signature, killer = killer, objective_bonus = objective_boost.rarity_bonus }, state.SpawnDrop, ApplyRogueAbilities, function(i, d, c) return RaritySystem.RollAbilitiesForItem(i, d, c, ABILITY_DEFS) end)
                main_meta = meta or main_meta
            elseif gear_pool then
                local item = BossDropSystem.PickBossGearBySignature(gear_pool, victim, objective_boost) or deps.PickWeightedCandidate(gear_pool, gear_w)
                if item then
                    local _, meta = BossDropSystem.SpawnBossGearDrop(victim, item.prefab, day, { pity_key = "boss_gear", boss_signature = boss_signature, killer = killer, objective_bonus = objective_boost.rarity_bonus }, state.SpawnDrop, ApplyRogueAbilities, function(i, d, c) return RaritySystem.RollAbilitiesForItem(i, d, c, ABILITY_DEFS) end)
                    main_meta = meta or main_meta
                end
            end
            if gear_pool then
                local boss_extra_base = bal.boss_extra_base or 0.12
                local boss_extra_step = bal.boss_extra_tier_step or 0.1
                local boss_extra_cap = bal.boss_extra_cap or 0.6
                local extra_chance = math.min(boss_extra_cap, boss_extra_base + boss_extra_step * tier)
                if has_greed then extra_chance = extra_chance + 0.3 end
                if math.random() < extra_chance then
                    local extra = BossDropSystem.PickBossGearBySignature(gear_pool, victim, objective_boost) or deps.PickWeightedCandidate(gear_pool, gear_w)
                    if extra then
                        BossDropSystem.SpawnBossGearDrop(victim, extra.prefab, day, { pity_key = "boss_gear", boss_signature = boss_signature, killer = killer, objective_bonus = objective_boost.rarity_bonus }, state.SpawnDrop, ApplyRogueAbilities, function(i, d, c) return RaritySystem.RollAbilitiesForItem(i, d, c, ABILITY_DEFS) end)
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
            if has_greed then elite_gear_chance = elite_gear_chance + 0.15 end
            for _ = 1, math.random(1, 2) do
                local roll = math.random()
                if roll < elite_gear_chance and gear_pool then
                    local item = deps.PickWeightedCandidate(gear_pool, gear_w)
                    if item then
                        BossDropSystem.SpawnBossGearDrop(victim, item.prefab, day, { elite_bonus = true, pity_key = "boss_gear", killer = killer, objective_bonus = objective_boost.rarity_bonus * 0.6 }, state.SpawnDrop, ApplyRogueAbilities, function(i, d, c) return RaritySystem.RollAbilitiesForItem(i, d, c, ABILITY_DEFS) end)
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
        local chance = deps.Config.NORMAL_DROP_CHANCE + math.floor((day - 1) / 15) * 0.02 + drop_bonus + wave_drop_bonus + route_drop_bonus + threat_drop_bonus
        if has_greed then chance = chance + 0.15 end
        if math.random() < math.min(deps.CONST.MAX_NORMAL_DROP_CHANCE, chance) then
            local pool, w = deps.PoolCatalog.GetRuntimePool("DROPS_NORMAL", day)
            local item = deps.PickWeightedCandidate(pool, w)
            if item then state.SpawnDrop(victim, item.prefab) end
        end
    end

    -- 函数说明：为玩家当前装备的物品添加一个新的附魔能力（附魔升级）
    state.UpgradeItemAbility = function(player, slot, ability_id)
        if not player or not player:IsValid() then return false end
        if not player.components.inventory then return false end

        local slot_map = { hand = EQUIPSLOTS.HANDS, body = EQUIPSLOTS.BODY, head = EQUIPSLOTS.HEAD }
        local equip_slot = slot_map[slot]
        if not equip_slot then return false end

        local item = player.components.inventory:GetEquippedItem(equip_slot)
        if not item or not item:IsValid() then return false end
        if not IsAbilityEligibleItem(item) then return false end

        local current_abilities = item.rogue_abilities or {}
        if #current_abilities >= 3 then return false end

        for _, existing_id in ipairs(current_abilities) do
            if existing_id == ability_id then return false end
        end

        local def = ABILITY_MAP[ability_id]
        if not def then return false end

        if not RaritySystem.IsAbilitySlotMatch(item, def.slot) then return false end

        table.insert(current_abilities, ability_id)
        ApplyRogueAbilities(item, current_abilities, item.rogue_affix_meta, true)
        return true
    end

    -- 函数说明：获取指定槽位物品可用的附魔列表（用于商店附魔升级界面）
    state.GetAvailableAbilitiesForSlot = function(player, slot, day)
        if not player or not player:IsValid() then return {} end
        if not player.components.inventory then return {} end

        local slot_map = { hand = EQUIPSLOTS.HANDS, body = EQUIPSLOTS.BODY, head = EQUIPSLOTS.HEAD }
        local equip_slot = slot_map[slot]
        if not equip_slot then return {} end

        local item = player.components.inventory:GetEquippedItem(equip_slot)
        if not item or not item:IsValid() then return {} end

        local current_abilities = item.rogue_abilities or {}
        local existing = {}
        for _, id in ipairs(current_abilities) do
            existing[id] = true
        end

        local available = {}
        for _, def in ipairs(ABILITY_DEFS) do
            if day >= (def.min_day or 0)
               and RaritySystem.IsAbilitySlotMatch(item, def.slot)
               and not existing[def.id] then
                table.insert(available, {
                    id = def.id,
                    name = def.name,
                    desc = def.desc,
                    slot = def.slot,
                    min_day = def.min_day,
                    cost = math.max(5, (def.min_day or 1) * 2),
                })
            end
        end
        return available
    end

    -- 函数说明：为指定物品替换最后一个能力（重铸），直接修改能力列表并重新应用。
    state.ReforgeItemAbility = function(item, new_ability_id)
        if not item or not item:IsValid() then return false end
        if not IsAbilityEligibleItem(item) then return false end

        local current_abilities = item.rogue_abilities or {}
        if #current_abilities == 0 then return false end

        local def = ABILITY_MAP[new_ability_id]
        if not def then return false end

        if not RaritySystem.IsAbilitySlotMatch(item, def.slot) then return false end

        current_abilities[#current_abilities] = new_ability_id
        ApplyRogueAbilities(item, current_abilities, item.rogue_affix_meta or {}, true)
        return true
    end

    -- 函数说明：获取指定物品可用的附魔列表（用于黑市重铸界面，支持任意物品）
    state.GetAvailableAbilitiesForItem = function(item, day)
        if not item or not item:IsValid() then return {} end
        if not IsAbilityEligibleItem(item) then return {} end

        local current_abilities = item.rogue_abilities or {}
        local existing = {}
        for _, id in ipairs(current_abilities) do
            existing[id] = true
        end

        local available = {}
        for _, def in ipairs(ABILITY_DEFS) do
            if day >= (def.min_day or 0)
               and RaritySystem.IsAbilitySlotMatch(item, def.slot)
               and not existing[def.id] then
                table.insert(available, {
                    id = def.id,
                    name = def.name,
                    desc = def.desc,
                    slot = def.slot,
                    min_day = def.min_day,
                    cost = math.max(5, (def.min_day or 1) * 2),
                })
            end
        end
        return available
    end

    -- 函数说明：导出全部状态（保底计数器）
    state.ExportState = function()
        local rarity_state = RaritySystem.ExportState()
        local boss_state = BossDropSystem.ExportState()
        return {
            boss_loot_pity = boss_state.boss_loot_pity,
            gear_quality_pity = rarity_state.gear_quality_pity,
        }
    end

    -- 函数说明：导入全部状态
    state.ImportState = function(saved)
        if type(saved) ~= "table" then
            return
        end
        BossDropSystem.ImportState(saved)
        RaritySystem.ImportState(saved)
    end

    return state
end

return M
