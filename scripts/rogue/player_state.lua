--[[
    文件说明：player_state.lua
    功能：管理玩家在肉鸽模式下的个体状态与成长数据。
    包括数据的初始化、网络变量的同步（供UI展示）以及成长属性（如伤害倍率、最大生命值）的应用。
]]
local M = {}
local StateSchema = require("rogue/state_schema")

function M.Create(deps)
    local state = {}

    -- 确保玩家对象上的 rogue_data 存在并初始化各个默认字段
    state.EnsurePlayerData = function(player)
        if not player.rogue_data then
            player.rogue_data = { kills = 0, damage_bonus = 0, hp_bonus = 0, points = 0 }
        end
        local d = player.rogue_data
        d.points = d.points or 0
        d.last_talent_kills = d.last_talent_kills or 0
        d.combo_count = d.combo_count or 0
        d.combo_mult = d.combo_mult or 1
        d.combo_window_bonus = d.combo_window_bonus or 0
        d.drop_bonus = d.drop_bonus or 0
        d.daily_reward_bonus = d.daily_reward_bonus or 0
        d.talent_pick_count = d.talent_pick_count or 0
        d.talent_pending = d.talent_pending == true
        d.supply_pending = d.supply_pending == true
        d.relic_pending = d.relic_pending == true
        if not d.talent_options then d.talent_options = {} end
        if not d.supply_options then d.supply_options = { 1, 2, 3 } end
        if not d.relic_options then d.relic_options = {} end
        if not d.relics then d.relics = {} end
        d.relic_count = d.relic_count or 0
        if not d.relic_synergy_applied then d.relic_synergy_applied = {} end
        d.relic_synergy_count = d.relic_synergy_count or 0
        d.relic_initialized = d.relic_initialized == true
        d.last_relic_kills = d.last_relic_kills or 0
        d.best_season_score = d.best_season_score or 0
        d.season_last_score = d.season_last_score or 0
        d.season_last_rank = d.season_last_rank or 0
        d.season_rotation_id = d.season_rotation_id or 1
        d.season_medals = d.season_medals or 0
        d.season_objective_grade = d.season_objective_grade or 0
        d.season_objective_done = d.season_objective_done or 0
        if not d.season_obj_progress then d.season_obj_progress = { 0, 0, 0, 0 } end
        if not d.season_obj_target then d.season_obj_target = { 0, 0, 0, 0 } end
        d.loot_pity_stack = d.loot_pity_stack or 0
        d.build_score = d.build_score or 0
        if not d.build_affix_counts then d.build_affix_counts = {} end
        if not d.build_rarity_counts then d.build_rarity_counts = { common = 0, rare = 0, epic = 0, legendary = 0 } end
        if not d.season_history then d.season_history = {} end
        if not d.daily then d.daily = {} end
        d.wave_rule_active = d.wave_rule_active == true
        d.wave_rule_id = d.wave_rule_id or 0
        d.threat_tier = d.threat_tier or 1
        d.threat_reward_pct = d.threat_reward_pct or 0
        d.route_id = d.route_id or 0
        d.route_pending = d.route_pending == true
        if not d.route_options then d.route_options = {} end
        d.bounty_active = d.bounty_active == true
        d.bounty_progress = d.bounty_progress or 0
        d.bounty_target = d.bounty_target or 0
        d.catastrophe_active = d.catastrophe_active == true
        d.catastrophe_id = d.catastrophe_id or 0
        d.catastrophe_tier = d.catastrophe_tier or 0
        d.challenge_active = d.challenge_active == true
        d.challenge_progress = d.challenge_progress or 0
        d.challenge_target = d.challenge_target or 0
        d.challenge_kind = d.challenge_kind or 0

        if deps.GLOBAL and deps.GLOBAL.TheSim and player.userid and not player.rogue_history_loaded then
            player.rogue_history_loaded = true
            deps.GLOBAL.TheSim:GetPersistentString("rogue_history_" .. tostring(player.userid), function(load_success, str)
                if load_success and str and string.len(str) > 0 then
                    local status, saved = pcall(deps.GLOBAL.json.decode, str)
                    if status and saved and type(saved) == "table" then
                        d.season_history = saved
                        if state.SyncGrowthNetvars then
                            state.SyncGrowthNetvars(player, d)
                        end
                    end
                end
            end)
            
            deps.GLOBAL.TheSim:GetPersistentString("rogue_points_" .. tostring(player.userid), function(load_success, str)
                if load_success and str and string.len(str) > 0 then
                    local status, saved = pcall(deps.GLOBAL.json.decode, str)
                    if status and saved and type(saved) == "table" and saved.points then
                        -- 如果有 claimed 标记说明已经发过了，不再重复发放，避免玩家退出重进刷积分
                        if not saved.claimed then
                            d.points = saved.points
                            if player.rogue_points then
                                player.rogue_points:set(d.points)
                            end
                            
                            -- 提示玩家获得了上赛季结算的积分奖励
                            if player.components.talker then
                                player:DoTaskInTime(3, function(p)
                                    if p:IsValid() and p.components.talker then
                                        p.components.talker:Say("上个赛季结算奖励了: " .. saved.points .. " 积分")
                                    end
                                end)
                            end
                            
                            -- 标记为已发放，防止退出重进时错误地重复发放积分，或者覆盖本局累积的积分
                            saved.claimed = true
                            local p_status, p_str2 = pcall(deps.GLOBAL.json.encode, saved)
                            if p_status and p_str2 then
                                deps.GLOBAL.TheSim:SetPersistentString("rogue_points_" .. tostring(player.userid), p_str2, false, function() end)
                            end
                        end
                    end
                end
            end)
        end

        return player.rogue_data
    end

    -- 将服务端的玩家成长数据同步到对应的网络变量(netvars)中，供客户端UI展示
    state.SyncGrowthNetvars = function(player, data)
        data = data or player.rogue_data
        if not data then return end

        local h = data.season_history or {}
        for i = 1, 3 do
            local e = h[i] or {}
            data["season_hist" .. i .. "_score"] = e.score or 0
            data["season_hist" .. i .. "_rank"] = e.rank or 0
            data["season_hist" .. i .. "_grade"] = e.grade or 0
            data["season_hist" .. i .. "_badges"] = #(e.badges or {})
            data["season_hist" .. i .. "_kills"] = e.kills or 0
            data["season_hist" .. i .. "_boss"] = e.boss or 0
            data["season_hist" .. i .. "_deaths"] = e.deaths or 0
            data["season_hist" .. i .. "_build"] = e.build_score or 0
            data["season_hist" .. i .. "_route"] = e.route_id or 0
            data["season_hist" .. i .. "_catastrophe_days"] = e.catastrophe_days or 0
            data["season_hist" .. i .. "_challenge_done"] = e.challenge_done or 0
            data["season_hist" .. i .. "_challenge_total"] = e.challenge_total or 0
            data["season_hist" .. i .. "_bounty_done"] = e.bounty_done or 0
            data["season_hist" .. i .. "_bounty_total"] = e.bounty_total or 0
            data["season_hist" .. i .. "_style"] = e.style_id or 0
        end

        StateSchema.SyncToNetvars(player, data)
    end

    -- 应用玩家的成长数据到实际属性（如攻击倍率、生命值上限），并触发网络同步
    state.ApplyGrowthState = function(player, data, apply_health)
        data = data or player.rogue_data
        if not data then return end
        if player.components.combat then
            player.components.combat.externaldamagemultipliers:SetModifier(deps.CONST.DAMAGE_MODIFIER_KEY, 1 + (data.damage_bonus or 0))
        end
        if apply_health and player.components.health then
            local applied = player.rogue_applied_hp_bonus or 0
            local target = data.hp_bonus or 0
            local delta = target - applied
            if delta ~= 0 then
                player.components.health:SetMaxHealth(player.components.health.maxhealth + delta)
                if delta > 0 then
                    player.components.health:DoDelta(delta)
                end
                player.rogue_applied_hp_bonus = target
            end
        end
        state.SyncGrowthNetvars(player, data)
    end

    return state
end

return M
