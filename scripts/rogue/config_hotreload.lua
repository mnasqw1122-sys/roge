--[[
    文件说明：config_hotreload.lua
    功能：P3-14 配置热更新系统。
    支持在游戏运行期间重新读取模组配置，并将变更通知到各子系统，
    无需重启世界即可调整部分参数（如掉落率、精英概率、Boss间隔等）。
]]
local M = {}

-- 函数说明：创建配置热更新系统实例
function M.Create(deps)
    local state = {}
    state._last_config = nil
    state._reload_cooldown = 0

    -- 函数说明：记录当前配置快照，用于后续比对变更
    local function SnapshotConfig(cfg)
        return {
            NORMAL_DROP_CHANCE = cfg.NORMAL_DROP_CHANCE,
            ELITE_CHANCE = cfg.ELITE_CHANCE,
            BOSS_INTERVAL = cfg.BOSS_INTERVAL,
            MAX_HOSTILES_NEAR_PLAYER = cfg.MAX_HOSTILES_NEAR_PLAYER,
            ELITE_AFFIX_CHANCE = cfg.ELITE_AFFIX_CHANCE,
            SECOND_AFFIX_CHANCE = cfg.SECOND_AFFIX_CHANCE,
            BOSS_PHASE_MODE = cfg.BOSS_PHASE_MODE,
            BOSS_PHASE_MINION_COUNT = cfg.BOSS_PHASE_MINION_COUNT,
            BOSS_PHASE_FX_MODE = cfg.BOSS_PHASE_FX_MODE,
            GROUND_LOOT_CLEAN_ENABLED = cfg.GROUND_LOOT_CLEAN_ENABLED,
            GROUND_LOOT_CLEAN_INTERVAL_DAYS = cfg.GROUND_LOOT_CLEAN_INTERVAL_DAYS,
            GROUND_LOOT_CLEAN_DELAY_NIGHT = cfg.GROUND_LOOT_CLEAN_DELAY_NIGHT,
            GROUND_LOOT_CLEAN_BATCH_SIZE = cfg.GROUND_LOOT_CLEAN_BATCH_SIZE,
            GROUND_LOOT_CLEAN_SEARCH_RADIUS = cfg.GROUND_LOOT_CLEAN_SEARCH_RADIUS,
            AI_NPC_ENABLED = cfg.AI_NPC_ENABLED,
        }
    end

    -- 函数说明：比较两个配置快照，返回变更的键列表
    local function DiffConfig(old_cfg, new_cfg)
        local changed = {}
        if not old_cfg then
            for k, _ in pairs(new_cfg or {}) do
                table.insert(changed, k)
            end
            return changed
        end
        for k, v in pairs(new_cfg or {}) do
            if old_cfg[k] ~= v then
                table.insert(changed, k)
            end
        end
        return changed
    end

    -- 函数说明：根据变更的键列表，通知相关子系统更新
    local function NotifySubsystems(changed, new_cfg)
        if #changed == 0 then return end

        local changed_set = {}
        for _, k in ipairs(changed) do
            changed_set[k] = true
        end

        -- 更新主配置引用
        if deps.Config then
            for k, v in pairs(new_cfg) do
                if changed_set[k] then
                    deps.Config[k] = v
                end
            end
        end

        -- 通知波次系统更新Boss间隔
        if changed_set.BOSS_INTERVAL and deps.WaveSystem and deps.WaveSystem.UpdateBossInterval then
            deps.WaveSystem.UpdateBossInterval(new_cfg.BOSS_INTERVAL)
        end

        -- 通知运行时系统更新敌人上限
        if changed_set.MAX_HOSTILES_NEAR_PLAYER and deps.RuntimeSystem and deps.RuntimeSystem.UpdateHostileCap then
            deps.RuntimeSystem.UpdateHostileCap(new_cfg.MAX_HOSTILES_NEAR_PLAYER)
        end

        -- 广播配置变更消息
        if deps.Announce then
            local names = {}
            for _, k in ipairs(changed) do
                table.insert(names, k)
            end
            if #names <= 3 then
                deps.Announce("配置已热更新: " .. table.concat(names, ", "))
            else
                deps.Announce("配置已热更新: " .. #names .. " 项参数变更")
            end
        end
    end

    -- 函数说明：执行配置热更新，重新读取模组配置并通知子系统
    function state.ReloadConfig()
        local now = deps.GetTime and deps.GetTime() or 0
        if now - state._reload_cooldown < 5 then
            return false
        end
        state._reload_cooldown = now

        local RogueConfig = deps.RogueConfig
        if not RogueConfig then return false end

        local new_cfg = RogueConfig.LoadConfig(function(key)
            return deps.GetModConfigData(key)
        end)

        -- 保留不可热更新的字段
        if deps.Config then
            new_cfg.WORLD_VARIANT = deps.Config.WORLD_VARIANT
            new_cfg.START_DAY = deps.Config.START_DAY
            new_cfg.SEASON_PROFILE = deps.Config.SEASON_PROFILE
            new_cfg.SEASON_DAY_LIMIT = deps.Config.SEASON_DAY_LIMIT
            new_cfg.SEASON_RESET_DELAY = deps.Config.SEASON_RESET_DELAY
            new_cfg.SEASON_GRACE_DAYS = deps.Config.SEASON_GRACE_DAYS
            new_cfg.WAVE_START_DELAY = deps.Config.WAVE_START_DELAY
            new_cfg.WAVE_END_DELAY = deps.Config.WAVE_END_DELAY
        end

        local new_snapshot = SnapshotConfig(new_cfg)
        local changed = DiffConfig(state._last_config, new_snapshot)
        state._last_config = new_snapshot

        NotifySubsystems(changed, new_cfg)
        return true, #changed
    end

    -- 函数说明：初始化配置快照
    function state.InitSnapshot(cfg)
        state._last_config = SnapshotConfig(cfg)
    end

    -- 函数说明：获取当前配置快照
    function state.GetSnapshot()
        return state._last_config
    end

    return state
end

return M
