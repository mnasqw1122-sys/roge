require "behaviours/wander"
require "behaviours/chaseandattack"
require "behaviours/runaway"
require "behaviours/doaction"
require "behaviours/follow"

local AIPerception = require("rogue/rogue_ai_perception")

local RogueNPCBrain = Class(Brain, function(self, inst)
    Brain._ctor(self, inst)
end)

local MIN_FOLLOW_DIST = 5
local MAX_FOLLOW_DIST = 9
local TARGET_FOLLOW_DIST = 7

local MAX_CHASE_TIME = 20
local MAX_CHASE_DIST = 40

local KITE_DIST = 3.5
local KITE_STOP_DIST = 4.5

-- 函数说明：获取当前战斗目标
local function GetTarget(inst)
    return inst.components.combat.target
end

-- 函数说明：寻找可攻击的玩家
local function FindPlayerToAttack(inst)
    local target = GetTarget(inst)
    if target and target:IsValid() and not target:HasTag("playerghost") and not (target.components.health and target.components.health:IsDead()) then
        return target
    end
    local x, y, z = inst.Transform:GetWorldPosition()
    local players = FindPlayersInRange(x, y, z, 30, true)
    for _, p in ipairs(players) do
        if not p:HasTag("playerghost") and not (p.components.health and p.components.health:IsDead()) then
            inst.components.combat:SetTarget(p)
            return p
        end
    end
    return nil
end

-- 函数说明：获取出生点位置
local function GetHome(inst)
    if inst.components.knownlocations then
        return inst.components.knownlocations:GetLocation("home") or inst:GetPosition()
    end
    return inst:GetPosition()
end

-- 函数说明：获取跟随的玩家
local function GetPlayerToFollow(inst)
    local x, y, z = inst.Transform:GetWorldPosition()
    local players = FindPlayersInRange(x, y, z, 30, true)
    if #players > 0 then
        return players[1]
    end
    return nil
end

-- 函数说明：获取AI等级
local function GetLevel(inst)
    return inst._ai_level and inst._ai_level:value() or 1
end

-- 函数说明：获取AI个性配置
local function GetPersonality(inst)
    return inst._ai_personality or "balanced"
end

-- 函数说明：获取感知系统
local function GetPerception(inst)
    return inst._ai_perception
end

-- 函数说明：判断是否应该使用传送法杖逃生
local function ShouldUseTelelocator(inst)
    local level = GetLevel(inst)
    local personality = GetPersonality(inst)
    local threshold = 0.25 + math.min(0.25, (level - 1) * 0.02)
    if personality == "cautious" then
        threshold = threshold + 0.1
    elseif personality == "aggressive" then
        threshold = threshold - 0.05
    end
    if inst.components.health:GetPercent() < threshold and not inst.sg:HasStateTag("busy") then
        local now = GetTime()
        local cd = math.max(10, 30 - (level - 1) * 1.5)
        if not inst.last_teleport_time or (now - inst.last_teleport_time > cd) then
            local staff = inst.components.inventory:FindItem(function(item) return item.prefab == "telestaff" end)
            if staff then
                inst.last_teleport_time = now
                return BufferedAction(inst, inst, ACTIONS.CASTSPELL, staff)
            end
        end
    end
    return nil
end

-- 函数说明：判断是否应该使用排箫
local function ShouldUsePanFlute(inst)
    local level = GetLevel(inst)
    local personality = GetPersonality(inst)
    local threshold = 0.5 + math.min(0.3, (level - 1) * 0.02)
    if personality == "cautious" then
        threshold = threshold + 0.1
    elseif personality == "aggressive" then
        threshold = threshold + 0.15
    end
    if inst.components.health:GetPercent() < threshold and not inst.sg:HasStateTag("busy") then
        local now = GetTime()
        local cd = math.max(8, 20 - (level - 1) * 1.0)
        if not inst.last_panflute_time or (now - inst.last_panflute_time > cd) then
            local panflute = inst.components.inventory:FindItem(function(item) return item.prefab == "panflute" end)
            if panflute then
                local x, y, z = inst.Transform:GetWorldPosition()
                local ents = TheSim:FindEntities(x, y, z, 15, {"player"})
                local should_sleep = false
                for _, v in ipairs(ents) do
                    if not (v.components.sleeper and v.components.sleeper:IsAsleep()) then
                        should_sleep = true
                        break
                    end
                end
                if should_sleep then
                    inst.last_panflute_time = now
                    return BufferedAction(inst, nil, ACTIONS.PLAY, panflute)
                end
            end
        end
    end
    return nil
end

-- 函数说明：判断是否应该使用风向标施法
local function ShouldCastTornado(inst)
    local target = GetTarget(inst)
    if not target or not target:IsValid() then return nil end

    local weapon = inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
    if weapon and weapon.prefab == "staff_tornado" and not inst.sg:HasStateTag("busy") then
        local now = GetTime()
        local level = GetLevel(inst)
        local cd = math.max(3, 8 - (level - 1) * 0.5)
        if not inst.last_tornado_time or (now - inst.last_tornado_time > cd) then
            local distsq = inst:GetDistanceSqToInst(target)
            if distsq < 400 and distsq >= 36 then
                inst.last_tornado_time = now
                local buffaction = BufferedAction(inst, target, ACTIONS.CASTSPELL, weapon)
                buffaction.distance = 20
                return buffaction
            end
        end
    end
    return nil
end

-- 函数说明：判断是否应该吃食物回血
local function ShouldEatFood(inst)
    local level = GetLevel(inst)
    local personality = GetPersonality(inst)
    local threshold = 0.6 + math.min(0.3, (level - 1) * 0.02)
    if personality == "cautious" then
        threshold = threshold + 0.1
    elseif personality == "aggressive" then
        threshold = threshold - 0.1
    end
    if inst.components.health:GetPercent() < threshold and not inst.sg:HasStateTag("busy") then
        local target = GetTarget(inst)
        if target and target:IsValid() then
            local distsq = inst:GetDistanceSqToInst(target)
            if distsq < 16 then
                return nil
            end
        end

        local now = GetTime()
        local cd = math.max(8, 15 - (level - 1) * 0.5)
        if not inst.last_eat_time or (now - inst.last_eat_time > cd) then
            local food = inst.components.inventory:FindItem(function(item) return item.components.edible ~= nil end)
            if food then
                inst.last_eat_time = now
                return BufferedAction(inst, inst, ACTIONS.EAT, food)
            end
        end
    end
    return nil
end

-- 函数说明：判断是否应该进行战术闪避
local function ShouldTacticalDodge(inst)
    local perception = GetPerception(inst)
    if not perception then return false end
    perception:Scan()

    local level = GetLevel(inst)
    local personality = GetPersonality(inst)
    local dodge_chance = 0.1 + (level - 1) * 0.03
    if personality == "evasive" then
        dodge_chance = dodge_chance + 0.15
    elseif personality == "aggressive" then
        dodge_chance = dodge_chance - 0.05
    end

    if perception.player_is_attacking and perception.nearest_threat_dist < 12 then
        return math.random() < dodge_chance
    end
    return false
end

-- 函数说明：判断是否应该进行侧翼包抄
local function ShouldFlank(inst)
    local perception = GetPerception(inst)
    if not perception then return false end
    local level = GetLevel(inst)
    local personality = GetPersonality(inst)

    if personality == "aggressive" and level >= 3 then
        local advantage = perception:GetCombatAdvantage()
        return advantage > 0 and perception.nearest_threat_dist > 36
    end
    return false
end

-- 函数说明：判断是否应该低血量撤退
local function ShouldRetreat(inst)
    local perception = GetPerception(inst)
    if not perception then return false end
    local level = GetLevel(inst)
    local personality = GetPersonality(inst)
    local hp_pct = inst.components.health and inst.components.health:GetPercent() or 1
    local retreat_threshold = 0.2
    if personality == "cautious" then
        retreat_threshold = 0.35
    elseif personality == "aggressive" then
        retreat_threshold = 0.1
    end
    retreat_threshold = retreat_threshold + (level - 1) * 0.01
    return hp_pct < retreat_threshold and perception.retreat_path_clear
end

-- 函数说明：判断是否应该追击低血量玩家
local function ShouldPursueLowHP(inst)
    local perception = GetPerception(inst)
    if not perception then return false end
    local level = GetLevel(inst)
    local personality = GetPersonality(inst)

    if level >= 5 and (personality == "aggressive" or personality == "balanced") then
        return perception.player_health_pct < 0.3
    end
    return false
end

function RogueNPCBrain:OnStart()
    self.inst._ai_perception = AIPerception.Create(self.inst)

    local root = PriorityNode({
        -- 1. 危急时刻使用传送法杖
        DoAction(self.inst, ShouldUseTelelocator, "Use Telelocator", true),

        -- 2. 血量低时使用排箫
        DoAction(self.inst, ShouldUsePanFlute, "Use Pan Flute", true),

        -- 3. 没满血尝试吃东西
        DoAction(self.inst, ShouldEatFood, "Eat Food", true),

        -- 4. 如果拿着风向标，优先远程施法
        DoAction(self.inst, ShouldCastTornado, "Cast Tornado", true),

        -- 5. 战斗决策层
        WhileNode(function() return FindPlayerToAttack(self.inst) ~= nil end, "Combat",
            PriorityNode({
                -- 5.1 低血量撤退
                IfNode(function() return ShouldRetreat(self.inst) end, "Should Retreat",
                    RunAway(self.inst, function()
                        return GetTarget(self.inst)
                    end, 10, 15)
                ),

                -- 5.2 风向标专属拉扯
                RunAway(self.inst, { getfn = function()
                    local target = GetTarget(self.inst)
                    local w = self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
                    if target and w and w.prefab == "staff_tornado" then
                        local time_since_hit = GetTime() - (self.inst.components.combat.lastwasattackedtime or 0)
                        if time_since_hit < 0.5 then
                            return nil
                        end
                        local now = GetTime()
                        local level = GetLevel(self.inst)
                        local cd = math.max(3, 8 - (level - 1) * 0.5)
                        if self.inst.last_tornado_time and (now - self.inst.last_tornado_time <= cd) then
                            return target
                        end
                        if self.inst:GetDistanceSqToInst(target) < 36 then
                            return target
                        end
                    end
                    return nil
                end }, 8, 10),

                -- 5.3 智能风筝（基于感知系统增强）
                RunAway(self.inst, { getfn = function()
                    local target = GetTarget(self.inst)
                    if not target or not target:IsValid() then return nil end

                    local w = self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
                    local is_tornado = w and w.prefab == "staff_tornado"
                    if is_tornado then return nil end

                    local distsq = self.inst:GetDistanceSqToInst(target)
                    if distsq < 2.25 then return nil end

                    local personality = GetPersonality(self.inst)
                    local level = GetLevel(self.inst)

                    if target.sg and target.sg:HasStateTag("attack") and distsq < 12 then
                        if personality == "evasive" then
                            return target
                        end
                        if personality == "aggressive" then
                            return nil
                        end
                        return target
                    end

                    if self.inst.components.combat:InCooldown() and distsq < 9 then
                        if self.inst.components.health:GetPercent() > 0.5 or (target.components.health and target.components.health:GetPercent() < 0.3) then
                            if personality == "aggressive" then return nil end
                            if personality == "evasive" then return target end
                            return nil
                        end
                        return target
                    end

                    return nil
                end }, KITE_DIST, KITE_STOP_DIST),

                -- 5.4 追击低血量玩家
                IfNode(function() return ShouldPursueLowHP(self.inst) end, "Pursue Low HP",
                    ChaseAndAttack(self.inst, MAX_CHASE_TIME * 1.5, MAX_CHASE_DIST + GetLevel(self.inst) * 2)
                ),

                -- 5.5 正常追击和攻击
                ChaseAndAttack(self.inst, MAX_CHASE_TIME, MAX_CHASE_DIST + GetLevel(self.inst)),
            }, 0.25)
        ),

        -- 6. 如果找不到玩家，主动跑向玩家位置
        Follow(self.inst, GetPlayerToFollow, MIN_FOLLOW_DIST, TARGET_FOLLOW_DIST, MAX_FOLLOW_DIST),

        -- 7. 游荡
        Wander(self.inst, GetHome, 20)
    }, .25)

    self.bt = BT(self.inst, root)
end

return RogueNPCBrain
