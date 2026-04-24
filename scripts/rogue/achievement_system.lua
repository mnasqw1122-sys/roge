--[[
    文件说明：achievement_system.lua
    功能：成就/里程碑系统。
    追踪玩家在局内的各种里程碑（首次击杀、连杀记录、Boss首杀等），完成时给予积分奖励和公告。
    成就数据持久化在 rogue_data.achievements 中，跨局保留。
]]
local M = {}

function M.Create(deps)
    local S = {}

    -- 函数说明：成就定义表，kind对应CheckProgress的kind参数，target为达成阈值。
    local ACHIEVEMENT_DEFS = {
        { id = "first_blood", name = "初见之血", desc = "击杀第一个敌人", kind = "kill", target = 1, points = 5 },
        { id = "hunter_50", name = "猎手初成", desc = "累计击杀50个敌人", kind = "kill", target = 50, points = 15 },
        { id = "slayer_200", name = "杀戮机器", desc = "累计击杀200个敌人", kind = "kill", target = 200, points = 30 },
        { id = "exterminator_500", name = "灭绝者", desc = "累计击杀500个敌人", kind = "kill", target = 500, points = 60 },
        { id = "elite_hunter", name = "精英猎手", desc = "击杀第一个精英敌人", kind = "elite_kill", target = 1, points = 10 },
        { id = "elite_master", name = "精英克星", desc = "累计击杀20个精英敌人", kind = "elite_kill", target = 20, points = 40 },
        { id = "boss_slayer", name = "王者终结", desc = "击杀第一个Boss", kind = "boss_kill", target = 1, points = 20 },
        { id = "boss_dominion", name = "Boss统治者", desc = "累计击杀5个Boss", kind = "boss_kill", target = 5, points = 50 },
        { id = "combo_5", name = "连杀达人", desc = "达成5连杀", kind = "combo", target = 5, points = 10 },
        { id = "combo_15", name = "连杀大师", desc = "达成15连杀", kind = "combo", target = 15, points = 25 },
        { id = "combo_30", name = "连杀传说", desc = "达成30连杀", kind = "combo", target = 30, points = 50 },
        { id = "survivor_10", name = "生存者", desc = "存活10天", kind = "survive_day", target = 10, points = 15 },
        { id = "survivor_30", name = "坚忍不拔", desc = "存活30天", kind = "survive_day", target = 30, points = 30 },
        { id = "survivor_60", name = "不朽意志", desc = "存活60天", kind = "survive_day", target = 60, points = 60 },
        { id = "relic_3", name = "收藏家", desc = "收集3个遗物", kind = "relic_count", target = 3, points = 10 },
        { id = "relic_6", name = "遗物大师", desc = "收集6个遗物", kind = "relic_count", target = 6, points = 25 },
        { id = "talent_5", name = "天赋觉醒", desc = "选择5次天赋", kind = "talent_pick", target = 5, points = 15 },
        { id = "talent_10", name = "天赋满载", desc = "选择10次天赋", kind = "talent_pick", target = 10, points = 30 },
        { id = "shop_rich", name = "豪商", desc = "累计消费100积分", kind = "shop_spend", target = 100, points = 15 },
        { id = "death_defy", name = "死里逃生", desc = "触发1次免死效果", kind = "death_defy", target = 1, points = 15 },
        { id = "set_bonus", name = "套装觉醒", desc = "激活任意套装效果", kind = "set_bonus", target = 1, points = 15 },
        { id = "chain_complete", name = "连锁终结", desc = "完成一条连锁事件", kind = "chain_complete", target = 1, points = 25 },
    }

    -- 函数说明：检查玩家成就进度，当达成条件时解锁成就并发放奖励。
    S.CheckProgress = function(player, kind, amount)
        if not player or not player:IsValid() then return end
        local data = deps.EnsurePlayerData(player)
        if not data.achievements then data.achievements = {} end

        for _, ach in ipairs(ACHIEVEMENT_DEFS) do
            if ach.kind == kind and not data.achievements[ach.id] then
                local progress = data.achievement_progress or {}
                local key = ach.id
                progress[key] = (progress[key] or 0) + (amount or 1)
                data.achievement_progress = progress

                if progress[key] >= ach.target then
                    data.achievements[ach.id] = true

                    data.points = (data.points or 0) + ach.points
                    if player.rogue_points then
                        player.rogue_points:set(data.points)
                    end

                    deps.Announce("【成就解锁】" .. player:GetDisplayName() .. " 达成「" .. ach.name .. "」：" .. ach.desc .. "（+" .. ach.points .. "积分）")

                    if player.components.talker then
                        player.components.talker:Say("成就解锁：" .. ach.name .. "！")
                    end
                end
            end
        end

        if deps.SyncGrowthNetvars then
            deps.SyncGrowthNetvars(player, data)
        end
    end

    -- 函数说明：获取玩家已解锁的成就列表。
    S.GetUnlockedAchievements = function(player)
        if not player then return {} end
        local data = deps.EnsurePlayerData(player)
        local unlocked = {}
        for _, ach in ipairs(ACHIEVEMENT_DEFS) do
            if data.achievements and data.achievements[ach.id] then
                table.insert(unlocked, ach)
            end
        end
        return unlocked
    end

    -- 函数说明：获取所有成就定义（含解锁状态）。
    S.GetAllAchievements = function(player)
        if not player then return ACHIEVEMENT_DEFS end
        local data = deps.EnsurePlayerData(player)
        local result = {}
        for _, ach in ipairs(ACHIEVEMENT_DEFS) do
            local copy = {}
            for k, v in pairs(ach) do copy[k] = v end
            copy.unlocked = data.achievements and data.achievements[ach.id] or false
            copy.progress = (data.achievement_progress and data.achievement_progress[ach.id]) or 0
            table.insert(result, copy)
        end
        return result
    end

    return S
end

return M
