--[[
    文件说明：modmain.lua
    功能：肉鸽模式的主入口文件。
    负责初始化所有肉鸽子系统（状态、掉落、波次、养成、遗物、赛季等），注册相关RPC，监听并干预游戏生命周期事件（如建服、世界阶段改变、实体生成）。
]]
GLOBAL.setmetatable(env, {__index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end})

local require = GLOBAL.require
local SpawnPrefab = GLOBAL.SpawnPrefab
local Vector3 = GLOBAL.Vector3
local PI = GLOBAL.PI
local TheNet = GLOBAL.TheNet
local FindWalkableOffset = GLOBAL.FindWalkableOffset
local AllPlayers = GLOBAL.AllPlayers
local IsServer = GLOBAL.TheNet:GetIsServer()
local RogueConfig = require("rogue/config")
local RogueHelpers = require("rogue/helpers")
local RoguePlayerState = require("rogue/player_state")
local RogueDropSystem = require("rogue/drop_system")
local RogueWaveSystem = require("rogue/wave_system")
local RogueTalentSupply = require("rogue/talent_supply")
local RogueEventSystem = require("rogue/event_system")
local RogueProgressionSystem = require("rogue/progression_system")
local RogueAffixSystem = require("rogue/affix_system")
local RogueRuntimeSystem = require("rogue/runtime_system")
local RogueBossMechanics = require("rogue/boss_mechanics")
local RogueBossLoot = require("rogue/boss_loot")
local RogueRelicSystem = require("rogue/relic_system")
local RogueSeasonSystem = require("rogue/season_system")
local RogueSeasonResult = require("rogue/season_result")
local RogueStateSchema = require("rogue/state_schema")
local RogueShopSystem = require("rogue/shop_system")
local Config = RogueConfig.LoadConfig(function(key)
    return GetModConfigData(key)
end)
local CONST = RogueConfig.CONST
local VALID_WORLD_VARIANTS = {
    standard = true,
    shipwrecked = true,
    hamlet = true,
}
Config.WORLD_VARIANT = VALID_WORLD_VARIANTS[Config.WORLD_VARIANT] and Config.WORLD_VARIANT or "standard"

local wave_state = nil

-- [UI 挂载] --------------------------------------------------------------------
AddClassPostConstruct("widgets/controls", function(self)
    if self.owner then
        local RogueStatusDisplay = require("widgets/rogue_status_display")
        self.rogue_status = self:AddChild(RogueStatusDisplay(self.owner))
        -- 确保 UI 位于顶层，避免被其他 UI 遮挡
        self.rogue_status:MoveToFront()
        -- 设置对齐和位置，放到右上角避免与左侧制作栏重叠
        self.rogue_status:SetHAnchor(GLOBAL.ANCHOR_RIGHT)
        self.rogue_status:SetVAnchor(GLOBAL.ANCHOR_TOP)
        self.rogue_status:SetPosition(-320, -160, 0)

        local RogueShopPanel = require("widgets/rogue_shop_panel")
        self.rogue_shop = self:AddChild(RogueShopPanel(self.owner))
        self.rogue_shop:Hide()
        
        -- 给 status UI 传递 shop panel 的引用，方便开关
        self.rogue_status.shop_panel = self.rogue_shop
    end
end)

-- [网络变量注册] --------------------------------------------------------------------
AddPlayerPostInit(function(inst)
    RogueStateSchema.RegisterNetvars(inst, GLOBAL)
end)

-- 处理玩家选择天赋的 RPC 请求
AddModRPCHandler("rogue_mode", "pick_talent", function(player, slot)
    if GLOBAL._rogue_mode_pick_talent_rpc then
        GLOBAL._rogue_mode_pick_talent_rpc(player, slot)
    end
end)

-- 处理玩家选择补给的 RPC 请求
AddModRPCHandler("rogue_mode", "pick_supply", function(player, slot)
    if GLOBAL._rogue_mode_pick_supply_rpc then
        GLOBAL._rogue_mode_pick_supply_rpc(player, slot)
    end
end)

-- 处理玩家选择遗物的 RPC 请求
AddModRPCHandler("rogue_mode", "pick_relic", function(player, slot)
    if GLOBAL._rogue_mode_pick_relic_rpc then
        GLOBAL._rogue_mode_pick_relic_rpc(player, slot)
    end
end)

AddModRPCHandler("rogue_mode", "pick_route", function(player, slot)
    if GLOBAL._rogue_mode_pick_route_rpc then
        GLOBAL._rogue_mode_pick_route_rpc(player, slot)
    end
end)

-- 处理玩家购买商店物品的 RPC 请求
AddModRPCHandler("rogue_mode", "buy_shop_item", function(player, item_id)
    if GLOBAL._rogue_mode_buy_shop_item_rpc then
        GLOBAL._rogue_mode_buy_shop_item_rpc(player, item_id)
    end
end)

-- 处理玩家回收物品的 RPC 请求
AddModRPCHandler("rogue_mode", "recycle_item", function(player, prefab)
    if GLOBAL._rogue_mode_recycle_item_rpc then
        GLOBAL._rogue_mode_recycle_item_rpc(player, prefab)
    end
end)

if RemapSoundEvent then
    RemapSoundEvent("rifts4/rabbit_king/aggressive/spawn_pst", "dontstarve/common/dropGeneric")
    RemapSoundEvent("dontstarve/creatures/pengull/splash", "dontstarve/common/dropGeneric")
end

-- 加载池目录（客户端和服务器都需要加载，以保证网络变量注册一致）
local PoolCatalog = require("pool_catalog")
if PoolCatalog and PoolCatalog.SetWorldVariant then
    PoolCatalog.SetWorldVariant(Config.WORLD_VARIANT)
end

-- [网络变量同步修复] -----------------------------------------------------------
-- 由于 _rogue_affix_nettext 是通过 AddPrefabPostInitAny 动态添加的网络变量，
-- 必须保证客户端和服务器以完全相同的顺序和条件注册它，否则会导致所有后续网络变量错位！
-- 这会引起 modactioncomponents、inventoryitem 等组件状态完全错乱，导致崩溃和无法拾取。
local ROGUE_AFFIX_PREFAB_WHITELIST = {}
do
    local pool, _ = PoolCatalog.GetRuntimePool("DROPS_BOSS_GEAR", 999)
    for _, item in ipairs(pool or {}) do
        if item.prefab then
            ROGUE_AFFIX_PREFAB_WHITELIST[item.prefab] = true
            local alias = RogueConfig.PREFAB_RUNTIME_ALIASES[item.prefab]
            if alias then
                ROGUE_AFFIX_PREFAB_WHITELIST[alias] = true
            end
        end
    end
end

local function IsRogueAffixCandidatePrefab(prefab)
    return prefab ~= nil and ROGUE_AFFIX_PREFAB_WHITELIST[prefab] == true
end

AddPrefabPostInitAny(function(inst)
    -- 为带有词缀的装备添加网络同步和悬浮提示
    if IsRogueAffixCandidatePrefab(inst.prefab) then
        if not inst._rogue_affix_nettext then
            inst._rogue_affix_nettext = GLOBAL.net_string(inst.GUID, "rogue_affix_nettext", "roguedirty")
            
            if not GLOBAL.TheWorld.ismastersim then
                inst:ListenForEvent("roguedirty", function(i)
                    i.rogue_affix_text = i._rogue_affix_nettext:value()
                end)
            end

            -- 修改悬浮提示 (Hover Text)
            if not inst._rogue_displaynamefn_base_set then
                inst._rogue_displaynamefn_base_set = true
                local old_displaynamefn = inst.displaynamefn
                inst.displaynamefn = function(i)
                    local affix_text = i.rogue_affix_text or ""
                    local base_name = old_displaynamefn and old_displaynamefn(i) or nil
                    
                    if affix_text == "" then
                        return base_name
                    end
                    
                    if base_name == nil then
                        if i.replica and i.replica.named then
                            base_name = i.replica.named:GetName()
                        elseif i.components and i.components.named then
                            base_name = i.components.named:GetName()
                        else
                            base_name = i.name or (GLOBAL.STRINGS.NAMES[string.upper(i.prefab)] or "")
                        end
                    end
                    
                    return (base_name or "") .. affix_text
                end
            end
        end
    end
end)

if not IsServer then return end

local RogueShopConfig = require("rogue/shop_config")

if RogueShopConfig and RogueShopConfig.InitVariant then
    RogueShopConfig.InitVariant(Config.WORLD_VARIANT)
end
local BUFF_TYPES = RogueConfig.BUFF_TYPES
local TALENT_DEFS = RogueConfig.TALENT_DEFS
local DAILY_KIND_NAMES = RogueConfig.DAILY_KIND_NAMES
local WAVE_RULE_DEFS = RogueConfig.WAVE_RULE_DEFS
local REGION_ROUTE_DEFS = RogueConfig.REGION_ROUTE_DEFS
local SUPPLY_DEFS = RogueConfig.SUPPLY_DEFS
local CATASTROPHE_DEFS = RogueConfig.CATASTROPHE_DEFS
local CHALLENGE_KIND_NAMES = RogueConfig.CHALLENGE_KIND_NAMES
local DAILY_TASK_KIND_WEIGHTS = RogueConfig.DAILY_TASK_KIND_WEIGHTS
local DAILY_TASK_ROTATION_MODS = RogueConfig.DAILY_TASK_ROTATION_MODS
local DAILY_REWARD_RULES = RogueConfig.DAILY_REWARD_RULES
local THREAT_ROTATION_MODS = RogueConfig.THREAT_ROTATION_MODS
local ELITE_AFFIX_DEFS = RogueConfig.ELITE_AFFIX_DEFS
local AFFIX_CONFLICTS = RogueConfig.AFFIX_CONFLICTS
local BOSS_TEMPLATE_DEFS = RogueConfig.BOSS_TEMPLATE_DEFS
local BOSS_TEMPLATE_ROTATION_MODS = RogueConfig.BOSS_TEMPLATE_ROTATION_MODS
local SEASON_PHASE_NAMES = RogueConfig.SEASON_PHASE_NAMES
local SEASON_AFFIX_ROTATION_DEFS = RogueConfig.SEASON_AFFIX_ROTATION_DEFS
local BOSS_LOOT_SIGNATURE_DEFS = RogueConfig.BOSS_LOOT_SIGNATURE_DEFS
local SEASON_OBJECTIVE_DEFS = RogueConfig.SEASON_OBJECTIVE_DEFS
local SEASON_OBJECTIVE_BALANCE = RogueConfig.SEASON_OBJECTIVE_BALANCE
local SEASON_STYLE_NAMES = RogueConfig.SEASON_STYLE_NAMES
local DROP_PITY_RULES = RogueConfig.DROP_PITY_RULES
local VNEXT_DROP_BALANCE = RogueConfig.VNEXT_DROP_BALANCE

-- [工具函数] --------------------------------------------------------------------

local last_announce_time = 0
-- 广播消息给所有玩家，包含防刷屏机制（0.5秒冷却）
local function Announce(msg)
    if TheNet then
        local t = GetTime()
        if t - last_announce_time > 0.5 then
            TheNet:Announce(msg)
            last_announce_time = t
        end
    end
end

local PREFAB_RUNTIME_ALIASES = RogueConfig.PREFAB_RUNTIME_ALIASES

-- 清理并格式化预制体名称
local function SanitizePrefabName(prefab)
    return RogueHelpers.SanitizePrefabName(prefab)
end

-- 检查预制体是否已在全局注册
local function IsPrefabRegistered(prefab)
    return RogueHelpers.IsPrefabRegistered(prefab, GLOBAL.Prefabs)
end

-- 解析运行时的真实预制体名称（处理别名）
local function ResolveRuntimePrefab(prefab)
    return RogueHelpers.ResolveRuntimePrefab(prefab, PREFAB_RUNTIME_ALIASES, GLOBAL.Prefabs)
end

local SHIPWRECKED_PROBE_PREFABS = {
    "crocodog",
    "jellyfish",
    "dragoon",
    "ox",
}

local HAMLET_PROBE_PREFABS = {
    "antman",
    "pigbandit",
    "ancient_hulk",
    "bill",
}

-- 函数说明：检查海难关键预制体是否已被注册，用于提示玩家是否正确启用海难模组。
local function HasShipwreckedContent()
    for _, prefab in ipairs(SHIPWRECKED_PROBE_PREFABS) do
        if IsPrefabRegistered(prefab) then
            return true
        end
    end
    return false
end

-- 函数说明：检查哈姆雷特关键预制体是否已被注册，用于提示玩家是否正确启用哈姆雷特模组。
local function HasHamletContent()
    for _, prefab in ipairs(HAMLET_PROBE_PREFABS) do
        if IsPrefabRegistered(prefab) then
            return true
        end
    end
    return false
end



AddPrefabPostInit("world", function(inst)
    if not (inst and inst.ismastersim) then
        return
    end

    if inst.components.wagpunk_arena_manager then
        inst.components.wagpunk_arena_manager.OnInit = function() end
        inst:RemoveComponent("wagpunk_arena_manager")
    end
    if inst.components.hermitcrab_relocation_manager then
        inst.components.hermitcrab_relocation_manager.OnInit = function() end
        inst:RemoveComponent("hermitcrab_relocation_manager")
    end

    inst:ListenForEvent("playeractivated", function(world, player)
        if player and player.components.roccontroller then
            local old_FadeOutFinished = player.components.roccontroller.FadeOutFinished
            if type(old_FadeOutFinished) == "function" then
                player.components.roccontroller.FadeOutFinished = function(self)
                    self.inst:DoTaskInTime(2, function()
                        local pt
                        if self.inst.roc_nest and self.inst.roc_nest:IsValid() then
                            pt = GLOBAL.Vector3(self.inst.roc_nest.Transform:GetWorldPosition())
                        else
                            pt = GLOBAL.Vector3(self.inst.Transform:GetWorldPosition())
                        end
                        self.inst.Transform:SetPosition(pt.x, pt.y, pt.z)

                        local grabbed_player = self.grabbed_player
                        if grabbed_player and grabbed_player:IsValid() then
                            grabbed_player.Physics:Teleport(pt.x, pt.y, pt.z)
                            if grabbed_player.components.sanity then
                                grabbed_player.components.sanity:DoDelta(-GLOBAL.TUNING.SANITY_MED)
                            end

                            if grabbed_player.sg then
                                grabbed_player.sg:GoToState("wakeup")
                            end
                        end

                        if type(self.FadeInFinished) == "function" then
                            self:FadeInFinished()
                        end
                    end)
                end
            end
        end
    end)

    inst:DoTaskInTime(0, function()
        if Config.WORLD_VARIANT == "shipwrecked" then
            if HasShipwreckedContent() then
                Announce("已启用肉鸽模式-海难版，世界将使用海难单岛地形。")
            else
                Announce("海难版未检测到关键内容，请勾选并启用海难模组后重开世界。")
            end
        elseif Config.WORLD_VARIANT == "hamlet" then
            if HasHamletContent() then
                Announce("已启用肉鸽模式-哈姆雷特版，世界将使用哈姆雷特单岛地形。")
            else
                Announce("哈姆雷特版未检测到关键内容，请勾选并启用哈姆雷特模组后重开世界。")
            end
        end
    end)
end)

AddComponentPostInit("batted", function(self)
    if not self then
        return
    end
    local raw_on_update = self.OnUpdate
    if type(raw_on_update) == "function" then
        self.OnUpdate = function(component, dt)
            local ok = pcall(raw_on_update, component, dt)
            if not ok then
                if component then
                    component.OnUpdate = function() end
                    if type(component.LongUpdate) == "function" then
                        component.LongUpdate = function() end
                    end
                    local inst = component.inst
                    if inst and type(inst.StopUpdatingComponent) == "function" then
                        inst:StopUpdatingComponent(component)
                    end
                end
            end
        end
    end
end)

-- [池管理] --------------------------------------------------------------------

-- 基于权重的随机选择器
local function PickWeightedCandidate(pool, total_weight)
    return RogueHelpers.PickWeightedCandidate(pool, total_weight)
end

-- [逻辑函数] --------------------------------------------------------------------

-- 判断是否是合法存活玩家
local function IsValidPlayer(player)
    return RogueHelpers.IsValidPlayer(player)
end

-- 收集所有存活的玩家
local function CollectAlivePlayers()
    return RogueHelpers.CollectAlivePlayers(AllPlayers)
end

local PlayerState = RoguePlayerState.Create({ CONST = CONST, GLOBAL = GLOBAL })

-- 确保玩家的肉鸽状态数据已初始化
local function EnsurePlayerData(player)
    return PlayerState.EnsurePlayerData(player)
end

-- 同步玩家的成长数据到网络变量（供UI使用）
local function SyncGrowthNetvars(player, data)
    return PlayerState.SyncGrowthNetvars(player, data)
end

-- 将玩家的状态数据应用到其实际属性（攻击、血量等）
local function ApplyGrowthState(player, data, apply_health)
    return PlayerState.ApplyGrowthState(player, data, apply_health)
end

-- 检查玩家周围的敌对生物是否已达上限（避免生成过多导致卡顿）
local function IsSpawnAreaBusy(player)
    if Config.MAX_HOSTILES_NEAR_PLAYER <= 0 then return false end
    local pt = player:GetPosition()
    local nearby = GLOBAL.TheSim:FindEntities(pt.x, pt.y, pt.z, CONST.HOSTILE_SCAN_RADIUS, {"_combat"}, {"player", "playerghost", "INLIMBO"})
    return nearby and #nearby >= Config.MAX_HOSTILES_NEAR_PLAYER
end

local function PickRandom(list)
    return RogueHelpers.PickRandom(list)
end

local function RollRange(range)
    return RogueHelpers.RollRange(range)
end

local function GetEntityName(ent)
    return RogueHelpers.GetEntityName(ent)
end

local AffixSystem = RogueAffixSystem.Create({
    Config = Config,
    CONST = CONST,
    ELITE_AFFIX_DEFS = ELITE_AFFIX_DEFS,
    AFFIX_CONFLICTS = AFFIX_CONFLICTS,
    BossMechanics = RogueBossMechanics.Create({
        BOSS_TEMPLATE_DEFS = BOSS_TEMPLATE_DEFS,
        BOSS_TEMPLATE_ROTATION_MODS = BOSS_TEMPLATE_ROTATION_MODS,
        EnsurePlayerData = EnsurePlayerData,
        GetWaveState = function() return wave_state end,
        SpawnPrefab = SpawnPrefab,
        CollectAlivePlayers = CollectAlivePlayers,
        PickRandom = PickRandom,
        FindWalkableOffset = FindWalkableOffset,
        PI = PI,
        Vector3 = GLOBAL.Vector3,
        GetWorld = function() return GLOBAL.TheWorld end,
        Announce = Announce,
        GetEntityName = GetEntityName,
    }),
    SpawnPrefab = SpawnPrefab,
    CollectAlivePlayers = CollectAlivePlayers,
    PickRandom = PickRandom,
    FindWalkableOffset = FindWalkableOffset,
    PI = PI,
    Announce = Announce,
    GetEntityName = GetEntityName,
})

local function ApplyEliteAffix(ent, day, force)
    return AffixSystem.ApplyEliteAffix(ent, day, force)
end

local function SetupBossPhases(ent, day)
    return AffixSystem.SetupBossPhases(ent, day)
end

-- [掉落与成长] --------------------------------------------------------------------

local DropSystem = RogueDropSystem.Create({
    AddPrefabPostInitAny = AddPrefabPostInitAny,
    IsMasterSim = function() return GLOBAL.TheWorld and GLOBAL.TheWorld.ismastersim end,
    IsRogueAffixCandidatePrefab = IsRogueAffixCandidatePrefab,
    ResolveRuntimePrefab = ResolveRuntimePrefab,
    IsPrefabRegistered = IsPrefabRegistered,
    SpawnPrefab = SpawnPrefab,
    FindWalkableOffset = FindWalkableOffset,
    PI = PI,
    Config = Config,
    PoolCatalog = PoolCatalog,
    PickWeightedCandidate = PickWeightedCandidate,
    RollRange = RollRange,
    EnsurePlayerData = EnsurePlayerData,
    IsValidPlayer = IsValidPlayer,
    BUFF_TYPES = BUFF_TYPES,
    GEAR_BUFFS = GEAR_BUFFS,
    SEASON_AFFIX_ROTATION_DEFS = SEASON_AFFIX_ROTATION_DEFS,
    BOSS_LOOT_SIGNATURE_DEFS = BOSS_LOOT_SIGNATURE_DEFS,
    SEASON_OBJECTIVE_DEFS = SEASON_OBJECTIVE_DEFS,
    DROP_PITY_RULES = DROP_PITY_RULES,
    VNEXT_DROP_BALANCE = VNEXT_DROP_BALANCE,
    SyncGrowthNetvars = SyncGrowthNetvars,
    CONST = CONST,
    Announce = Announce,
    GetWaveState = function() return wave_state end,
    GetWorld = function() return GLOBAL.TheWorld end,
    Vector3 = GLOBAL.Vector3,
    BossLoot = RogueBossLoot,
    GLOBAL = GLOBAL,
    TheSim = GLOBAL.TheSim,
})
DropSystem.RegisterItemPersistenceHook()

local function SpawnDrop(victim, prefab, buffs)
    return DropSystem.SpawnDrop(victim, prefab, buffs)
end

local function DropLoot(victim, is_boss, day, killer)
    return DropSystem.DropLoot(victim, is_boss, day, killer)
end

local function ApplyBuff(player, is_boss)
    return DropSystem.ApplyBuff(player, is_boss)
end

local TalentSupply = RogueTalentSupply.Create({
    GLOBAL = GLOBAL,
    CONST = CONST,
    TALENT_DEFS = TALENT_DEFS,
    SUPPLY_DEFS = SUPPLY_DEFS,
    EnsurePlayerData = EnsurePlayerData,
    ApplyGrowthState = ApplyGrowthState,
    SyncGrowthNetvars = SyncGrowthNetvars,
    IsValidPlayer = IsValidPlayer,
    PoolCatalog = PoolCatalog,
    PickWeightedCandidate = PickWeightedCandidate,
    SpawnDrop = SpawnDrop,
    Announce = Announce,
    GetCurrentDay = function() return GLOBAL.TheWorld.state.cycles + 1 end,
})
TalentSupply.RegisterRPCCallbacks()

local function OfferNightSupply(player, day)
    return TalentSupply.OfferNightSupply(player, day)
end

local ProgressionSystem = RogueProgressionSystem.Create({
    CONST = CONST,
    DAILY_KIND_NAMES = DAILY_KIND_NAMES,
    DAILY_TASK_KIND_WEIGHTS = DAILY_TASK_KIND_WEIGHTS,
    DAILY_TASK_ROTATION_MODS = DAILY_TASK_ROTATION_MODS,
    DAILY_REWARD_RULES = DAILY_REWARD_RULES,
    EnsurePlayerData = EnsurePlayerData,
    SyncGrowthNetvars = SyncGrowthNetvars,
    IsValidPlayer = IsValidPlayer,
    ApplyBuff = ApplyBuff,
    PoolCatalog = PoolCatalog,
    PickWeightedCandidate = PickWeightedCandidate,
    SpawnDrop = SpawnDrop,
    Announce = Announce,
    GetTime = GetTime,
})

local function ResetComboState(player)
    return ProgressionSystem.ResetComboState(player)
end

local function RefreshComboState(player)
    return ProgressionSystem.RefreshComboState(player)
end

local function EnsureDailyTask(player, day)
    return ProgressionSystem.EnsureDailyTask(player, day)
end

local function ProgressDailyTaskOnKill(player, victim, is_boss, day)
    return ProgressionSystem.ProgressDailyTaskOnKill(player, victim, is_boss, day)
end

local function ProgressDailyTaskOnWaveEnd(player, day)
    return ProgressionSystem.ProgressDailyTaskOnWaveEnd(player, day)
end

local function ProgressDailyTaskOnChallengeReward(player, day)
    return ProgressionSystem.ProgressDailyTaskOnChallengeReward(player, day)
end

local function ProgressDailyTaskOnBountyReward(player, day)
    return ProgressionSystem.ProgressDailyTaskOnBountyReward(player, day)
end

local function CheckTalentTrigger(player)
    return TalentSupply.CheckTalentTrigger(player)
end

local RelicSystem = RogueRelicSystem.Create({
    GLOBAL = GLOBAL,
    SpawnPrefab = SpawnPrefab,
    EnsurePlayerData = EnsurePlayerData,
    ApplyGrowthState = ApplyGrowthState,
    SyncGrowthNetvars = SyncGrowthNetvars,
    IsValidPlayer = IsValidPlayer,
    Announce = Announce,
})
RelicSystem.RegisterRPCCallbacks()

local function OfferInitialRelicChoice(player)
    return RelicSystem.OfferInitialRelicChoice(player)
end

local function OfferRelicChoice(player, source, day)
    return RelicSystem.OfferRelicChoice(player, source, day)
end

local function CheckRelicTrigger(player, day)
    return RelicSystem.CheckRelicTrigger(player, day)
end

local function RequestWorldReset()
    Announce("赛季重生执行中...")
    if GLOBAL.c_regenerateworld then
        local ok = pcall(GLOBAL.c_regenerateworld)
        if ok then return true end
    end
    if GLOBAL.TheWorld then
        local ok = pcall(function()
            GLOBAL.TheWorld:PushEvent("ms_regenerateworld")
        end)
        if ok then return true end
    end
    if GLOBAL.TheWorld and GLOBAL.TheWorld.components and GLOBAL.TheWorld.components.worldreset then
        local wr = GLOBAL.TheWorld.components.worldreset
        if wr.Regenerate then
            local ok = pcall(function() wr:Regenerate() end)
            if ok then return true end
        end
        if wr.BeginRegenerate then
            local ok = pcall(function() wr:BeginRegenerate() end)
            if ok then return true end
        end
        if wr.BeginRegeneration then
            local ok = pcall(function() wr:BeginRegeneration() end)
            if ok then return true end
        end
    end
    Announce("未找到可用的世界重生接口。")
    return false
end

local SeasonSystem = nil
local SeasonResultSystem = RogueSeasonResult.Create({
    GLOBAL = GLOBAL,
    AllPlayers = AllPlayers,
    EnsurePlayerData = EnsurePlayerData,
    IsValidPlayer = IsValidPlayer,
    GetWorld = function() return GLOBAL.TheWorld end,
    SyncGrowthNetvars = SyncGrowthNetvars,
    Announce = Announce,
    GetSeasonId = function() return SeasonSystem and SeasonSystem.GetSeasonId() or 1 end,
    GetCurrentDay = function() return GLOBAL.TheWorld.state.cycles + 1 end,
    SEASON_OBJECTIVE_DEFS = SEASON_OBJECTIVE_DEFS,
    SEASON_OBJECTIVE_BALANCE = SEASON_OBJECTIVE_BALANCE,
    SEASON_STYLE_NAMES = SEASON_STYLE_NAMES,
    PoolCatalog = PoolCatalog,
    PickWeightedCandidate = PickWeightedCandidate,
    SpawnDrop = function(victim, prefab, buffs)
        return DropSystem and DropSystem.SpawnDrop and DropSystem.SpawnDrop(victim, prefab, buffs) or nil
    end,
})

SeasonSystem = RogueSeasonSystem.Create({
    Config = Config,
    AllPlayers = AllPlayers,
    START_DAY = Config.START_DAY,
    SEASON_PHASE_NAMES = SEASON_PHASE_NAMES,
    SEASON_AFFIX_ROTATION_DEFS = SEASON_AFFIX_ROTATION_DEFS,
    EnsurePlayerData = EnsurePlayerData,
    SyncGrowthNetvars = SyncGrowthNetvars,
    GetCurrentDay = function() return GLOBAL.TheWorld.state.cycles + 1 end,
    GetTime = GetTime,
    RequestWorldReset = RequestWorldReset,
    OnSeasonChanged = function() SeasonResultSystem.OnSeasonChanged() end,
    FinalizeSeason = function(day) return SeasonResultSystem.Finalize(day) end,
    Announce = Announce,
})

local function SyncSeasonStateToPlayer(player)
    return SeasonSystem.SyncSeasonStateToPlayer(player)
end

local function SyncSeasonStateToAllPlayers()
    return SeasonSystem.SyncSeasonStateToAllPlayers()
end

local function OnWorldPhaseChange(world, phase)
    return SeasonSystem.OnWorldPhaseChange(world, phase)
end

local function CanRunCombatLoop()
    return SeasonSystem.CanRunCombatLoop()
end

local function IsFinalNight()
    return SeasonSystem.IsFinalNight()
end

local function IsGracePeriod(day)
    return SeasonSystem.IsGracePeriod(day)
end

local function OnSeasonKill(player, victim, is_boss, day)
    return SeasonResultSystem.OnKill(player, victim, is_boss, day)
end

local function OnSeasonPlayerDeath(player, day)
    return SeasonResultSystem.OnDeath(player, day)
end

local function OnSeasonChallengeReward(player, day)
    return SeasonResultSystem.OnChallengeReward(player, day)
end

local function OnSeasonBountyReward(player, day)
    return SeasonResultSystem.OnBountyReward(player, day)
end

-- [特殊事件] --------------------------------------------------------------------

local EventSystem = RogueEventSystem.Create({
    Announce = Announce,
    GetWorld = function() return GLOBAL.TheWorld end,
    CollectAlivePlayers = CollectAlivePlayers,
    EnsurePlayerData = EnsurePlayerData,
    PickRandom = PickRandom,
    PoolCatalog = PoolCatalog,
    PickWeightedCandidate = PickWeightedCandidate,
    ResolveRuntimePrefab = ResolveRuntimePrefab,
    SpawnPrefab = SpawnPrefab,
    FindWalkableOffset = FindWalkableOffset,
    PI = PI,
    OfferRelicChoice = OfferRelicChoice,
})

local function TriggerRandomEvent(day)
    return EventSystem.TriggerRandomEvent(day)
end

-- [波次管理] --------------------------------------------------------------------

local WaveSystem = RogueWaveSystem.Create({
    Config = Config,
    CONST = CONST,
    AllPlayers = AllPlayers,
    GetWorld = function() return GLOBAL.TheWorld end,
    GetTime = GetTime,
    PoolCatalog = PoolCatalog,
    WAVE_RULE_DEFS = WAVE_RULE_DEFS,
    REGION_ROUTE_DEFS = REGION_ROUTE_DEFS,
    THREAT_ROTATION_MODS = THREAT_ROTATION_MODS,
    CATASTROPHE_DEFS = CATASTROPHE_DEFS,
    CHALLENGE_KIND_NAMES = CHALLENGE_KIND_NAMES,
    EnsurePlayerData = EnsurePlayerData,
    SyncGrowthNetvars = SyncGrowthNetvars,
    PickWeightedCandidate = PickWeightedCandidate,
    ResolveRuntimePrefab = ResolveRuntimePrefab,
    IsPrefabRegistered = IsPrefabRegistered,
    SpawnPrefab = SpawnPrefab,
    FindWalkableOffset = FindWalkableOffset,
    PI = PI,
    CollectAlivePlayers = CollectAlivePlayers,
    IsValidPlayer = IsValidPlayer,
    IsSpawnAreaBusy = IsSpawnAreaBusy,
    PickRandom = PickRandom,
    GetEntityName = GetEntityName,
    ApplyEliteAffix = ApplyEliteAffix,
    SetupBossPhases = SetupBossPhases,
    ApplyBuff = ApplyBuff,
    SpawnDrop = SpawnDrop,
    ProgressDailyTaskOnWaveEnd = ProgressDailyTaskOnWaveEnd,
    ProgressDailyTaskOnChallengeReward = ProgressDailyTaskOnChallengeReward,
    ProgressDailyTaskOnBountyReward = ProgressDailyTaskOnBountyReward,
    OfferNightSupply = OfferNightSupply,
    TriggerRandomEvent = TriggerRandomEvent,
    OfferRelicChoice = OfferRelicChoice,
    OnSeasonChallengeReward = OnSeasonChallengeReward,
    OnSeasonBountyReward = OnSeasonBountyReward,
    Announce = Announce,
    GLOBAL = GLOBAL,
})
if WaveSystem.RegisterRPCCallbacks then
    WaveSystem.RegisterRPCCallbacks()
end
wave_state = WaveSystem.GetState()

local function SyncWaveStateToPlayer(player)
    return WaveSystem.SyncWaveStateToPlayer(player)
end

local function SyncWaveStateToAllPlayers()
    return WaveSystem.SyncWaveStateToAllPlayers()
end

local function ProgressChallenge(kind, add, day)
    return WaveSystem.ProgressChallenge(kind, add, day)
end

local function RewardBounty(player, day)
    return WaveSystem.RewardBounty(player, day)
end

local function EndWave()
    return WaveSystem.EndWave()
end

local function StartWave(day, opts)
    return WaveSystem.StartWave(day, opts)
end

local function ExportWaveState()
    return WaveSystem.ExportState and WaveSystem.ExportState() or nil
end

local function ImportWaveState(saved)
    if WaveSystem.ImportState then
        WaveSystem.ImportState(saved)
    end
end

local function ExportSeasonState()
    return SeasonSystem and SeasonSystem.ExportState and SeasonSystem.ExportState() or nil
end

local function ImportSeasonState(saved)
    if SeasonSystem and SeasonSystem.ImportState then
        SeasonSystem.ImportState(saved)
    end
end

local function ExportDropState()
    return DropSystem and DropSystem.ExportState and DropSystem.ExportState() or nil
end

local function ImportDropState(saved)
    if DropSystem and DropSystem.ImportState then
        DropSystem.ImportState(saved)
    end
end

local ShopSystem = RogueShopSystem.Create({
    EnsurePlayerData = EnsurePlayerData,
    SpawnPrefab = SpawnPrefab,
    Announce = Announce,
})
GLOBAL._rogue_mode_buy_shop_item_rpc = ShopSystem.BuyItem
GLOBAL._rogue_mode_recycle_item_rpc = ShopSystem.RecycleItem

local RuntimeSystem = RogueRuntimeSystem.Create({
    GLOBAL = GLOBAL,
    Config = Config,
    CONST = CONST,
    AllPlayers = AllPlayers,
    SpawnPrefab = SpawnPrefab,
    AddPlayerPostInit = AddPlayerPostInit,
    AddPrefabPostInit = AddPrefabPostInit,
    IsMasterSim = function() return GLOBAL.TheWorld and GLOBAL.TheWorld.ismastersim end,
    IsValidPlayer = IsValidPlayer,
    GetCurrentDay = function() return GLOBAL.TheWorld.state.cycles + 1 end,
    EnsurePlayerData = EnsurePlayerData,
    ApplyGrowthState = ApplyGrowthState,
    EnsureDailyTask = EnsureDailyTask,
    SyncWaveStateToPlayer = SyncWaveStateToPlayer,
    SyncSeasonStateToPlayer = SyncSeasonStateToPlayer,
    SyncSeasonStateToAllPlayers = SyncSeasonStateToAllPlayers,
    OnWorldPhaseChange = OnWorldPhaseChange,
    CanRunCombatLoop = CanRunCombatLoop,
    IsFinalNight = IsFinalNight,
    IsGracePeriod = IsGracePeriod,
    DropLoot = DropLoot,
    RefreshComboState = RefreshComboState,
    ProgressDailyTaskOnKill = ProgressDailyTaskOnKill,
    ProgressChallenge = ProgressChallenge,
    RewardBounty = RewardBounty,
    OnSeasonKill = OnSeasonKill,
    OnSeasonPlayerDeath = OnSeasonPlayerDeath,
    SyncWaveStateToAllPlayers = SyncWaveStateToAllPlayers,
    ApplyBuff = ApplyBuff,
    CheckTalentTrigger = CheckTalentTrigger,
    OfferInitialRelicChoice = OfferInitialRelicChoice,
    CheckRelicTrigger = CheckRelicTrigger,
    GetWaveState = function() return wave_state end,
    ExportWaveState = ExportWaveState,
    ImportWaveState = ImportWaveState,
    ExportSeasonState = ExportSeasonState,
    ImportSeasonState = ImportSeasonState,
    ExportDropState = ExportDropState,
    ImportDropState = ImportDropState,
    StartWave = StartWave,
    EndWave = EndWave,
    CollectAlivePlayers = CollectAlivePlayers,
    Announce = Announce,
})
RuntimeSystem.RegisterPlayerLifecycle()
RuntimeSystem.RegisterWorldLifecycle()
