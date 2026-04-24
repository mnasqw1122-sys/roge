--[[
    文件说明：relic_system.lua
    功能：遗物与协同系统。
    管理遗物的抽取、选择和属性应用，并检查同标签遗物的组合，触发额外的协同增益。
]]
local M = {}
local RogueConfig = require("rogue/config")

function M.Create(deps)
    local S = {}

    local RELIC_DEFS = RogueConfig.RELIC_DEFS or {}
    local SYNERGY_DEFS = RogueConfig.RELIC_SYNERGY_DEFS or {}
    local BUILD_DEFS = RogueConfig.RELIC_BUILD_DEFS or {}
    local SOURCE_PROFILE = RogueConfig.RELIC_SOURCE_PROFILE or {}
    local SOURCE_NAME = RogueConfig.RELIC_SOURCE_NAME or {}

    -- 预构建组索引：group → { [id]=true }，将 IsDefBlockedByOwnership 的 O(n) 优化为 O(同组数)
    local GROUP_INDEX = {}
    for _, def in ipairs(RELIC_DEFS) do
        if def.group then
            GROUP_INDEX[def.group] = GROUP_INDEX[def.group] or {}
            GROUP_INDEX[def.group][def.id] = true
        end
    end

    -- 获取不同来源（击杀、挑战等）的遗物稀有度概率分布
    local function GetSourceProfile(source)
        return SOURCE_PROFILE[source or "kill"] or SOURCE_PROFILE.kill
    end

    -- 根据 ID 查找遗物配置
    local function GetRelicById(id)
        for _, def in ipairs(RELIC_DEFS) do
            if def.id == id then return def end
        end
        return nil
    end

    -- 检查玩家是否已拥有指定遗物
    local function HasRelic(data, relic_id)
        return data.relics and (data.relics[relic_id] or 0) > 0
    end

    -- 检查遗物是否因为冲突（同组互斥或达到最大堆叠数）而不可选
    -- O(1)组索引查表替代O(n)全局遍历
    local function IsDefBlockedByOwnership(data, def)
        if not def then return true end
        local cur = data.relics and (data.relics[def.id] or 0) or 0
        if cur >= (def.max_stack or 1) then return true end
        local group_members = GROUP_INDEX[def.group]
        if not group_members then return false end
        for id, _ in pairs(group_members) do
            if id ~= def.id and HasRelic(data, id) then
                return true
            end
        end
        return false
    end

    local function PickWeightedFromList(list)
        local total = 0
        for _, def in ipairs(list) do
            total = total + (def.weight or 1)
        end
        if total <= 0 then return nil end
        local roll = math.random() * total
        local acc = 0
        for _, def in ipairs(list) do
            acc = acc + (def.weight or 1)
            if roll <= acc then return def end
        end
        return list[#list]
    end

    -- 函数说明：根据稀有度概率分布随机抽取稀有度（含传说级）
    local function RollRarity(profile)
        local r = math.random()
        if r < (profile.legendary or 0) then return "legendary" end
        if r < (profile.legendary or 0) + (profile.epic or 0) then return "epic" end
        if r < (profile.legendary or 0) + (profile.epic or 0) + (profile.rare or 0) then return "rare" end
        return "common"
    end

    local function BuildRelicChoices(data, source, day)
        local profile = GetSourceProfile(source)
        if day and day >= 35 then
            profile = { common = math.max(0.28, profile.common - 0.10), rare = profile.rare + 0.05, epic = math.min(0.30, profile.epic + 0.05) }
        end
        local picked = {}
        local used = {}
        for _, def in ipairs(RELIC_DEFS) do
            if not used[def.id] then
                used[def.id] = false
            end
        end
        for _ = 1, 3 do
            local rarity = RollRarity(profile)
            local pool = {}
            for _, def in ipairs(RELIC_DEFS) do
                if def.rarity == rarity and not used[def.id] and not IsDefBlockedByOwnership(data, def) then
                    table.insert(pool, def)
                end
            end
            if #pool == 0 then
                for _, def in ipairs(RELIC_DEFS) do
                    if not used[def.id] and not IsDefBlockedByOwnership(data, def) then
                        table.insert(pool, def)
                    end
                end
            end
            local hit = PickWeightedFromList(pool)
            if hit then
                used[hit.id] = true
                table.insert(picked, hit.id)
            end
        end
        local safety = 0
        while #picked < 3 and safety < 50 do
            safety = safety + 1
            local fallback_pool = {}
            for _, def in ipairs(RELIC_DEFS) do
                if not used[def.id] and not IsDefBlockedByOwnership(data, def) then
                    table.insert(fallback_pool, def)
                end
            end
            if #fallback_pool == 0 then
                for _, def in ipairs(RELIC_DEFS) do
                    if not used[def.id] then
                        table.insert(fallback_pool, def)
                    end
                end
            end
            if #fallback_pool == 0 then break end
            local fallback = fallback_pool[math.random(#fallback_pool)]
            used[fallback.id] = true
            table.insert(picked, fallback.id)
        end
        return picked
    end

    local function ApplySynergies(player, data, picked_id)
        data.relic_synergy_applied = data.relic_synergy_applied or {}
        data.relic_synergy_count = data.relic_synergy_count or 0
        for _, syn in ipairs(SYNERGY_DEFS) do
            if not data.relic_synergy_applied[syn.key] and (syn.need[1] == picked_id or syn.need[2] == picked_id) and HasRelic(data, syn.need[1]) and HasRelic(data, syn.need[2]) then
                data.relic_synergy_applied[syn.key] = true
                data.relic_synergy_count = data.relic_synergy_count + 1
                if syn.key == "atk_combo" then
                    data.damage_bonus = (data.damage_bonus or 0) + 0.02
                elseif syn.key == "hp_drop" then
                    data.drop_bonus = (data.drop_bonus or 0) + 0.02
                elseif syn.key == "combo_daily" then
                    data.daily_reward_bonus = (data.daily_reward_bonus or 0) + 0.15
                elseif syn.key == "core_guard" then
                    local val = 10
                    data.hp_bonus = (data.hp_bonus or 0) + val
                    if player.components and player.components.health then
                        player.components.health:SetMaxHealth(player.components.health.maxhealth + val)
                        player.components.health:DoDelta(val)
                    end
                    player.rogue_applied_hp_bonus = data.hp_bonus
                elseif syn.key == "elemental_speed" then
                    data.elemental_bonus = (data.elemental_bonus or 0) + 0.05
                    data.speed_bonus = (data.speed_bonus or 0) + 0.05
                    if player.components.locomotor then
                        player.components.locomotor:SetExternalSpeedMultiplier(player, "rogue_relic_12", 1 + (data.speed_bonus or 0))
                    end
                elseif syn.key == "regen_sanity" then
                    data.regen_bonus = (data.regen_bonus or 0) + 0.20
                    data.sanity_regen_bonus = (data.sanity_regen_bonus or 0) + 0.10
                elseif syn.key == "luck_crit" then
                    data.crit_chance = (data.crit_chance or 0) + 0.03
                    data.luck_bonus = (data.luck_bonus or 0) + 0.02
                elseif syn.key == "cooldown_elemental" then
                    data.cooldown_reduction = (data.cooldown_reduction or 0) + 0.05
                    data.elemental_bonus = (data.elemental_bonus or 0) + 0.03
                elseif syn.key == "survival_hp" then
                    data.death_defy_chance = (data.death_defy_chance or 0) + 0.05
                    local val = 10
                    data.hp_bonus = (data.hp_bonus or 0) + val
                    if player.components and player.components.health then
                        player.components.health:SetMaxHealth(player.components.health.maxhealth + val)
                        player.components.health:DoDelta(val)
                    end
                    player.rogue_applied_hp_bonus = data.hp_bonus
                elseif syn.key == "berserk_fang" then
                    data.relic_kill_damage_bonus = (data.relic_kill_damage_bonus or 0) + 0.05
                elseif syn.key == "armor_pen_crit" then
                    data.relic_armor_pen = (data.relic_armor_pen or 0) + 0.10
                elseif syn.key == "fire_ice" then
                    data.elemental_bonus = (data.elemental_bonus or 0) + 0.08
                    data.elemental_resist = (data.elemental_resist or 0) + 0.10
                elseif syn.key == "thunder_combo" then
                    data.relic_lightning_chance = (data.relic_lightning_chance or 0) + 0.05
                elseif syn.key == "boss_depths" then
                    data.relic_boss_damage = (data.relic_boss_damage or 0) + 0.10
                    data.crit_dmg_mult = (data.crit_dmg_mult or 1) + 0.10
                elseif syn.key == "immortal_regen" then
                    data.relic_damage_reduction = (data.relic_damage_reduction or 0) + 0.03
                    data.regen_bonus = (data.regen_bonus or 0) + 0.25
                elseif syn.key == "shield_first" then
                    data.relic_first_hit_shield_upgrade = true
                elseif syn.key == "gold_luck" then
                    data.luck_bonus = (data.luck_bonus or 0) + 0.04
                    data.relic_luck_all = (data.relic_luck_all or 0) + 0.03
                elseif syn.key == "rhythm_fury" then
                    data.relic_combo_max_mult_bonus = (data.relic_combo_max_mult_bonus or 0) + 0.1
                    data.combo_window_bonus = (data.combo_window_bonus or 0) + 0.25
                elseif syn.key == "phoenix_angel" then
                    data.death_defy_chance = (data.death_defy_chance or 0) + 0.05
                elseif syn.key == "void_mirror" then
                    data.relic_reflect_chance = (data.relic_reflect_chance or 0) + 0.03
                    data.relic_damage_reduction = (data.relic_damage_reduction or 0) + 0.03
                elseif syn.key == "genesis_tome" then
                    data.damage_bonus = (data.damage_bonus or 0) + 0.01
                    data.hp_bonus = (data.hp_bonus or 0) + 3
                elseif syn.key == "diligence_bounty" then
                    data.relic_daily_target_reduction = (data.relic_daily_target_reduction or 0) + 0.10
                    data.daily_reward_bonus = (data.daily_reward_bonus or 0) + 0.10
                elseif syn.key == "heal_saint" then
                    data.relic_heal_mult = (data.relic_heal_mult or 1) + 0.15
                    data.regen_bonus = (data.regen_bonus or 0) + 0.15
                elseif syn.key == "eternal_clock" then
                    data.cooldown_reduction = (data.cooldown_reduction or 0) + 0.05
                    data.combo_window_bonus = (data.combo_window_bonus or 0) + 0.25
                elseif syn.key == "deadly_mark" then
                    data.crit_chance = (data.crit_chance or 0) + 0.03
                    data.crit_dmg_mult = (data.crit_dmg_mult or 1) + 0.15
                end
                if deps.SpawnPrefab then
                    local fx = deps.SpawnPrefab("statue_transition_2")
                    if fx then
                        local x, y, z = player.Transform:GetWorldPosition()
                        fx.Transform:SetPosition(x, y, z)
                        fx.Transform:SetScale(0.7, 0.7, 0.7)
                    end
                end
                if player.components and player.components.colouradder then
                    player.components.colouradder:PushColour("rogue_relic_synergy", 0.22, 0.06, 0.25, 0)
                    player:DoTaskInTime(0.9, function(inst)
                        if inst and inst:IsValid() and inst.components and inst.components.colouradder then
                            inst.components.colouradder:PopColour("rogue_relic_synergy")
                        end
                    end)
                end
                if player.SoundEmitter then
                    player.SoundEmitter:PlaySound("dontstarve/common/dropGeneric")
                end
                deps.Announce(player:GetDisplayName() .. " 激活遗物协同：" .. syn.desc)
            end
        end
    end

    local function PlayRelicPickupFeedback(player, rarity)
        if not player or not player:IsValid() then return end
        if deps.SpawnPrefab then
            local prefab = rarity == "legendary" and "explode_reskin" or (rarity == "epic" and "explode_reskin" or (rarity == "rare" and "statue_transition_2" or "small_puff"))
            local fx = deps.SpawnPrefab(prefab)
            if fx then
                local x, y, z = player.Transform:GetWorldPosition()
                fx.Transform:SetPosition(x, y, z)
                local scale = rarity == "legendary" and 1.2 or (rarity == "epic" and 0.8 or (rarity == "rare" and 0.65 or 0.5))
                fx.Transform:SetScale(scale, scale, scale)
            end
        end
        if player.components and player.components.colouradder then
            if rarity == "legendary" then
                player.components.colouradder:PushColour("rogue_relic_pick", 0.30, 0.15, 0.0, 0)
            elseif rarity == "epic" then
                player.components.colouradder:PushColour("rogue_relic_pick", 0.28, 0.11, 0.02, 0)
            elseif rarity == "rare" then
                player.components.colouradder:PushColour("rogue_relic_pick", 0.05, 0.10, 0.22, 0)
            else
                player.components.colouradder:PushColour("rogue_relic_pick", 0.08, 0.08, 0.08, 0)
            end
            player:DoTaskInTime(0.6, function(inst)
                if inst and inst:IsValid() and inst.components and inst.components.colouradder then
                    inst.components.colouradder:PopColour("rogue_relic_pick")
                end
            end)
        end
        if player.SoundEmitter then
            player.SoundEmitter:PlaySound("dontstarve/common/dropGeneric")
        end
    end

    -- 函数说明：检测并应用Build组合加成
    local function CheckAndApplyBuilds(player, data)
        local BUILD_DEFS_REF = BUILD_DEFS
        data.relic_builds = data.relic_builds or {}
        for _, build in ipairs(BUILD_DEFS_REF) do
            if not data.relic_builds[build.key] then
                local all_core = true
                for _, rid in ipairs(build.core_relics) do
                    if not HasRelic(data, rid) then
                        all_core = false
                        break
                    end
                end
                if all_core then
                    data.relic_builds[build.key] = true
                    local bonus = build.bonus or {}
                    if bonus.damage_bonus then
                        data.damage_bonus = (data.damage_bonus or 0) + bonus.damage_bonus
                    end
                    if bonus.crit_chance then
                        data.crit_chance = (data.crit_chance or 0) + bonus.crit_chance
                    end
                    if bonus.damage_reduction then
                        data.relic_damage_reduction = (data.relic_damage_reduction or 0) + bonus.damage_reduction
                    end
                    if bonus.hp_bonus then
                        data.hp_bonus = (data.hp_bonus or 0) + bonus.hp_bonus
                        if player.components and player.components.health then
                            player.components.health:SetMaxHealth(player.components.health.maxhealth + bonus.hp_bonus)
                            player.components.health:DoDelta(bonus.hp_bonus)
                        end
                        player.rogue_applied_hp_bonus = data.hp_bonus
                    end
                    if bonus.combo_window_bonus then
                        data.combo_window_bonus = (data.combo_window_bonus or 0) + bonus.combo_window_bonus
                    end
                    if bonus.combo_max_mult_bonus then
                        data.relic_combo_max_mult_bonus = (data.relic_combo_max_mult_bonus or 0) + bonus.combo_max_mult_bonus
                    end
                    if bonus.drop_bonus then
                        data.drop_bonus = (data.drop_bonus or 0) + bonus.drop_bonus
                    end
                    if bonus.luck_bonus then
                        data.luck_bonus = (data.luck_bonus or 0) + bonus.luck_bonus
                    end
                    if bonus.elemental_bonus then
                        data.elemental_bonus = (data.elemental_bonus or 0) + bonus.elemental_bonus
                    end
                    if bonus.elemental_resist then
                        data.elemental_resist = (data.elemental_resist or 0) + bonus.elemental_resist
                    end
                    if bonus.death_defy_chance then
                        data.death_defy_chance = (data.death_defy_chance or 0) + bonus.death_defy_chance
                    end
                    if bonus.regen_bonus then
                        data.regen_bonus = (data.regen_bonus or 0) + bonus.regen_bonus
                    end
                    if deps.SpawnPrefab then
                        local fx = deps.SpawnPrefab("explode_reskin")
                        if fx then
                            local x, y, z = player.Transform:GetWorldPosition()
                            fx.Transform:SetPosition(x, y, z)
                            fx.Transform:SetScale(1.2, 1.2, 1.2)
                        end
                    end
                    deps.Announce(player:GetDisplayName() .. " 达成Build组合：【" .. build.name .. "】" .. build.bonus_desc)
                end
            end
        end
    end

    -- 函数说明：应用遗物11-46的效果
    local function ApplyRelicEffect_11_46(player, relic_id, data)
        if relic_id == 11 then
            data.elemental_bonus = (data.elemental_bonus or 0) + 0.10
        elseif relic_id == 12 then
            data.speed_bonus = (data.speed_bonus or 0) + 0.08
            if player.components.locomotor then
                player.components.locomotor:SetExternalSpeedMultiplier(player, "rogue_relic_12", 1 + (data.speed_bonus or 0))
            end
        elseif relic_id == 13 then
            data.regen_bonus = (data.regen_bonus or 0) + 0.25
            if not player._rogue_regen_task then
                player._rogue_regen_task = player:DoPeriodicTask(2, function(inst)
                    if inst:IsValid() and inst.components.health and not inst.components.health:IsDead() then
                        local d = inst.rogue_data
                        if d and (d.regen_bonus or 0) > 0 then
                            inst.components.health:DoDelta(d.regen_bonus)
                        end
                    end
                end)
            end
        elseif relic_id == 14 then
            data.luck_bonus = (data.luck_bonus or 0) + 0.04
        elseif relic_id == 15 then
            data.cooldown_reduction = (data.cooldown_reduction or 0) + 0.10
        elseif relic_id == 16 then
            data.death_defy_chance = (data.death_defy_chance or 0) + 0.10
            if not player._rogue_death_defy_listener then
                player._rogue_death_defy_listener = true
                player:ListenForEvent("healthdelta", function(inst, data)
                    if not inst:IsValid() or not inst.components.health then return end
                    if inst.components.health:IsDead() then
                        local d = inst.rogue_data
                        local chance = d and (d.death_defy_chance or 0) or 0
                        if chance > 0 and math.random() < chance then
                            inst.components.health:SetVal(1, "rogue_death_defy")
                            inst.components.health:SetPercent(0.1)
                            if inst.components.colouradder then
                                inst.components.colouradder:PushColour("rogue_death_defy", 1, 1, 0.5, 0)
                                inst:DoTaskInTime(1.2, function(i)
                                    if i and i:IsValid() and i.components and i.components.colouradder then
                                        i.components.colouradder:PopColour("rogue_death_defy")
                                    end
                                end)
                            end
                            if inst.SoundEmitter then
                                inst.SoundEmitter:PlaySound("dontstarve/common/rebirth_flare")
                            end
                            deps.Announce(inst:GetDisplayName() .. " 触发了守护天使！免死一次！")
                        end
                    end
                end)
            end
        elseif relic_id == 17 then
            data.sanity_regen_bonus = (data.sanity_regen_bonus or 0) + 0.20
            if not player._rogue_sanity_task then
                player._rogue_sanity_task = player:DoPeriodicTask(5, function(inst)
                    if inst:IsValid() and inst.components.sanity and not (inst.components.health and inst.components.health:IsDead()) then
                        local d = inst.rogue_data
                        if d and (d.sanity_regen_bonus or 0) > 0 then
                            inst.components.sanity:DoDelta(d.sanity_regen_bonus)
                        end
                    end
                end)
            end
        elseif relic_id == 18 then
            data.crit_chance = (data.crit_chance or 0) + 0.05
            if not player._rogue_crit_listener then
                player._rogue_crit_listener = true
                player:ListenForEvent("onhitother", function(inst, data)
                    if not inst:IsValid() or not data or not data.target then return end
                    local d = inst.rogue_data
                    local chance = d and (d.crit_chance or 0) or 0
                    if chance > 0 and math.random() < chance then
                        if data.target.components.health and not data.target.components.health:IsDead() then
                            local crit_dmg = 50
                            data.target.components.health:DoDelta(-crit_dmg, nil, "rogue_crit", nil, inst)
                            if data.target.SoundEmitter then
                                data.target.SoundEmitter:PlaySound("dontstarve/creatures/eyeballturret/shoot")
                            end
                            if inst.components.colouradder then
                                inst.components.colouradder:PushColour("rogue_crit", 1, 0.3, 0, 0)
                                inst:DoTaskInTime(0.3, function(i)
                                    if i and i:IsValid() and i.components and i.components.colouradder then
                                        i.components.colouradder:PopColour("rogue_crit")
                                    end
                                end)
                            end
                        end
                    end
                end)
            end
        elseif relic_id == 19 then
            data.crit_dmg_mult = (data.crit_dmg_mult or 1) + 0.25
        elseif relic_id == 20 then
            data.relic_kill_damage_bonus = (data.relic_kill_damage_bonus or 0) + 0.10
        elseif relic_id == 21 then
            data.relic_armor_pen = (data.relic_armor_pen or 0) + 0.12
        elseif relic_id == 22 then
            data.relic_fire_dmg = (data.relic_fire_dmg or 0) + 5
        elseif relic_id == 23 then
            data.relic_lightning_chance = (data.relic_lightning_chance or 0) + 0.08
        elseif relic_id == 24 then
            data.relic_boss_damage = (data.relic_boss_damage or 0) + 0.08
        elseif relic_id == 25 then
            data.relic_damage_reduction = (data.relic_damage_reduction or 0) + 0.08
        elseif relic_id == 26 then
            data.relic_regen_ring = (data.relic_regen_ring or 0) + 1
            if not player._rogue_regen_ring_task then
                player._rogue_regen_ring_task = player:DoPeriodicTask(3, function(inst)
                    if inst:IsValid() and inst.components.health and not inst.components.health:IsDead() then
                        local d = inst.rogue_data
                        if d and (d.relic_regen_ring or 0) > 0 then
                            inst.components.health:DoDelta(d.relic_regen_ring)
                        end
                    end
                end)
            end
        elseif relic_id == 27 then
            data.relic_first_hit_shield = true
        elseif relic_id == 28 then
            data.relic_kill_hp_recover = (data.relic_kill_hp_recover or 0) + 3
        elseif relic_id == 29 then
            data.luck_bonus = (data.luck_bonus or 0) + 0.06
        elseif relic_id == 30 then
            data.relic_elite_extra_drop = (data.relic_elite_extra_drop or 0) + 1
        elseif relic_id == 31 then
            data.drop_bonus = (data.drop_bonus or 0) + 0.01
            data.relic_risk_penalty = (data.relic_risk_penalty or 0) + 0.03
        elseif relic_id == 32 then
            data.relic_combo_fury = (data.relic_combo_fury or 0) + 0.03
        elseif relic_id == 33 then
            data.combo_window_bonus = (data.combo_window_bonus or 0) + 1.0
            data.relic_combo_max_mult_bonus = (data.relic_combo_max_mult_bonus or 0) + 0.2
        elseif relic_id == 34 then
            data.relic_daily_target_reduction = (data.relic_daily_target_reduction or 0) + 0.20
        elseif relic_id == 35 then
            data.elemental_bonus = (data.elemental_bonus or 0) + 0.12
            data.elemental_resist = (data.elemental_resist or 0) + 0.15
        elseif relic_id == 36 then
            data.elemental_bonus = (data.elemental_bonus or 0) + 0.12
            data.elemental_resist = (data.elemental_resist or 0) + 0.15
        elseif relic_id == 37 then
            data.speed_bonus = (data.speed_bonus or 0) + 0.12
            data.relic_dodge = (data.relic_dodge or 0) + 0.05
            if player.components.locomotor then
                player.components.locomotor:SetExternalSpeedMultiplier(player, "rogue_relic_12", 1 + (data.speed_bonus or 0))
            end
        elseif relic_id == 38 then
            data.relic_heal_mult = (data.relic_heal_mult or 1) + 0.30
        elseif relic_id == 39 then
            data.relic_luck_all = (data.relic_luck_all or 0) + 0.05
        elseif relic_id == 40 then
            data.cooldown_reduction = (data.cooldown_reduction or 0) + 0.15
            data.combo_window_bonus = (data.combo_window_bonus or 0) + 0.5
        elseif relic_id == 41 then
            data.relic_phoenix_revive = true
        elseif relic_id == 42 then
            data.relic_sanity_auto_recover = true
        elseif relic_id == 43 then
            data.crit_chance = (data.crit_chance or 0) + 0.04
            data.relic_crit_after_bonus = (data.relic_crit_after_bonus or 0) + 0.08
        elseif relic_id == 44 then
            data.damage_bonus = (data.damage_bonus or 0) + 0.02
            data.hp_bonus = (data.hp_bonus or 0) + 5
            data.speed_bonus = (data.speed_bonus or 0) + 0.02
            data.relic_chaos_penalty = (data.relic_chaos_penalty or 0) + 0.05
        elseif relic_id == 45 then
            data.relic_genesis_tome = true
        elseif relic_id == 46 then
            data.relic_reflect_chance = (data.relic_reflect_chance or 0) + 0.05
        end
    end

    local function ApplyRelicChoice(player, relic_id)
        local data = deps.EnsurePlayerData(player)
        local def = GetRelicById(relic_id)
        if not def or IsDefBlockedByOwnership(data, def) then
            data.relic_pending = false
            data.relic_options = {}
            deps.SyncGrowthNetvars(player, data)
            return
        end
        data.relics = data.relics or {}
        data.relic_count = (data.relic_count or 0) + 1
        data.relics[relic_id] = (data.relics[relic_id] or 0) + 1
        if relic_id == 1 then
            data.damage_bonus = (data.damage_bonus or 0) + 0.05
        elseif relic_id == 2 then
            local val = 20
            data.hp_bonus = (data.hp_bonus or 0) + val
            if player.components and player.components.health then
                player.components.health:SetMaxHealth(player.components.health.maxhealth + val)
                player.components.health:DoDelta(val)
            end
            player.rogue_applied_hp_bonus = data.hp_bonus
        elseif relic_id == 3 then
            data.drop_bonus = (data.drop_bonus or 0) + 0.03
        elseif relic_id == 4 then
            data.combo_window_bonus = (data.combo_window_bonus or 0) + 0.5
        elseif relic_id == 5 then
            data.daily_reward_bonus = (data.daily_reward_bonus or 0) + 0.25
        elseif relic_id == 6 then
            data.damage_bonus = (data.damage_bonus or 0) + 0.03
        elseif relic_id == 7 then
            local val = 15
            data.hp_bonus = (data.hp_bonus or 0) + val
            if player.components and player.components.health then
                player.components.health:SetMaxHealth(player.components.health.maxhealth + val)
                player.components.health:DoDelta(val)
            end
            player.rogue_applied_hp_bonus = data.hp_bonus
        elseif relic_id == 8 then
            data.drop_bonus = (data.drop_bonus or 0) + 0.02
        elseif relic_id == 9 then
            data.combo_window_bonus = (data.combo_window_bonus or 0) + 0.5
        elseif relic_id == 10 then
            data.daily_reward_bonus = (data.daily_reward_bonus or 0) + 0.25
        else
            ApplyRelicEffect_11_46(player, relic_id, data)
        end
        ApplySynergies(player, data, relic_id)
        CheckAndApplyBuilds(player, data)
        data.relic_pending = false
        data.relic_options = {}
        deps.ApplyGrowthState(player, data, false)
        deps.SyncGrowthNetvars(player, data)
        local relic = def
        local tag = relic and ((relic.rarity == "legendary" and "传说") or (relic.rarity == "epic" and "史诗") or (relic.rarity == "rare" and "稀有") or "普通") or "普通"
        PlayRelicPickupFeedback(player, relic and relic.rarity or "common")
        deps.Announce(player:GetDisplayName() .. " 获得遗物[" .. tag .. "]：" .. (relic and relic.name or "未知遗物"))
    end

    S.OfferRelicChoice = function(player, source, day)
        if not deps.IsValidPlayer(player) then return end
        local data = deps.EnsurePlayerData(player)
        if data.relic_pending then return end
        local options = BuildRelicChoices(data, source, day)
        data.relic_pending = true
        data.relic_options = options
        deps.SyncGrowthNetvars(player, data)
        deps.Announce(player:GetDisplayName() .. " 获得了遗物抉择机会！请在弹出的面板中选择。")
        if player.rogue_relic_auto_task then player.rogue_relic_auto_task:Cancel() end
        player.rogue_relic_auto_task = player:DoTaskInTime(20, function()
            if not player:IsValid() then return end
            local d = deps.EnsurePlayerData(player)
            if d.relic_pending and d.relic_options and #d.relic_options > 0 then
                ApplyRelicChoice(player, d.relic_options[math.random(#d.relic_options)])
            end
        end)
    end

    S.OfferInitialRelicChoice = function(player)
        local data = deps.EnsurePlayerData(player)
        if data.relic_initialized then return end
        data.relic_initialized = true
        S.OfferRelicChoice(player, "init", 1)
    end

    S.CheckRelicTrigger = function(player, day)
        if not deps.IsValidPlayer(player) then return end
        local data = deps.EnsurePlayerData(player)
        local kills = data.kills or 0
        local last = data.last_relic_kills or 0
        if kills - last >= 250 then
            data.last_relic_kills = kills
            S.OfferRelicChoice(player, "kill", day or 1)
        end
    end

    S.RegisterRPCCallbacks = function()
        if deps.SetRPCHandler then
            deps.SetRPCHandler("pick_relic", function(player, slot)
                if not player or not player:IsValid() then return end
                local idx = tonumber(slot)
                if not idx or idx < 1 or idx > 3 then return end
                local data = deps.EnsurePlayerData(player)
                if not data.relic_pending then return end
                local relic_id = data.relic_options and data.relic_options[idx]
                if not relic_id then return end
                if player.rogue_relic_auto_task then
                    player.rogue_relic_auto_task:Cancel()
                    player.rogue_relic_auto_task = nil
                end
                ApplyRelicChoice(player, relic_id)
            end)
        else
            deps.GLOBAL.rawset(deps.GLOBAL, "_rogue_mode_pick_relic_rpc", function(player, slot)
                if not player or not player:IsValid() then return end
                local idx = tonumber(slot)
                if not idx or idx < 1 or idx > 3 then return end
                local data = deps.EnsurePlayerData(player)
                if not data.relic_pending then return end
                local relic_id = data.relic_options and data.relic_options[idx]
                if not relic_id then return end
                if player.rogue_relic_auto_task then
                    player.rogue_relic_auto_task:Cancel()
                    player.rogue_relic_auto_task = nil
                end
                ApplyRelicChoice(player, relic_id)
            end)
        end
    end

    return S
end

return M
