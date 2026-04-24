--[[
    文件说明：rogue_ai_perception.lua
    功能：AI感知系统，为行为树提供环境信息。
    管理NPC对周围环境的感知，包括敌人位置、威胁评估、地形分析、队友状态等。
]]
local M = {}

function M.Create(inst)
    local P = {}
    P.inst = inst
    P.last_scan_time = 0
    P.scan_interval = 0.5
    P.nearby_enemies = {}
    P.nearby_allies = {}
    P.nearest_threat = nil
    P.nearest_threat_dist = math.huge
    P.surround_danger_count = 0
    P.has_los_to_target = false
    P.terrain_info = { near_fire = false, near_water = false, near_structure = false }
    P.player_weapon_type = "melee"
    P.player_is_attacking = false
    P.player_health_pct = 1
    P.player_stamina_pct = 1
    P.average_enemy_dist = 0
    P.flanking_angle = 0
    P.retreat_path_clear = true
    P.aggro_table = {}

    -- 函数说明：执行环境扫描
    function P:Scan()
        local now = GetTime()
        if now - self.last_scan_time < self.scan_interval then return end
        self.last_scan_time = now

        local x, y, z = self.inst.Transform:GetWorldPosition()
        self.nearby_enemies = {}
        self.nearby_allies = {}
        self.surround_danger_count = 0
        local total_dist = 0
        local enemy_count = 0

        local ents = TheSim:FindEntities(x, y, z, 20, nil, { "INLIMBO" })
        for _, ent in ipairs(ents) do
            if ent ~= self.inst and ent:IsValid() then
                local dist = self.inst:GetDistanceSqToInst(ent)
                local is_enemy = ent:HasTag("player") and not ent:HasTag("playerghost")
                    and not (ent.components.health and ent.components.health:IsDead())
                local is_ally = ent:HasTag("rogue_ai_npc") or ent:HasTag("companion")

                if is_enemy then
                    table.insert(self.nearby_enemies, { entity = ent, dist = dist })
                    total_dist = total_dist + math.sqrt(dist)
                    enemy_count = enemy_count + 1
                    if dist < 36 then
                        self.surround_danger_count = self.surround_danger_count + 1
                    end
                elseif is_ally then
                    table.insert(self.nearby_allies, { entity = ent, dist = dist })
                end
            end
        end

        self.average_enemy_dist = enemy_count > 0 and (total_dist / enemy_count) or math.huge

        table.sort(self.nearby_enemies, function(a, b) return a.dist < b.dist end)
        self.nearest_threat = #self.nearby_enemies > 0 and self.nearby_enemies[1].entity or nil
        self.nearest_threat_dist = #self.nearby_enemies > 0 and self.nearby_enemies[1].dist or math.huge

        self:ScanPlayerInfo()
        self:ScanTerrain(x, y, z)
        self:ScanRetreatPath(x, y, z)
        self:UpdateFlankingAngle()
    end

    -- 函数说明：扫描玩家信息
    function P:ScanPlayerInfo()
        local target = self.inst.components.combat and self.inst.components.combat.target
        if target and target:IsValid() and target:HasTag("player") then
            local weapon = target.components.inventory and target.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
            if weapon then
                if weapon.prefab == "staff_tornado" or weapon.prefab == "firestaff" or weapon.prefab == "icestaff"
                    or weapon.prefab == "telestaff" or weapon.prefab == "orangestaff" or weapon.prefab == "greenstaff" then
                    self.player_weapon_type = "ranged"
                elseif weapon.prefab == "boomerang" or weapon.prefab == "blowdart_pipe" then
                    self.player_weapon_type = "projectile"
                else
                    self.player_weapon_type = "melee"
                end
            else
                self.player_weapon_type = "unarmed"
            end

            self.player_is_attacking = target.sg and target.sg:HasStateTag("attack") or false
            self.player_health_pct = target.components.health and target.components.health:GetPercent() or 1
        else
            self.player_weapon_type = "melee"
            self.player_is_attacking = false
            self.player_health_pct = 1
        end
    end

    -- 函数说明：扫描地形信息
    function P:ScanTerrain(x, y, z)
        self.terrain_info.near_fire = false
        self.terrain_info.near_water = false
        self.terrain_info.near_structure = false

        local fires = TheSim:FindEntities(x, y, z, 8, { "campfire", "fire" })
        if #fires > 0 then self.terrain_info.near_fire = true end

        local structures = TheSim:FindEntities(x, y, z, 6, { "structure" })
        if #structures > 0 then self.terrain_info.near_structure = true end

        local tile = TheWorld.Map and TheWorld.Map:GetTileAtPoint(x, y, z) or 0
        if tile == WORLD_TILES.OCEAN_COASTAL or tile == WORLD_TILES.OCEAN_SWELL
            or tile == WORLD_TILES.OCEAN_ROUGH or tile == WORLD_TILES.OCEAN_BRINE then
            self.terrain_info.near_water = true
        end
    end

    -- 函数说明：扫描撤退路径
    function P:ScanRetreatPath(x, y, z)
        local target = self.inst.components.combat and self.inst.components.combat.target
        if not target or not target:IsValid() then
            self.retreat_path_clear = true
            return
        end
        local tx, ty, tz = target.Transform:GetWorldPosition()
        local dx, dz = x - tx, z - tz
        local dist = math.sqrt(dx * dx + dz * dz)
        if dist < 0.1 then
            self.retreat_path_clear = false
            return
        end
        local nx, nz = dx / dist, dz / dist
        local check_dist = 6
        local cx, cz = x + nx * check_dist, z + nz * check_dist
        self.retreat_path_clear = TheWorld.Map and TheWorld.Map:IsAboveGroundAtPoint(cx, y, cz) or true
    end

    -- 函数说明：计算侧翼角度
    function P:UpdateFlankingAngle()
        local target = self.inst.components.combat and self.inst.components.combat.target
        if not target or not target:IsValid() then
            self.flanking_angle = 0
            return
        end
        local x, y, z = self.inst.Transform:GetWorldPosition()
        local tx, ty, tz = target.Transform:GetWorldPosition()
        local angle_to_target = math.atan2(tz - z, tx - x)
        local facing = self.inst.Transform:GetRotation() * DEGREES
        self.flanking_angle = math.abs(angle_to_target - facing)
        if self.flanking_angle > PI then
            self.flanking_angle = 2 * PI - self.flanking_angle
        end
    end

    -- 函数说明：获取威胁等级（0-10）
    function P:GetThreatLevel()
        local hp_pct = self.inst.components.health and self.inst.components.health:GetPercent() or 1
        local threat = 0
        threat = threat + (1 - hp_pct) * 4
        threat = threat + math.min(3, self.surround_danger_count)
        if self.player_is_attacking then threat = threat + 1 end
        if self.player_weapon_type == "ranged" then threat = threat + 1 end
        if not self.retreat_path_clear then threat = threat + 1 end
        return math.min(10, threat)
    end

    -- 函数说明：获取战斗优势评估（-5到+5）
    function P:GetCombatAdvantage()
        local advantage = 0
        local my_hp = self.inst.components.health and self.inst.components.health:GetPercent() or 1
        advantage = advantage + (my_hp - self.player_health_pct) * 2
        advantage = advantage + (#self.nearby_allies - self.surround_danger_count) * 0.5
        if self.player_weapon_type == "melee" then
            local weapon = self.inst.components.inventory and self.inst.components.inventory:GetEquippedItem(EQUIPSLOTS.HANDS)
            if weapon and weapon.prefab == "staff_tornado" then
                advantage = advantage + 1
            end
        end
        return math.max(-5, math.min(5, advantage))
    end

    -- 函数说明：更新仇恨表
    function P:UpdateAggro(attacker, damage)
        if not attacker or not attacker:IsValid() then return end
        local guid = attacker.GUID
        self.aggro_table[guid] = (self.aggro_table[guid] or 0) + (damage or 0)
    end

    -- 函数说明：获取最高仇恨目标
    function P:GetHighestAggroTarget()
        local max_aggro = 0
        local target = nil
        for guid, aggro in pairs(self.aggro_table) do
            if aggro > max_aggro then
                local ent = Ents[guid]
                if ent and ent:IsValid() and not (ent.components.health and ent.components.health:IsDead()) then
                    max_aggro = aggro
                    target = ent
                else
                    self.aggro_table[guid] = nil
                end
            end
        end
        return target
    end

    -- 函数说明：衰减仇恨表
    function P:DecayAggro()
        for guid, aggro in pairs(self.aggro_table) do
            self.aggro_table[guid] = aggro * 0.95
            if self.aggro_table[guid] < 1 then
                self.aggro_table[guid] = nil
            end
        end
    end

    return P
end

return M
