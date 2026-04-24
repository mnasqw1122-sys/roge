--[[
    文件说明：player_state.lua
    功能：管理玩家在肉鸽模式下的个体状态与成长数据。
    包括数据的初始化、网络变量的同步（供UI展示）以及成长属性（如伤害倍率、最大生命值）的应用。
]]
local M = {}
local StateSchema = require("rogue/state_schema")
local RogueConfig = require("rogue/config")

-- 函数说明：根据构筑评分返回流派等级名称
local function GetBuildTier(score)
    if score >= 120 then return "神话" end
    if score >= 80 then return "传说" end
    if score >= 45 then return "史诗" end
    if score >= 20 then return "精良" end
    return "普通"
end

-- 函数说明：生成加成摘要文本，供客户端"加成"标签页显示
local function BuildBonusSummaryText(data)
    if not data then return "" end
    local lines = {}

    local function Pct(v) return math.floor((v or 0) * 100 + 0.5) end

    local atk = {}
    if (data.damage_bonus or 0) > 0 then atk[#atk+1] = string.format("伤害+%d%%", Pct(data.damage_bonus)) end
    if (data.talent_crit_chance or 0) > 0 then atk[#atk+1] = string.format("暴击%d%%x%.1f", Pct(data.talent_crit_chance), data.talent_crit_dmg_mult or 1) end
    if (data.crit_chance or 0) > 0 then atk[#atk+1] = string.format("暴击%d%%", Pct(data.crit_chance)) end
    if (data.crit_dmg_mult or 1) > 1 then atk[#atk+1] = string.format("暴伤x%.1f", data.crit_dmg_mult) end
    if (data.talent_armor_pen or 0) > 0 then atk[#atk+1] = string.format("穿甲%d%%", Pct(data.talent_armor_pen)) end
    if (data.lifesteal_chance or 0) > 0 then atk[#atk+1] = string.format("虹吸%d%%(+%d)", Pct(data.lifesteal_chance), data.lifesteal_amount or 0) end
    if (data.elemental_bonus or 0) > 0 then atk[#atk+1] = string.format("元素+%d%%", Pct(data.elemental_bonus)) end
    if #atk > 0 then lines[#lines+1] = "═══攻击═══"; lines[#lines+1] = table.concat(atk, " ") end

    local def = {}
    if (data.hp_bonus or 0) > 0 then def[#def+1] = string.format("生命+%d", data.hp_bonus) end
    if (data.relic_damage_reduction or 0) > 0 then def[#def+1] = string.format("减伤%d%%", Pct(data.relic_damage_reduction)) end
    if (data.death_defy_chance or 0) > 0 then def[#def+1] = string.format("免死%d%%", Pct(data.death_defy_chance)) end
    if (data.elemental_resist or 0) > 0 then def[#def+1] = string.format("元素抗+%d%%", Pct(data.elemental_resist)) end
    if #def > 0 then lines[#lines+1] = "═══防御═══"; lines[#lines+1] = table.concat(def, " ") end

    local util = {}
    if (data.drop_bonus or 0) > 0 then util[#util+1] = string.format("掉落+%d%%", Pct(data.drop_bonus)) end
    if (data.speed_bonus or 0) > 0 then util[#util+1] = string.format("速度+%d%%", Pct(data.speed_bonus)) end
    if (data.luck_bonus or 0) > 0 then util[#util+1] = string.format("幸运+%d%%", Pct(data.luck_bonus)) end
    if (data.cooldown_reduction or 0) > 0 then util[#util+1] = string.format("冷却-%d%%", Pct(data.cooldown_reduction)) end
    if (data.combo_window_bonus or 0) > 0 then util[#util+1] = string.format("连杀窗+%.1fs", data.combo_window_bonus) end
    if (data.daily_reward_bonus or 0) > 0 then util[#util+1] = string.format("日常奖+%d%%", Pct(data.daily_reward_bonus)) end
    if #util > 0 then lines[#lines+1] = "═══辅助═══"; lines[#lines+1] = table.concat(util, " ") end

    local reg = {}
    if (data.talent_regen or 0) > 0 then reg[#reg+1] = string.format("回血+%.1f/3s", data.talent_regen) end
    if (data.regen_bonus or 0) > 0 then reg[#reg+1] = string.format("回血+%.1f/s", data.regen_bonus) end
    if (data.sanity_regen_bonus or 0) > 0 then reg[#reg+1] = string.format("回理智+%.1f/s", data.sanity_regen_bonus) end
    if #reg > 0 then lines[#lines+1] = "═══恢复═══"; lines[#lines+1] = table.concat(reg, " ") end

    if data.talent_levels and next(data.talent_levels) then
        local td = RogueConfig.TALENT_DEFS or {}
        local parts = {}
        for id, level in pairs(data.talent_levels) do
            for _, t in ipairs(td) do
                if t.id == id then
                    parts[#parts+1] = string.format("%sLv%d", t.name or "?", level)
                    break
                end
            end
        end
        if #parts > 0 then lines[#lines+1] = "═══天赋═══"; lines[#lines+1] = table.concat(parts, " ") end
    end

    if data.relics and #data.relics > 0 then
        local rd = RogueConfig.RELIC_DEFS or {}
        local parts = {}
        for _, rid in ipairs(data.relics) do
            for _, r in ipairs(rd) do
                if r.id == rid then
                    parts[#parts+1] = r.name or "?"
                    break
                end
            end
        end
        if #parts > 0 then lines[#lines+1] = "═══遗物═══"; lines[#lines+1] = table.concat(parts, " ") end
    end

    if data.relic_synergy_applied then
        local sd = RogueConfig.RELIC_SYNERGY_DEFS or {}
        local parts = {}
        if type(data.relic_synergy_applied) == "table" then
            for _, key in ipairs(data.relic_synergy_applied) do
                for _, s in ipairs(sd) do
                    if s.key == key or s.id == key then
                        parts[#parts+1] = s.name or tostring(key)
                        break
                    end
                end
            end
        end
        if #parts > 0 then lines[#lines+1] = "协同:" .. table.concat(parts, "、") end
    end

    if data.set_bonuses_applied and next(data.set_bonuses_applied) then
        local sd = RogueConfig.SET_BONUS_DEFS or {}
        local parts = {}
        for set_id, val in pairs(data.set_bonuses_applied) do
            local cnt = type(val) == "number" and val or 1
            for _, s in ipairs(sd) do
                if s.id == set_id then
                    local max_th = s.threshold and s.threshold[#s.threshold] or 4
                    parts[#parts+1] = string.format("%s%d/%d", s.name or "?", cnt, max_th)
                    break
                end
            end
        end
        if #parts > 0 then lines[#lines+1] = "═══套装═══"; lines[#lines+1] = table.concat(parts, " ") end
    end

    if data.relic_builds and next(data.relic_builds) then
        local bd = RogueConfig.RELIC_BUILD_DEFS or {}
        local parts = {}
        for build_key, active in pairs(data.relic_builds) do
            if active then
                for _, b in ipairs(bd) do
                    if b.key == build_key then
                        parts[#parts+1] = b.name or build_key
                        break
                    end
                end
            end
        end
        if #parts > 0 then lines[#lines+1] = "═══构筑═══"; lines[#lines+1] = table.concat(parts, "、") end
    end

    if (data.build_score or 0) > 0 then
        lines[#lines+1] = string.format("构筑:%s(%d)", GetBuildTier(data.build_score), data.build_score)
    end

    return #lines > 0 and table.concat(lines, "\n") or "暂无加成"
end

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
        if not d.talent_levels then d.talent_levels = {} end
        d.elemental_bonus = d.elemental_bonus or 0
        d.elemental_resist = d.elemental_resist or 0
        d.speed_bonus = d.speed_bonus or 0
        d.lifesteal_chance = d.lifesteal_chance or 0
        d.lifesteal_amount = d.lifesteal_amount or 0
        d.luck_bonus = d.luck_bonus or 0
        d.cooldown_reduction = d.cooldown_reduction or 0
        if not d.achievements then d.achievements = {} end
        if not d.achievement_progress then d.achievement_progress = {} end
        if not d.set_bonuses_applied then d.set_bonuses_applied = {} end
        d.set_damage_bonus = d.set_damage_bonus or 0
        d.set_combo_window = d.set_combo_window or 0
        d.set_sanity_regen_bonus = d.set_sanity_regen_bonus or 0
        d.set_ignite_chance = d.set_ignite_chance or 0
        d.set_shadow_dmg_bonus = d.set_shadow_dmg_bonus or 0
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
            data["season_hist" .. i .. "_challenge_done"] = e.challenge_done or 0
            data["season_hist" .. i .. "_challenge_total"] = e.challenge_total or 0
            data["season_hist" .. i .. "_bounty_done"] = e.bounty_done or 0
            data["season_hist" .. i .. "_bounty_total"] = e.bounty_total or 0
            data["season_hist" .. i .. "_style"] = e.style_id or 0
        end

        data.bonus_text = BuildBonusSummaryText(data)

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
