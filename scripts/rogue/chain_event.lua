--[[
    文件说明：chain_event.lua
    功能：连锁事件系统。
    当特定条件满足时触发一系列连续事件，每个事件完成后自动触发下一个，形成叙事性游戏体验。
    连锁事件比普通随机事件更复杂，具有多阶段推进和累计奖励。
]]
local M = {}
local EventBus = require("rogue/event_bus")

-- 模块级防重复订阅标记（modmain 只执行一次，此处兜底防世界重置后重复订阅）
local _build_combo_subscribed = false

function M.Create(deps)
    local S = {}

    -- 函数说明：连锁事件链定义，每条链包含多个阶段，按顺序触发。
    local CHAIN_DEFS = {
        {
            id = "shadow_invasion",
            name = "暗影入侵",
            trigger = "elite_kill",
            trigger_count = 3,
            stages = {
                {
                    desc = "暗影裂隙出现！消灭暗影生物！",
                    spawn = { prefab = "crawlinghorror", count = 2, radius = 12, extra = { { prefab = "terrorbeak", count = 1 } } },
                    reward = { points = 15 },
                },
                {
                    desc = "更大的裂隙被撕开！暗影骑士来袭！",
                    spawn = { prefab = "shadow_knight", count = 2, radius = 10 },
                    reward = { points = 25 },
                },
                {
                    desc = "暗影之主降临！击败它！",
                    spawn = { prefab = "shadow_knight", count = 1, radius = 8, hp_mult = 3, dmg_mult = 1.5 },
                    reward = { points = 50, prefab = "nightmarefuel", count = 4 },
                },
            }
        },
        {
            id = "hunters_call",
            name = "猎人之召",
            trigger = "boss_kill",
            trigger_count = 1,
            stages = {
                {
                    desc = "猎犬群闻到了血腥味！",
                    spawn = { prefab = "hound", count = 5, radius = 14 },
                    reward = { points = 10 },
                },
                {
                    desc = "火猎犬和冰猎犬混编来袭！",
                    spawn = { prefab = "firehound", count = 2, radius = 12, extra = { { prefab = "icehound", count = 2 } } },
                    reward = { points = 20 },
                },
                {
                    desc = "猎犬之王现身！",
                    spawn = { prefab = "hound", count = 1, radius = 8, hp_mult = 5, dmg_mult = 2, size_mult = 2.0 },
                    reward = { points = 40, prefab = "hounds_tooth", count = 3 },
                },
            }
        },
        {
            id = "treasure_hunt",
            name = "宝藏猎人",
            trigger = "wave_clear",
            trigger_count = 2,
            stages = {
                {
                    desc = "发现了一个神秘的藏宝图碎片！",
                    reward = { points = 5 },
                    announce_only = true,
                },
                {
                    desc = "第二块碎片出现了！宝藏就在附近！",
                    spawn = { prefab = "spider", count = 4, radius = 12 },
                    reward = { points = 10, prefab = "goldnugget", count = 3 },
                },
                {
                    desc = "宝藏守护者苏醒了！",
                    spawn = { prefab = "spiderqueen", count = 1, radius = 10, hp_mult = 0.6 },
                    reward = { points = 35, prefab = "treasurechest", count = 1 },
                },
            }
        }
    }

    -- 函数说明：Build协同组合规则定义（方向A - Task A3）。
    -- 达成「指定套装 + 至少一件指定遗物 + 指定天赋达到等级」后，触发一次联动事件（生成挑战 + 发放奖励）。
    -- 判定数据：套装 data.active_set_tags、遗物 data.relics、天赋 data.talent_levels。
    local BUILD_COMBO_DEFS = {
        {
            key = "god_of_war",
            name = "战神降临",
            desc = "战神武装 + 灭世之刃/力量之戒/嗜血獠牙 + 破军技巧Lv3",
            require_set = "battle_set",
            require_relics = { 18, 19, 20 },
            require_talents = { [2] = 3 },
            stages = {
                {
                    desc = "战神试炼开启！击败狂战猎犬！",
                    spawn = { prefab = "hound", count = 1, radius = 8, hp_mult = 3, dmg_mult = 1.5 },
                    reward = { points = 40, prefab = "treasurechest", count = 1 },
                },
            },
        },
        {
            key = "immortal_guard",
            name = "不灭守护",
            desc = "求生本能 + 守护天使/不朽铠甲/生命之树 + 铁壁体魄Lv3",
            require_set = "survival_set",
            require_relics = { 16, 25, 13 },
            require_talents = { [1] = 3 },
            stages = {
                {
                    desc = "远古守护者苏醒！",
                    spawn = { prefab = "spiderqueen", count = 1, radius = 10, hp_mult = 0.6 },
                    reward = { points = 35, prefab = "nightmarefuel", count = 4 },
                },
            },
        },
        {
            key = "elemental_storm",
            name = "元素风暴",
            desc = "龙焰之心 + 炎龙之心/雷神之锤 + 元素亲和Lv2",
            require_set = "dragon_set",
            require_relics = { 22, 23 },
            require_talents = { [6] = 2 },
            stages = {
                {
                    desc = "火与雷的暴动！",
                    spawn = { prefab = "firehound", count = 2, radius = 12, extra = { { prefab = "icehound", count = 2 } } },
                    reward = { points = 30, prefab = "goldnugget", count = 3 },
                },
            },
        },
        {
            key = "shadow_hunter",
            name = "暗影猎手",
            desc = "暗影契约 + 深渊之触/虚空之镜 + 暗影分身Lv1",
            require_set = "shadow_set",
            require_relics = { 24, 46 },
            require_talents = { [35] = 1 },
            stages = {
                {
                    desc = "暗影骑士从裂隙中降临！",
                    spawn = { prefab = "shadow_knight", count = 1, radius = 10, hp_mult = 2, dmg_mult = 1.2 },
                    reward = { points = 45, prefab = "nightmarefuel", count = 6 },
                },
            },
        },
        {
            key = "void_combo",
            name = "虚空连战",
            desc = "虚空行者 + 节奏之心/连击刻印 + 连战专精Lv3",
            require_set = "void_set",
            require_relics = { 33, 4 },
            require_talents = { [3] = 3 },
            stages = {
                {
                    desc = "虚空裂隙裂开，猎犬群来袭！",
                    spawn = { prefab = "hound", count = 4, radius = 12, extra = { { prefab = "terrorbeak", count = 2 } } },
                    reward = { points = 50, prefab = "treasurechest", count = 1 },
                },
            },
        },
        {
            key = "treasure_master",
            name = "宝藏大师",
            desc = "月光庇佑 + 黄金罗盘/幸运金币 + 猎手本能Lv3",
            require_set = "lunar_set",
            require_relics = { 29, 14 },
            require_talents = { [4] = 3 },
            stages = {
                {
                    desc = "藏宝图的秘密被揭开！宝藏守护者现身！",
                    spawn = { prefab = "spider", count = 4, radius = 12, extra = { { prefab = "spiderqueen", count = 1 } } },
                    reward = { points = 30, prefab = "goldnugget", count = 5 },
                },
            },
        },
    }

    -- 函数说明：检测单个Build组合是否达成，达成则触发一次联动事件（每玩家每组合仅一次）。
    local function CheckBuildCombo(player, combo)
        if not player or not player:IsValid() then return false end
        local data = deps.EnsurePlayerData(player)
        data.combo_done = data.combo_done or {}
        if data.combo_done[combo.key] then return false end

        -- 套装判定
        local set_tags = data.active_set_tags or {}
        if not set_tags[combo.require_set] then return false end

        -- 遗物判定（满足任意一件即可）
        local relics = data.relics or {}
        local relic_ok = false
        for _, rid in ipairs(combo.require_relics) do
            if (relics[rid] or 0) > 0 then
                relic_ok = true
                break
            end
        end
        if not relic_ok then return false end

        -- 天赋判定（须达到指定等级）
        local levels = data.talent_levels or {}
        for tid, min_level in pairs(combo.require_talents) do
            if (levels[tid] or 0) < min_level then return false end
        end

        -- 达成！标记并触发联动事件
        data.combo_done[combo.key] = true
        deps.Announce("【Build协同】达成组合：【" .. combo.name .. "】" .. combo.desc)
        S.ExecuteStage(player, combo, 1)
        return true
    end

    -- 函数说明：检查玩家的全部Build组合规则，供遗物/天赋/套装变更后调用。
    S.CheckBuildCombos = function(player)
        if not player or not player:IsValid() then return end
        for _, combo in ipairs(BUILD_COMBO_DEFS) do
            CheckBuildCombo(player, combo)
        end
    end

    -- 订阅 Build 组合检查事件：遗物拾取 / 天赋选择 / 套装变更时统一触发
    if not _build_combo_subscribed then
        _build_combo_subscribed = true
        EventBus.Subscribe("on_build_combo_check", function(payload)
            local player = payload and payload.player
            if player and player:IsValid() then
                S.CheckBuildCombos(player)
            end
        end)
    end

    -- 函数说明：尝试触发连锁事件，当指定类型的触发条件满足时启动事件链。
    S.TryTrigger = function(player, trigger_type)
        if not player or not player:IsValid() then return end
        local data = deps.EnsurePlayerData(player)

        for _, chain_def in ipairs(CHAIN_DEFS) do
            if chain_def.trigger == trigger_type then
                local key = "chain_" .. chain_def.id
                local progress = data[key] or { count = 0, stage = 0 }

                if progress.stage <= 0 then
                    progress.count = (progress.count or 0) + 1
                    if progress.count >= chain_def.trigger_count then
                        progress.count = 0
                        progress.stage = 1
                        data[key] = progress
                        deps.Announce("【连锁事件】" .. chain_def.name .. " 开始！" .. chain_def.stages[1].desc)
                        S.ExecuteStage(player, chain_def, 1)
                    else
                        data[key] = progress
                    end
                end
            end
        end
    end

    -- 函数说明：执行连锁事件的指定阶段，生成敌人或发放奖励。
    S.ExecuteStage = function(player, chain_def, stage_idx)
        if not player or not player:IsValid() then return end
        local stage = chain_def.stages[stage_idx]
        if not stage then return end

        if not stage.announce_only then
            local spawn = stage.spawn
            if spawn then
                local pt = player:GetPosition()
                for i = 1, (spawn.count or 1) do
                    local offset = deps.FindWalkableOffset(pt, math.random() * 2 * deps.PI, spawn.radius + math.random() * 4, 8, true, false)
                    local spawn_pt = offset and (pt + offset) or pt
                    local ent = deps.SpawnPrefab(spawn.prefab)
                    if ent then
                        ent.Transform:SetPosition(spawn_pt:Get())
                        if spawn.hp_mult and spawn.hp_mult ~= 1 and ent.components.health then
                            ent.components.health:SetMaxHealth(ent.components.health.maxhealth * spawn.hp_mult)
                        end
                        if spawn.dmg_mult and spawn.dmg_mult ~= 1 and ent.components.combat then
                            ent.components.combat.defaultdamage = (ent.components.combat.defaultdamage or 10) * spawn.dmg_mult
                        end
                        if spawn.size_mult and ent.Transform then
                            ent.Transform:SetScale(spawn.size_mult, spawn.size_mult, spawn.size_mult)
                        end
                        if ent.components.combat then
                            ent.components.combat:SetTarget(player)
                        end
                    end
                end

                if spawn.extra then
                    for _, extra in ipairs(spawn.extra) do
                        for i = 1, (extra.count or 1) do
                            local offset = deps.FindWalkableOffset(pt, math.random() * 2 * deps.PI, spawn.radius + math.random() * 4, 8, true, false)
                            local spawn_pt = offset and (pt + offset) or pt
                            local ent = deps.SpawnPrefab(extra.prefab)
                            if ent then
                                ent.Transform:SetPosition(spawn_pt:Get())
                                if ent.components.combat then
                                    ent.components.combat:SetTarget(player)
                                end
                            end
                        end
                    end
                end
            end
        end

        -- 发放阶段奖励
        local reward = stage.reward
        if reward then
            local d = deps.EnsurePlayerData(player)
            if reward.points and reward.points > 0 then
                d.points = (d.points or 0) + reward.points
                if player.rogue_points then
                    player.rogue_points:set(d.points)
                end
            end
            if reward.prefab and player.components.inventory then
                for i = 1, (reward.count or 1) do
                    local item = deps.SpawnPrefab(reward.prefab)
                    if item then
                        player.components.inventory:GiveItem(item)
                    end
                end
            end
        end
    end

    -- 函数说明：推进连锁事件到下一阶段，由外部系统在条件满足时调用。
    S.AdvanceChain = function(player, chain_id)
        if not player or not player:IsValid() then return end
        local data = deps.EnsurePlayerData(player)
        local key = "chain_" .. chain_id

        local chain_def = nil
        for _, cd in ipairs(CHAIN_DEFS) do
            if cd.id == chain_id then chain_def = cd; break end
        end
        if not chain_def then return end

        local progress = data[key] or { count = 0, stage = 0 }
        local next_stage = (progress.stage or 0) + 1

        if next_stage > #chain_def.stages then
            progress.stage = 0
            progress.count = 0
            data[key] = progress
            deps.Announce("【连锁事件】" .. chain_def.name .. " 已完成！")
            return
        end

        progress.stage = next_stage
        data[key] = progress
        deps.Announce("【连锁事件】" .. chain_def.name .. " 阶段" .. next_stage .. "：" .. chain_def.stages[next_stage].desc)
        S.ExecuteStage(player, chain_def, next_stage)
    end

    return S
end

return M
