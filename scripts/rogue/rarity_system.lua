--[[
    文件说明：rarity_system.lua
    功能：装备品质与保底系统。
    负责品质权重计算、保底计数器管理、赛季词缀轮换、能力池构建与随机抽取。
    从 drop_system.lua 拆分而来。
]]
local M = {}

-- 函数说明：创建品质与保底系统实例
function M.Create(deps)
    local state = {}
    state.gear_quality_pity = { boss_gear = 0, trial_gear = 0 }

    -- 函数说明：计算递减收益，使用平滑对数衰减曲线防止属性无限叠加
    -- 优化：使用对数衰减替代激进阶梯衰减(100%→50%→10%)，1.5倍阈值后增长率持续递减但不会断崖式下降
    local function CalculateDiminishingReturn(current_val, add_val, threshold)
        threshold = threshold or 1.5
        if current_val <= threshold then
            return add_val
        end
        return add_val * (threshold / current_val)
    end

    -- 品质定义表
    local RARITY_DEFS = {
        common = { rarity_name = "普通", mult = 0.9, min_affix = 1, max_affix = 1 },
        rare = { rarity_name = "精良", mult = 1.08, min_affix = 1, max_affix = 2 },
        epic = { rarity_name = "史诗", mult = 1.26, min_affix = 2, max_affix = 2 },
        legendary = { rarity_name = "传说", mult = 1.5, min_affix = 2, max_affix = 3 },
    }

    -- 函数说明：获取当前赛季的词缀轮换配置
    local function GetSeasonRotation(day)
        local defs = deps.SEASON_AFFIX_ROTATION_DEFS
        if not defs or #defs == 0 then return nil end
        local idx = ((math.max(1, day) - 1) % #defs) + 1
        return defs[idx]
    end

    -- 函数说明：将列表转换为集合（用于快速查找）
    local function BuildSet(list)
        local set = {}
        for _, v in ipairs(list or {}) do
            set[v] = true
        end
        return set
    end

    -- 函数说明：检查物品是否匹配指定的能力槽位
    local function IsAbilitySlotMatch(item, slot)
        if slot == "all" then
            return true
        end
        if slot == "weapon" then
            return item.components and item.components.weapon ~= nil
        end
        if slot == "armor" then
            return item.components and item.components.armor ~= nil
        end
        if slot == "equippable" then
            return item.components and item.components.equippable ~= nil
        end
        return false
    end

    -- 函数说明：根据物品和天数构建可用的能力池
    local function BuildAbilityPool(item, day, ability_defs)
        local out = {}
        local rotation = GetSeasonRotation(day)
        local enabled = BuildSet(rotation and rotation.enable or nil)
        local disabled = BuildSet(rotation and rotation.disable or nil)
        for _, def in ipairs(ability_defs) do
            if day >= (def.min_day or 0) and IsAbilitySlotMatch(item, def.slot) and not disabled[def.id] then
                local node = def
                if next(enabled) ~= nil and enabled[def.id] then
                    node = {
                        id = def.id, name = def.name, slot = def.slot,
                        weight = (def.weight or 1) * 1.45, min_day = def.min_day,
                    }
                end
                table.insert(out, node)
            end
        end
        return out
    end

    -- 函数说明：从能力池中按权重随机抽取一个未使用的能力
    local function PickAbilityOnce(pool, used)
        local total = 0
        for _, v in ipairs(pool) do
            if not used[v.id] then
                total = total + (v.weight or 1)
            end
        end
        if total <= 0 then
            return nil
        end
        local roll = math.random() * total
        for _, v in ipairs(pool) do
            if not used[v.id] then
                roll = roll - (v.weight or 1)
                if roll <= 0 then
                    return v
                end
            end
        end
        return nil
    end

    -- 函数说明：根据天数获取进度阶段（1-4）
    local function GetProgressTier(day)
        if day >= 90 then return 4 end
        if day >= 60 then return 3 end
        if day >= 30 then return 2 end
        return 1
    end

    -- 函数说明：应用保底机制调整品质权重
    local function ApplyRarityPity(common, rare, epic, legendary, pity_key)
        local rules = deps.DROP_PITY_RULES and deps.DROP_PITY_RULES[pity_key] or nil
        if not rules then
            return common, rare, epic, legendary
        end
        local stacks = state.gear_quality_pity[pity_key] or 0
        if stacks <= (rules.start_after or 99) then
            return common, rare, epic, legendary
        end
        local active = math.min((rules.max_stacks or stacks), stacks) - (rules.start_after or 0)
        if active <= 0 then
            return common, rare, epic, legendary
        end
        local add_rare = (rules.per_stack_rare or 0) * active
        local add_epic = (rules.per_stack_epic or 0) * active
        local add_legendary = (rules.per_stack_legendary or 0) * active
        local common_cut = add_rare + add_epic + add_legendary
        common = math.max(0, common - common_cut * 100)
        rare = rare + add_rare * 100
        epic = epic + add_epic * 100
        legendary = legendary + add_legendary * 100
        return common, rare, epic, legendary
    end

    -- 函数说明：根据天数和上下文随机决定品质
    local function PickRarity(day, ctx)
        ctx = ctx or {}
        local tier = GetProgressTier(day)
        local w = {
            [1] = { common = 62, rare = 30, epic = 8, legendary = 0 },
            [2] = { common = 42, rare = 36, epic = 18, legendary = 4 },
            [3] = { common = 26, rare = 38, epic = 24, legendary = 12 },
            [4] = { common = 14, rare = 34, epic = 32, legendary = 20 },
        }
        local row = w[tier] or w[2]
        local common = row.common
        local rare = row.rare
        local epic = row.epic
        local legendary = row.legendary
        if ctx.is_trial then
            common = math.max(5, common - 10)
            rare = rare + 3
            epic = epic + 5
            legendary = legendary + 2
        end
        if ctx.is_special then
            common = math.max(0, common - 18)
            rare = math.max(0, rare - 4)
            epic = epic + 10
            legendary = legendary + 12
        end
        local rotation = GetSeasonRotation(day)
        if rotation and rotation.rarity_bonus then
            rare = rare + (rotation.rarity_bonus.rare or 0) * 100
            epic = epic + (rotation.rarity_bonus.epic or 0) * 100
            legendary = legendary + (rotation.rarity_bonus.legendary or 0) * 100
            common = math.max(0, common - ((rotation.rarity_bonus.rare or 0) + (rotation.rarity_bonus.epic or 0) + (rotation.rarity_bonus.legendary or 0)) * 100)
        end
        if ctx.objective_bonus and ctx.objective_bonus > 0 then
            rare = rare + ctx.objective_bonus
            epic = epic + ctx.objective_bonus * 0.75
            legendary = legendary + ctx.objective_bonus * 0.45
            common = math.max(0, common - ctx.objective_bonus * 2.2)
        end
        common, rare, epic, legendary = ApplyRarityPity(common, rare, epic, legendary, ctx.pity_key)
        local total = common + rare + epic + legendary
        if total <= 0 then
            return "common"
        end
        local roll = math.random() * total
        if roll <= common then return "common" end
        roll = roll - common
        if roll <= rare then return "rare" end
        roll = roll - rare
        if roll <= epic then return "epic" end
        return "legendary"
    end

    -- 函数说明：提交保底计数器，高品质重置，低品质累加
    local function CommitRarityPity(pity_key, rarity_key, killer)
        if not pity_key then return end
        state.gear_quality_pity[pity_key] = state.gear_quality_pity[pity_key] or 0
        local rules = deps.DROP_PITY_RULES and deps.DROP_PITY_RULES[pity_key] or nil
        local reset_on_epic = rules and rules.reset_on_epic
        if rarity_key == "legendary" or (reset_on_epic and rarity_key == "epic") then
            state.gear_quality_pity[pity_key] = 0
        else
            state.gear_quality_pity[pity_key] = math.min((rules and rules.max_stacks) or 9, state.gear_quality_pity[pity_key] + 1)
        end
        if killer and deps.IsValidPlayer and deps.IsValidPlayer(killer) and deps.EnsurePlayerData then
            local data = deps.EnsurePlayerData(killer)
            data.loot_pity_stack = state.gear_quality_pity[pity_key] or 0
            if deps.SyncGrowthNetvars then
                deps.SyncGrowthNetvars(killer, data)
            end
        end
    end

    -- 函数说明：记录玩家的构筑统计数据
    local function RecordBuildStats(killer, meta, abilities)
        if not killer or not deps.IsValidPlayer or not deps.IsValidPlayer(killer) or not deps.EnsurePlayerData then
            return
        end
        local data = deps.EnsurePlayerData(killer)
        data.build_affix_counts = data.build_affix_counts or {}
        data.build_rarity_counts = data.build_rarity_counts or { common = 0, rare = 0, epic = 0, legendary = 0 }
        if meta and meta.rarity then
            data.build_rarity_counts[meta.rarity] = (data.build_rarity_counts[meta.rarity] or 0) + 1
        end
        for _, ab in ipairs(abilities or {}) do
            data.build_affix_counts[ab] = (data.build_affix_counts[ab] or 0) + 1
        end
        local score =
            (data.build_rarity_counts.common or 0) * 1 +
            (data.build_rarity_counts.rare or 0) * 3 +
            (data.build_rarity_counts.epic or 0) * 6 +
            (data.build_rarity_counts.legendary or 0) * 10
        data.build_score = score
        if deps.SyncGrowthNetvars then
            deps.SyncGrowthNetvars(killer, data)
        end
    end

    -- 函数说明：为物品随机抽取能力并生成元数据
    function state.RollAbilitiesForItem(item, day, ctx, ability_defs)
        if not item or not item:IsValid() then return nil, nil end
        local rarity_key = PickRarity(day, ctx)
        local rarity = RARITY_DEFS[rarity_key] or RARITY_DEFS.common
        local pool = BuildAbilityPool(item, day, ability_defs)
        if #pool == 0 then return nil, nil end
        local count = math.random(rarity.min_affix, rarity.max_affix)
        local used = {}
        local abilities = {}
        local names = {}
        for _ = 1, count do
            local picked = PickAbilityOnce(pool, used)
            if not picked then break end
            used[picked.id] = true
            table.insert(abilities, picked.id)
            table.insert(names, picked.name)
        end

        local signature = ctx and ctx.boss_signature or nil
        if signature and signature.bonus_affix then
            for k, _ in pairs(signature.bonus_affix) do
                if not used[k] then
                    local is_valid = false
                    for _, d in ipairs(ability_defs) do
                        if d.id == k and IsAbilitySlotMatch(item, d.slot) then
                            is_valid = true
                            table.insert(names, d.name)
                            break
                        end
                    end
                    if is_valid then
                        table.insert(abilities, k)
                        used[k] = true
                    end
                end
            end
        end

        if #abilities == 0 then
            return nil, nil
        end
        local meta = {
            rarity = rarity_key,
            rarity_name = rarity.rarity_name,
            affix_names = table.concat(names, "、"),
            season_rotation = (GetSeasonRotation(day) and GetSeasonRotation(day).id) or nil,
        }
        CommitRarityPity(ctx and ctx.pity_key or nil, rarity_key, ctx and ctx.killer or nil)
        RecordBuildStats(ctx and ctx.killer or nil, meta, abilities)
        return abilities, meta
    end

    -- 函数说明：获取品质定义表
    function state.GetRarityDefs()
        return RARITY_DEFS
    end

    -- 函数说明：获取进度阶段
    function state.GetProgressTier(day)
        return GetProgressTier(day)
    end

    -- 函数说明：检查物品是否匹配能力槽位
    function state.IsAbilitySlotMatch(item, slot)
        return IsAbilitySlotMatch(item, slot)
    end

    -- 函数说明：获取赛季轮换配置
    function state.GetSeasonRotation(day)
        return GetSeasonRotation(day)
    end

    -- 函数说明：导出保底状态
    function state.ExportState()
        local out = {}
        for k, v in pairs(state.gear_quality_pity) do
            local n = tonumber(v)
            if n ~= nil then
                out[k] = n
            end
        end
        return { gear_quality_pity = out }
    end

    -- 函数说明：导入保底状态
    function state.ImportState(saved)
        if type(saved) ~= "table" then return end
        if type(saved.gear_quality_pity) == "table" then
            for k, v in pairs(saved.gear_quality_pity) do
                local n = tonumber(v)
                if n ~= nil then
                    state.gear_quality_pity[k] = n
                end
            end
        end
    end

    return state
end

return M
