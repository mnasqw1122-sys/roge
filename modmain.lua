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

PrefabFiles = {
    "rogue_recycle_bin",
    "rogue_npc",
}

Assets = {
    Asset("IMAGE", "images/rogue_icon.tex"),
    Asset("ATLAS", "images/rogue_icon.xml"),
    Asset("IMAGE", "images/rogue_panel.tex"),
    Asset("ATLAS", "images/rogue_panel.xml"),
}

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
local RogueBossMechanicsV2 = require("rogue/boss_mechanics_v2") -- 引入 V2 深度机制引擎
local AffixArenaForge = require("rogue/affix_arena_forge") -- 引入 V2 领域工匠词缀
local AffixSummonerLegion = require("rogue/affix_summoner_legion") -- 引入 V2 统御军势/雷暴猎场/双相裂变/压迫领域词缀
local RogueBossLoot = require("rogue/boss_loot")
local RogueRelicSystem = require("rogue/relic_system")
local RogueSeasonSystem = require("rogue/season_system")
local RogueSeasonResult = require("rogue/season_result")
local RogueStateSchema = require("rogue/state_schema")
local RogueShopSystem = require("rogue/shop_system")
local RogueSetBonus = require("rogue/set_bonus")
local RogueChainEvent = require("rogue/chain_event")
local RogueAchievement = require("rogue/achievement_system")
local RogueCoopSystem = require("rogue/coop_system")
local RogueMilestoneSystem = require("rogue/milestone_system")
local RogueConfigHotreload = require("rogue/config_hotreload")

-- 预声明：连锁任务奖励等系统需要在运行期回调遗物/天赋选择，
-- 此处先声明变量槽，待对应系统创建完成后赋值（见下方函数定义处）。
local OfferRelicChoice = nil
-- 预声明：world 生命周期回调（AddPrefabPostInit）在运行期才执行，
-- 需要引用创建顺序靠后的系统实例，同样先声明变量槽。
local EnvSystem = nil
local CoopSystem = nil
local ComboSystem = nil
local MilestoneSystem = nil

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
        -- 挂载到 topright_root 缩放节点，自动参与 HUD 缩放系统
        local mount_root = self.topright_root or self
        self.rogue_status = mount_root:AddChild(RogueStatusDisplay(self.owner))
        self.rogue_status:MoveToFront()

        local RogueShopPanel = require("widgets/rogue_shop_panel")
        self.rogue_shop = self:AddChild(RogueShopPanel(self.owner))
        self.rogue_shop:Hide()
        
        -- 给 status UI 传递 shop panel 的引用，方便开关
        self.rogue_status.shop_panel = self.rogue_shop

        -- 遗物三选一弹窗面板
        local RogueRelicPanel = require("widgets/rogue_relic_panel")
        self.rogue_relic_panel = self:AddChild(RogueRelicPanel(self.owner))
        self.rogue_relic_panel:Hide()

        -- 天赋三选一弹窗面板
        local RogueTalentPanel = require("widgets/rogue_talent_panel")
        self.rogue_talent_panel = self:AddChild(RogueTalentPanel(self.owner))
        self.rogue_talent_panel:Hide()

        -- 补给三选一弹窗面板
        local RogueSupplyPanel = require("widgets/rogue_supply_panel")
        self.rogue_supply_panel = self:AddChild(RogueSupplyPanel(self.owner))
        self.rogue_supply_panel:Hide()
    end
end)

AddClassPostConstruct("widgets/containerwidget", function(self)
    local old_Open = self.Open
    self.Open = function(self, container, doer)
        old_Open(self, container, doer)
        if container and container.prefab == "rogue_recycle_bin" then
            if self.bganim then self.bganim:Hide() end
            if self.bgimage then self.bgimage:Hide() end
            
            -- 将该容器直接挂载到玩家的肉鸽商店回收界面
            if doer and doer.HUD and doer.HUD.controls and doer.HUD.controls.rogue_shop then
                local shop = doer.HUD.controls.rogue_shop
                shop.recycle_container:AddChild(self)
                self:SetPosition(0, 0, 0)
                -- 修正缩放，保持 1:1，不再过度放大
                self:SetScale(1, 1, 1)
                shop.active_recycle_widget = self
            end
        end
    end

    local old_Close = self.Close
    self.Close = function(self)
        if self.container and self.container.prefab == "rogue_recycle_bin" then
            if self.owner and self.owner.HUD and self.owner.HUD.controls and self.owner.HUD.controls.rogue_shop then
                local shop = self.owner.HUD.controls.rogue_shop
                if shop.active_recycle_widget == self then
                    shop.active_recycle_widget = nil
                end
            end
        end
        old_Close(self)
    end
end)

-- [网络变量注册] --------------------------------------------------------------------
local containers = require("containers")
local params = containers.params

local rogue_recycle_bin_slots = {}
-- [V2.3.3] 回收容器扩充为 5x5 = 25 格
for y = 0, 4 do
    for x = 0, 4 do
        table.insert(rogue_recycle_bin_slots, GLOBAL.Vector3(-250 + x * 120, 60 - y * 90, 0))
    end
end

params.rogue_recycle_bin = {
    widget = {
        slotpos = rogue_recycle_bin_slots,
        animbank = "ui_chest_3x3",
        animbuild = "ui_chest_3x3",
        pos = GLOBAL.Vector3(0, 0, 0),
        side_align_tip = 160,
    },
    type = "chest",
    excludefromcrafting = true,
}

for k, v in pairs(params) do
    containers.MAXITEMSLOTS = math.max(containers.MAXITEMSLOTS, v.widget.slotpos ~= nil and #v.widget.slotpos or 0)
end

AddPlayerPostInit(function(inst)
    RogueStateSchema.RegisterNetvars(inst, GLOBAL)
end)

-- [RPC闭包注册] --------------------------------------------------------------------
-- 使用本地handler表替代GLOBAL全局函数桥接，避免命名空间污染
-- handler表在子系统初始化后填充，RPC回调通过闭包引用此表
-- 注册统一走 rpc_registry（集中管理 + 客户端合并窗口机制）
local RPCRegistry = require("rogue/rpc_registry")
local _rpc_handlers = {}

-- 函数说明：注册RPC处理器到本地表（替代GLOBAL._rogue_mode_*_rpc赋值）
local function SetRPCHandler(name, fn)
    _rpc_handlers[name] = fn
end

-- 函数说明：创建RPC回调闭包（从本地表查找处理器）
local function MakeRPCCallback(name)
    return function(player, ...)
        local handler = _rpc_handlers[name]
        if handler then
            handler(player, ...)
        end
    end
end

RPCRegistry.Register("pick_talent", MakeRPCCallback("pick_talent"))
RPCRegistry.Register("pick_supply", MakeRPCCallback("pick_supply"))
RPCRegistry.Register("pick_relic", MakeRPCCallback("pick_relic"))
RPCRegistry.Register("pick_route", MakeRPCCallback("pick_route"))
RPCRegistry.Register("buy_shop_item", MakeRPCCallback("buy_shop_item"))
RPCRegistry.Register("buy_black_market_item", MakeRPCCallback("buy_black_market_item"))
RPCRegistry.Register("recycle_item", MakeRPCCallback("recycle_item"))
RPCRegistry.Register("open_recycle_bin", MakeRPCCallback("open_recycle_bin"))
RPCRegistry.Register("close_recycle_bin", MakeRPCCallback("close_recycle_bin"))
RPCRegistry.Register("recycle_all_items", MakeRPCCallback("recycle_all_items"))
RPCRegistry.Register("reload_config", MakeRPCCallback("reload_config"))
RPCRegistry.Register("combo_skill", MakeRPCCallback("combo_skill"))

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

-- 按名称排序后注册，保证客户端/服务器以完全一致的顺序创建网络变量，
-- 避免 Lua table pairs 遍历顺序不确定性导致后续网络变量错位崩溃。
local affix_prefab_names = {}
for prefab_name, _ in pairs(ROGUE_AFFIX_PREFAB_WHITELIST) do
    table.insert(affix_prefab_names, prefab_name)
end
table.sort(affix_prefab_names)

for _, prefab_name in ipairs(affix_prefab_names) do
    AddPrefabPostInit(prefab_name, function(inst)
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
                            base_name = STRINGS.NAMES[string.upper(i.prefab)] or i.prefab
                        end
                    end
                    
                    return string.format("[%s] %s", affix_text, base_name)
                end
            end
        end
    end)
end

if not IsServer then return end

local RogueShopConfig = require("rogue/shop_config")

if RogueShopConfig and RogueShopConfig.InitVariant then
    RogueShopConfig.InitVariant(Config.WORLD_VARIANT)
end
local BUFF_TYPES = RogueConfig.BUFF_TYPES
local TALENT_DEFS = RogueConfig.TALENT_DEFS
local DAILY_KIND_NAMES = RogueConfig.DAILY_KIND_NAMES
local DAILY_TASK_TARGETS = RogueConfig.DAILY_TASK_TARGETS
local DAILY_SPECIFIC_TARGET_DEFS = RogueConfig.DAILY_SPECIFIC_TARGET_DEFS
local DAILY_CHAIN_DEFS = RogueConfig.DAILY_CHAIN_DEFS
local DAILY_TASK_REWARDS = RogueConfig.DAILY_TASK_REWARDS
local WAVE_RULE_DEFS = RogueConfig.WAVE_RULE_DEFS
local REGION_ROUTE_DEFS = RogueConfig.REGION_ROUTE_DEFS
local SUPPLY_DEFS = RogueConfig.SUPPLY_DEFS
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
local COOP_BUFF_DEFS = RogueConfig.COOP_BUFF_DEFS
local COOP_REVIVE_COST = RogueConfig.COOP_REVIVE_COST
local COOP_EVENT_DEFS = RogueConfig.COOP_EVENT_DEFS
local SEASON_MILESTONE_DEFS = RogueConfig.SEASON_MILESTONE_DEFS
local SEASON_MILESTONE_UNLOCK_METRICS = RogueConfig.SEASON_MILESTONE_UNLOCK_METRICS

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

    inst:AddComponent("rogue_ai_npc_manager")

    -- [V2.3] 环境词缀过期检查：每秒驱动一次（环境词缀生命周期管理）
    -- pcall 防护：定时器内单点错误不允许影响世界模拟
    if EnvSystem and EnvSystem.OnUpdate then
        inst:DoPeriodicTask(1, function()
            local ok, err = pcall(EnvSystem.OnUpdate)
            if not ok and Config.DEBUG_MODE then
                print("[Rogue][EnvSystem] OnUpdate error: " .. tostring(err))
            end
        end)
    end

    -- [V2.3] 多人协作系统：近距离增益刷新/守护据点事件推进/自动救援（2秒周期）
    -- pcall 防护：定时器内单点错误不允许影响世界模拟
    if CoopSystem then
        inst:DoPeriodicTask(2, function()
            local ok, err = pcall(function()
                if not CoopSystem.RefreshCoopBuffs then return end
                CoopSystem.RefreshCoopBuffs()
                if CoopSystem.UpdateCoopEvents then
                    CoopSystem.UpdateCoopEvents(inst, inst.state and inst.state.isday == true)
                end
                -- 自动救援：鬼魂玩家附近有存活队友时，队友自动支付生命复活（90秒间隔）
                local now = GetTime()
                for _, p in ipairs(AllPlayers) do
                    if p and p:IsValid() and p:HasTag("playerghost") and p.rogue_data then
                        local last = p.rogue_data._coop_auto_revive_last or 0
                        if now - last >= 90 then
                            local px, py, pz = p.Transform:GetWorldPosition()
                            local nearby = GLOBAL.TheSim:FindEntities(px, py, pz, 10, {"player"}, {"playerghost", "INLIMBO"})
                            for _, ally in ipairs(nearby) do
                                if ally ~= p and ally:IsValid() and not ally:HasTag("playerghost") and ally.rogue_data then
                                    local ok_revive = CoopSystem.TryReviveAlly and CoopSystem.TryReviveAlly(ally, p)
                                    if ok_revive then
                                        p.rogue_data._coop_auto_revive_last = now
                                        Announce(ally:GetDisplayName() .. " 救援了 " .. p:GetDisplayName() .. "！")
                                    end
                                    break
                                end
                            end
                        end
                    end
                end
            end)
            if not ok and Config.DEBUG_MODE then
                print("[Rogue][CoopSystem] tick error: " .. tostring(err))
            end
        end)
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
                    old_FadeOutFinished(self) -- call the original function
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
            if not component or not component.inst or not component.inst:IsValid() then return end
            raw_on_update(component, dt)
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

local function SafeSpawnPrefab(prefab)
    return RogueHelpers.SafeSpawnPrefab(prefab)
end

local function SafeCall(fn, ...)
    return RogueHelpers.SafeCall(fn, ...)
end

local function SafeFindEntities(x, y, z, radius, tags, excludetags)
    return RogueHelpers.SafeFindEntities(x, y, z, radius, tags, excludetags)
end

-- 环境/全局词缀系统（V2.3 接线）：需要先于所有消费方创建
local AffixEnvironment = require("rogue/affix_environment")
EnvSystem = AffixEnvironment.Create({
    SpawnPrefab = SpawnPrefab,
    GetTime = GetTime,
    Announce = Announce,
})

-- 函数说明：读取当前激活的全局词缀修正值（world.rogue_env_data），供各系统消费
local function GetGlobalModifier(key)
    if EnvSystem and EnvSystem.GetGlobalModifier then
        return EnvSystem.GetGlobalModifier(key)
    end
    return nil
end

local AffixSystem = RogueAffixSystem.Create({
    Config = Config,
    CONST = CONST,
    ELITE_AFFIX_DEFS = ELITE_AFFIX_DEFS,
    AFFIX_CONFLICTS = AFFIX_CONFLICTS,
    BOSS_AFFIX_DEFS = RogueConfig.BOSS_AFFIX_DEFS,
    GetGlobalModifier = GetGlobalModifier,
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
        RogueBossMechanicsV2 = RogueBossMechanicsV2, -- 注入 V2 核心
    }),
    SpawnPrefab = SpawnPrefab,
    SafeSpawnPrefab = SafeSpawnPrefab,
    SafeCall = SafeCall,
    SafeFindEntities = SafeFindEntities,
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
    SafeSpawnPrefab = SafeSpawnPrefab,
    SafeCall = SafeCall,
    SafeFindEntities = SafeFindEntities,
    FindWalkableOffset = FindWalkableOffset,
    PI = PI,
    Config = Config,
    PoolCatalog = PoolCatalog,
    PickWeightedCandidate = PickWeightedCandidate,
    RollRange = RollRange,
    EnsurePlayerData = EnsurePlayerData,
    IsValidPlayer = IsValidPlayer,
    BUFF_TYPES = BUFF_TYPES,
    SEASON_AFFIX_ROTATION_DEFS = SEASON_AFFIX_ROTATION_DEFS,
    BOSS_LOOT_SIGNATURE_DEFS = BOSS_LOOT_SIGNATURE_DEFS,
    SEASON_OBJECTIVE_DEFS = SEASON_OBJECTIVE_DEFS,
    DROP_PITY_RULES = DROP_PITY_RULES,
    VNEXT_DROP_BALANCE = VNEXT_DROP_BALANCE,
    GetGlobalModifier = GetGlobalModifier,
    BossBalance = RogueConfig.BOSS_BALANCE,
    SyncGrowthNetvars = SyncGrowthNetvars,
    CONST = CONST,
    Announce = Announce,
    GetWaveState = function() return wave_state end,
    GetWorld = function() return GLOBAL.TheWorld end,
    Vector3 = GLOBAL.Vector3,
    BossLoot = RogueBossLoot,
    GLOBAL = GLOBAL,
    TheSim = GLOBAL.TheSim,
    ROGUE_AFFIX_PREFAB_WHITELIST = ROGUE_AFFIX_PREFAB_WHITELIST,
    AddPrefabPostInit = AddPrefabPostInit,
})
DropSystem.RegisterItemPersistenceHook()

local function SpawnDrop(victim, prefab, buffs)
    return DropSystem.SpawnDrop(victim, prefab, buffs)
end

local function DropLoot(victim, is_boss, day, killer)
    return DropSystem.DropLoot(victim, is_boss, day, killer)
end

local function ApplyBuff(player, is_boss)
    local result = DropSystem.ApplyBuff(player, is_boss)
    if player and player.rogue_data then
        PlayerState.SyncGrowthNetvars(player, player.rogue_data)
    end
    return result
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
    SpawnPrefab = SpawnPrefab,
    GetTime = GetTime,
    Announce = Announce,
    GetCurrentDay = function() return GLOBAL.TheWorld.state.cycles + 1 end,
    SetRPCHandler = SetRPCHandler,
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
    DAILY_TASK_TARGETS = DAILY_TASK_TARGETS,
    DAILY_SPECIFIC_TARGET_DEFS = DAILY_SPECIFIC_TARGET_DEFS,
    DAILY_CHAIN_DEFS = DAILY_CHAIN_DEFS,
    DAILY_TASK_REWARDS = DAILY_TASK_REWARDS,
    GetGlobalModifier = GetGlobalModifier,
    EnsurePlayerData = EnsurePlayerData,
    SyncGrowthNetvars = SyncGrowthNetvars,
    IsValidPlayer = IsValidPlayer,
    ApplyBuff = ApplyBuff,
    PoolCatalog = PoolCatalog,
    PickWeightedCandidate = PickWeightedCandidate,
    SpawnDrop = SpawnDrop,
    Announce = Announce,
    GetTime = GetTime,
    -- 连锁任务奖励兑现：闭包运行期取最新赋值，避免创建顺序导致的 nil
    OfferRelicChoice = function(player, source, day)
        if OfferRelicChoice then return OfferRelicChoice(player, source, day) end
    end,
    OfferTalentChoice = function(player)
        if TalentSupply and TalentSupply.OfferTalentChoice then
            return TalentSupply.OfferTalentChoice(player)
        end
    end,
})

local function ResetComboState(player)
    ProgressionSystem.ResetComboState(player)
    -- [V2.3] 连击重置时同步重置连击里程碑状态
    if ComboSystem and ComboSystem.OnComboExpired and player and player.rogue_data then
        ComboSystem.OnComboExpired(player, player.rogue_data)
    end
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

-- [V2.3] 连击技能系统：里程碑/技能/冷却管理（连击计数沿用 ProgressionSystem）
local RogueComboSystem = require("rogue/combo_system")
ComboSystem = RogueComboSystem.Create({
    GetTime = GetTime,
    ApplyGrowthState = ApplyGrowthState,
    EnsurePlayerData = EnsurePlayerData,
    Announce = Announce,
    SpawnPrefab = SpawnPrefab,
    GetGlobalModifier = GetGlobalModifier,
    SetRPCHandler = SetRPCHandler,
})
ComboSystem.RegisterRPCCallbacks()

local function ReapplyTalentEffects(player)
    return TalentSupply.ReapplyTalentEffects(player)
end

local RelicSystem = RogueRelicSystem.Create({
    GLOBAL = GLOBAL,
    SpawnPrefab = SpawnPrefab,
    EnsurePlayerData = EnsurePlayerData,
    ApplyGrowthState = ApplyGrowthState,
    SyncGrowthNetvars = SyncGrowthNetvars,
    IsValidPlayer = IsValidPlayer,
    Announce = Announce,
    SetRPCHandler = SetRPCHandler,
})
RelicSystem.RegisterRPCCallbacks()

local function OfferInitialRelicChoice(player)
    return RelicSystem.OfferInitialRelicChoice(player)
end

function OfferRelicChoice(player, source, day)
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
    REGION_ROUTE_DEFS = REGION_ROUTE_DEFS,
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
    OnSeasonChanged = function(season_id)
        SeasonResultSystem.OnSeasonChanged()
        -- [V2.3] 新赛季开始时抽取全局词缀（赛季级效果，2个）
        if EnvSystem and EnvSystem.SelectGlobalAffixes then
            EnvSystem.SelectGlobalAffixes((GLOBAL.TheWorld and GLOBAL.TheWorld.state.cycles + 1) or 1, 2)
        end
        -- [V2.3] 新赛季重置里程碑领取状态
        if MilestoneSystem and MilestoneSystem.ResetMilestones then
            MilestoneSystem.ResetMilestones()
        end
    end,
    FinalizeSeason = function(day)
        -- [V2.3] 赛季结算时清除全部环境/全局词缀
        if EnvSystem and EnvSystem.ClearAll then
            EnvSystem.ClearAll()
        end
        return SeasonResultSystem.Finalize(day)
    end,
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
    SafeSpawnPrefab = SafeSpawnPrefab,
    SafeCall = SafeCall,
    SafeFindEntities = SafeFindEntities,
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
    CHALLENGE_KIND_NAMES = CHALLENGE_KIND_NAMES,
    EnsurePlayerData = EnsurePlayerData,
    SyncGrowthNetvars = SyncGrowthNetvars,
    GetGlobalModifier = GetGlobalModifier,
    PickWeightedCandidate = PickWeightedCandidate,
    ResolveRuntimePrefab = ResolveRuntimePrefab,
    IsPrefabRegistered = IsPrefabRegistered,
    SpawnPrefab = SpawnPrefab,
    SafeSpawnPrefab = SafeSpawnPrefab,
    SafeCall = SafeCall,
    SafeFindEntities = SafeFindEntities,
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
    SetRPCHandler = SetRPCHandler,
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
    SafeSpawnPrefab = SafeSpawnPrefab,
    SafeCall = SafeCall,
    SafeFindEntities = SafeFindEntities,
    Announce = Announce,
    DropSystem = DropSystem,
    IsMasterSim = function() return GLOBAL.TheWorld and GLOBAL.TheWorld.ismastersim end,
    GetCurrentDay = function() return GLOBAL.TheWorld.state.cycles + 1 end,
    AddComponentPostInit = AddComponentPostInit,
})
-- 注册升级属性持久化钩子：确保武器/护甲/装备的强化数据在存档加载时自动恢复
ShopSystem.InitPersistence()
SetRPCHandler("buy_shop_item", ShopSystem.BuyItem)
SetRPCHandler("buy_black_market_item", ShopSystem.BuyBlackMarketItem)
SetRPCHandler("recycle_item", ShopSystem.RecycleItem)
SetRPCHandler("open_recycle_bin", ShopSystem.OpenRecycleBin)
SetRPCHandler("close_recycle_bin", ShopSystem.CloseRecycleBin)
SetRPCHandler("recycle_all_items", ShopSystem.RecycleAllItems)

-- 函数说明：创建套装效果系统实例。
local SetBonusSystem = RogueSetBonus.Create({
    SET_BONUS_DEFS = RogueConfig.SET_BONUS_DEFS,
    EnsurePlayerData = EnsurePlayerData,
    Announce = Announce,
    DAMAGE_MODIFIER_KEY = CONST.DAMAGE_MODIFIER_KEY,
})

-- 函数说明：创建连锁事件系统实例。
local ChainEventSystem = RogueChainEvent.Create({
    EnsurePlayerData = EnsurePlayerData,
    Announce = Announce,
    SpawnPrefab = SpawnPrefab,
    SafeSpawnPrefab = SafeSpawnPrefab,
    SafeCall = SafeCall,
    SafeFindEntities = SafeFindEntities,
    CollectAlivePlayers = CollectAlivePlayers,
    PickRandom = PickRandom,
    GetWorld = GetWorld,
    IsValidPlayer = IsValidPlayer,
    FindWalkableOffset = FindWalkableOffset,
    PI = PI,
    GLOBAL = GLOBAL,
})

-- 函数说明：创建成就/里程碑系统实例。
local AchievementSystem = RogueAchievement.Create({
    EnsurePlayerData = EnsurePlayerData,
    Announce = Announce,
    SpawnPrefab = SpawnPrefab,
    SafeSpawnPrefab = SafeSpawnPrefab,
    SafeCall = SafeCall,
    SafeFindEntities = SafeFindEntities,
    IsValidPlayer = IsValidPlayer,
    SyncGrowthNetvars = SyncGrowthNetvars,
})

local RuntimeSystem = RogueRuntimeSystem.Create({
    GLOBAL = GLOBAL,
    Config = Config,
    CONST = CONST,
    AllPlayers = AllPlayers,
    SpawnPrefab = SpawnPrefab,
    SafeSpawnPrefab = SafeSpawnPrefab,
    SafeCall = SafeCall,
    SafeFindEntities = SafeFindEntities,
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
    ProgressDailyTaskOnCombo = function(player, combo_count, day)
        -- [V2.3] 连击里程碑检查（冲击波/无敌等自动奖励）
        if ComboSystem and ComboSystem.CheckMilestone and player and player.rogue_data then
            ComboSystem.CheckMilestone(player, player.rogue_data)
        end
        return ProgressionSystem.ProgressDailyTaskOnCombo(player, combo_count, day)
    end,
    GetGlobalModifier = GetGlobalModifier,
    ProgressDailyTaskOnCollect = function(player, amount, day)
        return ProgressionSystem.ProgressDailyTaskOnCollect(player, amount, day)
    end,
    MarkDailyTaskDamageTaken = function(player)
        return ProgressionSystem.MarkDailyTaskDamageTaken(player)
    end,
    ProgressChallenge = ProgressChallenge,
    RewardBounty = RewardBounty,
    OnSeasonKill = OnSeasonKill,
    OnSeasonPlayerDeath = OnSeasonPlayerDeath,
    SyncWaveStateToAllPlayers = SyncWaveStateToAllPlayers,
    ApplyBuff = ApplyBuff,
    CheckTalentTrigger = CheckTalentTrigger,
    ReapplyTalentEffects = ReapplyTalentEffects,
    RegisterSetBonusWatcher = function(player) SetBonusSystem.RegisterEquipmentWatcher(player) end,
    RefreshSetBonuses = function(player)
        SetBonusSystem.RefreshSetBonuses(player)
        if player and player.rogue_data then
            PlayerState.SyncGrowthNetvars(player, player.rogue_data)
        end
    end,
    CheckAchievement = function(player, kind, amount) AchievementSystem.CheckProgress(player, kind, amount) end,
    TriggerChainEvent = function(player, trigger_type) ChainEventSystem.TryTrigger(player, trigger_type) end,
    OfferInitialRelicChoice = OfferInitialRelicChoice,
    CheckRelicTrigger = CheckRelicTrigger,
    GetWaveState = function() return wave_state end,
    ExportWaveState = ExportWaveState,
    ImportWaveState = ImportWaveState,
    ExportSeasonState = ExportSeasonState,
    ImportSeasonState = ImportSeasonState,
    ExportDropState = ExportDropState,
    ImportDropState = ImportDropState,
    ExportMilestoneState = function()
        return MilestoneSystem and MilestoneSystem.ExportState and MilestoneSystem.ExportState() or nil
    end,
    ImportMilestoneState = function(saved)
        if MilestoneSystem and MilestoneSystem.ImportState then
            MilestoneSystem.ImportState(saved)
        end
    end,
    StartWave = StartWave,
    EndWave = EndWave,
    CollectAlivePlayers = CollectAlivePlayers,
    Announce = Announce,
})
RuntimeSystem.RegisterPlayerLifecycle()
RuntimeSystem.RegisterWorldLifecycle()

-- [多人协作系统] --------------------------------------------------------------------

CoopSystem = RogueCoopSystem.Create({
    COOP_BUFF_DEFS = COOP_BUFF_DEFS,
    COOP_REVIVE_COST = COOP_REVIVE_COST,
    COOP_EVENT_DEFS = COOP_EVENT_DEFS,
    IsValidPlayer = IsValidPlayer,
    EnsurePlayerData = EnsurePlayerData,
    SyncGrowthNetvars = SyncGrowthNetvars,
    SpawnPrefab = SpawnPrefab,
    SafeSpawnPrefab = SafeSpawnPrefab,
    SafeCall = SafeCall,
    SafeFindEntities = SafeFindEntities,
    Announce = Announce,
    CollectAlivePlayers = CollectAlivePlayers,
    GLOBAL = GLOBAL,
    PoolCatalog = PoolCatalog,
    PickWeightedCandidate = PickWeightedCandidate,
    FindWalkableOffset = FindWalkableOffset,
    PI = PI,
    GetWaveState = function() return wave_state end,
    DropLoot = DropLoot,
})

-- [赛季里程碑系统] --------------------------------------------------------------------

MilestoneSystem = RogueMilestoneSystem.Create({
    SEASON_MILESTONE_DEFS = SEASON_MILESTONE_DEFS,
    SEASON_MILESTONE_UNLOCK_METRICS = SEASON_MILESTONE_UNLOCK_METRICS,
    EnsurePlayerData = EnsurePlayerData,
    SyncGrowthNetvars = SyncGrowthNetvars,
    IsValidPlayer = IsValidPlayer,
    SpawnDrop = SpawnDrop,
    Announce = Announce,
    PoolCatalog = PoolCatalog,
    PickWeightedCandidate = PickWeightedCandidate,
    SpawnPrefab = SpawnPrefab,
    SafeSpawnPrefab = SafeSpawnPrefab,
    SafeCall = SafeCall,
    SafeFindEntities = SafeFindEntities,
    CollectAlivePlayers = CollectAlivePlayers,
    GrantRelicChoice = OfferRelicChoice,
    GetCurrentDay = function() return GLOBAL.TheWorld.state.cycles + 1 end,
})

-- [配置热更新系统] --------------------------------------------------------------------

local ConfigHotreload = RogueConfigHotreload.Create({
    RogueConfig = RogueConfig,
    GetModConfigData = function(key) return GetModConfigData(key) end,
    Config = Config,
    GetTime = GetTime,
    Announce = Announce,
    WaveSystem = WaveSystem,
    RuntimeSystem = RuntimeSystem,
})
ConfigHotreload.InitSnapshot(Config)

SetRPCHandler("reload_config", function(player)
    if not IsValidPlayer(player) then return end
    local ok, count = ConfigHotreload.ReloadConfig()
    if ok then
        if player.components.talker then
            player.components.talker:Say("配置已热更新！变更 " .. tostring(count or 0) .. " 项")
        end
    end
end)

-- [事件总线订阅] --------------------------------------------------------------------
-- 集中订阅各系统通过 EventBus 发布的事件，驱动日常任务/里程碑进度钩子。
-- 订阅放在所有系统创建之后，闭包运行期读取最新的系统实例引用。
local RogueEventBus = require("rogue/event_bus")

local function CurrentRogueDay()
    return (GLOBAL.TheWorld and GLOBAL.TheWorld.state.cycles + 1) or 1
end

-- 天赋觉醒类日常任务（kind=12）
RogueEventBus.Subscribe("on_talent_select", function(data)
    if data and data.player and data.player:IsValid() then
        ProgressionSystem.ProgressDailyTaskOnTalentPick(data.player, CurrentRogueDay())
    end
end)

-- 遗物收集类日常任务（kind=11）
RogueEventBus.Subscribe("on_relic_pickup", function(data)
    if data and data.player and data.player:IsValid() then
        ProgressionSystem.ProgressDailyTaskOnRelicPick(data.player, CurrentRogueDay())
    end
end)

-- 连击技能类日常任务（kind=13）
RogueEventBus.Subscribe("on_combo_skill", function(data)
    if data and data.player and data.player:IsValid() then
        ProgressionSystem.ProgressDailyTaskOnComboSkill(data.player, CurrentRogueDay())
    end
end)

-- 存活天数类日常任务（kind=9）与赛季里程碑每日检查
RogueEventBus.Subscribe("on_day_changed", function(data)
    local new_day = (data and data.new_day) or CurrentRogueDay()
    for _, player in ipairs(AllPlayers) do
        if player and player:IsValid() and not player:HasTag("playerghost") then
            ProgressionSystem.ProgressDailyTaskOnDayChange(player, new_day)
        end
    end
    -- [V2.3] 环境词缀：每天白天有概率触发（含概率与冷却控制）
    if EnvSystem and EnvSystem.TriggerRandomEnvAffix then
        EnvSystem.TriggerRandomEnvAffix(new_day)
    end
    if MilestoneSystem and MilestoneSystem.CheckMilestones then
        MilestoneSystem.CheckMilestones(new_day)
    end
end)
