--[[
    文件说明：event_system.lua
    功能：随机事件系统。
    在波次过程中可能触发的各类随机事件（战斗伏击、资源空投、风险赌局等），为局内增添变数。
]]
local M = {}

function M.Create(deps)
    local S = {}
    local state = { last_event_day = -999, last_category = nil, category_last_day = {}, event_last_day = {} }
    local EVENT_ROTATION_CATEGORY_MODS = {
        [1] = { battle = 1.2, resource = 0.9, risk = 1.05 },
        [2] = { battle = 0.9, resource = 1.2, risk = 0.95 },
        [3] = { battle = 1.0, resource = 0.85, risk = 1.35 },
        [4] = { battle = 1.1, resource = 1.0, risk = 1.1 },
    }

    -- 在玩家附近随机生成指定预制体的实体
    local function SpawnEntityNearPlayer(target, prefab, radius_min, radius_max)
        if not target or not target:IsValid() or (target.components.health and target.components.health:IsDead()) then return nil end
        local resolved = deps.ResolveRuntimePrefab(prefab) or prefab
        local ent = deps.SpawnPrefab(resolved)
        if not ent then return nil end

        -- 移除原版掉落物，优化后期卡顿
        if ent.components and ent.components.lootdropper then
            ent.components.lootdropper.chanceloottable = nil
            ent.components.lootdropper.loot = nil
            ent.components.lootdropper.chanceloot = nil
            ent.components.lootdropper.randomloot = nil
        end

        local pt = target:GetPosition()
        local offset = deps.FindWalkableOffset(pt, math.random() * 2 * deps.PI, radius_min + math.random() * (radius_max - radius_min), 8, true, false)
        ent.Transform:SetPosition((offset and (pt + offset) or pt):Get())
        if ent.components and ent.components.combat then
            ent.components.combat:SetTarget(target)
        end
        return ent
    end

    local function SpawnFromPoolNearPlayer(pool_name, day, target)
        local pool, w = deps.PoolCatalog.GetRuntimePool(pool_name, day)
        local picked = deps.PickWeightedCandidate(pool, w)
        if not picked then return nil end
        return SpawnEntityNearPlayer(target, picked.prefab, 8, 14)
    end

    local function GiveRandomLootToChest(chest, pool_name, day, min_count, max_count)
        if not chest or not chest.components or not chest.components.container then return end
        local pool, w = deps.PoolCatalog.GetRuntimePool(pool_name, day)
        local count = math.random(min_count, max_count)
        for _ = 1, count do
            local picked = deps.PickWeightedCandidate(pool, w)
            if picked then
                local prefab = deps.ResolveRuntimePrefab(picked.prefab) or picked.prefab
                local loot = deps.SpawnPrefab(prefab)
                if loot then
                    chest.components.container:GiveItem(loot)
                end
            end
        end
    end

    local function GetRotationId(players)
        for _, p in ipairs(players or {}) do
            if p and p:IsValid() and deps.EnsurePlayerData then
                local data = deps.EnsurePlayerData(p)
                return data.season_rotation_id or data.season_rotation or 1
            end
        end
        return 1
    end

    local function DoChestRain(day, players)
        deps.Announce("天降横财！宝箱雨来了！")
        local target = deps.PickRandom(players)
        local pt = target:GetPosition()
        for i = 1, 6 do
            target:DoTaskInTime(i * 0.9, function()
                local offset = deps.FindWalkableOffset(pt, math.random() * 2 * deps.PI, math.random() * 7, 10, true, false)
                local spawn_pt = offset and (pt + offset) or pt
                local warn = deps.SpawnPrefab("spawn_fx_medium")
                if warn then warn.Transform:SetPosition(spawn_pt:Get()) end
                target:DoTaskInTime(0.45, function()
                    local chest = deps.SpawnPrefab("treasurechest")
                    if not chest then return end
                    chest.Transform:SetPosition(spawn_pt:Get())
                    chest:AddTag("irreplaceable")
                    chest:DoTaskInTime(120, function(inst) if inst and inst:IsValid() then inst:RemoveTag("irreplaceable") end end)
                    GiveRandomLootToChest(chest, "DROPS_NORMAL", day, 2, 3)
                end)
            end)
        end
    end

    local function DoLuckyPig(day, players)
        deps.Announce("一位带着宝物的幸运猪人路过！")
        local target = deps.PickRandom(players)
        local pig = SpawnEntityNearPlayer(target, "pigman", 9, 12)
        if not pig then return end
        pig.Transform:SetScale(1.5, 1.5, 1.5)
        pig:AddTag("rogue_lucky")
        if pig.components.health then pig.components.health:SetMaxHealth(1000) end
        if pig.components.lootdropper then
            pig.components.lootdropper:SetLoot({})
            local pool, w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_GEAR", day)
            for _ = 1, 3 do
                local loot = deps.PickWeightedCandidate(pool, w)
                if loot then pig.components.lootdropper:AddChanceLoot(loot.prefab, 1.0) end
            end
        end
        pig:DoTaskInTime(45, function()
            if pig:IsValid() then
                local fx = deps.SpawnPrefab("spawn_fx_medium")
                if fx then fx.Transform:SetPosition(pig.Transform:GetWorldPosition()) end
                pig:Remove()
            end
        end)
    end

    local EVENT_DEFS = {
        { id = "battle_ambush_elite", category = "battle", min_day = 3, weight = 8, cooldown = 2, run = function(day, players)
            deps.Announce("遭遇战：精英伏击！")
            local target = deps.PickRandom(players)
            SpawnFromPoolNearPlayer("ENEMIES_ELITE", day, target)
            SpawnFromPoolNearPlayer("ENEMIES_ELITE", day, target)
        end },
        { id = "battle_hound_hunt", category = "battle", min_day = 1, weight = 7, cooldown = 2, run = function(day, players)
            deps.Announce("猎犬围猎：小队来袭！")
            local target = deps.PickRandom(players)
            for _ = 1, math.min(6, 3 + math.floor(day / 15)) do
                SpawnEntityNearPlayer(target, "hound", 7, 13)
            end
        end },
        { id = "battle_shadow_push", category = "battle", min_day = 10, weight = 6, cooldown = 3, run = function(day, players)
            deps.Announce("暗影冲击：梦魇逼近！")
            local target = deps.PickRandom(players)
            for _ = 1, 3 do
                local ent = SpawnEntityNearPlayer(target, "terrorbeak", 8, 14)
                if not ent then
                    SpawnEntityNearPlayer(target, "spider_warrior", 8, 14)
                end
            end
        end },
        { id = "battle_lightning_field", category = "battle", min_day = 8, weight = 6, cooldown = 2, run = function(day, players)
            deps.Announce("雷暴领域：小心落雷！")
            local world = deps.GetWorld and deps.GetWorld()
            if not world then return end
            for i = 1, 4 + math.min(3, math.floor(day / 25)) do
                world:DoTaskInTime(i * 0.5, function()
                    local p = deps.PickRandom(players)
                    if p then
                        local pt = p:GetPosition()
                        local offset = deps.FindWalkableOffset(pt, math.random() * 2 * deps.PI, 3 + math.random() * 7, 8, true, false)
                        world:PushEvent("ms_sendlightningstrike", offset and (pt + offset) or pt)
                    end
                end)
            end
        end },
        { id = "battle_elite_scout", category = "battle", min_day = 12, weight = 6, cooldown = 3, run = function(day, players)
            deps.Announce("侦猎突袭：精英斥候进入战场！")
            for _ = 1, math.min(#players, 2 + math.floor(day / 25)) do
                local target = deps.PickRandom(players)
                SpawnFromPoolNearPlayer("ENEMIES_ELITE", day, target)
            end
        end },
        { id = "battle_mob_rush", category = "battle", min_day = 5, weight = 7, cooldown = 2, run = function(day, players)
            deps.Announce("怪潮前压：普通敌群涌入！")
            local target = deps.PickRandom(players)
            for _ = 1, 4 + math.min(4, math.floor(day / 20)) do
                SpawnFromPoolNearPlayer("ENEMIES_NORMAL", day, target)
            end
        end },
        { id = "resource_chest_rain", category = "resource", min_day = 1, weight = 7, cooldown = 2, run = function(day, players)
            DoChestRain(day, players)
        end },
        { id = "resource_lucky_pig", category = "resource", min_day = 1, weight = 6, cooldown = 2, run = function(day, players)
            DoLuckyPig(day, players)
        end },
        { id = "resource_supply_crate", category = "resource", min_day = 6, weight = 6, cooldown = 2, run = function(day, players)
            deps.Announce("补给空投：战备箱已投放！")
            for _, p in ipairs(players) do
                local chest = SpawnEntityNearPlayer(p, "treasurechest", 2, 5)
                if chest then
                    chest:AddTag("irreplaceable")
                    chest:DoTaskInTime(90, function(inst) if inst and inst:IsValid() then inst:RemoveTag("irreplaceable") end end)
                    GiveRandomLootToChest(chest, "DROPS_NORMAL", day, 1, 2)
                end
            end
        end },
        { id = "resource_material_shower", category = "resource", min_day = 8, weight = 5, cooldown = 2, run = function(day, players)
            deps.Announce("材料喷涌：稀有材料洒落！")
            local pool, w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_MATS", day)
            for _, p in ipairs(players) do
                for _ = 1, 2 + math.min(2, math.floor(day / 30)) do
                    local picked = deps.PickWeightedCandidate(pool, w)
                    if picked then
                        SpawnEntityNearPlayer(p, picked.prefab, 2, 6)
                    end
                end
            end
        end },
        { id = "risk_blood_contract", category = "risk", min_day = 12, weight = 4, cooldown = 3, run = function(day, players)
            deps.Announce("血契交易：失去部分生命，换取高价值战利品！")
            for _, p in ipairs(players) do
                if p.components and p.components.health then
                    p.components.health:DoDelta(-(p.components.health.maxhealth or 100) * 0.12)
                end
                local pool, w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_GEAR", day)
                local picked = deps.PickWeightedCandidate(pool, w)
                if picked then
                    SpawnEntityNearPlayer(p, picked.prefab, 2, 4)
                end
                if deps.OfferRelicChoice and math.random() < 0.28 then
                    deps.OfferRelicChoice(p, "risk", day)
                end
            end
        end },
        { id = "risk_void_gamble", category = "risk", min_day = 15, weight = 4, cooldown = 3, run = function(day, players)
            if math.random() < 0.5 then
                deps.Announce("虚空赌局：你赌赢了，奖励翻倍！")
                for _, p in ipairs(players) do
                    local pool, w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_GEAR", day)
                    for _ = 1, 2 do
                        local picked = deps.PickWeightedCandidate(pool, w)
                        if picked then
                            SpawnEntityNearPlayer(p, picked.prefab, 2, 4)
                        end
                    end
                    if deps.OfferRelicChoice and math.random() < 0.4 then
                        deps.OfferRelicChoice(p, "risk", day)
                    end
                end
            else
                deps.Announce("虚空赌局：你赌输了，精英追猎已开始！")
                for _, p in ipairs(players) do
                    SpawnFromPoolNearPlayer("ENEMIES_ELITE", day, p)
                    SpawnFromPoolNearPlayer("ENEMIES_ELITE", day, p)
                end
            end
        end },
        { id = "risk_chaos_beacon", category = "risk", min_day = 18, weight = 3, cooldown = 4, run = function(day, players)
            deps.Announce("混沌信标：高危追猎与高额回报并存！")
            for _, p in ipairs(players) do
                SpawnFromPoolNearPlayer("ENEMIES_ELITE", day, p)
                SpawnFromPoolNearPlayer("ENEMIES_ELITE", day, p)
                if math.random() < 0.6 then
                    local pool, w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_GEAR", day)
                    local picked = deps.PickWeightedCandidate(pool, w)
                    if picked then
                        SpawnEntityNearPlayer(p, picked.prefab, 2, 5)
                    end
                end
                local mpool, mw = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_MATS", day)
                local mpicked = deps.PickWeightedCandidate(mpool, mw)
                if mpicked then
                    SpawnEntityNearPlayer(p, mpicked.prefab, 2, 5)
                end
                if deps.OfferRelicChoice and math.random() < 0.45 then
                    deps.OfferRelicChoice(p, "risk", day)
                end
            end
        end },
    }

    local function PickEvent(day, players)
        local candidates = {}
        local total = 0
        local rotation_id = GetRotationId(players)
        local cat_mod = EVENT_ROTATION_CATEGORY_MODS[rotation_id] or {}
        for _, ev in ipairs(EVENT_DEFS) do
            local ok_day = day >= (ev.min_day or 1) and (not ev.max_day or day <= ev.max_day)
            local event_cd = state.event_last_day[ev.id]
            local in_event_cd = event_cd and day - event_cd < (ev.cooldown or 0)
            local cat_last = state.category_last_day[ev.category]
            local in_cat_cd = cat_last and day - cat_last < 1
            if ok_day and not in_event_cd and not in_cat_cd then
                local adjusted_weight = (ev.weight or 1) * (cat_mod[ev.category] or 1)
                if adjusted_weight < 0.2 then
                    adjusted_weight = 0.2
                end
                table.insert(candidates, ev)
                total = total + adjusted_weight
                ev.__event_adj_weight = adjusted_weight
            end
        end
        if #candidates == 0 then return nil end
        local roll = math.random() * total
        local acc = 0
        for _, ev in ipairs(candidates) do
            acc = acc + (ev.__event_adj_weight or ev.weight or 1)
            if roll <= acc then return ev end
        end
        return candidates[#candidates]
    end

    local function TriggerRandomEvent(day)
        local players = deps.CollectAlivePlayers()
        if #players == 0 then return end
        local ev = PickEvent(day, players)
        if not ev then return end
        state.last_event_day = day
        state.last_category = ev.category
        state.event_last_day[ev.id] = day
        state.category_last_day[ev.category] = day
        ev.run(day, players)
    end

    S.TriggerRandomEvent = TriggerRandomEvent
    return S
end

return M
