--[[
    文件说明：bootstrap/module_loader.lua
    功能：子系统加载与依赖解析模块。
    从runtime_system.lua中独立，负责按主题分类加载所有子系统模块。
    支持依赖注入和模块间依赖顺序管理。
]]
local M = {}

local MODULE_MAP = {
    world         = { "server_creation", "worldgen" },
    player        = { "state_schema", "player_state", "talent_supply" },
    combat        = { "combo_system", "coop_system" },
    loot          = { "drop_system", "rarity_system", "relic_system",
                      "boss_drop_system", "boss_loot", "set_bonus" },
    season        = { "season_system", "season_result", "progression_system",
                      "achievement_system", "milestone_system" },
    world_events  = { "wave_system", "event_system", "chain_event" },
    affix         = { "affix_system", "affix_arena_forge",
                      "affix_environment", "affix_summoner_legion" },
    economy       = { "shop_system", "shop_config" },
    rpc           = { "rpc_registry" },
    ai            = { "rogue_ai_perception" },
    host          = { "wave_boss_compat" },
    boss          = { "boss_mechanics" },
}

-- 模块加载路径前缀
local MODULE_PREFIX = "rogue/"

-- 加载单个模块并执行Create(deps)
local function LoadModule(module_name, deps, namespace)
    local path = MODULE_PREFIX .. module_name
    local ok, mod = pcall(require, path)
    if not ok then
        print("[ModuleLoader] Failed to load module: " .. tostring(module_name) .. " (" .. tostring(path) .. ")")
        return nil
    end
    if type(mod.Create) ~= "function" then
        print("[ModuleLoader] Module " .. tostring(module_name) .. " has no Create() factory")
        return nil
    end
    local instance = mod.Create(deps)
    if instance then
        if namespace then
            deps[namespace] = instance
            deps["_all_modules"] = deps["_all_modules"] or {}
            deps["_all_modules"][namespace] = instance
        end
    end
    return instance
end

-- 加载某一类别的所有模块
function M.LoadCategory(category_name, deps)
    local names = MODULE_MAP[category_name]
    if not names then
        print("[ModuleLoader] Unknown category: " .. tostring(category_name))
        return {}
    end
    local results = {}
    for _, module_name in ipairs(names) do
        local inst = LoadModule(module_name, deps, module_name)
        if inst then
            results[module_name] = inst
        end
    end
    return results
end

-- 按顺序加载所有类别
function M.LoadAll(deps)
    local category_order = {
        "world", "player", "combat", "loot", "season",
        "world_events", "affix", "economy", "rpc", "ai", "host", "boss",
    }
    local loaded = {}
    for _, category in ipairs(category_order) do
        local results = M.LoadCategory(category, deps)
        for k, v in pairs(results) do
            loaded[k] = v
        end
    end
    return loaded
end

-- 获取模块主题分类表
function M.GetModuleMap()
    return MODULE_MAP
end

return M
