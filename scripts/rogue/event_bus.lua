--[[
    文件说明：event_bus.lua
    功能：事件总线（发布-订阅模式）。
    从runtime_system.lua中独立，提供统一的事件通信机制。
    包含完整的事件目录(EventCatalog)用于文档化所有系统间通信。
]]
local M = {}

M._listeners = {}
M._event_log = {}
M._max_log_size = 100
M._debug_mode = false

--[[ 事件目录 (EventCatalog)
    on_kill            — 玩家击杀敌人  { killer, victim, damage }
    on_boss_kill       — Boss被击杀    { killer, boss, day }
    on_wave_start      — 新波次开始    { wave_id, wave_rule, day }
    on_wave_end        — 波次结束      { wave_id, day, players_alive }
    on_day_changed     — 天数变化      { new_day, old_day }
    on_player_death    — 玩家死亡      { player, killer }
    on_player_revive   — 玩家复活      { player, method }
    on_relic_pickup    — 遗物拾取      { player, relic_id, source }
    on_relic_choice    — 遗物选择      { player, relic_id }
    on_gear_drop       — 装备掉落      { player, item, rarity, day }
    on_gear_equip      — 装备穿戴      { player, item }
    on_season_phase_change — 赛季阶段切换 { phase_id, new_phase, day }
    on_season_start    — 赛季开始      { season_id, style, day_limit }
    on_season_end      — 赛季结束      { season_id, result }
    on_shop_purchase   — 商店购买      { player, item, price }
    on_shop_sell       — 物品出售      { player, item, value }
    on_talent_select   — 天赋选择      { player, talent_id }
    on_supply_use      — 补给使用      { player, supply_id }
    on_combo_milestone — 连击里程碑    { player, milestone_name, combo_count }
    on_combo_skill     — 连击技能释放  { player, skill_id }
    on_affix_roll      — 词缀抽取      { player, item, rarity, abilities }
    on_badge_earn      — 徽章获得      { player, badge_id }
    on_achievement_unlock — 成就解锁   { player, achievement_id }
]]

-- 订阅事件
function M.Subscribe(event_name, listener_fn, priority)
    if type(event_name) ~= "string" or type(listener_fn) ~= "function" then
        return false
    end
    M._listeners[event_name] = M._listeners[event_name] or {}
    local entry = { fn = listener_fn, priority = priority or 0 }
    table.insert(M._listeners[event_name], entry)
    -- 按优先级降序排序
    table.sort(M._listeners[event_name], function(a, b) return a.priority > b.priority end)
    return true
end

-- 取消订阅
function M.Unsubscribe(event_name, listener_fn)
    local listeners = M._listeners[event_name]
    if not listeners then return false end
    for i, entry in ipairs(listeners) do
        if entry.fn == listener_fn then
            table.remove(listeners, i)
            return true
        end
    end
    return false
end

-- 发布事件
function M.Emit(event_name, data)
    if M._debug_mode then
        table.insert(M._event_log, { name = event_name, data = data, time = os.time() })
        if #M._event_log > M._max_log_size then
            table.remove(M._event_log, 1)
        end
    end
    local listeners = M._listeners[event_name]
    if not listeners then return 0 end
    local count = 0
    for _, entry in ipairs(listeners) do
        local ok, err = pcall(entry.fn, data or {})
        if ok then
            count = count + 1
        elseif M._debug_mode then
            print("[EventBus] Listener error for " .. tostring(event_name) .. ": " .. tostring(err))
        end
    end
    return count
end

-- 清空某事件的所有监听器
function M.ClearEvent(event_name)
    M._listeners[event_name] = nil
end

-- 启用/禁用调试日志
function M.SetDebugMode(enabled)
    M._debug_mode = enabled == true
end

-- 获取最近的事件日志
function M.GetEventLog()
    return M._event_log
end

-- 获取事件目录
function M.GetEventCatalog()
    return {
        on_kill = "玩家击杀敌人",
        on_boss_kill = "Boss被击杀",
        on_wave_start = "新波次开始",
        on_wave_end = "波次结束",
        on_day_changed = "天数变化",
        on_player_death = "玩家死亡",
        on_player_revive = "玩家复活",
        on_relic_pickup = "遗物拾取",
        on_relic_choice = "遗物选择",
        on_gear_drop = "装备掉落",
        on_gear_equip = "装备穿戴",
        on_season_phase_change = "赛季阶段切换",
        on_season_start = "赛季开始",
        on_season_end = "赛季结束",
        on_shop_purchase = "商店购买",
        on_shop_sell = "物品出售",
        on_talent_select = "天赋选择",
        on_supply_use = "补给使用",
        on_combo_milestone = "连击里程碑",
        on_combo_skill = "连击技能释放",
        on_affix_roll = "词缀抽取",
        on_badge_earn = "徽章获得",
        on_achievement_unlock = "成就解锁",
    }
end

return M
