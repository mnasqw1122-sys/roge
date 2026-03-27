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
    local SOURCE_PROFILE = RogueConfig.RELIC_SOURCE_PROFILE or {}
    local SOURCE_NAME = RogueConfig.RELIC_SOURCE_NAME or {}

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
    local function IsDefBlockedByOwnership(data, def)
        if not def then return true end
        local cur = data.relics and (data.relics[def.id] or 0) or 0
        if cur >= (def.max_stack or 1) then return true end
        for _, other in ipairs(RELIC_DEFS) do
            if other.id ~= def.id and other.group == def.group and HasRelic(data, other.id) then
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

    local function RollRarity(profile)
        local r = math.random()
        if r < (profile.epic or 0) then return "epic" end
        if r < (profile.epic or 0) + (profile.rare or 0) then return "rare" end
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
            local prefab = rarity == "epic" and "explode_reskin" or (rarity == "rare" and "statue_transition_2" or "small_puff")
            local fx = deps.SpawnPrefab(prefab)
            if fx then
                local x, y, z = player.Transform:GetWorldPosition()
                fx.Transform:SetPosition(x, y, z)
                local scale = rarity == "epic" and 0.8 or (rarity == "rare" and 0.65 or 0.5)
                fx.Transform:SetScale(scale, scale, scale)
            end
        end
        if player.components and player.components.colouradder then
            if rarity == "epic" then
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
        end
        ApplySynergies(player, data, relic_id)
        data.relic_pending = false
        data.relic_options = {}
        deps.ApplyGrowthState(player, data, false)
        deps.SyncGrowthNetvars(player, data)
        local relic = def
        local tag = relic and ((relic.rarity == "epic" and "史诗") or (relic.rarity == "rare" and "稀有") or "普通") or "普通"
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
        local r1 = GetRelicById(options[1])
        local r2 = GetRelicById(options[2])
        local r3 = GetRelicById(options[3])
        local src_name = SOURCE_NAME[source or "kill"] or "遗物"
        deps.Announce(player:GetDisplayName() .. " " .. src_name .. "抉择(F1/F2/F3)："
            .. "1." .. r1.name .. "（" .. r1.desc .. "） "
            .. "2." .. r2.name .. "（" .. r2.desc .. "） "
            .. "3." .. r3.name .. "（" .. r3.desc .. "）")
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

    return S
end

return M
