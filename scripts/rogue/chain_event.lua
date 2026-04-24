--[[
    文件说明：chain_event.lua
    功能：连锁事件系统。
    当特定条件满足时触发一系列连续事件，每个事件完成后自动触发下一个，形成叙事性游戏体验。
    连锁事件比普通随机事件更复杂，具有多阶段推进和累计奖励。
]]
local M = {}

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
