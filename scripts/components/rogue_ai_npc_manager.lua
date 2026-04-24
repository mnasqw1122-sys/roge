local GLOBAL = _G or GLOBAL

local weapons = {
    "glasscutter",
    "nightsword",
    "ruins_bat",
    "staff_tornado",
}

local armors = {
    "armor_sanity",
    "shieldofterror",
    "armordragonfly",
    "armorruins",
    "armorskeleton",
    "armor_bramble",
    "armordreadstone",
    "armor_lunarplant",
    "armor_voidcloth",
    "armorsnurtleshell",
}

local hats = {
    "ruinshat",
    "skeletonhat",
    "slurtlehat",
    "dreadstonehat",
    "voidclothhat",
    "lunarplanthat",
}

local characters = {
    "wilson", "willow", "wendy", "wx78", "wickerbottom", "woodie",
    "wes", "waxwell", "wathgrithr", "webber", "winona", "warly",
    "wortox", "wormwood", "wurt", "walter", "wanda"
}

local PERSONALITIES = { "aggressive", "cautious", "evasive", "balanced" }

local PERSONALITY_WEIGHTS = {
    aggressive = 3,
    balanced = 4,
    cautious = 2,
    evasive = 3,
}

local RogueAINPCManager = Class(function(self, inst)
    self.inst = inst
    self.active_npc = nil
    self.saved_npc_data = nil
    self.ai_learning_data = {
        level = 1,
        exp = 0,
        deaths = 0,
        escapes = 0,
        total_damage_dealt = 0,
        total_damage_taken = 0,
    }
    self.tactical_memory = {
        player_dodge_patterns = {},
        player_weapon_preferences = {},
        player_combat_styles = {},
        last_fight_duration = 0,
        last_fight_result = nil,
    }
    self.spawn_count = 0
end)

-- 函数说明：存档
function RogueAINPCManager:OnSave()
    return {
        saved_npc_data = self.saved_npc_data,
        ai_learning_data = self.ai_learning_data,
        tactical_memory = self.tactical_memory,
        spawn_count = self.spawn_count,
    }
end

-- 函数说明：读档
function RogueAINPCManager:OnLoad(data)
    if data then
        if data.saved_npc_data then
            self.saved_npc_data = data.saved_npc_data
        end
        if data.ai_learning_data then
            self.ai_learning_data = data.ai_learning_data
        end
        if data.tactical_memory then
            self.tactical_memory = data.tactical_memory
        end
        if data.spawn_count then
            self.spawn_count = data.spawn_count
        end
    end
end

-- 函数说明：获取经验并处理升级
function RogueAINPCManager:GainExp(amount)
    if not self.ai_learning_data then
        self.ai_learning_data = { level = 1, exp = 0, deaths = 0, escapes = 0, total_damage_dealt = 0, total_damage_taken = 0 }
    end
    self.ai_learning_data.exp = self.ai_learning_data.exp + amount
    local req = self.ai_learning_data.level * 100
    local leveled_up = false
    while self.ai_learning_data.exp >= req do
        self.ai_learning_data.exp = self.ai_learning_data.exp - req
        self.ai_learning_data.level = self.ai_learning_data.level + 1
        req = self.ai_learning_data.level * 100
        leveled_up = true
    end

    if leveled_up and GLOBAL.TheNet then
        GLOBAL.TheNet:Announce("【系统提示】神秘的挑战者在战斗中吸取了经验，进化到了等级 " .. self.ai_learning_data.level .. "！")
    end
end

-- 函数说明：根据战术记忆选择AI个性
local function PickPersonalityFromMemory(tactical_memory, level)
    local weights = {}
    for _, p in ipairs(PERSONALITIES) do
        weights[p] = PERSONALITY_WEIGHTS[p] or 1
    end

    if tactical_memory then
        if tactical_memory.last_fight_result == "death" then
            weights.cautious = (weights.cautious or 1) + 2
            weights.evasive = (weights.evasive or 1) + 1
        elseif tactical_memory.last_fight_result == "escape" then
            weights.aggressive = (weights.aggressive or 1) + 2
        end

        if level >= 5 then
            weights.aggressive = (weights.aggressive or 1) + 1
        end
        if level >= 8 then
            weights.evasive = (weights.evasive or 1) + 1
        end
    end

    local total = 0
    for _, w in pairs(weights) do
        total = total + w
    end
    local r = math.random() * total
    local acc = 0
    for _, p in ipairs(PERSONALITIES) do
        acc = acc + (weights[p] or 1)
        if r <= acc then
            return p
        end
    end
    return "balanced"
end

-- 函数说明：根据战术记忆选择武器
local function PickWeaponFromMemory(tactical_memory, personality)
    if personality == "aggressive" then
        local melee_weapons = { "glasscutter", "nightsword", "ruins_bat" }
        return melee_weapons[math.random(#melee_weapons)]
    elseif personality == "evasive" then
        if math.random() < 0.6 then
            return "staff_tornado"
        end
        return weapons[math.random(#weapons)]
    elseif personality == "cautious" then
        if math.random() < 0.4 then
            return "staff_tornado"
        end
        return weapons[math.random(#weapons)]
    else
        return weapons[math.random(#weapons)]
    end
end

-- 函数说明：根据战术记忆选择护甲
local function PickArmorFromMemory(tactical_memory, personality)
    if personality == "aggressive" then
        local light_armors = { "armor_sanity", "armorskeleton", "armor_bramble" }
        return light_armors[math.random(#light_armors)]
    elseif personality == "cautious" then
        local heavy_armors = { "armorruins", "armordragonfly", "armordreadstone", "armorsnurtleshell" }
        return heavy_armors[math.random(#heavy_armors)]
    else
        return armors[math.random(#armors)]
    end
end

-- 函数说明：生成NPC数据（基于战术记忆和个性）
function RogueAINPCManager:GenerateNPCData()
    local level = self.ai_learning_data and self.ai_learning_data.level or 1
    local personality = PickPersonalityFromMemory(self.tactical_memory, level)

    return {
        build = characters[math.random(#characters)],
        weapon = PickWeaponFromMemory(self.tactical_memory, personality),
        armor = PickArmorFromMemory(self.tactical_memory, personality),
        hat = hats[math.random(#hats)],
        personality = personality,
    }
end

-- 函数说明：在休息天尝试生成NPC
function RogueAINPCManager:TrySpawnNPC(day, players)
    if self.active_npc and self.active_npc:IsValid() then
        return
    end

    if not self.saved_npc_data then
        self.saved_npc_data = self:GenerateNPCData()
    end

    local data = self.saved_npc_data

    local target_player = players[math.random(#players)]
    if not target_player then return end

    local pt = target_player:GetPosition()
    local offset = FindWalkableOffset(pt, math.random() * 2 * PI, math.random(10, 15), 8, true, false)
    if not offset then return end

    local spawn_pt = pt + offset

    local npc = SpawnPrefab("rogue_npc")
    if not npc then return end

    npc.Transform:SetPosition(spawn_pt:Get())

    local level = self.ai_learning_data and self.ai_learning_data.level or 1

    if npc._ai_level then
        npc._ai_level:set(level)
    end

    if data.personality then
        npc._ai_personality = data.personality
    end

    local base_hp = 500
    local hp_mult = 1 + (level - 1) * 0.15
    npc.components.health:SetMaxHealth(base_hp * hp_mult)
    npc.components.health:SetPercent(1)

    local base_dmg = 34
    local dmg_mult = 1 + (level - 1) * 0.1
    npc.components.combat:SetDefaultDamage(base_dmg * dmg_mult)

    local base_run = 6.5
    npc.components.locomotor.runspeed = base_run + math.min(3, (level - 1) * 0.2)

    local base_period = 0.5
    npc.components.combat:SetAttackPeriod(math.max(0.3, base_period - (level - 1) * 0.02))

    npc.components.combat:SetRange(2 + math.min(1, (level - 1) * 0.05))

    npc.AnimState:SetBuild(data.build)

    npc.rogue_weapon = data.weapon
    npc.rogue_armor = data.armor
    npc.rogue_hat = data.hat

    local function EquipItem(prefab)
        if prefab then
            local item = SpawnPrefab(prefab)
            if item then
                if item.components.armor then
                    item.components.armor:InitCondition(999999, item.components.armor.absorb_percent)
                end
                if item.components.weapon then
                    item.components.weapon:SetDamage(item.components.weapon.damage)
                end
                if item.components.finiteuses then
                    item.components.finiteuses:SetMaxUses(999999)
                    item.components.finiteuses:SetUses(999999)
                end
                npc.components.inventory:Equip(item)
            end
        end
    end

    EquipItem(data.weapon)
    EquipItem(data.armor)
    EquipItem(data.hat)

    local function GiveInfiniteItem(prefab)
        local item = SpawnPrefab(prefab)
        if item then
            if item.components.finiteuses then
                item.components.finiteuses:SetMaxUses(999999)
                item.components.finiteuses:SetUses(999999)
            end
            npc.components.inventory:GiveItem(item)
        end
    end

    GiveInfiniteItem("panflute")
    GiveInfiniteItem("telestaff")

    local food_count = math.min(10, 5 + math.floor(level / 3))
    for i = 1, food_count do
        local food = SpawnPrefab("perogies")
        if food then
            npc.components.inventory:GiveItem(food)
        end
    end

    if level >= 5 then
        GiveInfiniteItem("healingsalve")
    end
    if level >= 8 then
        GiveInfiniteItem("mandrake")
    end

    self.active_npc = npc
    self.spawn_count = (self.spawn_count or 0) + 1

    local personality_names = {
        aggressive = "狂战士",
        cautious = "守卫",
        evasive = "游侠",
        balanced = "战士",
    }
    local p_name = personality_names[data.personality] or "战士"

    if GLOBAL.TheNet then
        GLOBAL.TheNet:Announce("一个神秘的挑战者·" .. p_name .. "（" .. data.build .. " Lv." .. level .. "）出现了！击败它获取丰厚奖励！")
    end
end

-- 函数说明：NPC被击杀时调用
function RogueAINPCManager:OnNPCKilled(npc)
    if self.active_npc == npc then
        self.active_npc = nil
    end
    self.saved_npc_data = nil

    if self.ai_learning_data then
        self.ai_learning_data.deaths = (self.ai_learning_data.deaths or 0) + 1
    end
    self:GainExp(50)

    if self.tactical_memory then
        self.tactical_memory.last_fight_result = "death"
    end

    if GLOBAL.TheNet then
        GLOBAL.TheNet:Announce("神秘的挑战者被击败了！它会记住这次失败的教训...")
    end
end

-- 函数说明：休息天结束时调用
function RogueAINPCManager:OnRestDayEnd()
    if self.active_npc and self.active_npc:IsValid() then
        SpawnPrefab("statue_transition_2").Transform:SetPosition(self.active_npc.Transform:GetWorldPosition())
        self.active_npc:Remove()
        self.active_npc = nil

        if self.ai_learning_data then
            self.ai_learning_data.escapes = (self.ai_learning_data.escapes or 0) + 1
        end
        self:GainExp(100)

        if self.tactical_memory then
            self.tactical_memory.last_fight_result = "escape"
        end

        if GLOBAL.TheNet then
            GLOBAL.TheNet:Announce("神秘的挑战者见势不妙，逃跑了...下个休息天它会带着新的经验回来。")
        end
    end
end

-- 函数说明：记录玩家战斗行为到战术记忆
function RogueAINPCManager:RecordPlayerBehavior(player_guid, behavior_type, data)
    if not self.tactical_memory then return end

    if behavior_type == "dodge" then
        self.tactical_memory.player_dodge_patterns[player_guid] = (self.tactical_memory.player_dodge_patterns[player_guid] or 0) + 1
    elseif behavior_type == "weapon_switch" then
        self.tactical_memory.player_weapon_preferences[player_guid] = data and data.weapon or "unknown"
    elseif behavior_type == "combat_style" then
        self.tactical_memory.player_combat_styles[player_guid] = data and data.style or "unknown"
    end
end

return RogueAINPCManager
