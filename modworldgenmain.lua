--[[
    文件说明：modworldgenmain.lua
    功能：控制世界生成逻辑。
    定义了肉鸽模式下标准、海难、哈姆雷特对应的自定义地形节点（Room）、任务（Task）、任务集（TaskSet）与最终世界预设（Level）。
    为了避免哈姆雷特中跳过城市生成导致的卡死，进行了必要的底层函数注入与保护（InstallHamletCityBuilderGuard等）。
]]
GLOBAL.setmetatable(env, {__index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end})

local STRINGS = GLOBAL.STRINGS
local LEVELTYPE = GLOBAL.LEVELTYPE
local HAMLET_CITY_GUARD_INSTALLED = false
local HAMLET_FOREST_GUARD_INSTALLED = false

-- 函数说明：按优先级选择可用地皮，兼容标准世界与海难扩展地皮。
local function PickGroundTile(...)
    for _, tile_name in ipairs({...}) do
        if GLOBAL.GROUND and GLOBAL.GROUND[tile_name] ~= nil then
            return GLOBAL.GROUND[tile_name]
        end
    end
    return GLOBAL.GROUND.DIRT
end

-- 函数说明：按优先级选择可用世界地皮，优先用于哈姆雷特云海边缘等 WORLD_TILES 类型地皮。
local function PickWorldTile(...)
    for _, tile_name in ipairs({...}) do
        if GLOBAL.WORLD_TILES and GLOBAL.WORLD_TILES[tile_name] ~= nil then
            return GLOBAL.WORLD_TILES[tile_name]
        end
    end
    return nil
end

-- 函数说明：判断海难海域地皮是否属于近岸浅滩，用于过滤水域内容生成范围。
local function IsShoreTile(tile)
    return tile == GLOBAL.WORLD_TILES.OCEAN_SHALLOW_SHORE or tile == GLOBAL.WORLD_TILES.MANGROVE_SHORE
end

-- 函数说明：构建 City_Foundation 全局标签节点集合，便于快速校验城市基础节点是否有效。
local function BuildCityFoundationNodeSet(global_tags)
    local set = {}
    if type(global_tags) ~= "table" then
        return set
    end
    local foundation = global_tags.City_Foundation
    if type(foundation) ~= "table" then
        return set
    end
    for _, node_list in pairs(foundation) do
        if type(node_list) == "table" then
            for _, node_id in ipairs(node_list) do
                set[node_id] = true
            end
        end
    end
    return set
end

-- 函数说明：检测哈姆雷特地形中是否存在可用于城市生成的有效节点，避免空节点触发随机区间崩溃。
local function HasValidHamletCityNodes(topology_save)
    if type(topology_save) ~= "table" or type(topology_save.root) ~= "table" then
        return false
    end
    local get_nodes = topology_save.root.GetNodes
    if type(get_nodes) ~= "function" then
        return false
    end
    local nodes = get_nodes(topology_save.root, true)
    if type(nodes) ~= "table" then
        return false
    end
    local foundation_set = BuildCityFoundationNodeSet(topology_save.GlobalTags)
    local city_counts = { [1] = 0, [2] = 0 }
    for _, node in pairs(nodes) do
        local node_id = node and node.id
        local tags = node and node.data and node.data.tags
        if node_id and foundation_set[node_id] and type(tags) == "table" then
            if table.contains(tags, "City1") then
                city_counts[1] = city_counts[1] + 1
            end
            if table.contains(tags, "City2") then
                city_counts[2] = city_counts[2] + 1
            end
        end
    end
    return city_counts[1] > 0 and city_counts[2] > 0
end

-- 函数说明：判断当前拓扑是否为肉鸽哈姆雷特单岛任务，命中时应跳过猪人城市生成避免卡死。
local function IsRogueHamletTopology(topology_save)
    if type(topology_save) ~= "table" or type(topology_save.root) ~= "table" then
        return false
    end
    local get_nodes = topology_save.root.GetNodes
    if type(get_nodes) ~= "function" then
        return false
    end
    local nodes = get_nodes(topology_save.root, true)
    if type(nodes) ~= "table" then
        return false
    end
    for _, node in pairs(nodes) do
        local raw_id = tostring((node and node.id) or "")
        local raw_name = tostring((node and node.name) or "")
        local raw_task = tostring((node and node.data and node.data.task) or "")
        if string.find(raw_id, "rogue_hamlet_task", 1, true)
            or string.find(raw_name, "rogue_hamlet_task", 1, true)
            or string.find(raw_task, "rogue_hamlet_task", 1, true) then
            return true
        end
    end
    return false
end

-- 函数说明：根据世界生成参数判断是否为肉鸽哈姆雷特单岛预设。
local function IsRogueHamletGenParams(setcurrent_gen_params)
    if type(setcurrent_gen_params) ~= "table" then
        return false
    end
    return setcurrent_gen_params.task_set == "rogue_hamlet_task_set"
        or setcurrent_gen_params.start_location == "rogue_hamlet_task"
end

-- 函数说明：为哈姆雷特城市生成器安装安全保护，在缺少有效城市节点时跳过城市建造流程。
local function InstallHamletCityBuilderGuard()
    if HAMLET_CITY_GUARD_INSTALLED then
        return
    end
    local ok_city, raw_make_cities = pcall(require, "map/city_builder")
    if not ok_city or type(raw_make_cities) ~= "function" then
        return
    end
    local function SafeMakeCities(entities, topology_save, worldsim, width, height, setcurrent_gen_params)
        if IsRogueHamletTopology(topology_save) or IsRogueHamletGenParams(setcurrent_gen_params) then
            return entities
        end
        if not HasValidHamletCityNodes(topology_save) then
            return entities
        end
        return raw_make_cities(entities, topology_save, worldsim, width, height, setcurrent_gen_params)
    end
    package.loaded["map/city_builder"] = SafeMakeCities

    local ok_build, build_porkland = pcall(require, "map/build_porkland")
    if not ok_build or type(build_porkland) ~= "function" then
        return
    end
    local debuglib = GLOBAL.debug or debug
    if type(debuglib) ~= "table" or type(debuglib.getupvalue) ~= "function" or type(debuglib.setupvalue) ~= "function" then
        return
    end
    for i = 1, 30 do
        local name = debuglib.getupvalue(build_porkland, i)
        if not name then
            break
        end
        if name == "make_cities" then
            debuglib.setupvalue(build_porkland, i, SafeMakeCities)
            break
        end
    end
    HAMLET_CITY_GUARD_INSTALLED = true
end

-- 函数说明：补丁哈姆雷特 forest_map 的 build_porkland 上值，肉鸽哈姆雷特预设时跳过高风险后处理，避免卡死。
local function InstallHamletForestMapGuard()
    if HAMLET_FOREST_GUARD_INSTALLED then
        return
    end
    local ok_forest_map, forest_map = pcall(require, "map/forest_map")
    if not ok_forest_map or type(forest_map) ~= "table" or type(forest_map.Generate) ~= "function" then
        return
    end
    local debuglib = GLOBAL.debug or debug
    if type(debuglib) ~= "table" or type(debuglib.getupvalue) ~= "function" or type(debuglib.setupvalue) ~= "function" then
        return
    end
    local generate_fn = forest_map.Generate
    for i = 1, 60 do
        local name, upv = debuglib.getupvalue(generate_fn, i)
        if not name then
            break
        end
        if name == "build_porkland" and type(upv) == "function" then
            local raw_build_porkland = upv
            local function SafeBuildPorkland(entities, topology_save, map_width, map_height, current_gen_params)
                if IsRogueHamletTopology(topology_save) or IsRogueHamletGenParams(current_gen_params) then
                    return entities
                end
                return raw_build_porkland(entities, topology_save, map_width, map_height, current_gen_params)
            end
            debuglib.setupvalue(generate_fn, i, SafeBuildPorkland)
            HAMLET_FOREST_GUARD_INSTALLED = true
            break
        end
    end
end

InstallHamletCityBuilderGuard()
InstallHamletForestMapGuard()
AddLevelPreInitAny(function()
    InstallHamletCityBuilderGuard()
    InstallHamletForestMapGuard()
end)

-- 1. 定义一个没有任何资源的标准空房间
AddRoom("rogue_empty_room", {
    colour = {r=0.3,g=0.2,b=0.1,a=0.3},
    value = GLOBAL.GROUND.DIRT,
    contents =  {
        countprefabs = {},
        distributepercent = 0,
        distributeprefabs = {},
    }
})

-- 2. 定义使用该房间的任务
AddTask("rogue_task", {
    locks = {},
    keys_given = {},
    room_choices = {
        ["rogue_empty_room"] = 4, 
    },
    room_bg = GLOBAL.GROUND.DIRT,
    background_room = "rogue_empty_room",
    colour = {r=1,g=1,b=0,a=1},
})

-- 3. 定义标准任务集
AddTaskSet("rogue_task_set", {
    name = "肉鸽任务集",
    location = "forest",
    tasks = {
        "rogue_task",
    },
    numoptionaltasks = 0,
    optionaltasks = {},
    valid_start_tasks = {"rogue_task"},
    set_pieces = {}, -- 彩蛋/置景现在必须放在这里
    required_prefabs = {"multiplayer_portal"},
})

-- 4. 定义海难版单岛房间与任务
AddRoom("rogue_sw_island_room", {
    colour = {r=0.2,g=0.45,b=0.65,a=0.35},
    value = PickGroundTile("BEACH", "JUNGLE", "SWAMP", "DIRT"),
    tags = {"ExitPiece"},
    contents =  {
        countprefabs = {
            spawnpoint_multiplayer = 1,
        },
        distributepercent = 0,
        distributeprefabs = {},
    }
})

AddTask("rogue_sw_task", {
    locks = {},
    keys_given = {},
    room_choices = {
        ["rogue_sw_island_room"] = 4,
    },
    room_bg = PickGroundTile("BEACH", "JUNGLE", "SWAMP", "DIRT"),
    background_room = "rogue_sw_island_room",
    colour = {r=0.4,g=0.8,b=1,a=1},
})

AddTaskSet("rogue_sw_task_set", {
    name = "肉鸽海难任务集",
    location = "shipwrecked",
    tasks = {
        "rogue_sw_task",
    },
    numoptionaltasks = 0,
    optionaltasks = {},
    valid_start_tasks = {"rogue_sw_task"},
    water_content = {
        ["WaterAll"] = {checkFn = function(ground) return GLOBAL.IsOceanTile(ground) and not IsShoreTile(ground) end},
        ["WaterShallow"] = {checkFn = function(ground) return ground == GLOBAL.WORLD_TILES.OCEAN_SHALLOW end},
        ["WaterMedium"] = {checkFn = function(ground) return ground == GLOBAL.WORLD_TILES.OCEAN_MEDIUM end},
        ["WaterDeep"] = {checkFn = function(ground) return ground == GLOBAL.WORLD_TILES.OCEAN_DEEP end},
        ["WaterCoral"] = {checkFn = function(ground) return ground == GLOBAL.WORLD_TILES.OCEAN_CORAL end},
        ["WaterShipGraveyard"] = {checkFn = function(ground) return ground == GLOBAL.WORLD_TILES.OCEAN_SHIPGRAVEYARD end},
    },
    water_prefill_setpieces = {},
    set_pieces = {},
    required_prefabs = {"multiplayer_portal"},
})

local HAMLET_LAND_TILE = PickGroundTile("RAINFOREST", "PLAINS", "FIELDS", "DEEPRAINFOREST", "DIRT")
local HAMLET_VOID_TILE = PickWorldTile("IMPASSABLE") or HAMLET_LAND_TILE

AddRoom("rogue_hamlet_void_room", {
    colour = {r=0.75,g=0.75,b=0.8,a=0.3},
    value = HAMLET_VOID_TILE,
    contents = {
        countprefabs = {},
        distributepercent = 0,
        distributeprefabs = {},
    }
})

AddRoom("rogue_hamlet_island_room", {
    colour = {r=0.2,g=0.5,b=0.2,a=0.35},
    value = HAMLET_LAND_TILE,
    tags = {"ExitPiece", "City1", "City2", "City_Foundation", "Cultivated"},
    contents = {
        countprefabs = {
            spawnpoint_multiplayer = 1,
        },
        distributepercent = 0,
        distributeprefabs = {},
    }
})

AddTask("rogue_hamlet_task", {
    locks = {},
    keys_given = {},
    room_tags = {"City1", "City2"},
    room_choices = {
        ["rogue_hamlet_island_room"] = 4,
    },
    room_bg = HAMLET_VOID_TILE,
    background_room = "rogue_hamlet_void_room",
    colour = {r=0.85,g=0.8,b=0.25,a=1},
})

AddTaskSet("rogue_hamlet_task_set", {
    name = "肉鸽哈姆雷特任务集",
    location = "porkland",
    tasks = {
        "rogue_hamlet_task",
    },
    numoptionaltasks = 0,
    optionaltasks = {},
    valid_start_tasks = {"rogue_hamlet_task"},
    set_pieces = {},
    required_prefabs = {"multiplayer_portal"},
})


-- 定义海难出生点
AddStartLocation("rogue_sw_task", {
    name = "肉鸽海难出生点",
    location = "shipwrecked",
    start_setpiece = "DefaultShipwreckedStart",
    start_setpeice = "DefaultShipwreckedStart",
    start_node = "rogue_sw_island_room",
})

AddStartLocation("rogue_hamlet_task", {
    name = "肉鸽哈姆雷特出生点",
    location = "porkland",
    start_setpiece = "PorkLandStart",
    start_setpeice = "PorkLandStart",
    start_node = "rogue_hamlet_island_room",
})

-- 5. 使用 AddLevel API 定义标准关卡（预设）
AddLevel(LEVELTYPE.SURVIVAL, {
    id = "ROGUE_SURVIVAL",
    name = "肉鸽模式",
    desc = "一个资源匮乏的小岛，迎接肉鸽挑战。",
    location = "forest", -- 位置现在是强制性的
    overrides = {
        task_set = "rogue_task_set", -- 指向我们的任务集
        world_size = "small", -- 回退到原始世界大小
        keep_disconnected_tiles = false,
        no_wormholes_to_disconnected_tiles = true,
        no_joining_islands = true,
        has_ocean = true,
        roads = "never",
        -- 移除所有随机生成的彩蛋/置景
        boons = "never", -- 尸骨/战利品
        touchstone = "never", -- 复活石
        traps = "never", -- 陷阱
        poi = "never", -- 兴趣点
        protected = "never", -- 保护资源
    },
    numrandom_set_pieces = 0, -- 确保没有随机置景
    random_set_pieces = {},
})

-- 6. 使用 AddLevel API 定义海难版关卡（预设）
AddLevel(LEVELTYPE.SURVIVAL, {
    id = "ROGUE_SHIPWRECKED_SURVIVAL",
    name = "肉鸽模式-海难版",
    desc = "一个资源匮乏的海难小岛，迎接海难肉鸽挑战。",
    location = "shipwrecked",
    overrides = {
        location = "shipwrecked",
        task_set = "rogue_sw_task_set",
        start_location = "rogue_sw_task",
        world_size = "small",
        keep_disconnected_tiles = false,
        no_wormholes_to_disconnected_tiles = true,
        no_joining_islands = true,
        has_ocean = true,
        roads = "never",
        boons = "never",
        touchstone = "never",
        traps = "never",
        poi = "never",
        protected = "never",
    },
    background_node_range = {0, 0},
    numrandom_set_pieces = 0,
    random_set_pieces = {},
})

AddLevel(LEVELTYPE.SURVIVAL, {
    id = "ROGUE_HAMLET_SURVIVAL",
    name = "肉鸽模式-哈姆雷特版",
    desc = "在哈姆雷特风格的单岛上迎接肉鸽挑战。",
    location = "porkland",
    overrides = {
        location = "porkland",
        task_set = "rogue_hamlet_task_set",
        start_location = "rogue_hamlet_task",
        world_size = "small",
        keep_disconnected_tiles = false,
        no_wormholes_to_disconnected_tiles = true,
        no_joining_islands = true,
        has_ocean = false,
        roads = "never",
        boons = "never",
        touchstone = "never",
        traps = "never",
        poi = "never",
        protected = "never",
        pl_clocktype = "plateau",
    },
    background_node_range = {0, 0},
    numrandom_set_pieces = 0,
    random_set_pieces = {},
})
