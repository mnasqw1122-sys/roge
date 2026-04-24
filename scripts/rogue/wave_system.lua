--[[
    文件说明：wave_system.lua
    功能：肉鸽模式的核心波次管理系统。
    负责控制每日波次的启动与结束，决定波次类型（普通/休息/Boss），生成各类敌人（普通、精英、Boss），
    以及管理区域路线投票、悬赏和挑战房等波次专属事件。
]]
local M = {}
local WaveBossCompatModule = require("rogue/wave_boss_compat")

function M.Create(deps)
    local S = {}
    local wave_active = false
    local wave_task = nil
    local wave_state = { used_bosses = {}, current_rule = nil, bounty = nil, challenge = nil, route_active = nil, route_pending_day = nil, route_runtime = nil, route_drop_bonus = 0, route_votes = nil, route_vote_task = nil, threat_tier = 1, threat_reward_pct = 0, threat_runtime = nil, threat_drop_bonus = 0 }
    local BossCompatController = WaveBossCompatModule.Create(deps)
    
    -- 获取当前世界对象
    local function GetWorld()
        return (deps.GetWorld and deps.GetWorld()) or deps.TheWorld
    end

    local function CloneTable(src)
        if type(src) ~= "table" then
            return nil
        end
        local out = {}
        for k, v in pairs(src) do
            if type(v) == "table" then
                local inner = {}
                for k2, v2 in pairs(v) do
                    inner[k2] = v2
                end
                out[k] = inner
            else
                out[k] = v
            end
        end
        return out
    end

    local function FindDefById(list, id)
        local nid = tonumber(id)
        if not nid then
            return nil
        end
        for _, def in ipairs(list or {}) do
            if def.id == nid then
                return def
            end
        end
        return nil
    end

    -- 将波次状态（悬赏、挑战等）同步到玩家的网络变量
    local function SyncWaveStateToPlayer(player)
        if not player or not player:IsValid() then return end
        local data = deps.EnsurePlayerData(player)
        data.wave_rule_active = wave_state.current_rule ~= nil
        data.wave_rule_id = wave_state.current_rule and wave_state.current_rule.id or 0
        data.threat_tier = wave_state.threat_tier or 1
        data.threat_reward_pct = wave_state.threat_reward_pct or 0
        data.route_id = wave_state.route_active and wave_state.route_active.id or 0
        data.route_pending = wave_state.route_pending_day ~= nil and wave_state.route_active == nil
        data.route_options = wave_state.route_active == nil and wave_state.route_pending_day ~= nil and {
            (wave_state.route_offer and wave_state.route_offer[1] and wave_state.route_offer[1].id) or 0,
            (wave_state.route_offer and wave_state.route_offer[2] and wave_state.route_offer[2].id) or 0,
        } or {}
        data.bounty_active = wave_state.bounty and (wave_state.bounty.completed ~= true) or false
        data.bounty_progress = wave_state.bounty and (wave_state.bounty.killed or 0) or 0
        data.bounty_target = wave_state.bounty and (wave_state.bounty.target or 0) or 0
        data.challenge_active = wave_state.challenge and (wave_state.challenge.completed ~= true) or false
        data.challenge_progress = wave_state.challenge and (wave_state.challenge.progress or 0) or 0
        data.challenge_target = wave_state.challenge and (wave_state.challenge.target or 0) or 0
        data.challenge_kind = wave_state.challenge and (wave_state.challenge.kind or 0) or 0
        deps.SyncGrowthNetvars(player, data)
    end

    -- 同步所有存活玩家的波次状态
    local function SyncWaveStateToAllPlayers()
        for _, p in ipairs(deps.AllPlayers) do
            SyncWaveStateToPlayer(p)
        end
    end

    -- 随机抽取波次规则
    local function PickWaveRule()
        local total = 0
        for _, rule in ipairs(deps.WAVE_RULE_DEFS) do
            total = total + (rule.weight or 1)
        end
        local roll = math.random() * total
        local acc = 0
        for _, rule in ipairs(deps.WAVE_RULE_DEFS) do
            acc = acc + (rule.weight or 1)
            if roll <= acc then return rule end
        end
        return deps.WAVE_RULE_DEFS[1]
    end

    local function RollWaveRule(day)
        local chance = math.min(deps.CONST.WAVE_RULE_MAX_CHANCE, deps.CONST.WAVE_RULE_BASE_CHANCE + math.floor((day - 1) / 20) * 0.05)
        if math.random() > chance then
            return nil
        end
        return PickWaveRule()
    end

    local function GetRotationId(players)
        for _, p in ipairs(players or {}) do
            if p and p:IsValid() then
                local data = deps.EnsurePlayerData(p)
                return data.season_rotation_id or data.season_rotation or 1
            end
        end
        return 1
    end

    -- 函数说明：根据存活玩家数量返回 Boss HP 缩放系数
    -- 优化：独立的 HP 倍率曲线，多人时提供更大的生命值挑战
    local function GetPlayerHPScale(count)
        if count <= 1 then return 1.0
        elseif count == 2 then return 1.6
        elseif count == 3 then return 2.2
        elseif count == 4 then return 2.8
        end
        return 3.3
    end

    -- 函数说明：根据天数、队伍生命状态与赛季轮换偏置计算当前波次危险阶梯。
    local function BuildThreatRuntime(day, players)
        local rotation_id = GetRotationId(players)
        local mod = (deps.THREAT_ROTATION_MODS and deps.THREAT_ROTATION_MODS[rotation_id]) or nil
        local tier = 1
        if day >= 52 then
            tier = 3
        elseif day >= 22 then
            tier = 2
        end
        local hp_sum = 0
        local hp_cnt = 0
        for _, p in ipairs(players or {}) do
            if p and p.components and p.components.health and p.components.health.maxhealth > 0 then
                hp_sum = hp_sum + p.components.health.currenthealth / p.components.health.maxhealth
                hp_cnt = hp_cnt + 1
            end
        end
        local avg_hp = hp_cnt > 0 and (hp_sum / hp_cnt) or 0.7
        if mod and mod.base_shift then
            avg_hp = avg_hp + mod.base_shift
        end
        if avg_hp >= 0.82 then
            tier = math.min(3, tier + 1)
        elseif avg_hp <= 0.35 then
            tier = math.max(1, tier - 1)
        end
        if mod and mod.hp_shift then
            if mod.hp_shift > 0 then
                tier = math.min(3, tier + 1)
            elseif mod.hp_shift < 0 then
                tier = math.max(1, tier - 1)
            end
        end
        if mod and mod.floor_tier then
            tier = math.max(mod.floor_tier, tier)
        end
        if mod and mod.ceil_tier then
            tier = math.min(mod.ceil_tier, tier)
        end
        local reward_pct = tier == 1 and 0 or (tier == 2 and 3 or 7)
        if mod and mod.reward_shift then
            reward_pct = math.max(0, reward_pct + mod.reward_shift)
        end
        return {
            rotation_id = rotation_id,
            tier = tier,
            reward_pct = reward_pct,
            hp_mult = tier == 1 and 1.00 or (tier == 2 and 1.10 or 1.22),
            dmg_mult = tier == 1 and 1.00 or (tier == 2 and 1.08 or 1.18),
            spawn_period_mult = tier == 1 and 1.00 or (tier == 2 and 0.92 or 0.84),
            drop_bonus = reward_pct / 100,
        }
    end

    local function PickWeightedRoute(exclude_id)
        local defs = deps.REGION_ROUTE_DEFS or {}
        local total = 0
        for _, def in ipairs(defs) do
            if def.id ~= exclude_id then
                total = total + (def.weight or 1)
            end
        end
        if total <= 0 then
            return nil
        end
        local roll = math.random() * total
        local acc = 0
        for _, def in ipairs(defs) do
            if def.id ~= exclude_id then
                acc = acc + (def.weight or 1)
                if roll <= acc then
                    return def
                end
            end
        end
        return defs[1]
    end

    local function BuildRouteOffer()
        local a = PickWeightedRoute(nil)
        local b = PickWeightedRoute(a and a.id or nil)
        if not a or not b then
            return nil
        end
        return { a, b }
    end

    local function PickRouteForPlayers(offer, players)
        if not offer or #offer < 2 then
            return nil
        end
        local alive = players or {}
        local hp_sum = 0
        local hp_cnt = 0
        for _, p in ipairs(alive) do
            if p and p.components and p.components.health and p.components.health.maxhealth > 0 then
                hp_sum = hp_sum + p.components.health.currenthealth / p.components.health.maxhealth
                hp_cnt = hp_cnt + 1
            end
        end
        local avg_hp = hp_cnt > 0 and (hp_sum / hp_cnt) or 0.7
        if avg_hp <= 0.45 then
            local a_score = (offer[1].enemy_hp_mult or 1) + (offer[1].enemy_dmg_mult or 1)
            local b_score = (offer[2].enemy_hp_mult or 1) + (offer[2].enemy_dmg_mult or 1)
            return a_score <= b_score and offer[1] or offer[2]
        end
        if avg_hp >= 0.8 then
            local a_score = (offer[1].drop_bonus or 0) + (offer[1].enemy_hp_mult or 1) + (offer[1].enemy_dmg_mult or 1)
            local b_score = (offer[2].drop_bonus or 0) + (offer[2].enemy_hp_mult or 1) + (offer[2].enemy_dmg_mult or 1)
            return a_score >= b_score and offer[1] or offer[2]
        end
        return offer[math.random(1, 2)]
    end

    local function ApplyRouteChoice(route, day)
        if not route then
            return
        end
        wave_state.route_active = route
        wave_state.route_pending_day = day + 1
        wave_state.route_offer = nil
        wave_state.route_votes = nil
        if wave_state.route_vote_task then
            wave_state.route_vote_task:Cancel()
            wave_state.route_vote_task = nil
        end
        for _, p in ipairs(deps.AllPlayers) do
            if p and p:IsValid() then
                local data = deps.EnsurePlayerData(p)
                data.season_route_pick_counts = data.season_route_pick_counts or {}
                local rid = route.id or 0
                data.season_route_pick_counts[rid] = (data.season_route_pick_counts[rid] or 0) + 1
            end
        end
        deps.Announce("路线已锁定：" .. route.name .. "，将在明日生效。")
        SyncWaveStateToAllPlayers()
    end

    local function GetRouteVoteResult(players)
        if not wave_state.route_offer or not wave_state.route_votes then
            return nil, 0, 0
        end
        local counts = { 0, 0 }
        for _, idx in pairs(wave_state.route_votes) do
            if idx == 1 or idx == 2 then
                counts[idx] = counts[idx] + 1
            end
        end
        if counts[1] == counts[2] then
            return nil, counts[1], counts[2]
        end
        return wave_state.route_offer[counts[1] > counts[2] and 1 or 2], counts[1], counts[2]
    end

    local function PickChallengeForDay(day, threat_tier)
        local chance = math.min(0.62, deps.CONST.CHALLENGE_BASE_CHANCE + math.floor((day - 1) / 25) * 0.05)
        if math.random() > chance then
            return nil
        end
        local tier = math.max(1, math.min(3, threat_tier or 1))
        local kind = (math.random() < 0.22) and 3 or math.random(1, 2)
        local target = 0
        if kind == 1 then
            target = math.min(40, 9 + math.floor(day * 0.6))
        elseif kind == 2 then
            target = math.min(3, 1 + math.floor((day - 1) / 18))
        else
            target = 1
        end
        local mult = tier == 1 and 1.0 or (tier == 2 and 1.15 or 1.3)
        target = math.max(1, math.floor(target * mult + 0.5))
        return { kind = kind, target = target, progress = 0, completed = false, rewarded = false, trial_spawned = false }
    end

    local function RewardChallenge(day)
        if not wave_state.challenge or wave_state.challenge.rewarded then return end
        wave_state.challenge.rewarded = true
        wave_state.challenge.completed = true
        local threat_tier = wave_state.threat_tier or 1
        for _, player in ipairs(deps.CollectAlivePlayers()) do
            deps.ApplyBuff(player, false)
            if deps.ProgressDailyTaskOnChallengeReward then
                deps.ProgressDailyTaskOnChallengeReward(player, day)
            end
            local route = wave_state.route_runtime
            local reward_times = (day >= 35 and 2 or 1) + (route and (route.gear_roll_bonus or 0) or 0) + (threat_tier - 1)
            for i = 1, reward_times do
                local should_drop = i == 1 and (day >= 12 or math.random() < 0.5) or (math.random() < 0.3)
                if should_drop then
                    local pool, w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_GEAR", day)
                    local item = deps.PickWeightedCandidate(pool, w)
                    if item then
                        deps.SpawnDrop(player, item.prefab)
                    end
                end
            end
            if deps.OfferRelicChoice and math.random() < ((day >= 30 and 0.45 or 0.3) + 0.08 * (threat_tier - 1)) then
                deps.OfferRelicChoice(player, "challenge", day)
            end
            if deps.OnSeasonChallengeReward then
                deps.OnSeasonChallengeReward(player, day)
            end
        end
        deps.Announce("挑战房奖励已发放！(危险阶梯" .. tostring(threat_tier) .. ")")
    end

    local function ProgressChallenge(kind, add, day)
        if not wave_state.challenge or wave_state.challenge.completed then return end
        if wave_state.challenge.kind ~= kind or add <= 0 then return end
        wave_state.challenge.progress = math.min(wave_state.challenge.target or 0, (wave_state.challenge.progress or 0) + add)
        if wave_state.challenge.progress >= (wave_state.challenge.target or 0) then
            RewardChallenge(day)
        end
        SyncWaveStateToAllPlayers()
    end

    local function PickWaveBounty(day, threat_tier)
        local pool, w = deps.PoolCatalog.GetRuntimePool("ENEMIES_ELITE", day)
        local picked = deps.PickWeightedCandidate(pool, w)
        if not picked then return nil end
        local tier = math.max(1, math.min(3, threat_tier or 1))
        local prefab = deps.ResolveRuntimePrefab(picked.prefab) or picked.prefab
        local target = math.min(5, (1 + math.floor((day - 1) / 24)) + (tier - 1))
        return { prefab = prefab, name = picked.prefab or prefab, target = target, killed = 0, completed = false, spawned = 0 }
    end

    local function RewardBounty(player, day)
        if not deps.IsValidPlayer(player) then return end
        deps.ApplyBuff(player, false)
        local threat_tier = wave_state.threat_tier or 1
        if deps.ProgressDailyTaskOnBountyReward then
            deps.ProgressDailyTaskOnBountyReward(player, day)
        end
        if deps.OnSeasonBountyReward then
            deps.OnSeasonBountyReward(player, day)
        end
        local mat_pool, mat_w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_MATS", day)
        local route = wave_state.route_runtime
        local reward_count = 1 + (day >= 35 and 1 or 0) + (route and (route.mat_bonus or 0) or 0) + (threat_tier - 1)
        for _ = 1, reward_count do
            local item = mat_pool and deps.PickWeightedCandidate(mat_pool, mat_w)
            if item then
                deps.SpawnDrop(player, item.prefab)
            end
        end
        if threat_tier >= 2 then
            local pool, w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_GEAR", day)
            local extra = deps.PickWeightedCandidate(pool, w)
            if extra and math.random() < (threat_tier == 2 and 0.35 or 0.6) then
                deps.SpawnDrop(player, extra.prefab)
            end
        end
        deps.Announce(player:GetDisplayName() .. " 完成通缉精英，领取了悬赏奖励！(危险阶梯" .. tostring(threat_tier) .. ")")
    end

    local function EndWave()
        if not wave_active then return end
        wave_active = false
        local world = GetWorld()
        if wave_task then wave_task:Cancel(); wave_task = nil end
        
        local day = world and world.state and (world.state.cycles + 1) or 1
        local is_rest_day = deps.Config.BOSS_INTERVAL > 1 and (day % deps.Config.BOSS_INTERVAL == deps.Config.BOSS_INTERVAL - 1)
        local is_boss_wave = deps.Config.BOSS_INTERVAL > 0 and (day % deps.Config.BOSS_INTERVAL == 0)
        
        if is_rest_day then
            deps.Announce("休息天结束。好好准备迎接明天的战斗吧！")
            if deps.Config.AI_NPC_ENABLED and world.components.rogue_ai_npc_manager then
                world.components.rogue_ai_npc_manager:OnRestDayEnd()
            end
        else
            deps.Announce("波次结束！今晚暂时安全了。")
        end
        
        if is_boss_wave then
            local offer = BuildRouteOffer()
            if offer then
                wave_state.route_offer = offer
                wave_state.route_pending_day = day + 1
                wave_state.route_active = nil
                wave_state.route_votes = {}
                deps.Announce("区域抉择投票(F1/F2)：" .. offer[1].name .. "（" .. offer[1].desc .. "） vs " .. offer[2].name .. "（" .. offer[2].desc .. "）")
                local world_time = GetWorld()
                if wave_state.route_vote_task then
                    wave_state.route_vote_task:Cancel()
                    wave_state.route_vote_task = nil
                end
                if world_time then
                    wave_state.route_vote_task = world_time:DoTaskInTime(12, function()
                        wave_state.route_vote_task = nil
                        if wave_state.route_offer and wave_state.route_active == nil then
                            local alives = deps.CollectAlivePlayers()
                            local voted_route = GetRouteVoteResult(alives)
                            local auto = PickRouteForPlayers(offer, alives)
                            ApplyRouteChoice(voted_route or auto or offer[1], day)
                        end
                    end)
                end
            end
        end
        for _, player in ipairs(deps.CollectAlivePlayers()) do
            if deps.ProgressDailyTaskOnWaveEnd then
                deps.ProgressDailyTaskOnWaveEnd(player, day)
            end
            if not is_boss_wave then
                deps.OfferNightSupply(player, day)
            end
        end
        if wave_state.route_runtime then
            -- 清理路线效果
            for _, p in ipairs(deps.CollectAlivePlayers()) do
                if p and p:IsValid() then
                    -- 移除移动速度提升
                    if p.components and p.components.locomotor then
                        p.components.locomotor:RemoveExternalSpeedMultiplier(p, "rogue_route_speed")
                    end
                    -- 移除生命恢复任务
                    if p._rogue_route_regen_task then
                        p._rogue_route_regen_task:Cancel()
                        p._rogue_route_regen_task = nil
                    end
                end
            end
            wave_state.route_runtime = nil
            wave_state.route_active = nil
            wave_state.route_pending_day = nil
            wave_state.route_drop_bonus = 0
            wave_state.route_offer = nil
            wave_state.route_votes = nil
            if wave_state.route_vote_task then
                wave_state.route_vote_task:Cancel()
                wave_state.route_vote_task = nil
            end
        end
        wave_state.current_rule = nil
        wave_state.bounty = nil
        wave_state.challenge = nil
        SyncWaveStateToAllPlayers()
        if world and math.random() < 0.12 then
            world:DoTaskInTime(5, function() deps.TriggerRandomEvent(day) end)
        end
    end

    local function PickBossForWave(day)
        local pool, w = deps.PoolCatalog.GetRuntimePool("BOSSES", day)
        local c = {}
        local c_w = 0
        for _, b in ipairs(pool) do
            if not wave_state.used_bosses[b.prefab] then
                table.insert(c, b)
                c_w = c_w + (b.weight or 10)
            end
        end
        if #c == 0 then
            wave_state.used_bosses = {}
            c = pool
            c_w = w
        end
        local picked = deps.PickWeightedCandidate(c, c_w)
        if picked then wave_state.used_bosses[picked.prefab] = true end
        return picked
    end

    -- 附加挑战房 Boss 超时消失逻辑（如果一定时间内无玩家攻击，则消失）
    local function AttachTrialBossTimeout(ent)
        BossCompatController.AttachTrialBossTimeout(ent)
    end

    -- 应用 Boss 兼容性修复（解决部分 Boss 无法正常刷新或脱战的问题）
    local function ApplyBossCompatibility(ent, is_trial_boss)
        BossCompatController.ApplyBossCompatibility(ent, is_trial_boss)
    end

    -- 生成敌人（普通怪物、精英、或 Boss）
    local function SpawnEnemy(player, is_boss, day, opts)
        opts = opts or {}
        if not deps.IsValidPlayer(player) then return end
        if not is_boss and deps.IsSpawnAreaBusy(player) then return end
        local pt = player:GetPosition()
        local offset = deps.FindWalkableOffset(pt, math.random() * 2 * deps.PI, 15, 8, true, false)
        if not offset then return end
        local spawn_pt = pt + offset
        local candidate
        local is_elite = false
        if is_boss then
            candidate = PickBossForWave(day)
        else
            if wave_state.bounty and not wave_state.bounty.completed and (wave_state.bounty.spawned or 0) < (wave_state.bounty.target or 1) then
                candidate = { prefab = wave_state.bounty.prefab }
                is_elite = true
                wave_state.bounty.spawned = (wave_state.bounty.spawned or 0) + 1
            end
            if not candidate then
                local rule_bonus = wave_state.current_rule and wave_state.current_rule.elite_bonus or 0
                local route_bonus = wave_state.route_runtime and (wave_state.route_runtime.elite_bonus or 0) or 0
                local elite_chance = math.min(deps.CONST.MAX_ELITE_CHANCE, deps.Config.ELITE_CHANCE + math.floor((day - 1) / 25) * 0.02 + rule_bonus + route_bonus)
                if math.random() < elite_chance then
                    local pool, w = deps.PoolCatalog.GetRuntimePool("ENEMIES_ELITE", day)
                    candidate = deps.PickWeightedCandidate(pool, w)
                    is_elite = true
                end
            end
            if not candidate then
                local pool, w = deps.PoolCatalog.GetRuntimePool("ENEMIES_NORMAL", day)
                candidate = deps.PickWeightedCandidate(pool, w)
            end
        end
        if not candidate then return end
        local count = 1
        if not is_boss and candidate.count then
            count = math.random(candidate.count[1], candidate.count[2])
        end
        for i = 1, count do
            local resolved_prefab = deps.ResolveRuntimePrefab(candidate.prefab) or candidate.prefab
            if not deps.IsPrefabRegistered(resolved_prefab) then
                if deps.Config.DEBUG_MODE then
                    print("SpawnEnemy: invalid prefab " .. tostring(candidate.prefab))
                end
                return
            end
            local ent = deps.SpawnPrefab(resolved_prefab)
            if ent then
                -- 移除原版掉落物，优化后期卡顿
                if ent.components.lootdropper then
                    ent.components.lootdropper.chanceloottable = nil
                    ent.components.lootdropper.loot = nil
                    ent.components.lootdropper.chanceloot = nil
                    ent.components.lootdropper.randomloot = nil
                end

                if is_boss then
                    ent:AddTag("rogue_wave_boss")
                    if opts.trial_boss then
                        ent:AddTag("rogue_trial_boss")
                        AttachTrialBossTimeout(ent)
                    end
                    ent.rogue_boss_loot_key = candidate.prefab
                    ApplyBossCompatibility(ent, opts.trial_boss == true)
                end
                local pos = spawn_pt
                if i > 1 then
                    local sub_offset = deps.FindWalkableOffset(spawn_pt, math.random() * 2 * deps.PI, math.random() * 3, 8, true, false)
                    if sub_offset then pos = spawn_pt + sub_offset end
                end
                ent.Transform:SetPosition(pos:Get())
                if ent.components.health then
                    if is_boss then
                        local pc = #deps.CollectAlivePlayers()
                        local hp = 0
                        if opts.trial_boss then
                            local step = math.floor((day - 1) / (deps.CONST.TRIAL_BOSS_HP_STEP_DAYS or 20))
                            hp = 4500 * GetPlayerHPScale(pc) * (deps.CONST.TRIAL_BOSS_HP_MULT or 0.78) * (1 + step * (deps.CONST.TRIAL_BOSS_HP_STEP_MULT or 0.12))
                        else
                            hp = 4500 * GetPlayerHPScale(pc) * (1 + math.floor((day - 1) / 30) * 0.2)
                        end
                        ent.components.health:SetMaxHealth(hp)
                        if not opts.trial_boss and math.random() < 0.35 then
                            ent:AddTag("rogue_elite")
                            if ent.components.combat then ent.components.combat:SetDefaultDamage(ent.components.combat.defaultdamage * 1.12) end
                        end
                        local affixed = false
                        if opts.trial_boss then
                            if ent.components.combat and ent.components.combat.defaultdamage then
                                ent.components.combat:SetDefaultDamage(ent.components.combat.defaultdamage * (deps.CONST.TRIAL_BOSS_DMG_MULT or 0.92))
                            end
                            if math.random() < (deps.CONST.TRIAL_BOSS_AFFIX_CHANCE or 0.58) then
                                affixed = deps.ApplyEliteAffix(ent, day, true)
                            end
                            if ent.components.colouradder then
                                ent.components.colouradder:PushColour("rogue_trial_boss", 0.18, 0.06, 0.28, 0)
                            else
                                ent.AnimState:SetMultColour(0.82, 0.65, 1, 1)
                            end
                        else
                            affixed = deps.ApplyEliteAffix(ent, day, day >= 25)
                            deps.SetupBossPhases(ent, day)
                        end
                        if affixed and deps.Config.AFFIX_ANNOUNCE_MODE >= 1 and i == 1 then
                            if opts.trial_boss then
                                deps.Announce("〖试炼词缀〗" .. deps.GetEntityName(ent) .. "【" .. (ent.rogue_affix_name or "") .. "】")
                            else
                                deps.Announce("Boss词缀化：" .. deps.GetEntityName(ent) .. "【" .. (ent.rogue_affix_name or "") .. "】")
                            end
                        end
                    else
                        if is_elite or ent:HasTag("rogue_elite") or math.random() < 0.2 then
                            ent.components.health:SetMaxHealth(math.random(150, 350))
                            deps.ApplyEliteAffix(ent, day, false)
                            if ent.rogue_affix_name and deps.Config.AFFIX_ANNOUNCE_MODE == 1 and i == 1 then
                                deps.Announce("精英出现：" .. deps.GetEntityName(ent) .. "【" .. ent.rogue_affix_name .. "】")
                            end
                            ent:AddTag("rogue_elite")
                            if wave_state.bounty and not wave_state.bounty.completed and ent.prefab == wave_state.bounty.prefab then
                                ent:AddTag("rogue_bounty_target")
                            end
                        else
                            ent.components.health:SetMaxHealth(math.random(50, 120))
                        end
                    end
                    if wave_state.current_rule and not is_boss then
                        local hp_mult = wave_state.current_rule.hp_mult or 1
                        if hp_mult ~= 1 then
                            ent.components.health:SetMaxHealth(ent.components.health.maxhealth * hp_mult)
                        end
                    end
                    if wave_state.route_runtime and not is_boss then
                        local hp_mult = wave_state.route_runtime.enemy_hp_mult or 1
                        if hp_mult ~= 1 then
                            ent.components.health:SetMaxHealth(ent.components.health.maxhealth * hp_mult)
                        end
                    end
                    if wave_state.threat_runtime and ent.components.health.maxhealth then
                        local hp_mult = wave_state.threat_runtime.hp_mult or 1
                        if hp_mult ~= 1 then
                            ent.components.health:SetMaxHealth(ent.components.health.maxhealth * hp_mult)
                        end
                    end
                    ent.components.health:SetPercent(1)
                end
                if ent.components.combat then
                    if wave_state.current_rule and not is_boss and ent.components.combat.defaultdamage then
                        local dmg_mult = wave_state.current_rule.dmg_mult or 1
                        if dmg_mult ~= 1 then
                            ent.components.combat:SetDefaultDamage(ent.components.combat.defaultdamage * dmg_mult)
                        end
                    end
                    if wave_state.route_runtime and not is_boss and ent.components.combat.defaultdamage then
                        local dmg_mult = wave_state.route_runtime.enemy_dmg_mult or 1
                        if dmg_mult ~= 1 then
                            ent.components.combat:SetDefaultDamage(ent.components.combat.defaultdamage * dmg_mult)
                        end
                    end
                    if wave_state.threat_runtime and ent.components.combat.defaultdamage then
                        local dmg_mult = wave_state.threat_runtime.dmg_mult or 1
                        if dmg_mult ~= 1 then
                            ent.components.combat:SetDefaultDamage(ent.components.combat.defaultdamage * dmg_mult)
                        end
                    end
                    ent.components.combat:SetTarget(player)
                end
            end
        end
    end

    local function StartWave(day, opts)
        opts = opts or {}
        if wave_active and opts.force_restart then
            EndWave()
        elseif wave_active then
            return
        end
        local world = GetWorld()
        if not world then return end
        local players = deps.CollectAlivePlayers()
        if #players == 0 then return end
        wave_active = true
        
        local is_boss_wave = deps.Config.BOSS_INTERVAL > 0 and (day % deps.Config.BOSS_INTERVAL == 0)
        local is_rest_day = deps.Config.BOSS_INTERVAL > 1 and (day % deps.Config.BOSS_INTERVAL == deps.Config.BOSS_INTERVAL - 1)
        
        if opts.force_non_boss then
            is_boss_wave = false
            is_rest_day = false
        elseif opts.force_boss then
            is_boss_wave = true
            is_rest_day = false
        end
        
        wave_state.route_runtime = (wave_state.route_active and wave_state.route_pending_day == day and not is_rest_day) and wave_state.route_active or nil
        wave_state.route_drop_bonus = wave_state.route_runtime and (wave_state.route_runtime.drop_bonus or 0) or 0
        wave_state.threat_runtime = is_rest_day and nil or BuildThreatRuntime(day, players)
        wave_state.threat_tier = (wave_state.threat_runtime and wave_state.threat_runtime.tier) or 1
        wave_state.threat_reward_pct = (wave_state.threat_runtime and wave_state.threat_runtime.reward_pct) or 0
        wave_state.threat_drop_bonus = (wave_state.threat_runtime and wave_state.threat_runtime.drop_bonus) or 0
        wave_state.current_rule = (is_boss_wave or is_rest_day) and nil or RollWaveRule(day)
        wave_state.bounty = (is_boss_wave or is_rest_day) and nil or PickWaveBounty(day, wave_state.threat_tier)
        wave_state.challenge = is_rest_day and nil or PickChallengeForDay(day, wave_state.threat_tier)
        if wave_state.bounty or wave_state.challenge then
            for _, p in ipairs(deps.AllPlayers) do
                if p and p:IsValid() then
                    local data = deps.EnsurePlayerData(p)
                    if wave_state.challenge then
                        data.season_challenge_total = (data.season_challenge_total or 0) + 1
                    end
                    if wave_state.bounty then
                        data.season_bounty_total = (data.season_bounty_total or 0) + 1
                    end
                end
            end
        end
        SyncWaveStateToAllPlayers()
        
        if is_rest_day then
            deps.Announce("第 " .. day .. " 天: 休息天！暴风雨前的宁静。今天没有敌人来袭。")
            
            -- AI NPC 刷新逻辑
            if deps.Config.AI_NPC_ENABLED then
                local current_world = GetWorld()
                if current_world and current_world.components.rogue_ai_npc_manager then
                    current_world.components.rogue_ai_npc_manager:TrySpawnNPC(day, players)
                end
            end
            
            return
        end
        
        deps.Announce("第 " .. day .. " 天: " .. (is_boss_wave and "BOSS 来袭！" or "敌人正在逼近！"))
        if wave_state.threat_runtime then
            deps.Announce("危险阶梯：" .. tostring(wave_state.threat_tier) .. "级（奖励+" .. tostring(wave_state.threat_reward_pct) .. "%，轮换偏置#" .. tostring(wave_state.threat_runtime.rotation_id or 1) .. "）")
        end
        if wave_state.route_runtime then
            deps.Announce("当前路线：" .. wave_state.route_runtime.name .. "（" .. wave_state.route_runtime.desc .. "）")
            for _, p in ipairs(players) do
                if wave_state.route_runtime.heal_pct and p.components and p.components.health then
                    p.components.health:DoDelta(p.components.health.maxhealth * wave_state.route_runtime.heal_pct)
                end
                if wave_state.route_runtime.sanity_bonus and p.components and p.components.sanity then
                    p.components.sanity:DoDelta(wave_state.route_runtime.sanity_bonus)
                end
                if wave_state.route_runtime.hp_cost_pct and p.components and p.components.health then
                    p.components.health:DoDelta(-p.components.health.maxhealth * wave_state.route_runtime.hp_cost_pct, nil, "rogue_route_cost")
                end
                if wave_state.route_runtime.speed_bonus and p.components and p.components.locomotor then
                    p.components.locomotor:SetExternalSpeedMultiplier(p, "rogue_route_speed", 1 + wave_state.route_runtime.speed_bonus)
                end
                if wave_state.route_runtime.regen_bonus and p.components and p.components.health then
                    -- 生命恢复速度提升
                    if not p._rogue_route_regen_task then
                        p._rogue_route_regen_task = p:DoPeriodicTask(1, function()
                            if p and p:IsValid() and p.components.health and not p.components.health:IsDead() then
                                p.components.health:DoDelta(1 * wave_state.route_runtime.regen_bonus)
                            end
                        end)
                    end
                end
            end
        end
        if wave_state.current_rule then
            deps.Announce("轮次事件：" .. wave_state.current_rule.name .. "（" .. wave_state.current_rule.desc .. "）")
        end
        if wave_state.bounty then
            deps.Announce("通缉精英：" .. tostring(wave_state.bounty.name) .. "，击杀 " .. tostring(wave_state.bounty.target) .. " 只后获得额外奖励！")
        end
        if wave_state.challenge then
            deps.Announce("挑战房：" .. (deps.CHALLENGE_KIND_NAMES[wave_state.challenge.kind] or "未知挑战") .. " " .. wave_state.challenge.target .. " 次（危险阶梯" .. tostring(wave_state.threat_tier) .. "）")
            if wave_state.challenge.kind == 3 and not wave_state.challenge.trial_spawned then
                wave_state.challenge.trial_spawned = true
                world:DoTaskInTime(1.2, function()
                    if not wave_active then return end
                    local p = deps.PickRandom(deps.CollectAlivePlayers())
                    if p then
                        SpawnEnemy(p, true, day, { trial_boss = true })
                        deps.Announce("〖紫晶试炼〗试炼Boss已出现！")
                    end
                end)
            end
        end
        if is_boss_wave then
            local count = math.max(1, #players) + math.floor((day - 1) / 30)
            for i = 1, count do
                world:DoTaskInTime(i * 0.5, function()
                    if wave_active then SpawnEnemy(deps.PickRandom(deps.CollectAlivePlayers()), true, day) end
                end)
            end
        else
            local function GetDynamicSpawnPeriod()
                -- 优化：基于天数的初始刷新时间
                local base_period = day <= 10 and math.max(4.0, 12 - day * 0.4) or (day <= 30 and math.max(2.5, 10 - (day - 10) * 0.3) or math.max(1.5, 6 - (day - 30) * 0.1))
                
                -- 多人动态平衡：因为生成时是“每个玩家”都会刷出一只怪，所以总刷怪量是成倍增加的。
                -- 为了防止瞬间卡顿，略微延长每次刷新的间隔，但大幅降低系数并设置上限，确保人多时怪也绝对够打。
                local alives_count = #deps.CollectAlivePlayers()
                if alives_count > 1 then
                    base_period = base_period * math.min(1.8, 1 + (alives_count - 1) * 0.15)
                end

                if wave_state.current_rule and wave_state.current_rule.spawn_period_mult then
                    base_period = math.max(1.0, base_period * wave_state.current_rule.spawn_period_mult)
                end
                if wave_state.threat_runtime and wave_state.threat_runtime.spawn_period_mult then
                    base_period = math.max(0.8, base_period * wave_state.threat_runtime.spawn_period_mult)
                end
                
                -- 黄昏延迟刷怪：平衡一天内的高压体验
                if world.state.isdusk then
                    base_period = base_period * 2.5
                end
                
                return base_period
            end

            local function ScheduleNextSpawn()
                if not wave_active then return end
                local period = GetDynamicSpawnPeriod()
                wave_task = world:DoTaskInTime(period, function()
                    if not wave_active then return end
                    local alives = deps.CollectAlivePlayers()
                    if #alives == 0 then EndWave(); return end
                    for _, p in ipairs(alives) do SpawnEnemy(p, false, day) end
                    ScheduleNextSpawn()
                end)
            end
            
            ScheduleNextSpawn()
        end
    end

    S.GetState = function() return wave_state end
    S.RegisterRPCCallbacks = function()
        local route_handler = function(player, slot)
            if not player or not player:IsValid() then return end
            local idx = tonumber(slot)
            if not idx or idx < 1 or idx > 2 then return end
            if not wave_state.route_offer or wave_state.route_active ~= nil then return end
            local uid = player.userid or tostring(player.GUID)
            wave_state.route_votes = wave_state.route_votes or {}
            wave_state.route_votes[uid] = idx
            local c1 = 0
            local c2 = 0
            for _, v in pairs(wave_state.route_votes) do
                if v == 1 then c1 = c1 + 1 elseif v == 2 then c2 = c2 + 1 end
            end
            deps.Announce(player:GetDisplayName() .. " 已投票：" .. (wave_state.route_offer[idx] and wave_state.route_offer[idx].name or "未知"))
            deps.Announce("当前票数：1号" .. c1 .. "票 / 2号" .. c2 .. "票")
            SyncWaveStateToAllPlayers()
            local alive = deps.CollectAlivePlayers()
            local majority = math.floor(#alive / 2) + 1
            if c1 >= majority or c2 >= majority then
                local route = wave_state.route_offer[c1 >= majority and 1 or 2]
                local day = (GetWorld() and GetWorld().state and (GetWorld().state.cycles + 1)) or 1
                ApplyRouteChoice(route, day)
            end
        end
        if deps.SetRPCHandler then
            deps.SetRPCHandler("pick_route", route_handler)
        else
            deps.GLOBAL.rawset(deps.GLOBAL, "_rogue_mode_pick_route_rpc", route_handler)
        end
    end
    S.ExportState = function()
        local route_offer_ids = nil
        if type(wave_state.route_offer) == "table" and #wave_state.route_offer > 0 then
            route_offer_ids = {}
            for i, def in ipairs(wave_state.route_offer) do
                route_offer_ids[i] = def and def.id or 0
            end
        end
        return {
            wave_active = wave_active == true,
            used_bosses = CloneTable(wave_state.used_bosses) or {},
            current_rule_id = wave_state.current_rule and wave_state.current_rule.id or 0,
            bounty = CloneTable(wave_state.bounty),
            challenge = CloneTable(wave_state.challenge),
            route_active_id = wave_state.route_active and wave_state.route_active.id or 0,
            route_pending_day = wave_state.route_pending_day or 0,
            route_offer_ids = route_offer_ids,
            route_votes = CloneTable(wave_state.route_votes),
            route_drop_bonus = wave_state.route_drop_bonus or 0,
            threat_tier = wave_state.threat_tier or 1,
            threat_reward_pct = wave_state.threat_reward_pct or 0,
            threat_drop_bonus = wave_state.threat_drop_bonus or 0,
        }
    end
    S.ImportState = function(saved)
        if type(saved) ~= "table" then
            return
        end
        wave_active = false
        if wave_task then
            wave_task:Cancel()
            wave_task = nil
        end
        if wave_state.route_vote_task then
            wave_state.route_vote_task:Cancel()
            wave_state.route_vote_task = nil
        end
        wave_state.used_bosses = CloneTable(saved.used_bosses) or {}
        wave_state.current_rule = FindDefById(deps.WAVE_RULE_DEFS, saved.current_rule_id)
        wave_state.bounty = CloneTable(saved.bounty)
        wave_state.challenge = CloneTable(saved.challenge)
        wave_state.route_active = FindDefById(deps.REGION_ROUTE_DEFS, saved.route_active_id)
        wave_state.route_pending_day = (tonumber(saved.route_pending_day) or 0) > 0 and tonumber(saved.route_pending_day) or nil
        if type(saved.route_offer_ids) == "table" then
            wave_state.route_offer = {}
            for i, rid in ipairs(saved.route_offer_ids) do
                wave_state.route_offer[i] = FindDefById(deps.REGION_ROUTE_DEFS, rid)
            end
            if not wave_state.route_offer[1] or not wave_state.route_offer[2] then
                wave_state.route_offer = nil
            end
        else
            wave_state.route_offer = nil
        end
        wave_state.route_votes = CloneTable(saved.route_votes)
        wave_state.route_runtime = nil
        wave_state.route_drop_bonus = tonumber(saved.route_drop_bonus) or 0
        wave_state.threat_tier = math.max(1, tonumber(saved.threat_tier) or 1)
        wave_state.threat_reward_pct = math.max(0, tonumber(saved.threat_reward_pct) or 0)
        wave_state.threat_runtime = nil
        wave_state.threat_drop_bonus = tonumber(saved.threat_drop_bonus) or 0
        SyncWaveStateToAllPlayers()
    end
    S.SyncWaveStateToPlayer = SyncWaveStateToPlayer
    S.SyncWaveStateToAllPlayers = SyncWaveStateToAllPlayers
    S.StartWave = StartWave
    S.EndWave = EndWave
    S.ProgressChallenge = ProgressChallenge
    S.RewardBounty = RewardBounty
    return S
end

return M
