--[[
    文件说明：talent_supply.lua
    功能：天赋与补给抉择系统。
    负责处理击杀数达标后的天赋升级选择，以及夜晚降临时的补给物资选择（带代价的增益），并通过RPC响应客户端的选择。
]]
local M = {}

function M.Create(deps)
    local S = {}

    -- 随机生成3个不同的天赋选项供玩家选择
    local function BuildTalentChoices()
        local ids = {}
        for _, def in ipairs(deps.TALENT_DEFS) do
            table.insert(ids, def.id)
        end
        for i = #ids, 2, -1 do
            local j = math.random(i)
            ids[i], ids[j] = ids[j], ids[i]
        end
        return { ids[1], ids[2], ids[3] }
    end

    local function GetTalentName(id)
        for _, def in ipairs(deps.TALENT_DEFS) do
            if def.id == id then
                return def.name
            end
        end
        return "未知天赋"
    end

    local function GetTalentDesc(id)
        for _, def in ipairs(deps.TALENT_DEFS) do
            if def.id == id then
                return def.desc or "无说明"
            end
        end
        return "无说明"
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

    -- 应用玩家选择的天赋效果
    local function ApplyTalentChoice(player, talent_id)
        local data = deps.EnsurePlayerData(player)
        if talent_id == 1 then
            local val = 25
            data.hp_bonus = (data.hp_bonus or 0) + val
            if player.components.health then
                player.components.health:SetMaxHealth(player.components.health.maxhealth + val)
                player.components.health:DoDelta(val)
            end
            player.rogue_applied_hp_bonus = data.hp_bonus
        elseif talent_id == 2 then
            data.damage_bonus = (data.damage_bonus or 0) + 0.08
        elseif talent_id == 3 then
            data.combo_window_bonus = (data.combo_window_bonus or 0) + 1.5
        elseif talent_id == 4 then
            data.drop_bonus = (data.drop_bonus or 0) + 0.04
        elseif talent_id == 5 then
            data.daily_reward_bonus = (data.daily_reward_bonus or 0) + 0.5
        end
        data.talent_pick_count = (data.talent_pick_count or 0) + 1
        data.talent_pending = false
        data.talent_options = {}
        deps.ApplyGrowthState(player, data, false)
        deps.Announce(player:GetDisplayName() .. " 选择天赋：" .. GetTalentName(talent_id) .. "（" .. GetTalentDesc(talent_id) .. "）")
    end

    -- 应用玩家选择的夜晚补给
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

        -- 函数说明：应用夜间补给的副作用代价，强化“收益-代价”抉择体验。
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

    -- 在夜晚降临时向玩家提供补给选项，并开启自动选择定时器
    local function OfferNightSupply(player, day)
        if not deps.IsValidPlayer(player) then return end
        local data = deps.EnsurePlayerData(player)
        if data.supply_pending or data.talent_pending then return end

        local options = BuildSupplyChoices()
        data.supply_pending = true
        data.supply_options = options
        deps.SyncGrowthNetvars(player, data)

        local s1 = GetSupplyById(options[1])
        local s2 = GetSupplyById(options[2])
        local s3 = GetSupplyById(options[3])
        local f1 = GetSupplyTradeoffFactor(data, options[1])
        local f2 = GetSupplyTradeoffFactor(data, options[2])
        local f3 = GetSupplyTradeoffFactor(data, options[3])
        deps.Announce(player:GetDisplayName() .. " 夜晚补给可选(F1/F2/F3)："
            .. "1." .. s1.name .. "（" .. s1.desc .. "｜代价倍率x" .. string.format("%.2f", f1) .. "） "
            .. "2." .. s2.name .. "（" .. s2.desc .. "｜代价倍率x" .. string.format("%.2f", f2) .. "） "
            .. "3." .. s3.name .. "（" .. s3.desc .. "｜代价倍率x" .. string.format("%.2f", f3) .. "）")

        if player.rogue_supply_auto_task then player.rogue_supply_auto_task:Cancel() end
        player.rogue_supply_auto_task = player:DoTaskInTime(deps.CONST.SUPPLY_AUTO_PICK_DELAY, function()
            if not player:IsValid() then return end
            local d = deps.EnsurePlayerData(player)
            if d.supply_pending and d.supply_options and #d.supply_options > 0 then
                ApplyNightSupply(player, d.supply_options[math.random(#d.supply_options)], day)
            end
        end)
    end

    -- 当玩家击杀数达到阈值时，向玩家提供天赋选择
    local function OfferTalentChoice(player)
        if not deps.IsValidPlayer(player) then return end
        local data = deps.EnsurePlayerData(player)
        if data.talent_pending then return end

        local options = BuildTalentChoices()
        data.talent_pending = true
        data.talent_options = options
        deps.SyncGrowthNetvars(player, data)

        deps.Announce(player:GetDisplayName() .. " 获得天赋抉择，按 F1/F2/F3 选择："
            .. "1." .. GetTalentName(options[1]) .. "（" .. GetTalentDesc(options[1]) .. "） "
            .. "2." .. GetTalentName(options[2]) .. "（" .. GetTalentDesc(options[2]) .. "） "
            .. "3." .. GetTalentName(options[3]) .. "（" .. GetTalentDesc(options[3]) .. "）")

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

    S.OfferNightSupply = OfferNightSupply
    S.CheckTalentTrigger = CheckTalentTrigger
    return S
end

return M
