--[[
    文件说明：progression_system.lua
    功能：局内成长与任务系统。
    管理玩家的连杀状态（Combo）以及每日挑战任务（15种类型+连锁任务），并在达成目标时发放额外奖励。
    V2扩展：支持15种日常任务类型、条件组合任务和连锁任务。
]]
local M = {}

function M.Create(deps)
    local S = {}

    local function GetRotationMod(data)
        local rid = (data and data.season_rotation_id) or 1
        local mods = deps.DAILY_TASK_ROTATION_MODS or {}
        return mods[rid]
    end

    -- 函数说明：按权重随机选择日常任务类型
    local function PickDailyKind(data)
        local base = deps.DAILY_TASK_KIND_WEIGHTS or {}
        local mod = GetRotationMod(data)
        local total = 0
        local kinds = {}
        for kind, _ in pairs(deps.DAILY_KIND_NAMES or {}) do
            local weight = base[kind] or 1
            if mod and mod.weight_mult and mod.weight_mult[kind] then
                weight = weight * mod.weight_mult[kind]
            end
            if weight > 0 then
                total = total + weight
                table.insert(kinds, { kind = kind, weight = weight })
            end
        end
        if total <= 0 or #kinds == 0 then
            return 1
        end
        local roll = math.random() * total
        local acc = 0
        for _, item in ipairs(kinds) do
            acc = acc + item.weight
            if roll <= acc then
                return item.kind
            end
        end
        return kinds[#kinds].kind
    end

    -- 函数说明：应用目标倍率修正
    local function ApplyTargetMultiplier(data, kind, target)
        local mod = GetRotationMod(data)
        if mod and mod.target_mult and mod.target_mult[kind] then
            target = math.floor(target * mod.target_mult[kind] + 0.5)
        end
        local reduction = data.relic_daily_target_reduction or 0
        if reduction > 0 then
            target = math.max(1, math.floor(target * (1 - reduction)))
        end
        return math.max(1, target)
    end

    -- 函数说明：重置玩家的连杀状态
    local function ResetComboState(player)
        if not deps.IsValidPlayer(player) then return end
        local data = deps.EnsurePlayerData(player)
        data.combo_count = 0
        data.combo_mult = 1
        data.combo_expire_time = nil
        if player.rogue_combo_reset_task then
            player.rogue_combo_reset_task:Cancel()
            player.rogue_combo_reset_task = nil
        end
        if player.components.combat then
            player.components.combat.externaldamagemultipliers:RemoveModifier(deps.CONST.COMBO_DAMAGE_MODIFIER_KEY)
        end
        deps.SyncGrowthNetvars(player, data)
    end

    -- 函数说明：刷新连杀状态
    local function RefreshComboState(player)
        if not deps.IsValidPlayer(player) then return end
        local data = deps.EnsurePlayerData(player)
        local now = deps.GetTime()
        local window = deps.CONST.COMBO_BASE_WINDOW + (data.combo_window_bonus or 0)

        if data.combo_expire_time and now <= data.combo_expire_time then
            data.combo_count = (data.combo_count or 0) + 1
        else
            data.combo_count = 1
        end

        data.combo_expire_time = now + window
        local steps = math.floor(((data.combo_count or 1) - 1) / deps.CONST.COMBO_STEP_KILLS)
        local max_mult = deps.CONST.COMBO_MAX_MULT + (data.relic_combo_max_mult_bonus or 0)
        data.combo_mult = math.min(max_mult, 1 + steps * deps.CONST.COMBO_STEP_MULT)

        if player.components.combat then
            player.components.combat.externaldamagemultipliers:SetModifier(deps.CONST.COMBO_DAMAGE_MODIFIER_KEY, data.combo_mult)
        end
        deps.SyncGrowthNetvars(player, data)

        if player.rogue_combo_reset_task then player.rogue_combo_reset_task:Cancel() end
        player.rogue_combo_reset_task = player:DoTaskInTime(window, function()
            if not player:IsValid() then return end
            local d = deps.EnsurePlayerData(player)
            if d.combo_expire_time and deps.GetTime() >= d.combo_expire_time then
                ResetComboState(player)
            end
        end)
    end

    -- 函数说明：获取日常任务目标值（支持15种类型）
    local function GetDailyTarget(kind, day)
        local targets = deps.DAILY_TASK_TARGETS or {}
        local tier = day < 20 and 1 or (day < 40 and 2 or 3)
        local base_targets = targets[kind]
        if base_targets and base_targets[tier] then
            return base_targets[tier]
        end
        return 5
    end

    -- 函数说明：获取特定生物目标
    local function PickSpecificTarget()
        local defs = deps.DAILY_SPECIFIC_TARGET_DEFS or {}
        if #defs == 0 then return nil end
        return defs[math.random(#defs)]
    end

    -- 函数说明：确保玩家拥有当天的每日任务
    local function EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if data.daily and data.daily.day == day then
            return
        end

        local kind = PickDailyKind(data)
        local target = GetDailyTarget(kind, day)
        target = ApplyTargetMultiplier(data, kind, target)

        local daily = {
            day = day,
            kind = kind,
            target = target,
            progress = 0,
            completed = false,
            rewarded = false,
        }

        if kind == 14 then
            daily.specific_target = PickSpecificTarget()
        elseif kind == 15 then
            daily.combo_targets = {
                { kind = 1, target = math.random(10, 20), progress = 0 },
                { kind = 2, target = math.random(2, 5), progress = 0 },
            }
        end

        data.daily = daily

        -- 函数说明：初始化连锁任务进度
        local chain_defs = deps.DAILY_CHAIN_DEFS or {}
        if #chain_defs > 0 and not data.chain_task then
            local chain = chain_defs[math.random(#chain_defs)]
            data.chain_task = {
                id = chain.id,
                name = chain.name,
                current_step = 1,
                steps = chain.steps,
                chain_reward = chain.chain_reward,
                progress = {},
            }
            for i, step in ipairs(chain.steps) do
                data.chain_task.progress[i] = 0
            end
        end

        deps.SyncGrowthNetvars(player, data)
        local kind_name = deps.DAILY_KIND_NAMES[kind] or "未知任务"
        local desc = kind_name .. " " .. target .. " 次"
        if kind == 14 and daily.specific_target then
            desc = kind_name .. "：" .. daily.specific_target.name .. " " .. target .. " 只"
        elseif kind == 15 then
            desc = "多目标组合任务"
        end
        deps.Announce(player:GetDisplayName() .. " 今日任务：" .. desc)
    end

    -- 函数说明：发放日常任务奖励
    local function RewardDailyTask(player, day)
        if not deps.IsValidPlayer(player) then return end
        local data = deps.EnsurePlayerData(player)
        if not data.daily or data.daily.rewarded then return end
        data.daily.rewarded = true
        data.daily.completed = true

        deps.ApplyBuff(player, false)

        local rules = deps.DAILY_REWARD_RULES or {}
        local rule = rules[data.daily.kind or 1] or {}
        local mat_pool, mat_w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_MATS", day)
        local mat_count = (rule.mat_base or 1) + math.floor(data.daily_reward_bonus or 0)
        for _ = 1, mat_count do
            local item = mat_pool and deps.PickWeightedCandidate(mat_pool, mat_w)
            if item then
                deps.SpawnDrop(player, item.prefab)
            end
        end

        local gear_pool, gear_w = deps.PoolCatalog.GetRuntimePool("DROPS_BOSS_GEAR", day)
        local gear_rolls = rule.gear_rolls or 0
        local gear_chance = rule.gear_chance or 0
        for _ = 1, gear_rolls do
            if math.random() < gear_chance then
                local gear = gear_pool and deps.PickWeightedCandidate(gear_pool, gear_w)
                if gear then
                    deps.SpawnDrop(player, gear.prefab)
                end
            end
        end

        local rewards = deps.DAILY_TASK_REWARDS or {}
        local reward = rewards[data.daily.kind] or {}
        data.gold = (data.gold or 0) + (reward.gold or 0)
        data.xp = (data.xp or 0) + (reward.xp or 0)

        deps.SyncGrowthNetvars(player, data)
        deps.Announce(player:GetDisplayName() .. " 完成每日任务，获得额外奖励！")
    end

    -- 函数说明：推进连锁任务进度
    local function ProgressChainTask(player, kind, amount, day)
        local data = deps.EnsurePlayerData(player)
        if not data.chain_task then return end
        local chain = data.chain_task
        local step_idx = chain.current_step
        if step_idx > #chain.steps then return end
        local step = chain.steps[step_idx]
        if step.kind == kind then
            chain.progress[step_idx] = math.min(step.target, (chain.progress[step_idx] or 0) + (amount or 1))
            if chain.progress[step_idx] >= step.target then
                chain.current_step = step_idx + 1
                if chain.current_step > #chain.steps then
                    local reward = chain.chain_reward or {}
                    data.gold = (data.gold or 0) + (reward.gold or 0)
                    data.xp = (data.xp or 0) + (reward.xp or 0)
                    if reward.bonus_relic then
                        deps.OfferRelicChoice(player, "challenge", day)
                    end
                    if reward.bonus_talent then
                        deps.OfferTalentChoice(player)
                    end
                    deps.Announce(player:GetDisplayName() .. " 完成连锁任务：【" .. chain.name .. "】获得丰厚奖励！")
                    data.chain_task = nil
                else
                    deps.Announce(player:GetDisplayName() .. " 连锁任务进展：步骤" .. tostring(chain.current_step) .. "/" .. tostring(#chain.steps))
                end
            end
            deps.SyncGrowthNetvars(player, data)
        end
    end

    -- 函数说明：在击杀敌人时推进每日任务进度
    local function ProgressDailyTaskOnKill(player, victim, is_boss, day)
        if not deps.IsValidPlayer(player) then return end
        EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if not data.daily or data.daily.completed then return end

        local add = 0
        if data.daily.kind == 1 then
            add = 1
        elseif data.daily.kind == 2 then
            if victim:HasTag("rogue_elite") then add = 1 end
        elseif data.daily.kind == 3 then
            if is_boss then add = 1 end
        elseif data.daily.kind == 7 then
            if (data.combo_count or 0) >= (data.daily.target or 999) then
                add = data.daily.target
            end
        elseif data.daily.kind == 10 then
            if not data._took_damage_today then
                add = 1
            end
        elseif data.daily.kind == 11 then
            local relic_count = 0
            for _ in pairs(data.relics or {}) do
                relic_count = relic_count + 1
            end
            if relic_count >= (data.daily.target or 999) then
                add = data.daily.target
            end
        elseif data.daily.kind == 14 then
            if data.daily.specific_target and victim.prefab then
                if victim.prefab == data.daily.specific_target.prefab then
                    add = 1
                end
            end
        elseif data.daily.kind == 15 then
            if data.daily.combo_targets then
                for _, ct in ipairs(data.daily.combo_targets) do
                    if ct.kind == 1 then
                        ct.progress = (ct.progress or 0) + 1
                    elseif ct.kind == 2 and victim:HasTag("rogue_elite") then
                        ct.progress = (ct.progress or 0) + 1
                    end
                end
                local all_done = true
                for _, ct in ipairs(data.daily.combo_targets) do
                    if (ct.progress or 0) < ct.target then
                        all_done = false
                        break
                    end
                end
                if all_done then
                    add = data.daily.target
                end
            end
        end

        if add <= 0 then return end

        data.daily.progress = math.min(data.daily.target or 0, (data.daily.progress or 0) + add)
        if data.daily.progress >= (data.daily.target or 0) then
            RewardDailyTask(player, day)
        else
            deps.SyncGrowthNetvars(player, data)
        end

        ProgressChainTask(player, data.daily.kind, add, day)
    end

    -- 函数说明：在波次结束时推进日常任务进度
    local function ProgressDailyTaskOnWaveEnd(player, day)
        if not deps.IsValidPlayer(player) then return end
        EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if not data.daily or data.daily.completed then return end
        if data.daily.kind == 4 then
            data.daily.progress = math.min(data.daily.target or 0, (data.daily.progress or 0) + 1)
            if data.daily.progress >= (data.daily.target or 0) then
                RewardDailyTask(player, day)
            else
                deps.SyncGrowthNetvars(player, data)
            end
        end
        ProgressChainTask(player, 4, 1, day)
    end

    -- 函数说明：在挑战奖励发放时推进日常任务进度
    local function ProgressDailyTaskOnChallengeReward(player, day)
        if not deps.IsValidPlayer(player) then return end
        EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if not data.daily or data.daily.completed then return end
        if data.daily.kind == 5 then
            data.daily.progress = math.min(data.daily.target or 0, (data.daily.progress or 0) + 1)
            if data.daily.progress >= (data.daily.target or 0) then
                RewardDailyTask(player, day)
            else
                deps.SyncGrowthNetvars(player, data)
            end
        end
        ProgressChainTask(player, 5, 1, day)
    end

    -- 函数说明：在悬赏奖励发放时推进日常任务进度
    local function ProgressDailyTaskOnBountyReward(player, day)
        if not deps.IsValidPlayer(player) then return end
        EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if not data.daily or data.daily.completed then return end
        if data.daily.kind == 6 then
            data.daily.progress = math.min(data.daily.target or 0, (data.daily.progress or 0) + 1)
            if data.daily.progress >= (data.daily.target or 0) then
                RewardDailyTask(player, day)
            else
                deps.SyncGrowthNetvars(player, data)
            end
        end
        ProgressChainTask(player, 6, 1, day)
    end

    -- 函数说明：推进连杀达标类日常任务
    local function ProgressDailyTaskOnCombo(player, combo_count, day)
        if not deps.IsValidPlayer(player) then return end
        EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if not data.daily or data.daily.completed then return end
        if data.daily.kind == 7 then
            data.daily.progress = math.min(data.daily.target or 0, combo_count)
            if data.daily.progress >= (data.daily.target or 0) then
                RewardDailyTask(player, day)
            else
                deps.SyncGrowthNetvars(player, data)
            end
        end
        ProgressChainTask(player, 7, 1, day)
    end

    -- 函数说明：推进资源收集类日常任务
    local function ProgressDailyTaskOnCollect(player, amount, day)
        if not deps.IsValidPlayer(player) then return end
        EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if not data.daily or data.daily.completed then return end
        if data.daily.kind == 8 then
            data.daily.progress = math.min(data.daily.target or 0, (data.daily.progress or 0) + (amount or 1))
            if data.daily.progress >= (data.daily.target or 0) then
                RewardDailyTask(player, day)
            else
                deps.SyncGrowthNetvars(player, data)
            end
        end
        ProgressChainTask(player, 8, amount or 1, day)
    end

    -- 函数说明：推进存活天数类日常任务
    local function ProgressDailyTaskOnDayChange(player, day)
        if not deps.IsValidPlayer(player) then return end
        EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if not data.daily or data.daily.completed then return end
        if data.daily.kind == 9 then
            data.daily.progress = math.min(data.daily.target or 0, (data.daily.progress or 0) + 1)
            if data.daily.progress >= (data.daily.target or 0) then
                RewardDailyTask(player, day)
            else
                deps.SyncGrowthNetvars(player, data)
            end
        end
        ProgressChainTask(player, 9, 1, day)
    end

    -- 函数说明：推进遗物收集类日常任务
    local function ProgressDailyTaskOnRelicPick(player, day)
        if not deps.IsValidPlayer(player) then return end
        EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if not data.daily or data.daily.completed then return end
        if data.daily.kind == 11 then
            data.daily.progress = math.min(data.daily.target or 0, (data.daily.progress or 0) + 1)
            if data.daily.progress >= (data.daily.target or 0) then
                RewardDailyTask(player, day)
            else
                deps.SyncGrowthNetvars(player, data)
            end
        end
        ProgressChainTask(player, 11, 1, day)
    end

    -- 函数说明：推进天赋觉醒类日常任务
    local function ProgressDailyTaskOnTalentPick(player, day)
        if not deps.IsValidPlayer(player) then return end
        EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if not data.daily or data.daily.completed then return end
        if data.daily.kind == 12 then
            data.daily.progress = math.min(data.daily.target or 0, (data.daily.progress or 0) + 1)
            if data.daily.progress >= (data.daily.target or 0) then
                RewardDailyTask(player, day)
            else
                deps.SyncGrowthNetvars(player, data)
            end
        end
        ProgressChainTask(player, 12, 1, day)
    end

    -- 函数说明：推进连击技能类日常任务
    local function ProgressDailyTaskOnComboSkill(player, day)
        if not deps.IsValidPlayer(player) then return end
        EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if not data.daily or data.daily.completed then return end
        if data.daily.kind == 13 then
            data.daily.progress = math.min(data.daily.target or 0, (data.daily.progress or 0) + 1)
            if data.daily.progress >= (data.daily.target or 0) then
                RewardDailyTask(player, day)
            else
                deps.SyncGrowthNetvars(player, data)
            end
        end
        ProgressChainTask(player, 13, 1, day)
    end

    -- 函数说明：推进无伤战斗类日常任务（标记受伤）
    local function MarkDailyTaskDamageTaken(player)
        if not deps.IsValidPlayer(player) then return end
        local data = deps.EnsurePlayerData(player)
        if data.daily and not data.daily.completed and data.daily.kind == 10 then
            data._took_damage_today = true
        end
    end

    S.ResetComboState = ResetComboState
    S.RefreshComboState = RefreshComboState
    S.EnsureDailyTask = EnsureDailyTask
    S.ProgressDailyTaskOnKill = ProgressDailyTaskOnKill
    S.ProgressDailyTaskOnWaveEnd = ProgressDailyTaskOnWaveEnd
    S.ProgressDailyTaskOnChallengeReward = ProgressDailyTaskOnChallengeReward
    S.ProgressDailyTaskOnBountyReward = ProgressDailyTaskOnBountyReward
    S.ProgressDailyTaskOnCombo = ProgressDailyTaskOnCombo
    S.ProgressDailyTaskOnCollect = ProgressDailyTaskOnCollect
    S.ProgressDailyTaskOnDayChange = ProgressDailyTaskOnDayChange
    S.ProgressDailyTaskOnRelicPick = ProgressDailyTaskOnRelicPick
    S.ProgressDailyTaskOnTalentPick = ProgressDailyTaskOnTalentPick
    S.ProgressDailyTaskOnComboSkill = ProgressDailyTaskOnComboSkill
    S.MarkDailyTaskDamageTaken = MarkDailyTaskDamageTaken
    S.ProgressChainTask = ProgressChainTask
    return S
end

return M
