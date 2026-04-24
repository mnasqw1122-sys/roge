--[[
    文件说明：boss_drop_system.lua
    功能：Boss掉落系统。
    负责Boss专属掉落选择、签名匹配、目标加成计算以及Boss装备掉落生成。
    从 drop_system.lua 拆分而来。
]]
local M = {}

-- 函数说明：创建Boss掉落系统实例
function M.Create(deps)
    local state = {}
    state.boss_loot_pity = {}

    -- 函数说明：将列表转换为集合
    local function BuildSet(list)
        local set = {}
        for _, v in ipairs(list or {}) do
            set[v] = true
        end
        return set
    end

    -- 函数说明：获取Boss的签名配置（决定掉落偏好和额外词缀）
    local function GetBossSignature(victim)
        local defs = deps.BOSS_LOOT_SIGNATURE_DEFS
        if not defs then return nil end
        local key = (victim and victim.rogue_boss_loot_key) or (victim and victim.prefab) or "default"
        return defs[key] or defs.default
    end

    -- 函数说明：获取击杀者的赛季目标加成数据
    local function GetObjectiveBoost(killer)
        if not killer or not deps.EnsurePlayerData then
            return { done = 0, grade = 0, gear_weight_mult = 1, rarity_bonus = 0 }
        end
        local data = deps.EnsurePlayerData(killer)
        local done = math.max(0, math.min(4, data.season_objective_done or 0))
        local grade = math.max(0, math.min(3, data.season_objective_grade or 0))
        local gear_weight_mult = 1 + done * 0.05 + grade * 0.03
        local rarity_bonus = done * 0.8 + grade * 1.2
        return {
            done = done,
            grade = grade,
            gear_weight_mult = gear_weight_mult,
            rarity_bonus = rarity_bonus,
        }
    end

    -- 函数说明：根据Boss签名偏好从装备池中加权选择装备
    local function PickBossGearBySignature(pool, victim, objective_boost)
        if not pool or #pool == 0 then return nil end
        local signature = GetBossSignature(victim)
        local sig_tags = BuildSet(signature and signature.tags or nil)
        local boost_mult = (objective_boost and objective_boost.gear_weight_mult) or 1
        local total = 0
        local weighted = {}
        for _, it in ipairs(pool) do
            local w = it.weight or 1
            if next(sig_tags) ~= nil then
                local match = 0
                for _, t in ipairs(it.tags or {}) do
                    if sig_tags[t] then
                        match = match + 1
                    end
                end
                if match > 0 then
                    w = w * (1 + 0.28 * match)
                end
            end
            w = w * boost_mult
            total = total + w
            weighted[#weighted + 1] = { item = it, w = w }
        end
        if total <= 0 then return pool[math.random(#pool)] end
        local roll = math.random() * total
        for _, node in ipairs(weighted) do
            roll = roll - node.w
            if roll <= 0 then
                return node.item
            end
        end
        return weighted[#weighted].item
    end

    -- 函数说明：尝试从Boss专属掉落池中抽取装备（含保底）
    local function PickBossSpecificGear(victim, day)
        if not deps.BossLoot then return nil, false, nil end
        local raw_key = (victim and victim.rogue_boss_loot_key) or (victim and victim.prefab) or nil
        local pool, key = deps.BossLoot.GetPool(raw_key)
        if not pool or #pool == 0 then return nil, false, nil end
        local pity = state.boss_loot_pity[key] or 0
        local chance = math.min(0.95, 0.65 + pity * 0.1)
        if math.random() <= chance then
            local total = 0
            for _, v in ipairs(pool) do
                total = total + (v.weight or 1)
            end
            local picked = deps.PickWeightedCandidate(pool, total)
            if picked then
                state.boss_loot_pity[key] = 0
                return picked.prefab, true, key
            end
        end
        state.boss_loot_pity[key] = math.min(6, pity + 1)
        return nil, false, key
    end

    -- 函数说明：生成Boss装备掉落（含附魔）
    function state.SpawnBossGearDrop(victim, prefab, day, ctx, spawn_fn, apply_fn, roll_fn)
        local item = spawn_fn(victim, prefab, nil)
        if not item then return false, nil end
        local abilities, meta = roll_fn(item, day, ctx)
        if abilities then
            apply_fn(item, abilities, meta, true)
        end
        return true, meta
    end

    -- 函数说明：获取Boss签名配置
    function state.GetBossSignature(victim)
        return GetBossSignature(victim)
    end

    -- 函数说明：获取目标加成数据
    function state.GetObjectiveBoost(killer)
        return GetObjectiveBoost(killer)
    end

    -- 函数说明：根据签名偏好选择装备
    function state.PickBossGearBySignature(pool, victim, objective_boost)
        return PickBossGearBySignature(pool, victim, objective_boost)
    end

    -- 函数说明：尝试选择Boss专属掉落
    function state.PickBossSpecificGear(victim, day)
        return PickBossSpecificGear(victim, day)
    end

    -- 函数说明：导出Boss掉落保底状态
    function state.ExportState()
        local out = {}
        for k, v in pairs(state.boss_loot_pity) do
            local n = tonumber(v)
            if n ~= nil then
                out[k] = n
            end
        end
        return { boss_loot_pity = out }
    end

    -- 函数说明：导入Boss掉落保底状态
    function state.ImportState(saved)
        if type(saved) ~= "table" then return end
        if type(saved.boss_loot_pity) == "table" then
            for k, v in pairs(saved.boss_loot_pity) do
                local n = tonumber(v)
                if n ~= nil then
                    state.boss_loot_pity[k] = n
                end
            end
        end
    end

    return state
end

return M
