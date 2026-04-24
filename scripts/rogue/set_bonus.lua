--[[
    文件说明：set_bonus.lua
    功能：套装效果系统。
    检测玩家当前装备组合，当满足套装条件时自动应用套装增益效果，装备变更时实时更新。
]]
local M = {}

function M.Create(deps)
    local S = {}
    local SET_DEFS = deps.SET_BONUS_DEFS or {}
    local EQUIP_BODY = EQUIPSLOTS.BODY or "body"
    local EQUIP_HEAD = EQUIPSLOTS.HEAD or "head"
    local EQUIP_HANDS = EQUIPSLOTS.HANDS or "hands"

    -- 函数说明：获取玩家当前装备的prefab映射表，按槽位分类。
    local function GetEquippedItems(player)
        if not player or not player.components or not player.components.inventory then
            return {}
        end
        local inv = player.components.inventory
        local equipped = {}
        if inv:GetEquippedItem(EQUIP_BODY) then
            local item = inv:GetEquippedItem(EQUIP_BODY)
            equipped.body = item.prefab
        end
        if inv:GetEquippedItem(EQUIP_HEAD) then
            local item = inv:GetEquippedItem(EQUIP_HEAD)
            equipped.head = item.prefab
        end
        if inv:GetEquippedItem(EQUIP_HANDS) then
            local item = inv:GetEquippedItem(EQUIP_HANDS)
            equipped.hand = item.prefab
        end
        return equipped
    end

    -- 函数说明：计算玩家当前激活的套装效果列表。
    local function CalculateActiveSets(player)
        local equipped = GetEquippedItems(player)
        local active_sets = {}

        for _, set_def in ipairs(SET_DEFS) do
            local count = 0
            for slot, prefab in pairs(set_def.pieces) do
                if equipped[slot] == prefab then
                    count = count + 1
                end
            end

            if count >= set_def.threshold then
                local best_bonus = nil
                for n, bonus in pairs(set_def.bonuses) do
                    if count >= n then
                        if not best_bonus or n > (best_bonus._piece_count or 0) then
                            best_bonus = bonus
                            best_bonus._piece_count = n
                        end
                    end
                end
                if best_bonus then
                    table.insert(active_sets, {
                        set_tag = set_def.set_tag,
                        name = set_def.name,
                        piece_count = count,
                        bonus = best_bonus,
                    })
                end
            end
        end

        return active_sets
    end

    -- 函数说明：移除玩家身上所有套装效果。
    local function RemoveAllSetBonuses(player, data)
        if not data then return end
        local applied = data.set_bonuses_applied or {}
        for set_tag, bonus in pairs(applied) do
            if bonus.dmg_taken_mult then
                if player.components.combat and player.components.combat.externaldamagetakenmultipliers then
                    player.components.combat.externaldamagetakenmultipliers:RemoveModifier(player, "set_bonus_" .. set_tag)
                end
            end
            if bonus.speed_bonus then
                if player.components.locomotor then
                    player.components.locomotor:RemoveExternalSpeedMultiplier(player, "set_bonus_" .. set_tag)
                end
            end
            if bonus.hp_bonus then
                if player.components.health then
                    player.components.health:SetMaxHealth(player.components.health.maxhealth - bonus.hp_bonus)
                end
            end
            if bonus.hunger_drain_mult then
                if player.components.hunger then
                    player.components.hunger:SetRate(player.components.hunger.hungerrate / bonus.hunger_drain_mult)
                end
            end
            if bonus.regen_per_sec then
                if player._set_regen_task then
                    player._set_regen_task:Cancel()
                    player._set_regen_task = nil
                end
            end
            if bonus.dmg_bonus then
                data.set_damage_bonus = (data.set_damage_bonus or 0) - bonus.dmg_bonus
            end
            if bonus.combo_window then
                data.set_combo_window = (data.set_combo_window or 0) - bonus.combo_window
            end
            if bonus.sanity_regen_bonus then
                data.set_sanity_regen_bonus = (data.set_sanity_regen_bonus or 0) - bonus.sanity_regen_bonus
            end
        end
        if player.components.combat and player.components.combat.externaldamagemultipliers then
            player.components.combat.externaldamagemultipliers:RemoveModifier(player, deps.DAMAGE_MODIFIER_KEY)
        end
        data.set_bonuses_applied = {}
    end

    -- 函数说明：为玩家应用当前激活的套装效果。
    local function ApplySetBonuses(player, data, active_sets)
        if not data then return end
        RemoveAllSetBonuses(player, data)
        data.set_bonuses_applied = {}

        for _, set_info in ipairs(active_sets) do
            local bonus = set_info.bonus
            local tag = set_info.set_tag
            data.set_bonuses_applied[tag] = bonus

            if bonus.dmg_taken_mult then
                if player.components.combat and player.components.combat.externaldamagetakenmultipliers then
                    player.components.combat.externaldamagetakenmultipliers:SetModifier(player, bonus.dmg_taken_mult, "set_bonus_" .. tag)
                end
            end

            if bonus.speed_bonus then
                if player.components.locomotor then
                    player.components.locomotor:SetExternalSpeedMultiplier(player, "set_bonus_" .. tag, 1 + bonus.speed_bonus)
                end
            end

            if bonus.hp_bonus then
                if player.components.health then
                    player.components.health:SetMaxHealth(player.components.health.maxhealth + bonus.hp_bonus)
                    player.components.health:DoDelta(bonus.hp_bonus)
                end
            end

            if bonus.hunger_drain_mult then
                if player.components.hunger then
                    player.components.hunger:SetRate(player.components.hunger.hungerrate * bonus.hunger_drain_mult)
                end
            end

            if bonus.regen_per_sec then
                if player._set_regen_task then player._set_regen_task:Cancel() end
                player._set_regen_task = player:DoPeriodicTask(1, function(inst)
                    if inst and inst:IsValid() and inst.components.health and not inst.components.health:IsDead() then
                        inst.components.health:DoDelta(bonus.regen_per_sec)
                    end
                end)
            end

            if bonus.dmg_bonus then
                data.set_damage_bonus = (data.set_damage_bonus or 0) + bonus.dmg_bonus
            end

            if bonus.combo_window then
                data.set_combo_window = (data.set_combo_window or 0) + bonus.combo_window
            end

            if bonus.sanity_regen_bonus then
                data.set_sanity_regen_bonus = (data.set_sanity_regen_bonus or 0) + bonus.sanity_regen_bonus
            end

            if bonus.ignite_chance then
                data.set_ignite_chance = (data.set_ignite_chance or 0) + bonus.ignite_chance
            end

            if bonus.shadow_dmg_bonus then
                data.set_shadow_dmg_bonus = (data.set_shadow_dmg_bonus or 0) + bonus.shadow_dmg_bonus
            end
        end

        if player.components.combat and player.components.combat.externaldamagemultipliers then
            local set_dmg = data.set_damage_bonus or 0
            player.components.combat.externaldamagemultipliers:SetModifier(player, 1 + set_dmg, deps.DAMAGE_MODIFIER_KEY)
        end
    end

    -- 函数说明：检测并更新玩家的套装效果状态，在装备变更时调用。
    S.RefreshSetBonuses = function(player)
        if not player or not player:IsValid() then return end
        local data = deps.EnsurePlayerData(player)
        local active_sets = CalculateActiveSets(player)
        ApplySetBonuses(player, data, active_sets)

        local prev_tags = data.active_set_tags or {}
        data.active_set_tags = {}
        for _, set_info in ipairs(active_sets) do
            data.active_set_tags[set_info.set_tag] = true
            if not prev_tags[set_info.set_tag] then
                deps.Announce(player:GetDisplayName() .. " 激活套装效果：" .. set_info.name .. "（" .. set_info.bonus.desc .. "）")
            end
        end
    end

    -- 函数说明：为玩家注册装备变更监听器，自动触发套装检测。
    S.RegisterEquipmentWatcher = function(player)
        if not player or player._set_bonus_watcher then return end
        player._set_bonus_watcher = true

        player:ListenForEvent("equip", function(inst)
            inst:DoTaskInTime(0, function()
                if inst and inst:IsValid() then
                    S.RefreshSetBonuses(inst)
                end
            end)
        end)

        player:ListenForEvent("unequip", function(inst)
            inst:DoTaskInTime(0, function()
                if inst and inst:IsValid() then
                    S.RefreshSetBonuses(inst)
                end
            end)
        end)
    end

    return S
end

return M
