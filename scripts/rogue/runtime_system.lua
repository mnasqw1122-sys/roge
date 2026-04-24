--[[
    文件说明：runtime_system.lua
    功能：肉鸽模式的运行时生命周期管理器（精简版）。
    引导层模块已拆分至 bootstrap/ (module_loader / hook_registry / lifecycle)，
    本文件负责核心内核：持久化钩子、玩家/世界生命周期、击杀/天变事件路由分发。
]]
local M = {}

local Logger = require("rogue/logger")
local EventBus = require("rogue/event_bus")

function M.Create(deps)
    local S = {}

    -- 注入事件总线，使 deps 可通过 deps.EventBus 访问
    deps.EventBus = EventBus

    local function DeepCopy(src, seen)
        if type(src) ~= "table" then
            return src
        end
        seen = seen or {}
        if seen[src] then
            return seen[src]
        end
        local out = {}
        seen[src] = out
        for k, v in pairs(src) do
            out[DeepCopy(k, seen)] = DeepCopy(v, seen)
        end
        return out
    end

    -- 挂载玩家数据的持久化钩子（保存与加载）
    local function HookPlayerPersistence(inst)
        if inst.rogue_persistence_hooked then return end
        inst.rogue_persistence_hooked = true

        local _OnSave = inst.OnSave
        inst.OnSave = function(self, data)
            if _OnSave then _OnSave(self, data) end

            if self.rogue_data then
                if deps.Config.DEBUG_MODE then
                    print("RogueMode: Saving data for " .. tostring(self), self.rogue_data.kills, self.rogue_data.damage_bonus, self.rogue_data.hp_bonus)
                end
                data.rogue_growth = DeepCopy(self.rogue_data)
                data.rogue_applied_hp_bonus = self.rogue_applied_hp_bonus or 0
                data.rogue_init_given = self.rogue_init == true
            end

            if self.rogue_starter_items then data.rogue_starter_items = self.rogue_starter_items end
        end

        local _OnLoad = inst.OnLoad
        inst.OnLoad = function(self, data)
            if _OnLoad then _OnLoad(self, data) end
            if data then
                if data.rogue_growth then
                    if deps.Config.DEBUG_MODE then
                        print("RogueMode: Loading data for " .. tostring(self), data.rogue_growth.kills, data.rogue_growth.damage_bonus, data.rogue_growth.hp_bonus)
                    end
                    local g = data.rogue_growth
                    if type(g) == "table" then
                        self.rogue_data = DeepCopy(g)
                    else
                        self.rogue_data = {}
                    end
                    local legacy_init = type(g) == "table" and g.init_given == true
                    self.rogue_init = data.rogue_init_given == true or legacy_init
                    self.rogue_applied_hp_bonus = 0
                    self:DoTaskInTime(0, function()
                        local ok_apply, err_apply = pcall(deps.ApplyGrowthState, self, self.rogue_data, true)
                        if not ok_apply then
                            print("[RogueMode] ApplyGrowthState error on load:", err_apply)
                        end
                        if deps.ReapplyTalentEffects then
                            local ok_talent, err_talent = pcall(deps.ReapplyTalentEffects, self)
                            if not ok_talent then
                                print("[RogueMode] ReapplyTalentEffects error on load:", err_talent)
                            end
                        end
                        if deps.RegisterSetBonusWatcher then
                            local ok_watcher, err_watcher = pcall(deps.RegisterSetBonusWatcher, self)
                            if not ok_watcher then
                                print("[RogueMode] RegisterSetBonusWatcher error on load:", err_watcher)
                            end
                        end
                        if deps.RefreshSetBonuses then
                            local ok_set, err_set = pcall(deps.RefreshSetBonuses, self)
                            if not ok_set then
                                print("[RogueMode] RefreshSetBonuses error on load:", err_set)
                            end
                        end
                    end)
                end
                if data.rogue_starter_items then self.rogue_starter_items = data.rogue_starter_items end
            end
        end
    end

    local function HookWorldPersistence(inst)
        if inst.rogue_world_persistence_hooked then return end
        inst.rogue_world_persistence_hooked = true

        local _OnSave = inst.OnSave
        inst.OnSave = function(self, data)
            if _OnSave then _OnSave(self, data) end
            data.rogue_world = data.rogue_world or {}
            if deps.ExportWaveState then
                data.rogue_world.wave = deps.ExportWaveState()
            end
            if deps.ExportSeasonState then
                data.rogue_world.season = deps.ExportSeasonState()
            end
            if deps.ExportDropState then
                data.rogue_world.drop = deps.ExportDropState()
            end
        end

        local _OnLoad = inst.OnLoad
        inst.OnLoad = function(self, data)
            if _OnLoad then _OnLoad(self, data) end
            local rw = data and data.rogue_world or nil
            if type(rw) ~= "table" then
                return
            end
            if deps.ImportDropState then
                deps.ImportDropState(rw.drop)
            end
            if deps.ImportSeasonState then
                deps.ImportSeasonState(rw.season)
            end
            if deps.ImportWaveState then
                deps.ImportWaveState(rw.wave)
            end
        end
    end

    S.RegisterPlayerLifecycle = function()
        deps.AddPlayerPostInit(function(inst)
            if not deps.IsMasterSim() then return end
            HookPlayerPersistence(inst)

            -- 函数说明：重进后分阶段重同步玩家成长、波次与赛季状态，避免UI短时显示默认值。
            local function ResyncPlayerRuntimeState(player, apply_health)
                if not player or not player:IsValid() then
                    return
                end
                deps.EnsurePlayerData(player)
                deps.ApplyGrowthState(player, player.rogue_data, apply_health == true)
                deps.EnsureDailyTask(player, deps.GetCurrentDay())
                deps.SyncWaveStateToPlayer(player)
                deps.SyncSeasonStateToPlayer(player)
            end

            inst:DoTaskInTime(0, function()
                ResyncPlayerRuntimeState(inst, false)
                inst:DoTaskInTime(1, function()
                    if inst:IsValid() then
                        ResyncPlayerRuntimeState(inst, true)
                    end
                end)
                inst:DoTaskInTime(3, function()
                    if inst:IsValid() then
                        ResyncPlayerRuntimeState(inst, false)
                    end
                end)

                if inst.components.inventory and not inst.rogue_init then
                    -- 函数说明：为新加入肉鸽模式的玩家发放初始装备
                    -- 发放：火腿棒、2个木甲、肉丸、火把。除女武神（wathgrithr）外额外发放1个橄榄球头盔（footballhat）。
                    local initial_items = { "hambat", "armorwood", "armorwood", "meatballs", "torch" }
                    if inst.prefab ~= "wathgrithr" then
                        table.insert(initial_items, "footballhat")
                    end

                    for _, v in ipairs(initial_items) do
                        local item = deps.SpawnPrefab(v)
                        if item then inst.components.inventory:GiveItem(item) end
                    end
                    inst.rogue_init = true
                end
                deps.OfferInitialRelicChoice(inst)
                if not inst.rogue_death_listener then
                    inst.rogue_death_listener = true
                    inst:ListenForEvent("death", function(player)
                        deps.OnSeasonPlayerDeath(player, deps.GetCurrentDay())
                    end)
                end

                if not inst.rogue_kill_listener then
                    inst.rogue_kill_listener = true
                    inst:ListenForEvent("killed", function(doer, data)
                        if deps.IsValidPlayer and not deps.IsValidPlayer(doer) then return end
                        if not doer or not doer:IsValid() then return end
                        if not data or not data.victim or not data.victim:IsValid() then return end
                        local victim = data.victim
                        if victim._rogue_killed_processed then return end
                        victim._rogue_killed_processed = true
                        local day = deps.GetCurrentDay()
                        local is_boss = victim:HasTag("rogue_wave_boss")
                        deps.OnSeasonKill(doer, victim, is_boss, day)

                        -- 积分系统接入贪婪契约：只有拥有贪婪标签的玩家才能通过击杀获取积分
                        -- 优化：积分曲线平滑化，随天数增长——解决前期不足后期过剩问题
                        -- 小怪: min(5, 2+day/10)  Boss: 20+day*2  精英: min(10, 3+day/5)
                        local has_greed = doer:HasTag("rogue_greed_pact")
                        if has_greed then
                            local point_gain
                            if is_boss then
                                point_gain = math.floor(20 + day * 2)
                            elseif victim:HasTag("rogue_elite") then
                                point_gain = math.min(10, math.floor(3 + day / 5))
                            else
                                point_gain = math.min(5, math.floor(2 + day / 10))
                            end
                            
                            local d_state = deps.EnsurePlayerData(doer)
                            d_state.points = (d_state.points or 0) + point_gain
                            if doer.rogue_points then
                                doer.rogue_points:set(d_state.points)
                            end
                        end

                        deps.DropLoot(victim, is_boss, day, doer)
                        deps.RefreshComboState(doer)
                        if deps.CheckAchievement then
                            local d = deps.EnsurePlayerData(doer)
                            if d.combo_count and d.combo_count >= 5 then
                                deps.CheckAchievement(doer, "combo", d.combo_count)
                            end
                        end
                        deps.ProgressDailyTaskOnKill(doer, victim, is_boss, day)
                        local ws = deps.GetWaveState()
                        if ws and ws.challenge and not ws.challenge.completed then
                            deps.ProgressChallenge(1, 1, day)
                            if victim:HasTag("rogue_elite") then
                                deps.ProgressChallenge(2, 1, day)
                            end
                            if is_boss then
                                deps.ProgressChallenge(3, 1, day)
                            end
                        end
                        if ws and ws.bounty and not ws.bounty.completed and victim:HasTag("rogue_bounty_target") then
                            ws.bounty.killed = (ws.bounty.killed or 0) + 1
                            if ws.bounty.killed >= (ws.bounty.target or 1) then
                                ws.bounty.completed = true
                                deps.RewardBounty(doer, day)
                            end
                            deps.SyncWaveStateToAllPlayers()
                        end

                        -- 通过事件总线广播击杀，各子系统独立消费
                        EventBus.Emit("on_kill", {
                            killer = doer,
                            victim = victim,
                            is_boss = is_boss,
                            day = day,
                        })

                        if is_boss then
                            deps.ApplyBuff(doer, true)
                            if deps.CheckAchievement then
                                deps.CheckAchievement(doer, "boss_kill", 1)
                                deps.CheckAchievement(doer, "kill", 1)
                            end
                            if deps.TriggerChainEvent then
                                deps.TriggerChainEvent(doer, "boss_kill")
                            end
                            EventBus.Emit("on_boss_kill", {
                                killer = doer,
                                boss = victim,
                                day = day,
                            })
                        else
                            local d = deps.EnsurePlayerData(doer)
                            d.kills = d.kills + 1
                            if doer.rogue_kills then doer.rogue_kills:set(d.kills) end
                            deps.CheckTalentTrigger(doer)
                            deps.CheckRelicTrigger(doer, day)
                            if d.kills % deps.CONST.BUFF_KILL_INTERVAL == 0 then deps.ApplyBuff(doer, false) end
                            if deps.CheckAchievement then
                                deps.CheckAchievement(doer, "kill", 1)
                                if victim:HasTag("rogue_elite") then
                                    deps.CheckAchievement(doer, "elite_kill", 1)
                                    if deps.TriggerChainEvent then
                                        deps.TriggerChainEvent(doer, "elite_kill")
                                    end
                                end
                            end
                        end
                    end)
                end
            end)
        end)
    end

    S.RegisterWorldLifecycle = function()
        deps.AddPrefabPostInit("world", function(inst)
            if not inst.ismastersim then return end
            HookWorldPersistence(inst)

            inst:WatchWorldState("phase", function(world, phase)
                deps.OnWorldPhaseChange(world, phase)
                if phase == "day" then
                    local day = world.state.cycles + 1
                    if day < deps.Config.START_DAY then return end
                    for _, player in ipairs(deps.AllPlayers) do
                        if player and player:IsValid() then
                            deps.EnsureDailyTask(player, day)
                            deps.SyncWaveStateToPlayer(player)
                            deps.SyncSeasonStateToPlayer(player)
                        end
                    end
                    deps.SyncSeasonStateToAllPlayers()
                    -- 广播天数变化事件
                    EventBus.Emit("on_day_changed", { new_day = day, old_day = day - 1 })
                    if not deps.CanRunCombatLoop() then return end
                    if deps.IsGracePeriod and deps.IsGracePeriod(day) then
                        if world.rogue_grace_announce_day ~= day then
                            world.rogue_grace_announce_day = day
                            deps.Announce("赛季保护期：第" .. day .. "天不启动波次。")
                        end
                        return
                    end

                    local is_rest_day = deps.Config.BOSS_INTERVAL > 1 and (day % deps.Config.BOSS_INTERVAL == deps.Config.BOSS_INTERVAL - 1)
                    local is_boss_wave = deps.Config.BOSS_INTERVAL > 0 and (day % deps.Config.BOSS_INTERVAL == 0)

                    if world.rogue_start_task then world.rogue_start_task:Cancel() end
                    if is_rest_day then
                        deps.Announce("休息天即将在 " .. deps.Config.WAVE_START_DELAY .. " 秒后开始，今天不会有敌人。")
                    elseif is_boss_wave then
                        deps.Announce("BOSS将在 " .. deps.Config.WAVE_START_DELAY .. " 秒后到达！")
                    else
                        deps.Announce("敌人将在 " .. deps.Config.WAVE_START_DELAY .. " 秒后到达！")
                    end
                    
                    world.rogue_start_task = world:DoTaskInTime(deps.Config.WAVE_START_DELAY, function()
                        if deps.CanRunCombatLoop() then
                            deps.StartWave(day)
                        end
                    end)
                elseif phase == "night" then
                    if world.rogue_start_task then
                        world.rogue_start_task:Cancel()
                        world.rogue_start_task = nil
                    end
                    if not deps.CanRunCombatLoop() then
                        deps.EndWave()
                        deps.SyncSeasonStateToAllPlayers()
                        return
                    end
                    if deps.IsFinalNight and deps.IsFinalNight() then
                        if world.rogue_end_task then world.rogue_end_task:Cancel() end
                        deps.Announce("终局夜波次已启动，持续至黎明结算。")
                        deps.StartWave(world.state.cycles + 1, { force_restart = true, force_non_boss = true })
                        deps.SyncSeasonStateToAllPlayers()
                        return
                    end
                    if world.rogue_end_task then world.rogue_end_task:Cancel() end
                    deps.Announce("夜幕降临。波次将在 " .. deps.Config.WAVE_END_DELAY .. " 秒后结束...")
                    world.rogue_end_task = world:DoTaskInTime(deps.Config.WAVE_END_DELAY, deps.EndWave)

                    if deps.Config.GROUND_LOOT_CLEAN_ENABLED then
                        local day = world.state.cycles + 1
                        if day % deps.Config.GROUND_LOOT_CLEAN_INTERVAL_DAYS == 0 then
                            if world.rogue_clean_task then world.rogue_clean_task:Cancel() end
                            world.rogue_clean_task = world:DoTaskInTime(deps.Config.GROUND_LOOT_CLEAN_DELAY_NIGHT, function()
                                local players = deps.CollectAlivePlayers()
                                if #players == 0 then return end
                                local radius = deps.Config.GROUND_LOOT_CLEAN_SEARCH_RADIUS or 70
                                local batch_size = deps.Config.GROUND_LOOT_CLEAN_BATCH_SIZE or 60
                                local player_idx = 1
                                local total_cleaned = 0

                                -- 分帧批处理：每帧处理batch_size个物品，避免单帧卡顿
                                local function clean_step()
                                    if player_idx > #players then
                                        if total_cleaned > 0 then
                                            deps.Announce("夜间清理：移除了 " .. total_cleaned .. " 个地面物品。")
                                        end
                                        return
                                    end
                                    local p = players[player_idx]
                                    if not p or not p:IsValid() then
                                        player_idx = player_idx + 1
                                        clean_step()
                                        return
                                    end
                                    local pt = p:GetPosition()
                                    local ents = deps.GLOBAL.TheSim:FindEntities(
                                        pt.x, pt.y, pt.z, radius,
                                        {"_inventoryitem"},
                                        {"INLIMBO", "irreplaceable", "rogue_supply_protected", "player", "companion"}
                                    )
                                    local cleaned_this_batch = 0
                                    for _, v in ipairs(ents) do
                                        if cleaned_this_batch >= batch_size then break end
                                        if v:IsValid() and v.components.inventoryitem
                                           and not v.components.inventoryitem:GetGrandOwner() then
                                            v:Remove()
                                            cleaned_this_batch = cleaned_this_batch + 1
                                            total_cleaned = total_cleaned + 1
                                        end
                                    end
                                    player_idx = player_idx + 1
                                    -- 下一帧继续
                                    world:DoTaskInTime(0, clean_step)
                                end
                                clean_step()
                            end)
                        end
                    end
                end
            end)
        end)
    end

    return S
end

return M
