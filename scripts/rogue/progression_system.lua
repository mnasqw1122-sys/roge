--[[
    文件说明：progression_system.lua
    功能：局内成长与任务系统。
    管理玩家的连杀状态（Combo）以及每日挑战任务（如击杀数量、完成波次），并在达成目标时发放额外奖励。
]]
local M = {}

function M.Create(deps)
    local S = {}

    local function GetRotationMod(data)
        local rid = (data and data.season_rotation_id) or 1
        local mods = deps.DAILY_TASK_ROTATION_MODS or {}
        return mods[rid]
    end

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

    local function ApplyTargetMultiplier(data, kind, target)
        local mod = GetRotationMod(data)
        if mod and mod.target_mult and mod.target_mult[kind] then
            target = math.floor(target * mod.target_mult[kind] + 0.5)
        end
        return math.max(1, target)
    end

    -- 重置玩家的连杀状态（连杀计数归零、移除连杀伤害倍率）
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

    -- 刷新连杀状态（增加击杀数，延长判定窗口，计算新的连击伤害倍率）
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
        data.combo_mult = math.min(deps.CONST.COMBO_MAX_MULT, 1 + steps * deps.CONST.COMBO_STEP_MULT)

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

    -- 确保玩家拥有当天的每日任务，如果没有则随机分配一个
    local function EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if data.daily and data.daily.day == day then
            return
        end

        local kind = PickDailyKind(data)
        local target = 0
        if kind == 1 then
            target = 20 + math.floor(day * 1.5)
        elseif kind == 2 then
            target = 2 + math.floor(day / 8)
        elseif kind == 3 then
            target = 1
        elseif kind == 4 then
            target = day >= 40 and 2 or 1
        elseif kind == 5 then
            target = day >= 45 and 2 or 1
        else
            target = day >= 45 and 2 or 1
        end
        target = ApplyTargetMultiplier(data, kind, target)

        data.daily = {
            day = day,
            kind = kind,
            target = target,
            progress = 0,
            completed = false,
            rewarded = false,
        }

        deps.SyncGrowthNetvars(player, data)
        deps.Announce(player:GetDisplayName() .. " 今日任务：" .. deps.DAILY_KIND_NAMES[kind] .. " " .. target .. " 次")
    end

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

        deps.SyncGrowthNetvars(player, data)
        deps.Announce(player:GetDisplayName() .. " 完成每日任务，获得额外奖励！")
    end

    -- 在击杀敌人时推进每日任务的进度，如果完成则发放奖励
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
        end

        if add <= 0 then return end

        data.daily.progress = math.min(data.daily.target or 0, (data.daily.progress or 0) + add)
        if data.daily.progress >= (data.daily.target or 0) then
            RewardDailyTask(player, day)
        else
            deps.SyncGrowthNetvars(player, data)
        end
    end

    -- 在波次结束时推进“生存类”每日任务进度，并在达成后发放奖励
    local function ProgressDailyTaskOnWaveEnd(player, day)
        if not deps.IsValidPlayer(player) then return end
        EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if not data.daily or data.daily.completed then return end
        if data.daily.kind ~= 4 then return end
        data.daily.progress = math.min(data.daily.target or 0, (data.daily.progress or 0) + 1)
        if data.daily.progress >= (data.daily.target or 0) then
            RewardDailyTask(player, day)
        else
            deps.SyncGrowthNetvars(player, data)
        end
    end

    -- 在挑战奖励发放时推进挑战类每日任务进度，并在达成后发放奖励
    local function ProgressDailyTaskOnChallengeReward(player, day)
        if not deps.IsValidPlayer(player) then return end
        EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if not data.daily or data.daily.completed then return end
        if data.daily.kind ~= 5 then return end
        data.daily.progress = math.min(data.daily.target or 0, (data.daily.progress or 0) + 1)
        if data.daily.progress >= (data.daily.target or 0) then
            RewardDailyTask(player, day)
        else
            deps.SyncGrowthNetvars(player, data)
        end
    end

    -- 在悬赏奖励发放时推进悬赏类每日任务进度，并在达成后发放奖励
    local function ProgressDailyTaskOnBountyReward(player, day)
        if not deps.IsValidPlayer(player) then return end
        EnsureDailyTask(player, day)
        local data = deps.EnsurePlayerData(player)
        if not data.daily or data.daily.completed then return end
        if data.daily.kind ~= 6 then return end
        data.daily.progress = math.min(data.daily.target or 0, (data.daily.progress or 0) + 1)
        if data.daily.progress >= (data.daily.target or 0) then
            RewardDailyTask(player, day)
        else
            deps.SyncGrowthNetvars(player, data)
        end
    end

    S.ResetComboState = ResetComboState
    S.RefreshComboState = RefreshComboState
    S.EnsureDailyTask = EnsureDailyTask
    S.ProgressDailyTaskOnKill = ProgressDailyTaskOnKill
    S.ProgressDailyTaskOnWaveEnd = ProgressDailyTaskOnWaveEnd
    S.ProgressDailyTaskOnChallengeReward = ProgressDailyTaskOnChallengeReward
    S.ProgressDailyTaskOnBountyReward = ProgressDailyTaskOnBountyReward
    return S
end

return M
