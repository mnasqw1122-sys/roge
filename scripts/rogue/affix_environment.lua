--[[
    文件说明：affix_environment.lua
    功能：环境词缀与全局词缀运行时系统。
    管理环境词缀的随机触发、持续时间、效果应用，以及全局词缀的赛季级效果。
]]
local M = {}
local RogueConfig = require("rogue/config")

function M.Create(deps)
    local S = {}

    local ENV_DEFS = RogueConfig.ENVIRONMENT_AFFIX_DEFS or {}
    local GLOBAL_DEFS = RogueConfig.GLOBAL_AFFIX_DEFS or {}

    -- 函数说明：根据当前天数筛选可用的环境词缀
    local function GetAvailableEnvAffixes(day)
        local available = {}
        for _, def in ipairs(ENV_DEFS) do
            if day >= (def.min_day or 1) then
                table.insert(available, def)
            end
        end
        return available
    end

    -- 函数说明：按权重随机选择一个环境词缀
    local function PickRandomEnvAffix(day)
        local available = GetAvailableEnvAffixes(day)
        if #available == 0 then return nil end
        local total_weight = 0
        for _, def in ipairs(available) do
            total_weight = total_weight + (def.weight or 1)
        end
        local r = math.random() * total_weight
        local cumulative = 0
        for _, def in ipairs(available) do
            cumulative = cumulative + (def.weight or 1)
            if r <= cumulative then
                return def
            end
        end
        return available[#available]
    end

    -- 函数说明：根据当前天数筛选可用的全局词缀
    local function GetAvailableGlobalAffixes(day)
        local available = {}
        for _, def in ipairs(GLOBAL_DEFS) do
            if day >= (def.min_day or 1) then
                table.insert(available, def)
            end
        end
        return available
    end

    -- 函数说明：按权重随机选择指定数量的全局词缀
    local function PickGlobalAffixes(day, count)
        local available = GetAvailableGlobalAffixes(day)
        count = math.min(count or 1, #available)
        local picked = {}
        local pool = {}
        for _, def in ipairs(available) do
            table.insert(pool, def)
        end
        for _ = 1, count do
            if #pool == 0 then break end
            local total_weight = 0
            for _, def in ipairs(pool) do
                total_weight = total_weight + (def.weight or 1)
            end
            local r = math.random() * total_weight
            local cumulative = 0
            local picked_idx = #pool
            for i, def in ipairs(pool) do
                cumulative = cumulative + (def.weight or 1)
                if r <= cumulative then
                    picked_idx = i
                    break
                end
            end
            table.insert(picked, pool[picked_idx])
            table.remove(pool, picked_idx)
        end
        return picked
    end

    -- 函数说明：应用环境词缀效果
    local function ApplyEnvAffixEffect(world, affix_id, data)
        if affix_id == "fog" then
            data.env_fog_active = true
            -- 浓雾实际效果：移动速度-10% + 理智缓慢流失（服务器端可感知）
            for _, player in ipairs(AllPlayers) do
                if player:IsValid() and player.components.locomotor then
                    player.components.locomotor:SetExternalSpeedMultiplier(player, "rogue_env_fog", 0.9)
                end
            end
            data.env_fog_task = world:DoPeriodicTask(5, function()
                for _, player in ipairs(AllPlayers) do
                    if player:IsValid() and player.components.sanity and not (player.components.health and player.components.health:IsDead()) then
                        player.components.sanity:DoDelta(-0.5, nil, "rogue_env_fog")
                    end
                end
            end)
        elseif affix_id == "rain_acid" then
            data.env_acid_task = world:DoPeriodicTask(10, function()
                for _, player in ipairs(AllPlayers) do
                    if player:IsValid() and player.components.health and not player.components.health:IsDead() then
                        player.components.health:DoDelta(-3, nil, "rogue_env_acid")
                    end
                end
            end)
        elseif affix_id == "wind_gale" then
            data.env_wind_active = true
            for _, player in ipairs(AllPlayers) do
                if player:IsValid() and player.components.locomotor then
                    player.components.locomotor:SetExternalSpeedMultiplier(player, "rogue_env_wind", 0.8)
                end
            end
        elseif affix_id == "darkness" then
            data.env_darkness_task = world:DoPeriodicTask(1, function()
                for _, player in ipairs(AllPlayers) do
                    if player:IsValid() and player.components.sanity and not (player.components.health and player.components.health:IsDead()) then
                        player.components.sanity:DoDelta(-0.3)
                    end
                end
            end)
        elseif affix_id == "heat_wave" then
            data.env_heat_task = world:DoPeriodicTask(5, function()
                for _, player in ipairs(AllPlayers) do
                    if player:IsValid() and player.components.temperature then
                        local current = player.components.temperature:GetCurrent()
                        player.components.temperature:SetCurrent(current + 2)
                    end
                end
            end)
        elseif affix_id == "frost_bite" then
            data.env_frost_task = world:DoPeriodicTask(5, function()
                for _, player in ipairs(AllPlayers) do
                    if player:IsValid() and player.components.temperature then
                        local current = player.components.temperature:GetCurrent()
                        player.components.temperature:SetCurrent(current - 2)
                    end
                end
            end)
        elseif affix_id == "earthquake" then
            data.env_quake_task = world:DoPeriodicTask(15, function()
                for _, player in ipairs(AllPlayers) do
                    if player:IsValid() and player.components.health and not player.components.health:IsDead() then
                        local x, y, z = player.Transform:GetWorldPosition()
                        local rock = deps.SpawnPrefab("rocks")
                        if rock then
                            local offset_x = (math.random() - 0.5) * 10
                            local offset_z = (math.random() - 0.5) * 10
                            rock.Transform:SetPosition(x + offset_x, 15, z + offset_z)
                        end
                        player.components.health:DoDelta(-5, nil, "rogue_env_quake")
                    end
                end
            end)
        elseif affix_id == "blood_moon" then
            data.env_blood_moon_active = true
        elseif affix_id == "static_field" then
            data.env_lightning_task = world:DoPeriodicTask(20, function()
                for _, player in ipairs(AllPlayers) do
                    if player:IsValid() then
                        local x, y, z = player.Transform:GetWorldPosition()
                        local offset_x = (math.random() - 0.5) * 20
                        local offset_z = (math.random() - 0.5) * 20
                        local lightning = deps.SpawnPrefab("lightning_rod")
                        if lightning then
                            lightning.Transform:SetPosition(x + offset_x, y, z + offset_z)
                        end
                        TheWorld:PushEvent("ms_sendlightningstrike", Vector3(x + offset_x, y, z + offset_z))
                    end
                end
            end)
        elseif affix_id == "spore_cloud" then
            data.env_spore_active = true
            -- 孢子云实际效果：理智持续流失 + 微量生命损伤（孢子致幻/过敏）
            data.env_spore_task = world:DoPeriodicTask(8, function()
                for _, player in ipairs(AllPlayers) do
                    if player:IsValid() then
                        if player.components.sanity and not (player.components.health and player.components.health:IsDead()) then
                            player.components.sanity:DoDelta(-1, nil, "rogue_env_spore")
                        end
                        if player.components.health and not player.components.health:IsDead() then
                            player.components.health:DoDelta(-2, nil, "rogue_env_spore")
                        end
                    end
                end
            end)
        elseif affix_id == "meteor_shower" then
            -- [V3] 陨石雨：每12秒在随机玩家位置落下陨石（伤害+特效）
            data.env_meteor_task = world:DoPeriodicTask(12, function()
                for _, player in ipairs(AllPlayers) do
                    if player:IsValid() and player.components.health and not player.components.health:IsDead() then
                        local x, y, z = player.Transform:GetWorldPosition()
                        local ox = (math.random() - 0.5) * 12
                        local oz = (math.random() - 0.5) * 12
                        local target = Vector3(x + ox, 0, z + oz)
                        if TheWorld.components.rogue_meteor then
                            TheWorld.components.rogue_meteor:DoMeteor(target, 8)
                        else
                            local rock = deps.SpawnPrefab("rock")
                            if rock then
                                rock.Transform:SetPosition(target.x, 15, target.z)
                            end
                        end
                        player.components.health:DoDelta(-6, nil, "rogue_env_meteor")
                    end
                end
            end)
        elseif affix_id == "soul_drain_mist" then
            -- [V3] 噬魂迷雾：全体玩家每5秒流失生命与理智
            data.env_soul_drain_task = world:DoPeriodicTask(5, function()
                for _, player in ipairs(AllPlayers) do
                    if player:IsValid() and not (player.components.health and player.components.health:IsDead()) then
                        if player.components.health then
                            player.components.health:DoDelta(-2, nil, "rogue_env_soul_drain")
                        end
                        if player.components.sanity then
                            player.components.sanity:DoDelta(-2.5, nil, "rogue_env_soul_drain")
                        end
                    end
                end
            end)
            data.env_soul_drain_active = true
        end
    end

    -- 函数说明：移除环境词缀效果
    local function RemoveEnvAffixEffect(world, affix_id, data)
        if affix_id == "fog" then
            data.env_fog_active = false
            for _, player in ipairs(AllPlayers) do
                if player:IsValid() and player.components.locomotor then
                    player.components.locomotor:RemoveExternalSpeedMultiplier(player, "rogue_env_fog")
                end
            end
            if data.env_fog_task then
                data.env_fog_task:Cancel()
                data.env_fog_task = nil
            end
        elseif affix_id == "rain_acid" then
            if data.env_acid_task then
                data.env_acid_task:Cancel()
                data.env_acid_task = nil
            end
        elseif affix_id == "wind_gale" then
            data.env_wind_active = false
            for _, player in ipairs(AllPlayers) do
                if player:IsValid() and player.components.locomotor then
                    player.components.locomotor:RemoveExternalSpeedMultiplier(player, "rogue_env_wind")
                end
            end
        elseif affix_id == "darkness" then
            if data.env_darkness_task then
                data.env_darkness_task:Cancel()
                data.env_darkness_task = nil
            end
        elseif affix_id == "heat_wave" then
            if data.env_heat_task then
                data.env_heat_task:Cancel()
                data.env_heat_task = nil
            end
        elseif affix_id == "frost_bite" then
            if data.env_frost_task then
                data.env_frost_task:Cancel()
                data.env_frost_task = nil
            end
        elseif affix_id == "earthquake" then
            if data.env_quake_task then
                data.env_quake_task:Cancel()
                data.env_quake_task = nil
            end
        elseif affix_id == "blood_moon" then
            data.env_blood_moon_active = false
        elseif affix_id == "static_field" then
            if data.env_lightning_task then
                data.env_lightning_task:Cancel()
                data.env_lightning_task = nil
            end
        elseif affix_id == "spore_cloud" then
            data.env_spore_active = false
            if data.env_spore_task then
                data.env_spore_task:Cancel()
                data.env_spore_task = nil
            end
        elseif affix_id == "meteor_shower" then
            if data.env_meteor_task then
                data.env_meteor_task:Cancel()
                data.env_meteor_task = nil
            end
        elseif affix_id == "soul_drain_mist" then
            if data.env_soul_drain_task then
                data.env_soul_drain_task:Cancel()
                data.env_soul_drain_task = nil
            end
            data.env_soul_drain_active = false
        end
    end

    -- 函数说明：应用全局词缀效果
    local function ApplyGlobalAffixEffect(world, affix_id, data)
        if affix_id == "elite_surge" then
            data.global_elite_surge = (data.global_elite_surge or 0) + 0.15
        elseif affix_id == "boss_empower" then
            data.global_boss_hp_mult = (data.global_boss_hp_mult or 1) + 0.20
            data.global_boss_dmg_mult = (data.global_boss_dmg_mult or 1) + 0.10
        elseif affix_id == "loot_famine" then
            data.global_loot_penalty = (data.global_loot_penalty or 0) + 0.15
        elseif affix_id == "heal_suppress" then
            data.global_heal_suppress = (data.global_heal_suppress or 0) + 0.25
        elseif affix_id == "speed_demon" then
            data.global_enemy_speed_mult = (data.global_enemy_speed_mult or 1) + 0.20
        elseif affix_id == "iron_skin" then
            data.global_enemy_damage_reduction = (data.global_enemy_damage_reduction or 0) + 0.10
        elseif affix_id == "berserk_world" then
            data.global_enemy_damage_mult = (data.global_enemy_damage_mult or 1) + 0.10
            data.global_enemy_hp_penalty = (data.global_enemy_hp_penalty or 0) + 0.05
        elseif affix_id == "double_affix" then
            data.global_double_affix_bonus = (data.global_double_affix_bonus or 0) + 0.15
        elseif affix_id == "night_terror" then
            data.global_night_damage_bonus = (data.global_night_damage_bonus or 0) + 0.15
        elseif affix_id == "resource_scarce" then
            data.global_resource_scarce = (data.global_resource_scarce or 0) + 0.30
            -- 消费端：世界资源刷新速度-30%（包装 regrowthmanager.OnUpdate 的 dt）
            if not data._resource_scarce_hooked then
                data._resource_scarce_hooked = true
                local rm = world.components and world.components.regrowthmanager
                if rm and rm.OnUpdate then
                    local old_update = rm.OnUpdate
                    rm.OnUpdate = function(self, dt)
                        old_update(self, dt * 0.7)
                    end
                end
            end
        elseif affix_id == "boss_gauntlet" then
            -- [V3] Boss连战：Boss波次额外+1 Boss，掉落奖励提升
            data.global_boss_gauntlet = (data.global_boss_gauntlet or 0) + 1
            data.global_boss_extra_drop = (data.global_boss_extra_drop or 0) + 0.25
        elseif affix_id == "combo_boost" then
            -- [V3] 连击风暴：连击持续时间窗口+50%
            data.global_combo_window_mult = (data.global_combo_window_mult or 1) + 0.5
        end
    end

    -- 函数说明：触发一个环境词缀（带概率与冷却控制）
    function S.TriggerRandomEnvAffix(day)
        local world = TheWorld
        if not world then return end
        local data = world.rogue_env_data
        if not data then
            data = {}
            world.rogue_env_data = data
        end
        if data.active_env_affix then
            return
        end
        -- 冷却控制：词缀结束 120 秒内不再触发，避免连续高压
        if data.last_env_affix_end_time and deps.GetTime() - data.last_env_affix_end_time < 120 then
            return
        end
        -- 概率控制：随天数提升，上限 45%
        local chance = math.min(0.45, 0.2 + (day - 8) * 0.01)
        if math.random() > chance then return end
        local affix = PickRandomEnvAffix(day)
        if not affix then return end
        data.active_env_affix = affix.id
        data.env_affix_end_time = deps.GetTime() + (affix.duration or 90)
        ApplyEnvAffixEffect(world, affix.id, data)
        deps.Announce("环境词缀触发：【" .. affix.name .. "】" .. affix.desc .. "（持续" .. tostring(affix.duration or 90) .. "秒）")
    end

    -- 函数说明：为赛季选择全局词缀
    function S.SelectGlobalAffixes(day, count)
        local world = TheWorld
        if not world then return {} end
        local data = world.rogue_env_data
        if not data then
            data = {}
            world.rogue_env_data = data
        end
        local picked = PickGlobalAffixes(day, count)
        data.active_global_affixes = {}
        for _, affix in ipairs(picked) do
            table.insert(data.active_global_affixes, affix.id)
            ApplyGlobalAffixEffect(world, affix.id, data)
            deps.Announce("全局词缀激活：【" .. affix.name .. "】" .. affix.desc)
        end
        return picked
    end

    -- 函数说明：每帧更新，检查环境词缀过期
    function S.OnUpdate()
        local world = TheWorld
        if not world then return end
        local data = world.rogue_env_data
        if not data or not data.active_env_affix then return end
        local now = deps.GetTime()
        if data.env_affix_end_time and now >= data.env_affix_end_time then
            local affix_id = data.active_env_affix
            RemoveEnvAffixEffect(world, affix_id, data)
            data.active_env_affix = nil
            data.env_affix_end_time = nil
            data.last_env_affix_end_time = now
            deps.Announce("环境词缀已结束")
        end
    end

    -- 函数说明：获取当前活跃的环境词缀ID
    function S.GetActiveEnvAffix()
        local world = TheWorld
        if not world then return nil end
        local data = world.rogue_env_data
        return data and data.active_env_affix or nil
    end

    -- 函数说明：获取当前活跃的全局词缀列表
    function S.GetActiveGlobalAffixes()
        local world = TheWorld
        if not world then return {} end
        local data = world.rogue_env_data
        return data and data.active_global_affixes or {}
    end

    -- 函数说明：获取全局词缀修正值
    function S.GetGlobalModifier(key)
        local world = TheWorld
        if not world then return nil end
        local data = world.rogue_env_data
        return data and data[key] or nil
    end

    -- 函数说明：清除所有环境词缀和全局词缀
    function S.ClearAll()
        local world = TheWorld
        if not world then return end
        local data = world.rogue_env_data
        if not data then return end
        if data.active_env_affix then
            RemoveEnvAffixEffect(world, data.active_env_affix, data)
            data.active_env_affix = nil
            data.env_affix_end_time = nil
        end
        data.active_global_affixes = {}
    end

    return S
end

return M
