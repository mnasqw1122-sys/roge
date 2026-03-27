--[[
    文件说明：season_system.lua
    功能：赛季流程控制器。
    负责推进赛季阶段（准备、进行中、终局日、终局夜、结算、重置），控制赛季天数限制、轮换词缀选择以及触发世界重置逻辑。
]]
local M = {}

function M.Create(deps)
    local S = {}

    local PHASE = {
        PREPARE = 1,
        RUNNING = 2,
        FINAL_DAY = 3,
        FINAL_NIGHT = 4,
        RESULT = 5,
        RESET_PENDING = 6,
    }

    local state = {
        season_id = 1,
        phase = PHASE.PREPARE,
        day_limit = deps.Config.SEASON_DAY_LIMIT or 80,
        rotation_id = 1,
        rotation_name = "默认赛季",
        reset_task = nil,
        reset_warn_tasks = nil,
        reset_retry_count = 0,
        reset_retry_max = 6,
        reset_eta = 0,
    }

    local function GetCurrentDay()
        return deps.GetCurrentDay()
    end

    local function IsGracePeriod(day)
        local d = day or GetCurrentDay()
        local start_day = deps.Config.STARTING_DAY or 1
        local grace_days = math.max(0, deps.Config.SEASON_GRACE_DAYS or 0)
        if grace_days <= 0 then return false end
        return d < (start_day + grace_days)
    end

    local function PickRotation(avoid_id)
        local defs = deps.SEASON_AFFIX_ROTATION_DEFS or {}
        if #defs <= 0 then
            return 0, "默认赛季"
        end
        if #defs == 1 then
            return 1, defs[1].name or "赛季轮换1"
        end
        local idx = math.random(#defs)
        if avoid_id and idx == avoid_id then
            idx = (idx % #defs) + 1
        end
        return idx, defs[idx].name or ("赛季轮换" .. tostring(idx))
    end

    local function ResolveRotationNameById(id)
        local defs = deps.SEASON_AFFIX_ROTATION_DEFS or {}
        local idx = tonumber(id) or 0
        if idx > 0 and defs[idx] then
            return defs[idx].name or ("赛季轮换" .. tostring(idx))
        end
        return "默认赛季"
    end

    local function SyncToPlayer(player)
        if not player or not player:IsValid() then return end
        local day = GetCurrentDay()
        local day_left = math.max(0, (state.day_limit or 0) - day)
        if player.rogue_season_id then player.rogue_season_id:set(state.season_id or 1) end
        if player.rogue_season_phase then player.rogue_season_phase:set(state.phase or PHASE.PREPARE) end
        if player.rogue_season_day_left then player.rogue_season_day_left:set(day_left) end
        if player.rogue_season_day_limit then player.rogue_season_day_limit:set(state.day_limit or 0) end
        if player.rogue_season_final_night then player.rogue_season_final_night:set(state.phase == PHASE.FINAL_NIGHT) end
        if player.rogue_season_rotation then player.rogue_season_rotation:set(state.rotation_id or 0) end
        if deps.EnsurePlayerData and deps.SyncGrowthNetvars then
            local data = deps.EnsurePlayerData(player)
            data.season_id = state.season_id or 1
            data.season_phase = state.phase or PHASE.PREPARE
            data.season_day_left = day_left
            data.season_day_limit = state.day_limit or 0
            data.season_final_night = state.phase == PHASE.FINAL_NIGHT
            data.season_rotation_id = state.rotation_id or 0
            deps.SyncGrowthNetvars(player, data)
        end
    end

    local function SyncToAllPlayers()
        for _, player in ipairs(deps.AllPlayers) do
            SyncToPlayer(player)
        end
    end

    local function SetPhase(phase, announce)
        if state.phase == phase then return end
        state.phase = phase
        if announce and announce ~= "" then
            deps.Announce(announce)
        end
        SyncToAllPlayers()
    end

    local function CancelResetTasks()
        if state.reset_task then
            state.reset_task:Cancel()
            state.reset_task = nil
        end
        if state.reset_warn_tasks then
            for _, t in ipairs(state.reset_warn_tasks) do
                if t then t:Cancel() end
            end
            state.reset_warn_tasks = nil
        end
        state.reset_retry_count = 0
        state.reset_eta = 0
    end

    local function BeginNewSeason(day)
        CancelResetTasks()
        state.season_id = (state.season_id or 1) + 1
        state.phase = IsGracePeriod(day) and PHASE.PREPARE or PHASE.RUNNING
        state.rotation_id, state.rotation_name = PickRotation(state.rotation_id)
        if deps.OnSeasonChanged then
            deps.OnSeasonChanged(state.season_id)
        end
        deps.Announce("新赛季开始：S" .. tostring(state.season_id) .. " · " .. tostring(state.rotation_name))
        SyncToAllPlayers()
    end

    local function BeginResetCountdown(world, additional_delay)
        if state.reset_task then return end
        local delay = math.max(5, deps.Config.SEASON_RESET_DELAY or 18)
        if additional_delay and type(additional_delay) == "number" then
            delay = delay + additional_delay
        end
        delay = math.ceil(delay)
        state.reset_eta = (deps.GetTime and deps.GetTime() or 0) + delay
        SetPhase(PHASE.RESET_PENDING, "赛季结算完成，世界将在 " .. delay .. " 秒后重置。")
        state.reset_warn_tasks = {}
        local marks = { 15, 10, 5, 3, 2, 1 }
        for _, sec in ipairs(marks) do
            if delay > sec then
                local t = world:DoTaskInTime(delay - sec, function()
                    deps.Announce("世界重置倒计时：" .. sec .. " 秒")
                end)
                table.insert(state.reset_warn_tasks, t)
            end
        end
        state.reset_task = world:DoTaskInTime(delay, function()
            state.reset_task = nil
            if state.reset_warn_tasks then
                for _, t in ipairs(state.reset_warn_tasks) do
                    if t then t:Cancel() end
                end
                state.reset_warn_tasks = nil
            end
            local ok = deps.RequestWorldReset()
            if ok ~= true then
                state.reset_retry_count = (state.reset_retry_count or 0) + 1
                if state.reset_retry_count > (state.reset_retry_max or 6) then
                    deps.Announce("世界重置多次失败，请检查管理权限或服务器重生配置。")
                    return
                end
                local wait_s = math.min(30, 8 + state.reset_retry_count * 2)
                deps.Announce("世界重置请求失败，" .. wait_s .. "秒后重试(" .. state.reset_retry_count .. "/" .. state.reset_retry_max .. ")...")
                state.reset_task = world:DoTaskInTime(wait_s, function()
                    state.reset_task = nil
                    deps.RequestWorldReset()
                end)
            else
                state.reset_retry_count = 0
            end
        end)
    end

    local function OnPhase(world, phase_name)
        local day = GetCurrentDay()
        if day <= (deps.Config.START_DAY or 1) and state.phase >= PHASE.RESULT then
            BeginNewSeason(day)
        end
        if state.phase == PHASE.RESET_PENDING then
            SyncToAllPlayers()
            return
        end
        if day < state.day_limit then
            if IsGracePeriod(day) then
                SetPhase(PHASE.PREPARE)
            else
                SetPhase(PHASE.RUNNING)
            end
            return
        end
        if day == state.day_limit then
            if phase_name == "day" then
                SetPhase(PHASE.FINAL_DAY, "赛季终局日到来，今晚将迎来终局战。")
            elseif phase_name == "night" then
                SetPhase(PHASE.FINAL_NIGHT, "终局夜开启！坚持到黎明，完成赛季。")
            end
            return
        end
        if day > state.day_limit then
            local settle_delay = 0
            if state.phase < PHASE.RESULT then
                SetPhase(PHASE.RESULT, "赛季结束，开始结算。")
                if deps.FinalizeSeason then
                    settle_delay = deps.FinalizeSeason(day) or 0
                end
            end
            BeginResetCountdown(world, settle_delay)
        end
    end

    S.GetState = function()
        return state
    end

    S.GetSeasonId = function()
        return state.season_id or 1
    end

    S.GetPhaseConst = function()
        return PHASE
    end

    S.SyncSeasonStateToPlayer = function(player)
        SyncToPlayer(player)
    end

    S.SyncSeasonStateToAllPlayers = function()
        SyncToAllPlayers()
    end

    S.OnWorldPhaseChange = function(world, phase_name)
        OnPhase(world, phase_name)
    end

    S.CanRunCombatLoop = function()
        return state.phase < PHASE.RESULT
    end

    S.IsFinalNight = function()
        return state.phase == PHASE.FINAL_NIGHT
    end

    S.IsGracePeriod = function(day)
        return IsGracePeriod(day)
    end

    S.ExportState = function()
        return {
            season_id = state.season_id or 1,
            phase = state.phase or PHASE.PREPARE,
            day_limit = state.day_limit or (deps.Config.SEASON_DAY_LIMIT or 80),
            rotation_id = state.rotation_id or 0,
            rotation_name = state.rotation_name or ResolveRotationNameById(state.rotation_id),
            reset_retry_count = state.reset_retry_count or 0,
            reset_eta = state.reset_eta or 0,
        }
    end

    S.ImportState = function(saved)
        if type(saved) ~= "table" then
            return
        end
        CancelResetTasks()
        state.season_id = math.max(1, tonumber(saved.season_id) or state.season_id or 1)
        state.phase = tonumber(saved.phase) or state.phase or PHASE.PREPARE
        state.day_limit = math.max(1, tonumber(saved.day_limit) or state.day_limit or (deps.Config.SEASON_DAY_LIMIT or 80))
        state.rotation_id = tonumber(saved.rotation_id) or state.rotation_id or 0
        state.rotation_name = saved.rotation_name or ResolveRotationNameById(state.rotation_id)
        state.reset_retry_count = 0
        state.reset_eta = tonumber(saved.reset_eta) or 0
        SyncToAllPlayers()
    end

    do
        state.rotation_id, state.rotation_name = PickRotation(nil)
    end

    return S
end

return M
