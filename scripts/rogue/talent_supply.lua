--[[
    文件说明：talent_supply.lua
    功能：天赋与补给抉择系统。
    负责处理击杀数达标后的天赋升级选择，以及夜晚降临时的补给物资选择（带代价的增益），并通过RPC响应客户端的选择。
    V2扩展：支持天赋树分支、前置依赖、36种天赋效果。
]]
local M = {}

function M.Create(deps)
    local S = {}

    -- 函数说明：根据ID查找天赋定义
    local function GetTalentDef(id)
        for _, def in ipairs(deps.TALENT_DEFS) do
            if def.id == id then return def end
        end
        return nil
    end

    -- 函数说明：随机生成3个不同的天赋选项供玩家选择（考虑前置依赖）
    local function BuildTalentChoices(data)
        local levels = data.talent_levels or {}
        local available = {}
        for _, def in ipairs(deps.TALENT_DEFS) do
            local cur_level = levels[def.id] or 0
            if cur_level < (def.max_level or 5) then
                local prereq_met = true
                if def.prereq then
                    local prereq_level = levels[def.prereq] or 0
                    local required = def.prereq_level or 1
                    if prereq_level < required then
                        prereq_met = false
                    end
                end
                if prereq_met then
                    table.insert(available, def.id)
                end
            end
        end
        for i = #available, 2, -1 do
            local j = math.random(i)
            available[i], available[j] = available[j], available[i]
        end
        if #available <= 3 then
            return available
        end
        return { available[1], available[2], available[3] }
    end

    local function GetTalentName(id)
        local def = GetTalentDef(id)
        return def and def.name or "未知天赋"
    end

    local function GetTalentDesc(id)
        local def = GetTalentDef(id)
        return def and (def.desc or "无说明") or "无说明"
    end

    local function GetSupplyById(id)
        for _, def in ipairs(deps.SUPPLY_DEFS) do
            if def.id == id then
                return def
            end
        end
        return nil
    end

    local function BuildSupplyChoices()
        local ids = {}
        for _, def in ipairs(deps.SUPPLY_DEFS or {}) do
            table.insert(ids, def.id)
        end
        for i = #ids, 2, -1 do
            local j = math.random(i)
            ids[i], ids[j] = ids[j], ids[i]
        end
        if #ids <= 3 then
            return ids
        end
        return { ids[1], ids[2], ids[3] }
    end

    local function GetSupplyRepeatCountAfterPick(data, supply_id)
        if data.last_supply_id == supply_id then
            return (data.supply_repeat_streak or 1) + 1
        end
        return 1
    end

    local function GetSupplyTradeoffFactor(data, supply_id)
        local next_count = GetSupplyRepeatCountAfterPick(data, supply_id)
        return 1 + math.min(0.3, 0.08 * (next_count - 1))
    end

    -- 函数说明：获取天赋当前等级
    local function GetTalentLevel(data, talent_id)
        local levels = data.talent_levels or {}
        return levels[talent_id] or 0
    end

    -- 函数说明：设置天赋等级
    local function SetTalentLevel(data, talent_id, level)
        if not data.talent_levels then data.talent_levels = {} end
        data.talent_levels[talent_id] = level
    end

    -- 函数说明：注册玩家攻击监听器（暴击/致命节奏/暗影分身等）
    local function EnsureAttackListener(player)
        if player._rogue_talent_attack_listener then return end
        player._rogue_talent_attack_listener = true
        player:ListenForEvent("onhitother", function(inst, hit_data)
            if not inst:IsValid() or not hit_data or not hit_data.target then return end
            if not hit_data.target:IsValid() then return end
            local d = inst.rogue_data
            if not d then return end
            local levels = d.talent_levels or {}

            -- 天赋8（生命虹吸）
            if (levels[8] or 0) > 0 then
                local chance = d.lifesteal_chance or 0
                local amount = d.lifesteal_amount or 0
                if chance > 0 and amount > 0 and math.random() < chance then
                    if inst.components.health and not inst.components.health:IsDead() then
                        inst.components.health:DoDelta(amount)
                        if inst.components.colouradder then
                            inst.components.colouradder:PushColour("rogue_lifesteal", 0, 0.8, 0, 0)
                            inst:DoTaskInTime(0.3, function(i)
                                if i and i:IsValid() and i.components and i.components.colouradder then
                                    i.components.colouradder:PopColour("rogue_lifesteal")
                                end
                            end)
                        end
                    end
                end
            end

            -- 天赋11（暴击本能）
            if (levels[11] or 0) > 0 then
                local crit_chance = d.talent_crit_chance or 0
                local crit_dmg_mult = d.talent_crit_dmg_mult or 1
                if crit_chance > 0 and math.random() < crit_chance then
                    local target = hit_data.target
                    if target.components.health and not target.components.health:IsDead() then
                        local base_dmg = 30
                        local crit_dmg = math.floor(base_dmg * crit_dmg_mult)
                        target.components.health:DoDelta(-crit_dmg, nil, "rogue_talent_crit", nil, inst)
                        if target.components.colouradder then
                            target.components.colouradder:PushColour("rogue_talent_crit", 1, 0.9, 0, 0)
                            target:DoTaskInTime(0.3, function(t)
                                if t and t:IsValid() and t.components and t.components.colouradder then
                                    t.components.colouradder:PopColour("rogue_talent_crit")
                                end
                            end)
                        end
                    end
                end
            end

            -- 天赋15（致命节奏）
            if (levels[15] or 0) > 0 then
                local target = hit_data.target
                if target:IsValid() then
                    d._rhythm_target = target
                    d._rhythm_stacks = (d._rhythm_target == target) and ((d._rhythm_stacks or 0) + 1) or 1
                    if d._rhythm_stacks > 5 then d._rhythm_stacks = 5 end
                end
            end

            -- 天赋22（寒冰护甲 反击冻结）
            if (levels[22] or 0) > 0 then
                -- 由attacked事件处理
            end

            -- 天赋35（暗影分身）
            if (levels[35] or 0) > 0 then
                local shadow_chance = d.talent_shadow_chance or 0
                if shadow_chance > 0 and math.random() < shadow_chance then
                    local x, y, z = inst.Transform:GetWorldPosition()
                    local shadow = deps.SpawnPrefab("shadowwaxwell")
                    if shadow then
                        local offset_x = (math.random() - 0.5) * 4
                        local offset_z = (math.random() - 0.5) * 4
                        shadow.Transform:SetPosition(x + offset_x, y, z + offset_z)
                        if shadow.components.health then
                            shadow.components.health:SetMaxHealth(50)
                        end
                        shadow:DoTaskInTime(5, function(s)
                            if s and s:IsValid() then s:Remove() end
                        end)
                    end
                end
            end
        end)
    end

    -- 函数说明：注册玩家受击监听器（暗影闪避/寒冰护甲等）
    local function EnsureAttackedListener(player)
        if player._rogue_talent_attacked_listener then return end
        player._rogue_talent_attacked_listener = true
        player:ListenForEvent("attacked", function(inst, data)
            if not inst:IsValid() then return end
            local d = inst.rogue_data
            if not d then return end
            local levels = d.talent_levels or {}

            -- 天赋31（暗影闪避）
            if (levels[31] or 0) > 0 then
                local dodge_chance = d.talent_shadow_dodge_chance or 0
                if dodge_chance > 0 and math.random() < dodge_chance then
                    local x, y, z = inst.Transform:GetWorldPosition()
                    local angle = math.random() * 2 * math.pi
                    local dist = 5
                    local nx = x + math.cos(angle) * dist
                    local nz = z + math.sin(angle) * dist
                    inst.Transform:SetPosition(nx, y, nz)
                    if inst.components.colouradder then
                        inst.components.colouradder:PushColour("rogue_shadow_dodge", 0.3, 0.1, 0.5, 0)
                        inst:DoTaskInTime(0.5, function(i)
                            if i and i:IsValid() and i.components and i.components.colouradder then
                                i.components.colouradder:PopColour("rogue_shadow_dodge")
                            end
                        end)
                    end
                    return
                end
            end

            -- 天赋22（寒冰护甲）
            if (levels[22] or 0) > 0 then
                local freeze_chance = d.talent_freeze_chance or 0
                if freeze_chance > 0 and data and data.attacker and data.attacker:IsValid() then
                    if math.random() < freeze_chance then
                        if data.attacker.components.freezable then
                            data.attacker.components.freezable:AddColdness(0.5)
                            data.attacker.components.freezable:SpawnShatterFX()
                        end
                    end
                end
            end
        end)
    end

    -- 函数说明：应用玩家选择的天赋效果（支持升级递减和36种天赋）
    local function ApplyTalentChoice(player, talent_id)
        local data = deps.EnsurePlayerData(player)
        local level = GetTalentLevel(data, talent_id) + 1
        SetTalentLevel(data, talent_id, level)
        local diminish = math.max(0.4, 1 - (level - 1) * 0.2)

        if talent_id == 1 then
            local val = math.floor(25 * diminish)
            data.hp_bonus = (data.hp_bonus or 0) + val
            if player.components.health then
                player.components.health:SetMaxHealth(player.components.health.maxhealth + val)
                player.components.health:DoDelta(val)
            end
            player.rogue_applied_hp_bonus = data.hp_bonus
        elseif talent_id == 2 then
            data.damage_bonus = (data.damage_bonus or 0) + 0.08 * diminish
        elseif talent_id == 3 then
            data.combo_window_bonus = (data.combo_window_bonus or 0) + 1.5 * diminish
        elseif talent_id == 4 then
            data.drop_bonus = (data.drop_bonus or 0) + 0.04 * diminish
        elseif talent_id == 5 then
            data.daily_reward_bonus = (data.daily_reward_bonus or 0) + 0.5 * diminish
        elseif talent_id == 6 then
            data.elemental_bonus = (data.elemental_bonus or 0) + 0.15 * diminish
            data.elemental_resist = (data.elemental_resist or 0) + 0.20 * diminish
        elseif talent_id == 7 then
            data.speed_bonus = (data.speed_bonus or 0) + 0.10 * diminish
            if player.components.locomotor then
                player.components.locomotor:SetExternalSpeedMultiplier(player, "rogue_talent_7", 1 + (data.speed_bonus or 0))
            end
        elseif talent_id == 8 then
            data.lifesteal_chance = (data.lifesteal_chance or 0) + 0.10 * diminish
            data.lifesteal_amount = (data.lifesteal_amount or 0) + 5 * diminish
            EnsureAttackListener(player)
        elseif talent_id == 9 then
            data.luck_bonus = (data.luck_bonus or 0) + 0.05 * diminish
        elseif talent_id == 10 then
            data.cooldown_reduction = (data.cooldown_reduction or 0) + 0.15 * diminish
        elseif talent_id == 11 then
            data.talent_crit_chance = (data.talent_crit_chance or 0) + 0.05 * diminish
            data.talent_crit_dmg_mult = (data.talent_crit_dmg_mult or 1) + 0.15 * diminish
            EnsureAttackListener(player)
        elseif talent_id == 12 then
            data.talent_armor_pen = (data.talent_armor_pen or 0) + 0.08 * diminish
        elseif talent_id == 13 then
            data.talent_combo_burst = (data.talent_combo_burst or 0) + 1
        elseif talent_id == 14 then
            data.talent_elemental_aoe = (data.talent_elemental_aoe or 0) + 0.15 * diminish
        elseif talent_id == 15 then
            data.talent_rhythm_bonus = (data.talent_rhythm_bonus or 0) + 0.03 * diminish
            EnsureAttackListener(player)
        elseif talent_id == 16 then
            data.talent_low_hp_damage = (data.talent_low_hp_damage or 0) + 0.20 * diminish
        elseif talent_id == 17 then
            data.talent_boss_damage = (data.talent_boss_damage or 0) + 0.12 * diminish
        elseif talent_id == 18 then
            data.talent_damage_reduction = (data.talent_damage_reduction or 0) + 0.06 * diminish
        elseif talent_id == 19 then
            data.talent_regen = (data.talent_regen or 0) + 1 * diminish
            if not player._rogue_talent_regen_task then
                player._rogue_talent_regen_task = player:DoPeriodicTask(3, function(inst)
                    if inst:IsValid() and inst.components.health and not inst.components.health:IsDead() then
                        local d = inst.rogue_data
                        if d and (d.talent_regen or 0) > 0 then
                            inst.components.health:DoDelta(d.talent_regen)
                        end
                    end
                end)
            end
        elseif talent_id == 20 then
            data.talent_stand_shield = (data.talent_stand_shield or 0) + 0.15 * diminish
        elseif talent_id == 21 then
            data.talent_death_defy = true
            data.talent_death_defy_cd = 120
            if not player._rogue_talent_death_defy_listener then
                player._rogue_talent_death_defy_listener = true
                player:ListenForEvent("healthdelta", function(inst)
                    if not inst:IsValid() or not inst.components.health then return end
                    if inst.components.health:IsDead() then
                        local d = inst.rogue_data
                        if d and d.talent_death_defy then
                            local now = deps.GetTime()
                            local last_trigger = d._talent_death_defy_last or 0
                            if now - last_trigger >= (d.talent_death_defy_cd or 120) then
                                d._talent_death_defy_last = now
                                inst.components.health:SetVal(1, "rogue_talent_death_defy")
                                inst.components.health:SetPercent(0.1)
                                if inst.components.colouradder then
                                    inst.components.colouradder:PushColour("rogue_talent_death_defy", 1, 1, 0.5, 0)
                                    inst:DoTaskInTime(1.5, function(i)
                                        if i and i:IsValid() and i.components and i.components.colouradder then
                                            i.components.colouradder:PopColour("rogue_talent_death_defy")
                                        end
                                    end)
                                end
                                if inst.SoundEmitter then
                                    inst.SoundEmitter:PlaySound("dontstarve/common/rebirth_flare")
                                end
                                deps.Announce(inst:GetDisplayName() .. " 触发了不屈意志！")
                            end
                        end
                    end
                end)
            end
        elseif talent_id == 22 then
            data.talent_freeze_chance = (data.talent_freeze_chance or 0) + 0.10 * diminish
            EnsureAttackedListener(player)
        elseif talent_id == 23 then
            local pct_bonus = 0.15 * diminish
            local base_max = player.components.health and player.components.health.maxhealth or 150
            local val = math.floor(base_max * pct_bonus)
            data.hp_bonus = (data.hp_bonus or 0) + val
            if player.components.health then
                player.components.health:SetMaxHealth(player.components.health.maxhealth + val)
                player.components.health:DoDelta(val)
            end
            player.rogue_applied_hp_bonus = data.hp_bonus
            data.talent_regen_mult = (data.talent_regen_mult or 1) + 0.20 * diminish
        elseif talent_id == 24 then
            data.talent_ally_defense = (data.talent_ally_defense or 0) + 0.04 * diminish
        elseif talent_id == 25 then
            data.talent_dodge = (data.talent_dodge or 0) + 0.08 * diminish
        elseif talent_id == 26 then
            data.talent_elite_extra_drop = (data.talent_elite_extra_drop or 0) + 1
        elseif talent_id == 27 then
            data.cooldown_reduction = (data.cooldown_reduction or 0) + 0.10 * diminish
            data.combo_window_bonus = (data.combo_window_bonus or 0) + 0.8 * diminish
        elseif talent_id == 28 then
            data.talent_gold_drop = (data.talent_gold_drop or 0) + 0.10 * diminish
        elseif talent_id == 29 then
            data.talent_team_damage = (data.talent_team_damage or 0) + 0.04 * diminish
            data.talent_team_speed = (data.talent_team_speed or 0) + 0.03 * diminish
        elseif talent_id == 30 then
            data.talent_luck_all = (data.talent_luck_all or 0) + 0.08 * diminish
        elseif talent_id == 31 then
            data.talent_shadow_dodge_chance = (data.talent_shadow_dodge_chance or 0) + 0.06 * diminish
            EnsureAttackedListener(player)
        elseif talent_id == 32 then
            data.talent_sanity_on_kill = (data.talent_sanity_on_kill or 0) + 2 * diminish
        elseif talent_id == 33 then
            data.damage_bonus = (data.damage_bonus or 0) + 0.03 * diminish
            data.hp_bonus = (data.hp_bonus or 0) + math.floor(5 * diminish)
            data.speed_bonus = (data.speed_bonus or 0) + 0.03 * diminish
            data.talent_chaos_penalty = (data.talent_chaos_penalty or 0) + 0.05 * diminish
        elseif talent_id == 34 then
            data.talent_invuln_cd = 120
            data.talent_invuln_duration = 3
            if not player._rogue_talent_invuln_task then
                player._rogue_talent_invuln_task = player:DoPeriodicTask(1, function(inst)
                    if not inst:IsValid() then return end
                    local d = inst.rogue_data
                    if not d then return end
                    local now = deps.GetTime()
                    local last = d._talent_invuln_last or 0
                    if now - last >= (d.talent_invuln_cd or 120) and inst.components.health then
                        local hp_pct = inst.components.health:GetPercent()
                        if hp_pct < 0.25 then
                            d._talent_invuln_last = now
                            if inst.components.health then
                                inst.components.health:SetInvincible(true)
                            end
                            if inst.components.colouradder then
                                inst.components.colouradder:PushColour("rogue_talent_invuln", 0.5, 0.5, 1, 0)
                            end
                            inst:DoTaskInTime(d.talent_invuln_duration or 3, function(i)
                                if i and i:IsValid() and i.components and i.components.health then
                                    i.components.health:SetInvincible(false)
                                end
                                if i and i:IsValid() and i.components and i.components.colouradder then
                                    i.components.colouradder:PopColour("rogue_talent_invuln")
                                end
                            end)
                            deps.Announce(inst:GetDisplayName() .. " 触发了时空裂隙！3秒无敌！")
                        end
                    end
                end)
            end
        elseif talent_id == 35 then
            data.talent_shadow_chance = (data.talent_shadow_chance or 0) + 0.05 * diminish
            EnsureAttackListener(player)
        elseif talent_id == 36 then
            data.talent_debuff_reduction = (data.talent_debuff_reduction or 0) + 0.25 * diminish
        end

        data.talent_pick_count = (data.talent_pick_count or 0) + 1
        data.talent_pending = false
        data.talent_options = {}
        deps.ApplyGrowthState(player, data, false)
        local level_str = level > 1 and (" Lv." .. level) or ""
        deps.Announce(player:GetDisplayName() .. " 选择天赋：" .. GetTalentName(talent_id) .. level_str .. "（" .. GetTalentDesc(talent_id) .. "）")
    end

    -- 函数说明：应用玩家选择的夜晚补给
    local function ApplyNightSupply(player, supply_id, day)
        if not deps.IsValidPlayer(player) then return end
        local data = deps.EnsurePlayerData(player)

        local function MarkSupplyDropProtected(item)
            if not item or not item:IsValid() then return end
            item:AddTag("rogue_supply_protected")
            item:DoTaskInTime(deps.CONST.SUPPLY_GROUND_PROTECT_TIME, function(inst)
                if inst and inst:IsValid() then
                    inst:RemoveTag("rogue_supply_protected")
                end
            end)
        end

        -- 函数说明：应用夜间补给的副作用代价
        local function ApplySupplyTradeoff(id, factor)
            if id == 1 then
                if player.components.hunger then
                    player.components.hunger:DoDelta(-20 * factor)
                end
            elseif id == 2 then
                if player.components.sanity then
                    player.components.sanity:DoDelta(-18 * factor)
                end
            elseif id == 3 then
                if player.components.health then
                    player.components.health:DoDelta(-player.components.health.maxhealth * 0.08 * factor, nil, "rogue_supply_tradeoff")
                end
            elseif id == 4 then
                if player.components.hunger then
                    player.components.hunger:DoDelta(-10 * factor)
                end
                if player.components.health then
                    player.components.health:DoDelta(-player.components.health.maxhealth * 0.04 * factor, nil, "rogue_supply_tradeoff")
                end
            end
        end

        if supply_id == 1 then
            if player.components.health then
                player.components.health:DoDelta(player.components.health.maxhealth * 0.30)
            end
            if player.components.sanity then
                player.components.sanity:DoDelta(15)
            end
        elseif supply_id == 2 then
            local pool, w = deps.PoolCatalog.GetRuntimePool("DROPS_NORMAL", day)
            local count = math.random() < 0.3 and 2 or 1
            for _ = 1, count do
                local item = deps.PickWeightedCandidate(pool, w)
                if item then
                    local spawned = deps.SpawnDrop(player, item.prefab)
                    MarkSupplyDropProtected(spawned)
                end
            end
        elseif supply_id == 3 then
            local add_dmg = (data.damage_bonus or 0) >= deps.CONST.V2_MAX_DAMAGE_BONUS_FROM_SUPPLY and 0.01 or 0.02
            local add_drop = (data.drop_bonus or 0) >= 0.14 and 0.015 or 0.025
            data.damage_bonus = (data.damage_bonus or 0) + add_dmg
            data.drop_bonus = math.min(deps.CONST.V2_MAX_DROP_BONUS, (data.drop_bonus or 0) + add_drop)
            deps.ApplyGrowthState(player, data, false)
        elseif supply_id == 4 then
            data.combo_window_bonus = (data.combo_window_bonus or 0) + 0.8
            if player.components.sanity then
                player.components.sanity:DoDelta(8)
            end
            deps.ApplyGrowthState(player, data, false)
        end
        local next_count = GetSupplyRepeatCountAfterPick(data, supply_id)
        local factor = GetSupplyTradeoffFactor(data, supply_id)
        data.supply_repeat_streak = next_count
        data.last_supply_id = supply_id
        ApplySupplyTradeoff(supply_id, factor)

        data.supply_pending = false
        data.supply_options = {}
        deps.SyncGrowthNetvars(player, data)
        local supply = GetSupplyById(supply_id)
        deps.Announce(player:GetDisplayName() .. " 选择夜晚补给：" .. (supply and supply.name or "未知选项") .. "（已支付代价x" .. string.format("%.2f", factor) .. "）")
    end

    -- 函数说明：在夜晚降临时向玩家提供补给选项
    local function OfferNightSupply(player, day)
        if not deps.IsValidPlayer(player) then return end
        local data = deps.EnsurePlayerData(player)
        if data.supply_pending or data.talent_pending then return end

        local options = BuildSupplyChoices()
        data.supply_pending = true
        data.supply_options = options
        deps.SyncGrowthNetvars(player, data)

        deps.Announce(player:GetDisplayName() .. " 获得了夜晚补给选择机会！请在弹出的面板中选择。")

        if player.rogue_supply_auto_task then player.rogue_supply_auto_task:Cancel() end
        player.rogue_supply_auto_task = player:DoTaskInTime(deps.CONST.SUPPLY_AUTO_PICK_DELAY, function()
            if not player:IsValid() then return end
            local d = deps.EnsurePlayerData(player)
            if d.supply_pending and d.supply_options and #d.supply_options > 0 then
                ApplyNightSupply(player, d.supply_options[math.random(#d.supply_options)], day)
            end
        end)
    end

    -- 函数说明：当玩家击杀数达到阈值时，向玩家提供天赋选择
    local function OfferTalentChoice(player)
        if not deps.IsValidPlayer(player) then return end
        local data = deps.EnsurePlayerData(player)
        if data.talent_pending then return end

        local options = BuildTalentChoices(data)
        if #options == 0 then return end
        data.talent_pending = true
        data.talent_options = options
        deps.SyncGrowthNetvars(player, data)

        deps.Announce(player:GetDisplayName() .. " 获得了天赋抉择机会！请在弹出的面板中选择。")

        if player.rogue_talent_auto_task then player.rogue_talent_auto_task:Cancel() end
        player.rogue_talent_auto_task = player:DoTaskInTime(deps.CONST.TALENT_AUTO_PICK_DELAY, function()
            if not player:IsValid() then return end
            local d = deps.EnsurePlayerData(player)
            if d.talent_pending and d.talent_options and #d.talent_options > 0 then
                ApplyTalentChoice(player, d.talent_options[math.random(#d.talent_options)])
            end
        end)
    end

    local function CheckTalentTrigger(player)
        if not deps.IsValidPlayer(player) then return end
        local data = deps.EnsurePlayerData(player)
        local kills = data.kills or 0
        local last = data.last_talent_kills or 0
        if kills - last >= deps.CONST.TALENT_TRIGGER_KILLS then
            data.last_talent_kills = kills
            OfferTalentChoice(player)
        end
    end

    S.RegisterRPCCallbacks = function()
        if deps.SetRPCHandler then
            deps.SetRPCHandler("pick_talent", function(player, slot)
                if not player or not player:IsValid() then return end
                local idx = tonumber(slot)
                if not idx or idx < 1 or idx > 3 then return end
                local data = deps.EnsurePlayerData(player)
                if not data.talent_pending then return end
                local talent_id = data.talent_options and data.talent_options[idx]
                if not talent_id then return end
                if player.rogue_talent_auto_task then
                    player.rogue_talent_auto_task:Cancel()
                    player.rogue_talent_auto_task = nil
                end
                ApplyTalentChoice(player, talent_id)
            end)

            deps.SetRPCHandler("pick_supply", function(player, slot)
                if not player or not player:IsValid() then return end
                local idx = tonumber(slot)
                if not idx or idx < 1 or idx > 3 then return end
                local data = deps.EnsurePlayerData(player)
                if not data.supply_pending then return end
                local supply_id = data.supply_options and data.supply_options[idx]
                if not supply_id then return end
                if player.rogue_supply_auto_task then
                    player.rogue_supply_auto_task:Cancel()
                    player.rogue_supply_auto_task = nil
                end
                ApplyNightSupply(player, supply_id, deps.GetCurrentDay())
            end)
        else
            deps.GLOBAL.rawset(deps.GLOBAL, "_rogue_mode_pick_talent_rpc", function(player, slot)
                if not player or not player:IsValid() then return end
                local idx = tonumber(slot)
                if not idx or idx < 1 or idx > 3 then return end
                local data = deps.EnsurePlayerData(player)
                if not data.talent_pending then return end
                local talent_id = data.talent_options and data.talent_options[idx]
                if not talent_id then return end
                if player.rogue_talent_auto_task then
                    player.rogue_talent_auto_task:Cancel()
                    player.rogue_talent_auto_task = nil
                end
                ApplyTalentChoice(player, talent_id)
            end)

            deps.GLOBAL.rawset(deps.GLOBAL, "_rogue_mode_pick_supply_rpc", function(player, slot)
                if not player or not player:IsValid() then return end
                local idx = tonumber(slot)
                if not idx or idx < 1 or idx > 3 then return end
                local data = deps.EnsurePlayerData(player)
                if not data.supply_pending then return end
                local supply_id = data.supply_options and data.supply_options[idx]
                if not supply_id then return end
                if player.rogue_supply_auto_task then
                    player.rogue_supply_auto_task:Cancel()
                    player.rogue_supply_auto_task = nil
                end
                ApplyNightSupply(player, supply_id, deps.GetCurrentDay())
            end)
        end
    end

    -- 函数说明：存档加载后重新应用天赋效果
    local function ReapplyTalentEffects(player)
        if not player or not player:IsValid() then return end
        local data = deps.EnsurePlayerData(player)
        local levels = data.talent_levels or {}

        -- 天赋7（暗影行者）：重新设置移动速度倍率
        if (levels[7] or 0) > 0 and player.components.locomotor then
            player.components.locomotor:SetExternalSpeedMultiplier(player, "rogue_talent_7", 1 + (data.speed_bonus or 0))
        end

        -- 天赋8（生命虹吸）：重新注册攻击监听器
        if (levels[8] or 0) > 0 then
            EnsureAttackListener(player)
        end

        -- 天赋11（暴击本能）：重新注册攻击监听器
        if (levels[11] or 0) > 0 then
            EnsureAttackListener(player)
        end

        -- 天赋15（致命节奏）：重新注册攻击监听器
        if (levels[15] or 0) > 0 then
            EnsureAttackListener(player)
        end

        -- 天赋19（再生之血）：重新注册定时回复
        if (levels[19] or 0) > 0 and not player._rogue_talent_regen_task then
            player._rogue_talent_regen_task = player:DoPeriodicTask(3, function(inst)
                if inst:IsValid() and inst.components.health and not inst.components.health:IsDead() then
                    local d = inst.rogue_data
                    if d and (d.talent_regen or 0) > 0 then
                        inst.components.health:DoDelta(d.talent_regen)
                    end
                end
            end)
        end

        -- 天赋21（不屈意志）：重新注册免死监听器
        if (levels[21] or 0) > 0 and not player._rogue_talent_death_defy_listener then
            player._rogue_talent_death_defy_listener = true
            player:ListenForEvent("healthdelta", function(inst)
                if not inst:IsValid() or not inst.components.health then return end
                if inst.components.health:IsDead() then
                    local d = inst.rogue_data
                    if d and d.talent_death_defy then
                        local now = deps.GetTime()
                        local last_trigger = d._talent_death_defy_last or 0
                        if now - last_trigger >= (d.talent_death_defy_cd or 120) then
                            d._talent_death_defy_last = now
                            inst.components.health:SetVal(1, "rogue_talent_death_defy")
                            inst.components.health:SetPercent(0.1)
                            if inst.components.colouradder then
                                inst.components.colouradder:PushColour("rogue_talent_death_defy", 1, 1, 0.5, 0)
                                inst:DoTaskInTime(1.5, function(i)
                                    if i and i:IsValid() and i.components and i.components.colouradder then
                                        i.components.colouradder:PopColour("rogue_talent_death_defy")
                                    end
                                end)
                            end
                            deps.Announce(inst:GetDisplayName() .. " 触发了不屈意志！")
                        end
                    end
                end
            end)
        end

        -- 天赋22（寒冰护甲）：重新注册受击监听器
        if (levels[22] or 0) > 0 then
            EnsureAttackedListener(player)
        end

        -- 天赋31（暗影闪避）：重新注册受击监听器
        if (levels[31] or 0) > 0 then
            EnsureAttackedListener(player)
        end

        -- 天赋34（时空裂隙）：重新注册无敌定时器
        if (levels[34] or 0) > 0 and not player._rogue_talent_invuln_task then
            player._rogue_talent_invuln_task = player:DoPeriodicTask(1, function(inst)
                if not inst:IsValid() then return end
                local d = inst.rogue_data
                if not d then return end
                local now = deps.GetTime()
                local last = d._talent_invuln_last or 0
                if now - last >= (d.talent_invuln_cd or 120) and inst.components.health then
                    local hp_pct = inst.components.health:GetPercent()
                    if hp_pct < 0.25 then
                        d._talent_invuln_last = now
                        inst.components.health:SetInvincible(true)
                        if inst.components.colouradder then
                            inst.components.colouradder:PushColour("rogue_talent_invuln", 0.5, 0.5, 1, 0)
                        end
                        inst:DoTaskInTime(d.talent_invuln_duration or 3, function(i)
                            if i and i:IsValid() and i.components and i.components.health then
                                i.components.health:SetInvincible(false)
                            end
                            if i and i:IsValid() and i.components and i.components.colouradder then
                                i.components.colouradder:PopColour("rogue_talent_invuln")
                            end
                        end)
                    end
                end
            end)
        end

        -- 天赋35（暗影分身）：重新注册攻击监听器
        if (levels[35] or 0) > 0 then
            EnsureAttackListener(player)
        end
    end

    S.OfferNightSupply = OfferNightSupply
    S.CheckTalentTrigger = CheckTalentTrigger
    S.ReapplyTalentEffects = ReapplyTalentEffects
    S.ApplyTalentChoice = ApplyTalentChoice
    return S
end

return M
