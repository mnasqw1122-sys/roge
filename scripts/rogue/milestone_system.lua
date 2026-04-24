--[[
    文件说明：milestone_system.lua
    功能：赛季中间里程碑系统。
    在赛季进行过程中，当达到指定天数且满足击杀/Boss/精英指标时，
    发放阶段性里程碑奖励（材料、装备、遗物），并公告全体玩家。
]]
local M = {}

function M.Create(deps)
    local S = {}
    local milestone_defs = deps.SEASON_MILESTONE_DEFS
    local unlock_metrics = deps.SEASON_MILESTONE_UNLOCK_METRICS
    local claimed_milestones = {}

    -- 函数说明：检查指定里程碑是否已领取。
    local function IsMilestoneClaimed(id)
        return claimed_milestones[id] == true
    end

    -- 函数说明：获取当前赛季的累计统计指标。
    local function GetCurrentMetrics()
        local metrics = { kills = 0, bosses = 0, elites = 0 }
        for _, p in ipairs(deps.CollectAlivePlayers()) do
            if p.rogue_data then
                metrics.kills = metrics.kills + (p.rogue_data.kills or 0)
                metrics.bosses = metrics.bosses + (p.rogue_data.boss_kills or 0)
                metrics.elites = metrics.elites + (p.rogue_data.elite_kills or 0)
            end
        end
        return metrics
    end

    -- 函数说明：检查指定里程碑是否满足解锁条件。
    local function CheckMilestoneUnlocked(id, metrics)
        local metric_def = nil
        for _, m in ipairs(unlock_metrics) do
            if m.id == id then metric_def = m break end
        end
        if not metric_def then return false end
        return metrics.kills >= metric_def.min_kills
            and metrics.bosses >= metric_def.min_bosses
            and metrics.elites >= metric_def.min_elites
    end

    -- 函数说明：为所有存活玩家发放里程碑奖励。
    local function GrantMilestoneRewards(milestone_def, day)
        local rewards = milestone_def.rewards
        if not rewards then return end

        for _, p in ipairs(deps.CollectAlivePlayers()) do
            -- 发放材料
            if rewards.mat_count and rewards.mat_count > 0 then
                local mat_pool, mat_w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_MATS", day)
                if mat_pool and mat_w > 0 then
                    for i = 1, rewards.mat_count do
                        local picked = deps.PickWeightedCandidate(mat_pool, mat_w)
                        if picked then
                            deps.SpawnDrop(p, picked.prefab, picked.count or 1)
                        end
                    end
                end
            end

            -- 概率发放装备
            if rewards.gear_chance and math.random() < rewards.gear_chance then
                local gear_pool, gear_w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_GEAR", day)
                if gear_pool and gear_w > 0 then
                    local picked = deps.PickWeightedCandidate(gear_pool, gear_w)
                    if picked then
                        deps.SpawnDrop(p, picked.prefab, 1)
                    end
                end
            end

            -- 概率发放遗物
            if rewards.relic_chance and math.random() < rewards.relic_chance then
                if deps.GrantRelicChoice then
                    deps.GrantRelicChoice(p)
                end
            end
        end
    end

    -- 函数说明：检查并触发里程碑（每天调用一次）。
    S.CheckMilestones = function(day)
        local metrics = GetCurrentMetrics()

        for _, milestone_def in ipairs(milestone_defs) do
            if not IsMilestoneClaimed(milestone_def.id) then
                if day >= milestone_def.day and CheckMilestoneUnlocked(milestone_def.id, metrics) then
                    claimed_milestones[milestone_def.id] = true
                    GrantMilestoneRewards(milestone_def, day)
                    -- 公告
                    for _, p in ipairs(deps.CollectAlivePlayers()) do
                        if p.components and p.components.talker then
                            p.components.talker:Say("里程碑达成：" .. milestone_def.name .. "！")
                        end
                    end
                end
            end
        end
    end

    -- 函数说明：获取所有里程碑的当前状态（供UI展示）。
    S.GetMilestoneStates = function()
        local metrics = GetCurrentMetrics()
        local states = {}
        for _, milestone_def in ipairs(milestone_defs) do
            local metric_def = nil
            for _, m in ipairs(unlock_metrics) do
                if m.id == milestone_def.id then metric_def = m break end
            end
            table.insert(states, {
                id = milestone_def.id,
                name = milestone_def.name,
                desc = milestone_def.desc,
                day = milestone_def.day,
                claimed = IsMilestoneClaimed(milestone_def.id),
                day_reached = false,
                metrics_met = metric_def and CheckMilestoneUnlocked(milestone_def.id, metrics) or false,
                kills_current = metrics.kills,
                kills_required = metric_def and metric_def.min_kills or 0,
                bosses_current = metrics.bosses,
                bosses_required = metric_def and metric_def.min_bosses or 0,
                elites_current = metrics.elites,
                elites_required = metric_def and metric_def.min_elites or 0,
            })
        end
        return states
    end

    -- 函数说明：重置里程碑状态（新赛季开始时调用）。
    S.ResetMilestones = function()
        claimed_milestones = {}
    end

    -- 函数说明：导出里程碑状态用于持久化。
    S.ExportState = function()
        return { claimed = claimed_milestones }
    end

    -- 函数说明：导入里程碑状态用于恢复。
    S.ImportState = function(data)
        if data and data.claimed then
            claimed_milestones = data.claimed
        end
    end

    return S
end

return M
