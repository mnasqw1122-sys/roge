--[[
    文件说明：season_result.lua
    功能：赛季结算与目标评级系统。
    负责在赛季末统计玩家各项数据（击杀、Boss、无伤等），评估赛季目标完成度，颁发徽章，并保存历史战报。
]]
local M = {}

function M.Create(deps)
    local S = {}

    local state = {
        finalized_season_id = -1,
    }

    local GRADE_TEXT = {
        [0] = "未评级",
        [1] = "B",
        [2] = "A",
        [3] = "S",
    }

    local function ReadObjectiveMetric(data, metric, day)
        if metric == "boss_kills" then
            return data.season_boss_kills or 0
        elseif metric == "trial_wins" then
            return data.season_challenge_done or 0
        elseif metric == "alive_days" then
            return day or 0
        elseif metric == "deathless_days" then
            return (data.season_deaths or 0) == 0 and (day or 0) or 0
        elseif metric == "elite_kills" then
            return data.season_elite_kills or 0
        elseif metric == "legendary_loot" then
            return (data.build_rarity_counts and data.build_rarity_counts.legendary) or 0
        end
        return 0
    end

    local function SnapshotObjectives(data, day)
        local defs = deps.SEASON_OBJECTIVE_DEFS or {}
        local progress = { 0, 0, 0, 0 }
        local target = { 0, 0, 0, 0 }
        local done = 0
        for i, def in ipairs(defs) do
            if i > 4 then break end
            local val = ReadObjectiveMetric(data, def.metric, day)
            local tar = def.target or 0
            progress[i] = val
            target[i] = tar
            if tar > 0 and val >= tar then
                done = done + 1
            end
        end
        data.season_obj_progress = progress
        data.season_obj_target = target
        data.season_objective_done = done
    end

    local function GrantObjectivePulse(player, data, def, idx, day)
        if not player or not deps.IsValidPlayer or not deps.IsValidPlayer(player) then return end
        data.loot_pity_stack = math.min(9, (data.loot_pity_stack or 0) + 1)
        local spawned = 0
        if deps.PoolCatalog and deps.PickWeightedCandidate and deps.SpawnDrop then
            local pool, w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_MATS", day or 1)
            local reward_count = 1
            if def and def.id == "boss_hunter" then
                reward_count = 2
            end
            for _ = 1, reward_count do
                local item = deps.PickWeightedCandidate(pool, w)
                if item then
                    local drop = deps.SpawnDrop(player, item.prefab)
                    if drop then
                        spawned = spawned + 1
                    end
                end
            end
        end
        local name = (def and def.name) or ("目标" .. tostring(idx))
        deps.Announce(player:GetDisplayName() .. " 达成赛季目标【" .. name .. "】！获得奖励脉冲（保底+1，材料+" .. tostring(spawned) .. "）")
    end

    local function ApplyObjectivePulseIfNeeded(player, data, day)
        local defs = deps.SEASON_OBJECTIVE_DEFS or {}
        data.season_obj_claimed = data.season_obj_claimed or { 0, 0, 0, 0 }
        for i, def in ipairs(defs) do
            if i > 4 then break end
            local tar = def.target or 0
            local val = ReadObjectiveMetric(data, def.metric, day)
            if tar > 0 and val >= tar and (data.season_obj_claimed[i] or 0) == 0 then
                data.season_obj_claimed[i] = 1
                GrantObjectivePulse(player, data, def, i, day)
            end
        end
    end

    local function RefreshSeasonHistorySnapshot(data)
        local h = data.season_history or {}
        local e1 = h[1] or {}
        local e2 = h[2] or {}
        local e3 = h[3] or {}
        data.season_hist1_score = e1.score or 0
        data.season_hist1_rank = e1.rank or 0
        data.season_hist1_grade = e1.grade or 0
        data.season_hist1_badges = #(e1.badges or {})
        data.season_hist1_kills = e1.kills or 0
        data.season_hist1_boss = e1.boss or 0
        data.season_hist1_deaths = e1.deaths or 0
        data.season_hist1_build = e1.build_score or 0
        data.season_hist1_route = e1.route_id or 0
        data.season_hist1_catastrophe_days = e1.catastrophe_days or 0
        data.season_hist1_challenge_done = e1.challenge_done or 0
        data.season_hist1_challenge_total = e1.challenge_total or 0
        data.season_hist1_bounty_done = e1.bounty_done or 0
        data.season_hist1_bounty_total = e1.bounty_total or 0
        data.season_hist1_style = e1.style_id or 0
        data.season_hist2_score = e2.score or 0
        data.season_hist2_rank = e2.rank or 0
        data.season_hist2_grade = e2.grade or 0
        data.season_hist2_badges = #(e2.badges or {})
        data.season_hist2_kills = e2.kills or 0
        data.season_hist2_boss = e2.boss or 0
        data.season_hist2_deaths = e2.deaths or 0
        data.season_hist2_build = e2.build_score or 0
        data.season_hist2_route = e2.route_id or 0
        data.season_hist2_catastrophe_days = e2.catastrophe_days or 0
        data.season_hist2_challenge_done = e2.challenge_done or 0
        data.season_hist2_challenge_total = e2.challenge_total or 0
        data.season_hist2_bounty_done = e2.bounty_done or 0
        data.season_hist2_bounty_total = e2.bounty_total or 0
        data.season_hist2_style = e2.style_id or 0
        data.season_hist3_score = e3.score or 0
        data.season_hist3_rank = e3.rank or 0
        data.season_hist3_grade = e3.grade or 0
        data.season_hist3_badges = #(e3.badges or {})
        data.season_hist3_kills = e3.kills or 0
        data.season_hist3_boss = e3.boss or 0
        data.season_hist3_deaths = e3.deaths or 0
        data.season_hist3_build = e3.build_score or 0
        data.season_hist3_route = e3.route_id or 0
        data.season_hist3_catastrophe_days = e3.catastrophe_days or 0
        data.season_hist3_challenge_done = e3.challenge_done or 0
        data.season_hist3_challenge_total = e3.challenge_total or 0
        data.season_hist3_bounty_done = e3.bounty_done or 0
        data.season_hist3_bounty_total = e3.bounty_total or 0
        data.season_hist3_style = e3.style_id or 0
    end

    local function EnsureEntry(player)
        local data = deps.EnsurePlayerData(player)
        local sid = deps.GetSeasonId()
        if data.season_stat_id ~= sid then
            local defs = deps.SEASON_OBJECTIVE_DEFS or {}
            local target = { 0, 0, 0, 0 }
            for i, def in ipairs(defs) do
                if i > 4 then break end
                target[i] = def.target or 0
            end
            data.season_stat_id = sid
            data.season_kills = 0
            data.season_boss_kills = 0
            data.season_elite_kills = 0
            data.season_deaths = 0
            data.season_challenge_done = 0
            data.season_challenge_total = 0
            data.season_bounty_done = 0
            data.season_bounty_total = 0
            data.season_objective_done = 0
            data.season_obj_progress = { 0, 0, 0, 0 }
            data.season_obj_target = target
            data.season_obj_claimed = { 0, 0, 0, 0 }
            data.build_affix_counts = {}
            data.build_rarity_counts = { common = 0, rare = 0, epic = 0, legendary = 0 }
            data.build_score = 0
            data.season_route_pick_counts = {}
            data.season_catastrophe_days = 0
            data.season_last_style_id = 0
            
            RefreshSeasonHistorySnapshot(data)
        end
        return data
    end

    local function ComputeScore(data)
        local kills = data.season_kills or 0
        local boss = data.season_boss_kills or 0
        local elite = data.season_elite_kills or 0
        local deaths = data.season_deaths or 0
        local challenge = data.season_challenge_done or 0
        local dmg = math.floor((data.damage_bonus or 0) * 1000)
        local relic = (data.relic_count or 0) * 16
        local synergy = (data.relic_synergy_count or 0) * 28
        local score = kills + boss * 120 + elite * 20 + challenge * 80 + dmg + relic + synergy - deaths * 45
        if score < 0 then score = 0 end
        return score
    end

    local function EvaluateObjectives(data, day)
        local defs = deps.SEASON_OBJECTIVE_DEFS or {}
        local bal = deps.SEASON_OBJECTIVE_BALANCE or {}
        local completed = 0
        local grade_score = 0
        local weight_total = 0
        local detail = {}
        for _, def in ipairs(defs) do
            local val = ReadObjectiveMetric(data, def.metric, day)
            local tier = 0
            local weight = def.weight or 1
            if def.grade and val >= (def.grade.s or 10^9) then
                tier = 3
            elseif def.grade and val >= (def.grade.a or 10^9) then
                tier = 2
            elseif def.grade and val >= (def.grade.b or 10^9) then
                tier = 1
            end
            if val >= (def.target or 0) then
                completed = completed + 1
            end
            grade_score = grade_score + tier * weight
            weight_total = weight_total + weight
            detail[#detail + 1] = { id = def.id, name = def.name, value = val, tier = tier }
        end
        local final_grade = 0
        local avg = (weight_total > 0) and (grade_score / weight_total) or 0
        if avg >= (bal.grade_avg_s or 2.5) then
            final_grade = 3
        elseif avg >= (bal.grade_avg_a or 1.6) then
            final_grade = 2
        elseif avg >= (bal.grade_avg_b or 0.8) then
            final_grade = 1
        end
        return {
            medals = completed,
            grade = final_grade,
            details = detail,
        }
    end

    local function BuildPlayerHighlights(rows)
        local top_kill = nil
        local top_boss = nil
        local top_challenge = nil
        local deathless = {}
        local badges = {}
        for _, row in ipairs(rows) do
            local d = row.data
            if not top_kill or (d.season_kills or 0) > (top_kill.data.season_kills or 0) then
                top_kill = row
            end
            if not top_boss or (d.season_boss_kills or 0) > (top_boss.data.season_boss_kills or 0) then
                top_boss = row
            end
            if not top_challenge or (d.season_challenge_done or 0) > (top_challenge.data.season_challenge_done or 0) then
                top_challenge = row
            end
            if (d.season_deaths or 0) == 0 then
                table.insert(deathless, row.player:GetDisplayName())
            end
        end
        local lines = {}
        if top_kill then
            lines[#lines + 1] = "高光·清剿先锋：" .. top_kill.player:GetDisplayName() .. "（击杀" .. tostring(top_kill.data.season_kills or 0) .. "）"
            badges[top_kill.player.userid or tostring(top_kill.player.GUID)] = badges[top_kill.player.userid or tostring(top_kill.player.GUID)] or {}
            table.insert(badges[top_kill.player.userid or tostring(top_kill.player.GUID)], "清剿先锋")
        end
        if top_boss then
            lines[#lines + 1] = "高光·王者终结：" .. top_boss.player:GetDisplayName() .. "（Boss" .. tostring(top_boss.data.season_boss_kills or 0) .. "）"
            badges[top_boss.player.userid or tostring(top_boss.player.GUID)] = badges[top_boss.player.userid or tostring(top_boss.player.GUID)] or {}
            table.insert(badges[top_boss.player.userid or tostring(top_boss.player.GUID)], "王者终结")
        end
        if top_challenge then
            lines[#lines + 1] = "高光·试炼征服：" .. top_challenge.player:GetDisplayName() .. "（挑战" .. tostring(top_challenge.data.season_challenge_done or 0) .. "）"
            badges[top_challenge.player.userid or tostring(top_challenge.player.GUID)] = badges[top_challenge.player.userid or tostring(top_challenge.player.GUID)] or {}
            table.insert(badges[top_challenge.player.userid or tostring(top_challenge.player.GUID)], "试炼征服")
        end
        if #deathless > 0 then
            lines[#lines + 1] = "高光·无伤统帅：" .. table.concat(deathless, "、")
            for _, row in ipairs(rows) do
                if (row.data.season_deaths or 0) == 0 then
                    local uid = row.player.userid or tostring(row.player.GUID)
                    badges[uid] = badges[uid] or {}
                    table.insert(badges[uid], "无伤统帅")
                end
            end
        end
        return lines, badges
    end

    local function BuildTeamHighlights(total_kills, total_boss, total_challenge, total_deaths, total_build, player_count)
        local lines = {}
        local team_badges = {}
        if player_count <= 0 then
            return lines, team_badges
        end
        local avg_build = math.floor(total_build / player_count)
        if total_deaths == 0 then
            lines[#lines + 1] = "团队战报：本赛季全员零死亡，执行完美。"
            table.insert(team_badges, "铁壁远征")
        elseif total_deaths <= math.max(1, player_count - 1) then
            lines[#lines + 1] = "团队战报：低伤亡推进，团队韧性优秀。"
            table.insert(team_badges, "稳健推进")
        end
        if total_challenge >= player_count * 2 then
            lines[#lines + 1] = "团队战报：挑战完成度极高，节奏侵略性强。"
            table.insert(team_badges, "试炼征服团")
        end
        if total_boss >= math.max(2, player_count) then
            lines[#lines + 1] = "团队战报：Boss压制力突出，终结效率稳定。"
            table.insert(team_badges, "王庭破军")
        end
        if avg_build >= 90 then
            lines[#lines + 1] = "团队战报：平均构筑评分" .. tostring(avg_build) .. "，构筑质量优异。"
            table.insert(team_badges, "极致构筑")
        elseif avg_build >= 55 then
            lines[#lines + 1] = "团队战报：平均构筑评分" .. tostring(avg_build) .. "，构筑成型良好。"
            table.insert(team_badges, "成型构筑")
        else
            lines[#lines + 1] = "团队战报：平均构筑评分" .. tostring(avg_build) .. "，建议下赛季提升构筑协同。"
        end
        if total_kills >= player_count * 220 then
            lines[#lines + 1] = "团队战报：清图强度高，整体推进速度快。"
            table.insert(team_badges, "风暴清图")
        end
        return lines, team_badges
    end

    local function GetPreferredRoute(data)
        local counts = data.season_route_pick_counts or {}
        local best_id = 0
        local best_count = -1
        for _, def in ipairs(deps.REGION_ROUTE_DEFS or {}) do
            local c = counts[def.id] or 0
            if c > best_count then
                best_count = c
                best_id = def.id
            end
        end
        if best_id <= 0 then
            return 0, "无"
        end
        for _, def in ipairs(deps.REGION_ROUTE_DEFS or {}) do
            if def.id == best_id then
                return best_id, def.name or "未知"
            end
        end
        return best_id, "未知"
    end

    local function EvaluateSeasonStyleByMetrics(ch_done, ch_total, bo_done, bo_total, cata_days, deaths)
        local ch_rate = ch_total > 0 and (ch_done / ch_total) or 0
        local bo_rate = bo_total > 0 and (bo_done / bo_total) or 0
        local style_id = 6
        if ch_rate >= 0.75 and bo_rate >= 0.75 then
            style_id = 1
        elseif ch_rate >= 0.8 and bo_rate <= 0.45 then
            style_id = 2
        elseif bo_rate >= 0.8 and ch_rate <= 0.45 then
            style_id = 3
        elseif cata_days >= 6 and deaths <= 2 then
            style_id = 4
        elseif deaths == 0 and (ch_rate >= 0.5 or bo_rate >= 0.5) then
            style_id = 5
        end
        local names = deps.SEASON_STYLE_NAMES or {}
        return style_id, (names[style_id] or "均衡推进")
    end

    local function EvaluateSeasonStyle(data)
        return EvaluateSeasonStyleByMetrics(
            data.season_challenge_done or 0,
            data.season_challenge_total or 0,
            data.season_bounty_done or 0,
            data.season_bounty_total or 0,
            data.season_catastrophe_days or 0,
            data.season_deaths or 0
        )
    end

    local function RefreshSeasonHistorySnapshot(data)
        local h = data.season_history or {}
        local e1 = h[1] or {}
        local e2 = h[2] or {}
        local e3 = h[3] or {}
        data.season_hist1_score = e1.score or 0
        data.season_hist1_rank = e1.rank or 0
        data.season_hist1_grade = e1.grade or 0
        data.season_hist1_badges = #(e1.badges or {})
        data.season_hist1_kills = e1.kills or 0
        data.season_hist1_boss = e1.boss or 0
        data.season_hist1_deaths = e1.deaths or 0
        data.season_hist1_build = e1.build_score or 0
        data.season_hist1_route = e1.route_id or 0
        data.season_hist1_catastrophe_days = e1.catastrophe_days or 0
        data.season_hist1_challenge_done = e1.challenge_done or 0
        data.season_hist1_challenge_total = e1.challenge_total or 0
        data.season_hist1_bounty_done = e1.bounty_done or 0
        data.season_hist1_bounty_total = e1.bounty_total or 0
        data.season_hist1_style = e1.style_id or 0
        data.season_hist2_score = e2.score or 0
        data.season_hist2_rank = e2.rank or 0
        data.season_hist2_grade = e2.grade or 0
        data.season_hist2_badges = #(e2.badges or {})
        data.season_hist2_kills = e2.kills or 0
        data.season_hist2_boss = e2.boss or 0
        data.season_hist2_deaths = e2.deaths or 0
        data.season_hist2_build = e2.build_score or 0
        data.season_hist2_route = e2.route_id or 0
        data.season_hist2_catastrophe_days = e2.catastrophe_days or 0
        data.season_hist2_challenge_done = e2.challenge_done or 0
        data.season_hist2_challenge_total = e2.challenge_total or 0
        data.season_hist2_bounty_done = e2.bounty_done or 0
        data.season_hist2_bounty_total = e2.bounty_total or 0
        data.season_hist2_style = e2.style_id or 0
        data.season_hist3_score = e3.score or 0
        data.season_hist3_rank = e3.rank or 0
        data.season_hist3_grade = e3.grade or 0
        data.season_hist3_badges = #(e3.badges or {})
        data.season_hist3_kills = e3.kills or 0
        data.season_hist3_boss = e3.boss or 0
        data.season_hist3_deaths = e3.deaths or 0
        data.season_hist3_build = e3.build_score or 0
        data.season_hist3_route = e3.route_id or 0
        data.season_hist3_catastrophe_days = e3.catastrophe_days or 0
        data.season_hist3_challenge_done = e3.challenge_done or 0
        data.season_hist3_challenge_total = e3.challenge_total or 0
        data.season_hist3_bounty_done = e3.bounty_done or 0
        data.season_hist3_bounty_total = e3.bounty_total or 0
        data.season_hist3_style = e3.style_id or 0
    end

    local function PersistResult(player, data, score, day, rank, objective_result, player_badges, team_badges)
        data.best_season_score = math.max(data.best_season_score or 0, score)
        data.season_last_score = score
        data.season_last_rank = rank or 0
        data.season_last_badges = player_badges or {}
        data.season_last_team_badges = team_badges or {}
        if objective_result then
            data.season_medals = objective_result.medals or 0
            data.season_objective_grade = objective_result.grade or 0
        end
        local style_id, style_tag = EvaluateSeasonStyle(data)
        data.season_last_style_id = style_id
        local route_id, route_name = GetPreferredRoute(data)
        local catastrophe_days = data.season_catastrophe_days or 0
        data.season_history = data.season_history or {}
        table.insert(data.season_history, 1, {
            day = day,
            score = score,
            rank = rank or 0,
            kills = data.season_kills or 0,
            boss = data.season_boss_kills or 0,
            deaths = data.season_deaths or 0,
            medals = data.season_medals or 0,
            grade = data.season_objective_grade or 0,
            build_score = data.build_score or 0,
            badges = player_badges or {},
            team_badges = team_badges or {},
            route_id = route_id,
            route_name = route_name,
            catastrophe_days = catastrophe_days,
            challenge_done = data.season_challenge_done or 0,
            challenge_total = data.season_challenge_total or 0,
            bounty_done = data.season_bounty_done or 0,
            bounty_total = data.season_bounty_total or 0,
            style_id = style_id,
            style_tag = style_tag,
        })
        while #data.season_history > 5 do
            table.remove(data.season_history)
        end
        RefreshSeasonHistorySnapshot(data)
        if deps.SyncGrowthNetvars then
            deps.SyncGrowthNetvars(player, data)
        end
        if deps.GLOBAL and deps.GLOBAL.TheSim and player.userid then
            local status, jstr = pcall(deps.GLOBAL.json.encode, data.season_history)
            if status and jstr then
                deps.GLOBAL.TheSim:SetPersistentString("rogue_history_" .. tostring(player.userid), jstr, false, function() end)
            end
        end
    end

    local function QueueAnnounces(lines)
        if not lines or #lines == 0 then return end
        local world = deps.GetWorld and deps.GetWorld() or nil
        if world then
            for i, line in ipairs(lines) do
                world:DoTaskInTime((i - 1) * 0.8, function()
                    deps.Announce(line)
                end)
            end
        else
            deps.Announce(lines[1])
        end
    end

    S.OnKill = function(player, victim, is_boss)
        if not deps.IsValidPlayer(player) then return end
        local data = EnsureEntry(player)
        data.season_kills = (data.season_kills or 0) + 1
        if is_boss then
            data.season_boss_kills = (data.season_boss_kills or 0) + 1
        end
        if victim and victim:HasTag("rogue_elite") then
            data.season_elite_kills = (data.season_elite_kills or 0) + 1
        end
        local day = deps.GetCurrentDay and deps.GetCurrentDay() or 0
        SnapshotObjectives(data, day)
        ApplyObjectivePulseIfNeeded(player, data, day)
        if deps.SyncGrowthNetvars then
            deps.SyncGrowthNetvars(player, data)
        end
    end

    S.OnDeath = function(player)
        if not deps.IsValidPlayer(player) then return end
        local data = EnsureEntry(player)
        data.season_deaths = (data.season_deaths or 0) + 1
        local day = deps.GetCurrentDay and deps.GetCurrentDay() or 0
        SnapshotObjectives(data, day)
        ApplyObjectivePulseIfNeeded(player, data, day)
        if deps.SyncGrowthNetvars then
            deps.SyncGrowthNetvars(player, data)
        end
    end

    S.OnChallengeReward = function(player)
        if not deps.IsValidPlayer(player) then return end
        local data = EnsureEntry(player)
        data.season_challenge_done = (data.season_challenge_done or 0) + 1
        local day = deps.GetCurrentDay and deps.GetCurrentDay() or 0
        SnapshotObjectives(data, day)
        ApplyObjectivePulseIfNeeded(player, data, day)
        if deps.SyncGrowthNetvars then
            deps.SyncGrowthNetvars(player, data)
        end
    end

    S.OnBountyReward = function(player)
        if not deps.IsValidPlayer(player) then return end
        local data = EnsureEntry(player)
        data.season_bounty_done = (data.season_bounty_done or 0) + 1
        local day = deps.GetCurrentDay and deps.GetCurrentDay() or 0
        SnapshotObjectives(data, day)
        ApplyObjectivePulseIfNeeded(player, data, day)
        if deps.SyncGrowthNetvars then
            deps.SyncGrowthNetvars(player, data)
        end
    end

    S.Finalize = function(day)
        local sid = deps.GetSeasonId()
        if state.finalized_season_id == sid then return end
        state.finalized_season_id = sid
        local rows = {}
        for _, player in ipairs(deps.AllPlayers) do
            if player and player:IsValid() then
                local data = EnsureEntry(player)
                local score = ComputeScore(data)
                table.insert(rows, { player = player, score = score, data = data })
            end
        end
        table.sort(rows, function(a, b) return a.score > b.score end)
        local total_score = 0
        local total_kills = 0
        local total_boss = 0
        local total_elite = 0
        local total_deaths = 0
        local total_challenge = 0
        local total_challenge_total = 0
        local total_bounty_done = 0
        local total_bounty_total = 0
        local total_cata_days = 0
        local total_medals = 0
        local total_build = 0
        local _, player_badges_map = BuildPlayerHighlights(rows)
        local objective_results = {}
        for i, row in ipairs(rows) do
            SnapshotObjectives(row.data, day)
            local objective_result = EvaluateObjectives(row.data, day)
            objective_results[i] = objective_result
            total_score = total_score + row.score
            total_kills = total_kills + (row.data.season_kills or 0)
            total_boss = total_boss + (row.data.season_boss_kills or 0)
            total_elite = total_elite + (row.data.season_elite_kills or 0)
            total_deaths = total_deaths + (row.data.season_deaths or 0)
            total_challenge = total_challenge + (row.data.season_challenge_done or 0)
            total_challenge_total = total_challenge_total + (row.data.season_challenge_total or 0)
            total_bounty_done = total_bounty_done + (row.data.season_bounty_done or 0)
            total_bounty_total = total_bounty_total + (row.data.season_bounty_total or 0)
            total_cata_days = total_cata_days + (row.data.season_catastrophe_days or 0)
            total_build = total_build + (row.data.build_score or 0)
        end
        local team_highlights, team_badges = BuildTeamHighlights(total_kills, total_boss, total_challenge, total_deaths, total_build, #rows)
        for i, row in ipairs(rows) do
            local uid = row.player.userid or tostring(row.player.GUID)
            PersistResult(row.player, row.data, row.score, day, i, objective_results[i], player_badges_map[uid], team_badges)
            total_medals = total_medals + (row.data.season_medals or 0)
            
            -- 赛季结算积分奖励：这里仅计算并保存，不直接发放（发放逻辑在 player_state.lua 中玩家重进时处理）
            local reward_points = math.floor(math.sqrt(math.max(0, row.score)) * 1.5)
            if reward_points > 0 then
                local p_data = { points = reward_points, claimed = false }
                local p_status, p_str = pcall(deps.GLOBAL.json.encode, p_data)
                if p_status and p_str then
                    deps.GLOBAL.TheSim:SetPersistentString("rogue_points_" .. tostring(uid), p_str, false, function() end)
                end
            end
        end
        local avg_cata_days = (#rows > 0) and math.floor(total_cata_days / #rows + 0.5) or 0
        local team_style_id, team_style = EvaluateSeasonStyleByMetrics(total_challenge, total_challenge_total, total_bounty_done, total_bounty_total, avg_cata_days, total_deaths)
        local lines = {
            "赛季结算：第" .. tostring(day) .. "天结束，参与人数 " .. tostring(#rows) .. "。本季风格：" .. tostring(team_style) .. "(#" .. tostring(team_style_id) .. ")",
            "团队统计：总分" .. tostring(total_score) .. " 击杀" .. tostring(total_kills) .. " Boss" .. tostring(total_boss) .. " 精英" .. tostring(total_elite),
            "团队统计：挑战完成" .. tostring(total_challenge) .. " 死亡" .. tostring(total_deaths),
            "团队统计：勋章" .. tostring(total_medals) .. " 构筑评分" .. tostring(total_build),
        }
        for _, line in ipairs(team_highlights) do
            table.insert(lines, line)
        end
        for i = 1, math.min(3, #rows) do
            local r = rows[i]
            table.insert(
                lines,
                "TOP" .. i .. " " .. r.player:GetDisplayName() .. " 分数:" .. tostring(r.score) .. " 评级:" .. (GRADE_TEXT[r.data.season_objective_grade or 0] or "未评级") .. " 勋章:" .. tostring(r.data.season_medals or 0) .. " 构筑:" .. tostring(r.data.build_score or 0)
            )
            local defs = deps.SEASON_OBJECTIVE_DEFS or {}
            local bal = deps.SEASON_OBJECTIVE_BALANCE or {}
            local limit = math.max(1, bal.detail_lines_per_player or 2)
            for idx, def in ipairs(defs) do
                if idx > limit then break end
                local cur = (r.data.season_obj_progress and r.data.season_obj_progress[idx]) or 0
                local tar = (r.data.season_obj_target and r.data.season_obj_target[idx]) or 0
                table.insert(lines, "  - " .. tostring(def.name or def.id or ("目标" .. idx)) .. " " .. tostring(cur) .. "/" .. tostring(tar))
            end
        end
        local player_highlights = BuildPlayerHighlights(rows)
        for _, line in ipairs(player_highlights) do
            table.insert(lines, line)
        end
        QueueAnnounces(lines)
        
        -- 返回预计播报所需的时间，用于延迟世界重置
        return #lines * 0.8
    end

    S.OnSeasonChanged = function()
        state.finalized_season_id = -1
    end

    return S
end

return M
