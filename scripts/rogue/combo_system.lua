--[[
    文件说明：combo_system.lua
    功能：连击系统独立模块。
    管理连杀状态、连击倍率、里程碑奖励和连击技能释放。
    从progression_system.lua中拆分并扩展。
]]
local M = {}
local RogueConfig = require("rogue/config")

function M.Create(deps)
    local S = {}

    local CONST = RogueConfig.CONST or {}

    -- 函数说明：获取连击里程碑定义
    local function GetMilestoneDefs()
        return {
            { kills = 10, reward = "combo_milestone_10", name = "初露锋芒", desc = "连杀10次：恢复20生命值" },
            { kills = 25, reward = "combo_milestone_25", name = "势不可挡", desc = "连杀25次：获得15秒+10%伤害增益" },
            { kills = 50, reward = "combo_milestone_50", name = "杀神降临", desc = "连杀50次：释放一次范围冲击波" },
            { kills = 75, reward = "combo_milestone_75", name = "修罗再临", desc = "连杀75次：3秒无敌+范围眩晕" },
            { kills = 100, reward = "combo_milestone_100", name = "万夫莫敌", desc = "连杀100次：全属性+5%持续30秒" },
        }
    end

    -- 函数说明：获取连击技能定义
    local function GetComboSkillDefs()
        return {
            { id = "shockwave", name = "冲击波", desc = "对周围8格内敌人造成50伤害", combo_required = 30, cooldown = 60 },
            { id = "time_dilation", name = "时间膨胀", desc = "周围敌人减速50%持续5秒", combo_required = 50, cooldown = 90 },
            { id = "blood_fury", name = "嗜血狂怒", desc = "10秒内伤害+25%，吸血+10%", combo_required = 70, cooldown = 120 },
            { id = "thunder_strike", name = "雷霆一击", desc = "对目标造成200%伤害的闪电打击", combo_required = 100, cooldown = 150 },
        }
    end

    -- 函数说明：刷新连击状态（核心逻辑）
    local function RefreshComboState(player, data)
        if not player:IsValid() then return end
        local now = deps.GetTime()
        local window = CONST.COMBO_BASE_WINDOW + (data.combo_window_bonus or 0)
        if data.combo_expire_time and now <= data.combo_expire_time then
            data.combo_count = (data.combo_count or 0) + 1
        else
            data.combo_count = 1
        end
        data.combo_expire_time = now + window
        local steps = math.floor(((data.combo_count or 1) - 1) / CONST.COMBO_STEP_KILLS)
        local max_mult = CONST.COMBO_MAX_MULT + (data.relic_combo_max_mult_bonus or 0)
        data.combo_mult = math.min(max_mult, 1 + steps * CONST.COMBO_STEP_MULT)
        player.components.combat.externaldamagemultipliers:SetModifier(CONST.COMBO_DAMAGE_MODIFIER_KEY, data.combo_mult)
        S.CheckMilestone(player, data)
        data.last_combo_count = data.combo_count
    end

    -- 函数说明：检查连击里程碑（预排序后支持早期退出，优化O(n)为摊销O(1)）
    function S.CheckMilestone(player, data)
        local milestones = GetMilestoneDefs()
        data.reached_milestones = data.reached_milestones or {}
        local kills = data.combo_count or 0
        for _, ms in ipairs(milestones) do
            if kills < ms.kills then break end  -- 里程碑按kills升序排列，未达到则后续均无法触发
            if not data.reached_milestones[ms.reward] then
                data.reached_milestones[ms.reward] = true
                S.ApplyMilestoneReward(player, ms, data)
            end
        end
    end

    -- 函数说明：应用里程碑奖励
    function S.ApplyMilestoneReward(player, milestone, data)
        if not player:IsValid() then return end
        if milestone.reward == "combo_milestone_10" then
            if player.components.health and not player.components.health:IsDead() then
                player.components.health:DoDelta(20)
            end
        elseif milestone.reward == "combo_milestone_25" then
            data.damage_bonus = (data.damage_bonus or 0) + 0.10
            player:DoTaskInTime(15, function(inst)
                if inst:IsValid() and inst.rogue_data then
                    inst.rogue_data.damage_bonus = (inst.rogue_data.damage_bonus or 0) - 0.10
                    deps.ApplyGrowthState(inst, inst.rogue_data, false)
                end
            end)
            deps.ApplyGrowthState(player, data, false)
        elseif milestone.reward == "combo_milestone_50" then
            S.ReleaseShockwave(player, 8, 50)
        elseif milestone.reward == "combo_milestone_75" then
            if player.components.health then
                player.components.health:SetInvincible(true)
            end
            S.ReleaseStunWave(player, 10, 3)
            player:DoTaskInTime(3, function(inst)
                if inst:IsValid() and inst.components and inst.components.health then
                    inst.components.health:SetInvincible(false)
                end
            end)
        elseif milestone.reward == "combo_milestone_100" then
            data.damage_bonus = (data.damage_bonus or 0) + 0.05
            data.hp_bonus = (data.hp_bonus or 0) + 5
            data.speed_bonus = (data.speed_bonus or 0) + 0.05
            deps.ApplyGrowthState(player, data, false)
            player:DoTaskInTime(30, function(inst)
                if inst:IsValid() and inst.rogue_data then
                    inst.rogue_data.damage_bonus = (inst.rogue_data.damage_bonus or 0) - 0.05
                    inst.rogue_data.speed_bonus = (inst.rogue_data.speed_bonus or 0) - 0.05
                    deps.ApplyGrowthState(inst, inst.rogue_data, false)
                end
            end)
        end
        if player.components.colouradder then
            player.components.colouradder:PushColour("rogue_combo_milestone", 1, 0.8, 0, 0)
            player:DoTaskInTime(1.0, function(inst)
                if inst and inst:IsValid() and inst.components and inst.components.colouradder then
                    inst.components.colouradder:PopColour("rogue_combo_milestone")
                end
            end)
        end
        deps.Announce(player:GetDisplayName() .. " 达成连击里程碑：【" .. milestone.name .. "】" .. milestone.desc)
    end

    -- 函数说明：释放范围冲击波
    function S.ReleaseShockwave(player, radius, damage)
        if not player:IsValid() then return end
        local x, y, z = player.Transform:GetWorldPosition()
        local ents = TheSim:FindEntities(x, y, z, radius or 8, { "_combat" }, { "player", "companion", "INLIMBO" })
        for _, ent in ipairs(ents) do
            if ent:IsValid() and ent.components.health and not ent.components.health:IsDead() then
                ent.components.health:DoDelta(-(damage or 50), nil, "rogue_combo_shockwave", nil, player)
            end
        end
        local fx = deps.SpawnPrefab("statue_transition_2")
        if fx then
            fx.Transform:SetPosition(x, y, z)
            fx.Transform:SetScale(1.5, 1.5, 1.5)
        end
    end

    -- 函数说明：释放范围眩晕波
    function S.ReleaseStunWave(player, radius, duration)
        if not player:IsValid() then return end
        local x, y, z = player.Transform:GetWorldPosition()
        local ents = TheSim:FindEntities(x, y, z, radius or 10, { "_combat" }, { "player", "companion", "INLIMBO" })
        for _, ent in ipairs(ents) do
            if ent:IsValid() then
                if ent.components.freezable then
                    ent.components.freezable:AddColdness(10)
                    ent.components.freezable:SpawnShatterFX()
                end
                if ent.components.sleeper then
                    ent.components.sleeper:GoToSleep(duration or 3)
                end
            end
        end
    end

    -- 函数说明：释放连击技能
    function S.ReleaseComboSkill(player, skill_id)
        if not player:IsValid() then return end
        local data = deps.EnsurePlayerData(player)
        local skills = GetComboSkillDefs()
        local skill = nil
        for _, s in ipairs(skills) do
            if s.id == skill_id then
                skill = s
                break
            end
        end
        if not skill then return end
        if (data.combo_count or 0) < skill.combo_required then
            deps.Announce("连击数不足，无法释放" .. skill.name .. "（需要" .. tostring(skill.combo_required) .. "连击）")
            return
        end
        local now = deps.GetTime()
        local last_use = data.combo_skill_last_use and data.combo_skill_last_use[skill_id] or 0
        if now - last_use < skill.cooldown then
            local remaining = math.ceil(skill.cooldown - (now - last_use))
            deps.Announce(skill.name .. "冷却中（剩余" .. tostring(remaining) .. "秒）")
            return
        end
        data.combo_skill_last_use = data.combo_skill_last_use or {}
        data.combo_skill_last_use[skill_id] = now
        if skill_id == "shockwave" then
            S.ReleaseShockwave(player, 8, 50)
        elseif skill_id == "time_dilation" then
            local x, y, z = player.Transform:GetWorldPosition()
            local ents = TheSim:FindEntities(x, y, z, 12, { "_combat" }, { "player", "companion", "INLIMBO" })
            for _, ent in ipairs(ents) do
                if ent:IsValid() and ent.components.locomotor then
                    ent.components.locomotor:SetExternalSpeedMultiplier(ent, "rogue_combo_time_dilation", 0.5)
                    ent:DoTaskInTime(5, function(e)
                        if e and e:IsValid() and e.components and e.components.locomotor then
                            e.components.locomotor:RemoveExternalSpeedMultiplier(e, "rogue_combo_time_dilation")
                        end
                    end)
                end
            end
        elseif skill_id == "blood_fury" then
            data.damage_bonus = (data.damage_bonus or 0) + 0.25
            data.lifesteal_chance = (data.lifesteal_chance or 0) + 0.10
            data.lifesteal_amount = (data.lifesteal_amount or 0) + 5
            deps.ApplyGrowthState(player, data, false)
            player:DoTaskInTime(10, function(inst)
                if inst:IsValid() and inst.rogue_data then
                    inst.rogue_data.damage_bonus = (inst.rogue_data.damage_bonus or 0) - 0.25
                    inst.rogue_data.lifesteal_chance = (inst.rogue_data.lifesteal_chance or 0) - 0.10
                    inst.rogue_data.lifesteal_amount = (inst.rogue_data.lifesteal_amount or 0) - 5
                    deps.ApplyGrowthState(inst, inst.rogue_data, false)
                end
            end)
        elseif skill_id == "thunder_strike" then
            local target = player.components.combat and player.components.combat.target
            if target and target:IsValid() and target.components.health and not target.components.health:IsDead() then
                local base_dmg = player.components.combat.defaultdamage or 30
                local thunder_dmg = math.floor(base_dmg * 2)
                target.components.health:DoDelta(-thunder_dmg, nil, "rogue_combo_thunder", nil, player)
                if target.components.colouradder then
                    target.components.colouradder:PushColour("rogue_combo_thunder", 0.5, 0.5, 1, 0)
                    target:DoTaskInTime(0.5, function(t)
                        if t and t:IsValid() and t.components and t.components.colouradder then
                            t.components.colouradder:PopColour("rogue_combo_thunder")
                        end
                    end)
                end
                local fx = deps.SpawnPrefab("lightning_rod")
                if fx then
                    local tx, ty, tz = target.Transform:GetWorldPosition()
                    fx.Transform:SetPosition(tx, ty, tz)
                end
            end
        end
        if player.components.colouradder then
            player.components.colouradder:PushColour("rogue_combo_skill", 0.2, 0.6, 1, 0)
            player:DoTaskInTime(0.8, function(inst)
                if inst and inst:IsValid() and inst.components and inst.components.colouradder then
                    inst.components.colouradder:PopColour("rogue_combo_skill")
                end
            end)
        end
        deps.Announce(player:GetDisplayName() .. " 释放连击技能：【" .. skill.name .. "】" .. skill.desc)
    end

    -- 函数说明：获取玩家可用的连击技能列表
    function S.GetAvailableSkills(player)
        if not player or not player:IsValid() then return {} end
        local data = deps.EnsurePlayerData(player)
        local skills = GetComboSkillDefs()
        local available = {}
        local now = deps.GetTime()
        for _, skill in ipairs(skills) do
            local combo_met = (data.combo_count or 0) >= skill.combo_required
            local last_use = data.combo_skill_last_use and data.combo_skill_last_use[skill.id] or 0
            local on_cd = (now - last_use) < skill.cooldown
            table.insert(available, {
                id = skill.id,
                name = skill.name,
                desc = skill.desc,
                combo_required = skill.combo_required,
                cooldown = skill.cooldown,
                combo_met = combo_met,
                on_cooldown = on_cd,
                cooldown_remaining = on_cd and math.ceil(skill.cooldown - (now - last_use)) or 0,
            })
        end
        return available
    end

    -- 函数说明：当连击超时重置时调用
    function S.OnComboExpired(player, data)
        data.reached_milestones = {}
    end

    -- 函数说明：注册RPC回调
    function S.RegisterRPCCallbacks()
        if deps.SetRPCHandler then
            deps.SetRPCHandler("combo_skill", function(player, skill_id)
                if not player or not player:IsValid() then return end
                S.ReleaseComboSkill(player, skill_id)
            end)
        end
    end

    S.RefreshComboState = RefreshComboState

    return S
end

return M
