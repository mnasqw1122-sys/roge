--[[
    文件说明：state_schema.lua
    功能：统一管理网络变量（Netvars）的定义。
    提供注册网络变量、从服务端数据同步到网络变量，以及从网络变量读取快照表给客户端UI展示的工具方法。
]]
local M = {}
local RogueConfig = require("rogue/config")

local function BuildBadgeMask(list, bits)
    if type(list) ~= "table" then
        return 0
    end
    local m = 0
    for _, name in ipairs(list) do
        local v = bits[name]
        if v then
            m = m + v
        end
    end
    return m
end

local NETVAR_FIELDS = {
    { netvar = "rogue_kills", type = "net_ushortint", key = "kills" },
    { netvar = "rogue_points", type = "net_uint", key = "points" },
    { netvar = "rogue_dmg_bonus", type = "net_float", key = "damage_bonus" },
    { netvar = "rogue_hp_bonus", type = "net_shortint", key = "hp_bonus" },
    { netvar = "rogue_combo_count", type = "net_ushortint", key = "combo_count" },
    { netvar = "rogue_daily_progress", type = "net_ushortint", get = function(data) return (data.daily and data.daily.progress) or 0 end },
    { netvar = "rogue_daily_target", type = "net_ushortint", get = function(data) return (data.daily and data.daily.target) or 0 end },
    { netvar = "rogue_daily_kind", type = "net_byte", get = function(data) return (data.daily and data.daily.kind) or 0 end },
    { netvar = "rogue_daily_done", type = "net_bool", get = function(data) return (data.daily and data.daily.completed) == true end },
    { netvar = "rogue_talent_pending", type = "net_bool", get = function(data) return data.talent_pending == true end },
    { netvar = "rogue_talent_a", type = "net_byte", get = function(data) return (data.talent_options and data.talent_options[1]) or 0 end },
    { netvar = "rogue_talent_b", type = "net_byte", get = function(data) return (data.talent_options and data.talent_options[2]) or 0 end },
    { netvar = "rogue_talent_c", type = "net_byte", get = function(data) return (data.talent_options and data.talent_options[3]) or 0 end },
    { netvar = "rogue_wave_rule_active", type = "net_bool", get = function(data) return data.wave_rule_active == true end },
    { netvar = "rogue_wave_rule_id", type = "net_byte", key = "wave_rule_id" },
    { netvar = "rogue_threat_tier", type = "net_byte", key = "threat_tier", default = 1 },
    { netvar = "rogue_threat_reward_pct", type = "net_byte", key = "threat_reward_pct" },
    { netvar = "rogue_route_id", type = "net_byte", key = "route_id" },
    { netvar = "rogue_route_pending", type = "net_bool", get = function(data) return data.route_pending == true end },
    { netvar = "rogue_route_a", type = "net_byte", get = function(data) return (data.route_options and data.route_options[1]) or 0 end },
    { netvar = "rogue_route_b", type = "net_byte", get = function(data) return (data.route_options and data.route_options[2]) or 0 end },
    { netvar = "rogue_bounty_active", type = "net_bool", get = function(data) return data.bounty_active == true end },
    { netvar = "rogue_bounty_progress", type = "net_ushortint", key = "bounty_progress" },
    { netvar = "rogue_bounty_target", type = "net_ushortint", key = "bounty_target" },
    { netvar = "rogue_supply_pending", type = "net_bool", get = function(data) return data.supply_pending == true end },
    { netvar = "rogue_supply_a", type = "net_byte", get = function(data) return (data.supply_options and data.supply_options[1]) or 0 end },
    { netvar = "rogue_supply_b", type = "net_byte", get = function(data) return (data.supply_options and data.supply_options[2]) or 0 end },
    { netvar = "rogue_supply_c", type = "net_byte", get = function(data) return (data.supply_options and data.supply_options[3]) or 0 end },
    { netvar = "rogue_relic_pending", type = "net_bool", get = function(data) return data.relic_pending == true end },
    { netvar = "rogue_relic_a", type = "net_byte", get = function(data) return (data.relic_options and data.relic_options[1]) or 0 end },
    { netvar = "rogue_relic_b", type = "net_byte", get = function(data) return (data.relic_options and data.relic_options[2]) or 0 end },
    { netvar = "rogue_relic_c", type = "net_byte", get = function(data) return (data.relic_options and data.relic_options[3]) or 0 end },
    { netvar = "rogue_relic_count", type = "net_ushortint", key = "relic_count" },
    { netvar = "rogue_relic_synergy_count", type = "net_ushortint", key = "relic_synergy_count" },
    { netvar = "rogue_catastrophe_active", type = "net_bool", get = function(data) return data.catastrophe_active == true end },
    { netvar = "rogue_catastrophe_id", type = "net_byte", key = "catastrophe_id" },
    { netvar = "rogue_catastrophe_tier", type = "net_byte", key = "catastrophe_tier" },
    { netvar = "rogue_challenge_active", type = "net_bool", get = function(data) return data.challenge_active == true end },
    { netvar = "rogue_challenge_progress", type = "net_ushortint", key = "challenge_progress" },
    { netvar = "rogue_challenge_target", type = "net_ushortint", key = "challenge_target" },
    { netvar = "rogue_challenge_kind", type = "net_byte", key = "challenge_kind" },
    { netvar = "rogue_season_id", type = "net_ushortint", key = "season_id", default = 1 },
    { netvar = "rogue_season_phase", type = "net_byte", key = "season_phase", default = 1 },
    { netvar = "rogue_season_day_left", type = "net_ushortint", key = "season_day_left" },
    { netvar = "rogue_season_day_limit", type = "net_ushortint", key = "season_day_limit" },
    { netvar = "rogue_season_final_night", type = "net_bool", key = "season_final_night" },
    { netvar = "rogue_season_rotation", type = "net_byte", get = function(data) return data.season_rotation_id or data.season_rotation or 0 end },
    { netvar = "rogue_season_medals", type = "net_byte", key = "season_medals" },
    { netvar = "rogue_season_grade", type = "net_byte", get = function(data) return data.season_objective_grade or data.season_grade or 0 end },
    { netvar = "rogue_obj_done", type = "net_byte", get = function(data) return data.season_objective_done or data.season_obj_done or 0 end },
    { netvar = "rogue_obj_a_cur", type = "net_ushortint", get = function(data) return (data.season_obj_progress and data.season_obj_progress[1]) or data.obj_a_cur or 0 end },
    { netvar = "rogue_obj_a_tar", type = "net_ushortint", get = function(data) return (data.season_obj_target and data.season_obj_target[1]) or data.obj_a_tar or 0 end },
    { netvar = "rogue_obj_b_cur", type = "net_ushortint", get = function(data) return (data.season_obj_progress and data.season_obj_progress[2]) or data.obj_b_cur or 0 end },
    { netvar = "rogue_obj_b_tar", type = "net_ushortint", get = function(data) return (data.season_obj_target and data.season_obj_target[2]) or data.obj_b_tar or 0 end },
    { netvar = "rogue_obj_c_cur", type = "net_ushortint", get = function(data) return (data.season_obj_progress and data.season_obj_progress[3]) or data.obj_c_cur or 0 end },
    { netvar = "rogue_obj_c_tar", type = "net_ushortint", get = function(data) return (data.season_obj_target and data.season_obj_target[3]) or data.obj_c_tar or 0 end },
    { netvar = "rogue_obj_d_cur", type = "net_ushortint", get = function(data) return (data.season_obj_progress and data.season_obj_progress[4]) or data.obj_d_cur or 0 end },
    { netvar = "rogue_obj_d_tar", type = "net_ushortint", get = function(data) return (data.season_obj_target and data.season_obj_target[4]) or data.obj_d_tar or 0 end },
    { netvar = "rogue_loot_pity", type = "net_byte", get = function(data) return data.loot_pity_stack or data.loot_pity or 0 end },
    { netvar = "rogue_build_score", type = "net_ushortint", key = "build_score", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_season_last_score", type = "net_ushortint", key = "season_last_score", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_season_best_score", type = "net_ushortint", get = function(data) return data.best_season_score or data.season_best_score or 0 end, clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_season_last_rank", type = "net_byte", key = "season_last_rank" },
    { netvar = "rogue_season_last_style", type = "net_byte", key = "season_last_style_id" },
    { netvar = "rogue_season_last_badges", type = "net_ushortint", get = function(data) return BuildBadgeMask(data.season_last_badges, RogueConfig.PLAYER_BADGE_BITS or {}) end },
    { netvar = "rogue_season_last_team_badges", type = "net_ushortint", get = function(data) return BuildBadgeMask(data.season_last_team_badges, RogueConfig.TEAM_BADGE_BITS or {}) end },
    { netvar = "rogue_hist1_score", type = "net_ushortint", key = "season_hist1_score", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist1_rank", type = "net_byte", key = "season_hist1_rank" },
    { netvar = "rogue_hist1_grade", type = "net_byte", key = "season_hist1_grade" },
    { netvar = "rogue_hist1_badges", type = "net_ushortint", key = "season_hist1_badges" },
    { netvar = "rogue_hist1_kills", type = "net_ushortint", key = "season_hist1_kills", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist1_boss", type = "net_ushortint", key = "season_hist1_boss", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist1_deaths", type = "net_ushortint", key = "season_hist1_deaths", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist1_build", type = "net_ushortint", key = "season_hist1_build", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist1_route", type = "net_byte", key = "season_hist1_route" },
    { netvar = "rogue_hist1_cata_days", type = "net_byte", key = "season_hist1_catastrophe_days" },
    { netvar = "rogue_hist1_ch_done", type = "net_byte", key = "season_hist1_challenge_done" },
    { netvar = "rogue_hist1_ch_total", type = "net_byte", key = "season_hist1_challenge_total" },
    { netvar = "rogue_hist1_bo_done", type = "net_byte", key = "season_hist1_bounty_done" },
    { netvar = "rogue_hist1_bo_total", type = "net_byte", key = "season_hist1_bounty_total" },
    { netvar = "rogue_hist1_style", type = "net_byte", key = "season_hist1_style" },
    { netvar = "rogue_hist2_score", type = "net_ushortint", key = "season_hist2_score", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist2_rank", type = "net_byte", key = "season_hist2_rank" },
    { netvar = "rogue_hist2_grade", type = "net_byte", key = "season_hist2_grade" },
    { netvar = "rogue_hist2_badges", type = "net_ushortint", key = "season_hist2_badges" },
    { netvar = "rogue_hist2_kills", type = "net_ushortint", key = "season_hist2_kills", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist2_boss", type = "net_ushortint", key = "season_hist2_boss", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist2_deaths", type = "net_ushortint", key = "season_hist2_deaths", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist2_build", type = "net_ushortint", key = "season_hist2_build", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist2_route", type = "net_byte", key = "season_hist2_route" },
    { netvar = "rogue_hist2_cata_days", type = "net_byte", key = "season_hist2_catastrophe_days" },
    { netvar = "rogue_hist2_ch_done", type = "net_byte", key = "season_hist2_challenge_done" },
    { netvar = "rogue_hist2_ch_total", type = "net_byte", key = "season_hist2_challenge_total" },
    { netvar = "rogue_hist2_bo_done", type = "net_byte", key = "season_hist2_bounty_done" },
    { netvar = "rogue_hist2_bo_total", type = "net_byte", key = "season_hist2_bounty_total" },
    { netvar = "rogue_hist2_style", type = "net_byte", key = "season_hist2_style" },
    { netvar = "rogue_hist3_score", type = "net_ushortint", key = "season_hist3_score", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist3_rank", type = "net_byte", key = "season_hist3_rank" },
    { netvar = "rogue_hist3_grade", type = "net_byte", key = "season_hist3_grade" },
    { netvar = "rogue_hist3_badges", type = "net_ushortint", key = "season_hist3_badges" },
    { netvar = "rogue_hist3_kills", type = "net_ushortint", key = "season_hist3_kills", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist3_boss", type = "net_ushortint", key = "season_hist3_boss", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist3_deaths", type = "net_ushortint", key = "season_hist3_deaths", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist3_build", type = "net_ushortint", key = "season_hist3_build", clamp_min = 0, clamp_max = 65535 },
    { netvar = "rogue_hist3_route", type = "net_byte", key = "season_hist3_route" },
    { netvar = "rogue_hist3_cata_days", type = "net_byte", key = "season_hist3_catastrophe_days" },
    { netvar = "rogue_hist3_ch_done", type = "net_byte", key = "season_hist3_challenge_done" },
    { netvar = "rogue_hist3_ch_total", type = "net_byte", key = "season_hist3_challenge_total" },
    { netvar = "rogue_hist3_bo_done", type = "net_byte", key = "season_hist3_bounty_done" },
    { netvar = "rogue_hist3_bo_total", type = "net_byte", key = "season_hist3_bounty_total" },
    { netvar = "rogue_hist3_style", type = "net_byte", key = "season_hist3_style" },
}

local function ClampValue(v, def)
    if type(v) == "number" then
        if def.clamp_min and v < def.clamp_min then
            v = def.clamp_min
        end
        if def.clamp_max and v > def.clamp_max then
            v = def.clamp_max
        end
    end
    return v
end

-- 函数说明：按网络变量类型规范化值，避免 set 时出现类型不匹配崩溃。
local function NormalizeByType(v, def)
    if def.type == "net_bool" then
        return v == true
    end
    if type(v) ~= "number" then
        return 0
    end
    return v
end

local function GetDataValue(data, def)
    local v
    if def.get then
        v = def.get(data or {})
    elseif def.key then
        v = (data and data[def.key]) or nil
    end
    if v == nil then
        v = def.default
    end
    if v == nil then
        v = 0
    end
    v = NormalizeByType(v, def)
    return ClampValue(v, def)
end

-- 函数说明：按统一字段定义为玩家实例注册所有网络变量。
function M.RegisterNetvars(inst, global_env)
    for _, def in ipairs(NETVAR_FIELDS) do
        local ctor = global_env[def.type]
        if ctor and not inst[def.netvar] then
            inst[def.netvar] = ctor(inst.GUID, def.netvar, "rogue_dirty")
        end
    end
end

-- 函数说明：根据统一字段定义把服务端数据同步到客户端网络变量。
function M.SyncToNetvars(player, data)
    if not player then
        return
    end
    for _, def in ipairs(NETVAR_FIELDS) do
        local netvar = player[def.netvar]
        if netvar and netvar.set then
            netvar:set(GetDataValue(data, def))
        end
    end
end

-- 函数说明：从玩家网络变量生成客户端可消费的快照表。
function M.ReadFromNetvars(player)
    local out = {}
    if not player then
        return out
    end
    for _, def in ipairs(NETVAR_FIELDS) do
        local netvar = player[def.netvar]
        if netvar and netvar.value then
            out[def.netvar] = netvar:value()
        else
            out[def.netvar] = def.type == "net_bool" and false or (def.default or 0)
        end
    end
    return out
end

function M.GetFields()
    return NETVAR_FIELDS
end

return M
