--[[
    文件说明：rogue_status_display.lua
    功能：肉鸽模式的状态显示UI组件。
    负责在客户端屏幕右上角渲染玩家的当前击杀、连击、赛季状态、天灾、遗物、悬赏等信息。
    支持按键响应（F1-F4）来进行天赋/补给/路线的选择，以及历史战报的开关。
]]
local Widget = require "widgets/widget"
local Text = require "widgets/text"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local NineSlice = require "widgets/nineslice"
local ScrollableList = require "widgets/scrollablelist"
local RogueConfig = require("rogue/config")
local StateSchema = require("rogue/state_schema")
local RogueShopPanel = require("widgets/rogue_shop_panel")
local TALENT_DEFS = RogueConfig.TALENT_DEFS
local SUPPLY_DEFS = RogueConfig.SUPPLY_DEFS
local RELIC_DEFS = RogueConfig.RELIC_DEFS
local DAILY_KIND_NAMES = RogueConfig.DAILY_KIND_NAMES
local CHALLENGE_KIND_NAMES = RogueConfig.CHALLENGE_KIND_NAMES
local SEASON_PHASE_NAMES = RogueConfig.SEASON_PHASE_NAMES
local SEASON_ROTATION_NAMES = RogueConfig.SEASON_ROTATION_NAMES
local SEASON_OBJECTIVE_NAMES = RogueConfig.SEASON_OBJECTIVE_NAMES
local WAVE_RULE_NAMES = RogueConfig.WAVE_RULE_NAMES
local THREAT_TIER_NAMES = RogueConfig.THREAT_TIER_NAMES
local REGION_ROUTE_NAMES = RogueConfig.REGION_ROUTE_NAMES
local PLAYER_BADGE_NAMES = RogueConfig.PLAYER_BADGE_NAMES
local TEAM_BADGE_NAMES = RogueConfig.TEAM_BADGE_NAMES
local SEASON_STYLE_NAMES = RogueConfig.SEASON_STYLE_NAMES

local MAX_VISIBLE_LINES = 20
local INFO_PAGE_SECONDS = 4

local function PaginateTextByLines(text, max_lines, page_seconds)
    local lines = {}
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end
    if #lines <= max_lines then
        return table.concat(lines, "\n"), #lines
    end
    local pages = math.ceil(#lines / max_lines)
    local t = (GetTime and GetTime() or 0)
    local page = (math.floor(t / math.max(1, page_seconds or INFO_PAGE_SECONDS)) % pages) + 1
    local start_idx = (page - 1) * max_lines + 1
    local end_idx = math.min(#lines, start_idx + max_lines - 1)
    local out = {}
    for i = start_idx, end_idx do
        out[#out + 1] = lines[i]
    end
    out[#out + 1] = string.format("信息页 %d/%d", page, pages)
    return table.concat(out, "\n"), #out
end

local TALENT_LOOKUP = {}
for _, def in ipairs(TALENT_DEFS or {}) do
    TALENT_LOOKUP[def.id] = def
end

local SUPPLY_LOOKUP = {}
for _, def in ipairs(SUPPLY_DEFS or {}) do
    SUPPLY_LOOKUP[def.id] = def
end

local RELIC_LOOKUP = {}
for _, def in ipairs(RELIC_DEFS or {}) do
    RELIC_LOOKUP[def.id] = def
end

local SEASON_GRADE_NAMES = {
    [0] = "未评级",
    [1] = "B",
    [2] = "A",
    [3] = "S",
}

local function DecodeBadges(mask, names)
    local out = {}
    if type(mask) ~= "number" or mask <= 0 then
        return out
    end
    for bit, name in pairs(names or {}) do
        if (mask % (bit * 2)) >= bit then
            table.insert(out, name)
        end
    end
    table.sort(out)
    return out
end

local function GetSeasonStyleTag(ch_done, ch_total, bo_done, bo_total, cata_days, deaths)
    local ch_rate = ch_total > 0 and (ch_done / ch_total) or 0
    local bo_rate = bo_total > 0 and (bo_done / bo_total) or 0
    if ch_rate >= 0.75 and bo_rate >= 0.75 then
        return "全能统筹"
    end
    if ch_rate >= 0.8 and bo_rate <= 0.45 then
        return "试炼主导"
    end
    if bo_rate >= 0.8 and ch_rate <= 0.45 then
        return "赏金主导"
    end
    if cata_days >= 6 and deaths <= 2 then
        return "灾厄韧性"
    end
    if deaths == 0 and (ch_rate >= 0.5 or bo_rate >= 0.5) then
        return "稳健推进"
    end
    return "均衡推进"
end

-- 根据装备积分评定构建流派强度等级
local function GetBuildTier(score)
    if score >= 120 then return "神话" end
    if score >= 80 then return "传说" end
    if score >= 45 then return "史诗" end
    if score >= 20 then return "精良" end
    return "普通"
end

-- 将赛季目标分页展示，以节省屏幕空间
local function ObjectivePages(day, a_cur, a_tar, b_cur, b_tar, c_cur, c_tar, d_cur, d_tar)
    local p1 = {
        { name = SEASON_OBJECTIVE_NAMES[1], cur = a_cur, tar = a_tar },
        { name = SEASON_OBJECTIVE_NAMES[2], cur = b_cur, tar = b_tar },
    }
    local p2 = {
        { name = SEASON_OBJECTIVE_NAMES[3], cur = c_cur, tar = c_tar },
        { name = SEASON_OBJECTIVE_NAMES[4], cur = d_cur, tar = d_tar },
    }
    local t = (GetTime and GetTime() or day or 0)
    if (math.floor(t / 6) % 2) == 0 then
        return 1, p1
    end
    return 2, p2
end

local function ShowLocalHint(msg)
    local p = ThePlayer
    if p and p.components and p.components.talker and p.components.talker.Say then
        p.components.talker:Say(msg, 2.5, true)
        return
    end
    if TheNet and TheNet.SystemMessage then
        TheNet:SystemMessage(msg)
    end
end

local RogueStatusDisplay = Class(Widget, function(self, owner)
    Widget._ctor(self, "RogueStatusDisplay")
    self.owner = owner
    
    -- 面板配置参数
    self.panel_width = 256
    self.panel_height = 384

    -- 缓存上一次快照，用于去重刷新
    self._cached_snapshot = nil
    -- dirty事件监听器函数引用
    self._netvar_listener = nil
    -- dirty事件节流计时器（避免同一帧多次触发）
    self._dirty_pending = false
    -- 当前标签页: "status" 或 "bonus"
    self.current_tab = "status"
    -- 加成标签页缓存的快照（独立于状态标签页）
    self._cached_bonus_text = nil
    -- 标签页切换待刷新标志
    self._tab_switch_pending = false

    -- topright_root 外层已有 ANCHOR_RIGHT + ANCHOR_TOP
    -- 子节点原点在屏幕右上角，需要向左偏移面板宽度+边距
    -- 额外偏移避开官方右上角UI（时钟、状态栏等）
    self:SetPosition(-self.panel_width - 80, -self.panel_height / 2 - 60, 0)
    
    -- 主显示面板
    self.info_panel = self:AddChild(Widget("info_panel"))
    self.info_panel:SetPosition(0, 0, 0)
    self.info_panel:Hide()
    
    -- 九宫格背景面板（替代固定背景图）
    -- 优先使用自定义九宫格纹理，失败时回退到官方 fepanels
    local ns_ok, ns_result = pcall(function()
        return self.info_panel:AddChild(NineSlice(
            "images/rogue_panel.xml",
            "topleft.tex", "top.tex", "topright.tex",
            "left.tex", "center.tex", "right.tex",
            "bottomleft.tex", "bottom.tex", "bottomright.tex"
        ))
    end)
    if ns_ok and ns_result then
        self.bg_frame = ns_result
    else
        self.bg_frame = self.info_panel:AddChild(NineSlice("images/fepanels.xml"))
    end
    self.bg_frame:SetSize(self.panel_width, self.panel_height)
    self.bg_frame:SetPosition(0, 0, 0)

    -- 顶部标题
    self.header_text = self.info_panel:AddChild(Text(TITLEFONT, 30))
    self.header_text:SetString("肉 鸽 信 息")
    self.header_text:SetColour(0.9, 0.9, 0.9, 1)
    self.header_text:SetPosition(0, self.panel_height / 2 - 45, 0)

    -- 分割线 - 标题下方
    self.divider = self.info_panel:AddChild(Image("images/global.xml", "square.tex"))
    self.divider:SetSize(self.panel_width - 80, 2)
    self.divider:SetTint(0.8, 0.8, 0.8, 0.5)
    self.divider:SetPosition(0, self.panel_height / 2 - 65, 0)

    -- 滚动列表容器
    -- ScrollableList 内部布局：
    --   滑动块初始 y = list_height/2 - 40
    --   子项起始 y = list_height/2 - 20（比滑动块低20px）
    -- 我们需要让滑动块和第一项文字都在分割线下方
    local list_width = math.max(self.panel_width - 40, 40)
    local list_height = math.max(self.panel_height - 130, 40)
    -- 分割线 y = panel_height/2 - 65
    -- 让滑动块在分割线下方30px处
    local scrollbar_target_y = self.panel_height / 2 - 95
    local list_offset_y = scrollbar_target_y - (list_height / 2 - 40)

    self.list_root = self.info_panel:AddChild(Widget("list_root"))
    self.list_root:SetPosition(0, list_offset_y, 0)

    self.scroll_list = self.list_root:AddChild(ScrollableList({}, list_width, list_height, 40, 40))
    self.scroll_list:SetPosition(0, 0, 0)
    
    -- 历史战报背景（使用九宫格面板替代纯色方块）
    local hist_ok, hist_result = pcall(function()
        return self:AddChild(NineSlice(
            "images/rogue_panel.xml",
            "topleft.tex", "top.tex", "topright.tex",
            "left.tex", "center.tex", "right.tex",
            "bottomleft.tex", "bottom.tex", "bottomright.tex"
        ))
    end)
    if hist_ok and hist_result then
        self.history_bg = hist_result
    else
        self.history_bg = self:AddChild(NineSlice("images/fepanels.xml"))
    end
    self.history_bg:SetSize(600, 400)
    self.history_bg:SetTint(0, 0, 0, 0.85)
    self.history_bg:SetPosition(-300, -200, 0)
    self.history_bg:Hide()

    self.history_title = self.history_bg:AddChild(Text(TITLEFONT, 40))
    self.history_title:SetPosition(0, 160, 0)
    self.history_title:SetString("肉 鸽 历 史 战 报")
    self.history_title:SetColour(1, 0.8, 0.1, 1)

    self.history_text = self.history_bg:AddChild(Text(UIFONT, 25))
    self.history_text:SetPosition(0, -30, 0)
    self.history_text:SetHAlign(ANCHOR_MIDDLE)
    self.history_text:SetVAlign(ANCHOR_MIDDLE)
    
    self.history_bg:SetClickable(false)

    self.history_detail_index = 0
    self.key_handlers = {
        TheInput:AddKeyUpHandler(KEY_F1, function() self:TryPickAction(1) end),
        TheInput:AddKeyUpHandler(KEY_F2, function() self:TryPickAction(2) end),
        TheInput:AddKeyUpHandler(KEY_F3, function() self:TryPickAction(3) end),
        TheInput:AddKeyDownHandler(KEY_F4, function() self:CycleHistoryDetail() end),
    }
    
    -- 商店按钮
    self.shop_btn = self:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_over.tex"))
    self.shop_btn:SetPosition(-80, -self.panel_height / 2 - 30)
    self.shop_btn:SetText("商店")
    
    self.shop_btn.GetTooltip = function(btn)
        if btn.focus then
            local rmb = TheInput:GetLocalizedControl(TheInput:GetControllerID(), CONTROL_SECONDARY)
            local lmb = TheInput:GetLocalizedControl(TheInput:GetControllerID(), CONTROL_PRIMARY)
            return "商店\n" .. lmb .. ": 打开\n" .. rmb .. ": 右键拖动"
        end
    end
    
    self.shop_btn:SetOnClick(function()
        if self.shop_panel then
            if self.shop_panel:IsVisible() then
                self.shop_panel:Hide()
            else
                self.shop_panel:Show()
                self.shop_panel:ShowTab("buy")
            end
        end
    end)
    
    local old_OnControl = self.shop_btn.OnControl
    self.shop_btn.OnControl = function(btn, control, down)
        if control == CONTROL_SECONDARY then
            if down then
                btn.dragging = true
                btn.drag_start_pos = btn:GetPosition()
                btn.drag_start_mouse = TheInput:GetScreenPosition()
                return true
            end
        end
        return old_OnControl(btn, control, down)
    end

    -- 新的肉鸽信息显示开关按钮
    self.info_btn = self:AddChild(ImageButton("images/rogue_icon.xml", "rogue_icon.tex"))
    self.info_btn:SetPosition(20, -self.panel_height / 2 - 30)
    self.info_btn:SetScale(0.12, 0.12, 1) -- 调整图标大小以符合游戏美观
    
    self.info_btn.GetTooltip = function(btn)
        if btn.focus then
            local rmb = TheInput:GetLocalizedControl(TheInput:GetControllerID(), CONTROL_SECONDARY)
            local lmb = TheInput:GetLocalizedControl(TheInput:GetControllerID(), CONTROL_PRIMARY)
            return "肉鸽信息\n" .. lmb .. ": 打开/隐藏\n" .. rmb .. ": 右键拖动"
        end
    end
    
    self.info_btn:SetOnClick(function()
        if self.info_panel:IsVisible() then
            self.info_panel:Hide()
        else
            self.info_panel:Show()
        end
    end)
    
    local old_info_OnControl = self.info_btn.OnControl
    self.info_btn.OnControl = function(btn, control, down)
        if control == CONTROL_SECONDARY then
            if down then
                btn.dragging = true
                btn.drag_start_pos = btn:GetPosition()
                btn.drag_start_mouse = TheInput:GetScreenPosition()
                return true
            end
        end
        return old_info_OnControl(btn, control, down)
    end

    -- 标签按钮（状态/加成），放置在面板顶部
    self.tab_status_btn = self.info_panel:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_over.tex"))
    self.tab_status_btn:SetPosition(-40, self.panel_height / 2 - 15, 0)
    self.tab_status_btn:SetText("状态")
    self.tab_status_btn:SetScale(0.7, 0.7, 1)
    self.tab_status_btn:SetTextColour(1, 0.8, 0.2, 1)
    self.tab_status_btn:SetOnClick(function()
        self:SwitchTab("status")
    end)

    self.tab_bonus_btn = self.info_panel:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_over.tex"))
    self.tab_bonus_btn:SetPosition(40, self.panel_height / 2 - 15, 0)
    self.tab_bonus_btn:SetText("加成")
    self.tab_bonus_btn:SetScale(0.7, 0.7, 1)
    self.tab_bonus_btn:SetTextColour(1, 1, 1, 1)
    self.tab_bonus_btn:SetOnClick(function()
        self:SwitchTab("bonus")
    end)

    self:StartUpdating()

    -- 注册dirty事件监听器，替代OnUpdate中的每帧轮询
    -- 当服务端网络变量变更时，设置节流标志，在下一帧OnUpdate中批量刷新UI
    if self.owner and self.owner.ListenForEvent then
        self._netvar_listener = function()
            self._dirty_pending = true
        end
        self.owner:ListenForEvent("rogue_dirty", self._netvar_listener)
        -- 首次加载时立即触发一次刷新
        self._dirty_pending = true
    end
end)

function RogueStatusDisplay:TryPickRoute(slot)
    if not self.owner or not self.owner:IsValid() then return false end
    if not (self.owner.rogue_route_pending and self.owner.rogue_route_pending:value()) then return false end
    if slot < 1 or slot > 2 then return false end
    if not (MOD_RPC and MOD_RPC["rogue_mode"] and MOD_RPC["rogue_mode"]["pick_route"]) then return false end
    SendModRPCToServer(MOD_RPC["rogue_mode"]["pick_route"], slot)
    return true
end

-- 根据优先级（路线）尝试执行操作（遗物/天赋/补给已由弹窗面板处理）
function RogueStatusDisplay:TryPickAction(slot)
    self:TryPickRoute(slot)
end

function RogueStatusDisplay:OnRemoveFromEntity()
    -- 移除dirty事件监听器
    if self.owner and self._netvar_listener then
        self.owner:RemoveEventCallback("rogue_dirty", self._netvar_listener)
        self._netvar_listener = nil
    end
    if self.key_handlers then
        for _, handler in ipairs(self.key_handlers) do
            if handler and handler.Remove then
                handler:Remove()
            end
        end
        self.key_handlers = nil
    end
end

-- 函数说明：屏幕尺寸变化时重新调整面板布局
-- topright_root 的 SCALEMODE_PROPORTIONAL 会自动处理缩放
function RogueStatusDisplay:OnScreenSizeChanged()
    self:SetPosition(-self.panel_width - 80, -self.panel_height / 2 - 60, 0)
end

-- 函数说明：切换到指定标签页，同时显示面板
function RogueStatusDisplay:SwitchTab(tab)
    if self.current_tab == tab then return end
    self.current_tab = tab
    self:UpdateTabButtons()
    if self.header_text then
        self.header_text:SetString(self.current_tab == "status" and "肉 鸽 信 息" or "肉 鸽 加 成")
    end
    if not self.info_panel:IsVisible() then
        self.info_panel:Show()
    end
    self._cached_bonus_text = nil
    self.last_bonus_hash = nil
    self.last_content_hash = nil
    self._tab_switch_pending = true
    self._dirty_pending = true
end

-- 函数说明：更新标签按钮的视觉状态（高亮当前激活的标签）
function RogueStatusDisplay:UpdateTabButtons()
    if self.tab_status_btn then
        if self.current_tab == "status" then
            self.tab_status_btn:SetTextColour(1, 0.8, 0.2, 1)
        else
            self.tab_status_btn:SetTextColour(1, 1, 1, 1)
        end
    end
    if self.tab_bonus_btn then
        if self.current_tab == "bonus" then
            self.tab_bonus_btn:SetTextColour(1, 0.8, 0.2, 1)
        else
            self.tab_bonus_btn:SetTextColour(1, 1, 1, 1)
        end
    end
end

function RogueStatusDisplay:CycleHistoryDetail()
    if not self.owner or not self.owner:IsValid() then
        return
    end
    if self.history_detail_index and self.history_detail_index > 0 then
        self.history_detail_index = 0
        self.history_bg:Hide()
        ShowLocalHint("历史战报已关闭")
    else
        self.history_detail_index = 1
        self.history_bg:Show()
        ShowLocalHint("已展开历史战报面板")
    end
end

function RogueStatusDisplay:OnUpdate(dt)
    -- 分辨率变化检测：当屏幕尺寸改变时重新调整面板位置
    local screen_w, screen_h = TheSim:GetScreenSize()
    if self._last_screen_w ~= screen_w or self._last_screen_h ~= screen_h then
        self._last_screen_w = screen_w
        self._last_screen_h = screen_h
        self:OnScreenSizeChanged()
    end

    -- 处理按钮拖拽（每帧更新起始位置，确保按钮跟随鼠标；检测右键松开防止粘连）
    if self.shop_btn and self.shop_btn.dragging then
        if not TheInput:IsControlPressed(CONTROL_SECONDARY) then
            self.shop_btn.dragging = false
        else
            local current_mouse = TheInput:GetScreenPosition()
            local dx = current_mouse.x - self.shop_btn.drag_start_mouse.x
            local dy = current_mouse.y - self.shop_btn.drag_start_mouse.y
            local scale = TheFrontEnd and TheFrontEnd:GetHUDScale() or 1
            self.shop_btn:SetPosition(self.shop_btn.drag_start_pos.x + dx / scale, self.shop_btn.drag_start_pos.y + dy / scale, 0)
            self.shop_btn.drag_start_pos = self.shop_btn:GetPosition()
            self.shop_btn.drag_start_mouse = current_mouse
        end
    end
    
    if self.info_btn and self.info_btn.dragging then
        if not TheInput:IsControlPressed(CONTROL_SECONDARY) then
            self.info_btn.dragging = false
        else
            local current_mouse = TheInput:GetScreenPosition()
            local dx = current_mouse.x - self.info_btn.drag_start_mouse.x
            local dy = current_mouse.y - self.info_btn.drag_start_mouse.y
            local scale = TheFrontEnd and TheFrontEnd:GetHUDScale() or 1
            self.info_btn:SetPosition(self.info_btn.drag_start_pos.x + dx / scale, self.info_btn.drag_start_pos.y + dy / scale, 0)
            self.info_btn.drag_start_pos = self.info_btn:GetPosition()
            self.info_btn.drag_start_mouse = current_mouse
        end
    end

    -- 处理dirty事件节流：在OnUpdate中执行延迟的UI刷新
    if self._dirty_pending then
        self._dirty_pending = false
        self:RefreshFromNetvars()
    end
end

-- 函数说明：从网络变量刷新UI（由dirty事件或节流触发）
-- 替代原OnUpdate中的每帧轮询，仅在数据变更时调用
function RogueStatusDisplay:RefreshFromNetvars()
    if not self.owner or not self.owner:IsValid() then return end
    
    local state = StateSchema.ReadFromNetvars(self.owner)
    local snapshot_changed = StateSchema.SnapshotChanged(state, self._cached_snapshot)
    local tab_switched = self._tab_switch_pending
    self._tab_switch_pending = false

    if not snapshot_changed and not tab_switched then
        return
    end
    self._cached_snapshot = state

    if self.current_tab == "bonus" then
        self:RefreshBonusTab(state)
        return
    end
    local kills = state.rogue_kills or 0
    local points = state.rogue_points or 0
    local dmg_bonus = state.rogue_dmg_bonus or 0
    local hp_bonus = state.rogue_hp_bonus or 0
    local combo = state.rogue_combo_count or 0
    local daily_progress = state.rogue_daily_progress or 0
    local daily_target = state.rogue_daily_target or 0
    local daily_kind = state.rogue_daily_kind or 0
    local daily_done = state.rogue_daily_done == true
    local talent_pending = state.rogue_talent_pending == true
    local talent_a = state.rogue_talent_a or 0
    local talent_b = state.rogue_talent_b or 0
    local talent_c = state.rogue_talent_c or 0
    local wave_rule_active = state.rogue_wave_rule_active == true
    local wave_rule_id = state.rogue_wave_rule_id or 0
    local threat_tier = state.rogue_threat_tier or 1
    local threat_reward_pct = state.rogue_threat_reward_pct or 0
    local route_id = state.rogue_route_id or 0
    local route_pending = state.rogue_route_pending == true
    local route_a = state.rogue_route_a or 0
    local route_b = state.rogue_route_b or 0
    local bounty_active = state.rogue_bounty_active == true
    local bounty_progress = state.rogue_bounty_progress or 0
    local bounty_target = state.rogue_bounty_target or 0
    local supply_pending = state.rogue_supply_pending == true
    local supply_a = state.rogue_supply_a or 0
    local supply_b = state.rogue_supply_b or 0
    local supply_c = state.rogue_supply_c or 0
    local relic_pending = state.rogue_relic_pending == true
    local relic_a = state.rogue_relic_a or 0
    local relic_b = state.rogue_relic_b or 0
    local relic_c = state.rogue_relic_c or 0
    local relic_count = state.rogue_relic_count or 0
    local relic_synergy_count = state.rogue_relic_synergy_count or 0
    local challenge_active = state.rogue_challenge_active == true
    local challenge_progress = state.rogue_challenge_progress or 0
    local challenge_target = state.rogue_challenge_target or 0
    local challenge_kind = state.rogue_challenge_kind or 0
    local season_phase = state.rogue_season_phase or 1
    local season_day_left = state.rogue_season_day_left or 0
    local season_day_limit = state.rogue_season_day_limit or 0
    local season_final_night = state.rogue_season_final_night == true
    local season_last_score = state.rogue_season_last_score or 0
    local season_best_score = state.rogue_season_best_score or 0
    local season_last_rank = state.rogue_season_last_rank or 0
    local season_last_style = state.rogue_season_last_style or 0
    local season_last_badges = state.rogue_season_last_badges or 0
    local season_last_team_badges = state.rogue_season_last_team_badges or 0
    local hist1_score = state.rogue_hist1_score or 0
    local hist1_rank = state.rogue_hist1_rank or 0
    local hist1_grade = state.rogue_hist1_grade or 0
    local hist1_badges = state.rogue_hist1_badges or 0
    local hist1_kills = state.rogue_hist1_kills or 0
    local hist1_boss = state.rogue_hist1_boss or 0
    local hist1_deaths = state.rogue_hist1_deaths or 0
    local hist1_build = state.rogue_hist1_build or 0
    local hist1_route = state.rogue_hist1_route or 0
    local hist1_cata_days = state.rogue_hist1_cata_days or 0
    local hist1_ch_done = state.rogue_hist1_ch_done or 0
    local hist1_ch_total = state.rogue_hist1_ch_total or 0
    local hist1_bo_done = state.rogue_hist1_bo_done or 0
    local hist1_bo_total = state.rogue_hist1_bo_total or 0
    local hist1_style = state.rogue_hist1_style or 0
    local hist2_score = state.rogue_hist2_score or 0
    local hist2_rank = state.rogue_hist2_rank or 0
    local hist2_grade = state.rogue_hist2_grade or 0
    local hist2_badges = state.rogue_hist2_badges or 0
    local hist2_kills = state.rogue_hist2_kills or 0
    local hist2_boss = state.rogue_hist2_boss or 0
    local hist2_deaths = state.rogue_hist2_deaths or 0
    local hist2_build = state.rogue_hist2_build or 0
    local hist2_route = state.rogue_hist2_route or 0
    local hist2_cata_days = state.rogue_hist2_cata_days or 0
    local hist2_ch_done = state.rogue_hist2_ch_done or 0
    local hist2_ch_total = state.rogue_hist2_ch_total or 0
    local hist2_bo_done = state.rogue_hist2_bo_done or 0
    local hist2_bo_total = state.rogue_hist2_bo_total or 0
    local hist2_style = state.rogue_hist2_style or 0
    local hist3_score = state.rogue_hist3_score or 0
    local hist3_rank = state.rogue_hist3_rank or 0
    local hist3_grade = state.rogue_hist3_grade or 0
    local hist3_badges = state.rogue_hist3_badges or 0
    local hist3_kills = state.rogue_hist3_kills or 0
    local hist3_boss = state.rogue_hist3_boss or 0
    local hist3_deaths = state.rogue_hist3_deaths or 0
    local hist3_build = state.rogue_hist3_build or 0
    local hist3_route = state.rogue_hist3_route or 0
    local hist3_cata_days = state.rogue_hist3_cata_days or 0
    local hist3_ch_done = state.rogue_hist3_ch_done or 0
    local hist3_ch_total = state.rogue_hist3_ch_total or 0
    local hist3_bo_done = state.rogue_hist3_bo_done or 0
    local hist3_bo_total = state.rogue_hist3_bo_total or 0
    local hist3_style = state.rogue_hist3_style or 0
    local season_rotation = state.rogue_season_rotation or 0
    local season_medals = state.rogue_season_medals or 0
    local season_grade = state.rogue_season_grade or 0
    local season_obj_done = state.rogue_obj_done or 0
    local obj_a_cur = state.rogue_obj_a_cur or 0
    local obj_a_tar = state.rogue_obj_a_tar or 0
    local obj_b_cur = state.rogue_obj_b_cur or 0
    local obj_b_tar = state.rogue_obj_b_tar or 0
    local obj_c_cur = state.rogue_obj_c_cur or 0
    local obj_c_tar = state.rogue_obj_c_tar or 0
    local obj_d_cur = state.rogue_obj_d_cur or 0
    local obj_d_tar = state.rogue_obj_d_tar or 0
    local loot_pity = state.rogue_loot_pity or 0
    local build_score = state.rogue_build_score or 0
    local day = (TheWorld and TheWorld.state and TheWorld.state.cycles + 1) or 1

    local combo_mult = 1 + math.floor(math.max(0, combo - 1) / 5) * 0.05
    if combo == 0 then combo_mult = 1 end

    local daily_name = DAILY_KIND_NAMES[daily_kind] or "未激活"
    local daily_text = daily_done and "已完成" or (daily_progress .. "/" .. daily_target)

    local str = string.format("第%d天  赛季:%s  轮换:%s\n剩余:%d/%d\n击杀:%d  积分:%d\n连杀:%d x%.2f  伤害:+%d%%\n生命:+%d  任务:%s %s",
        day,
        SEASON_PHASE_NAMES[season_phase] or "未知",
        SEASON_ROTATION_NAMES[season_rotation] or "默认",
        season_day_left,
        season_day_limit,
        kills,
        points,
        combo,
        combo_mult,
        math.floor(dmg_bonus * 100),
        hp_bonus,
        daily_name,
        daily_text
    )

    if wave_rule_active then
        str = str .. string.format("\n轮次事件:%s", WAVE_RULE_NAMES[wave_rule_id] or "未知")
    end
    str = str .. string.format("\n危险阶梯:%s(+%d%%,轮换修正)", THREAT_TIER_NAMES[threat_tier] or "稳态", threat_reward_pct)
    if route_id > 0 then
        str = str .. string.format("\n路线:%s", REGION_ROUTE_NAMES[route_id] or "未知")
    end
    if route_pending then
        str = str .. string.format("\n路线投票(F1/F2):\n1.%s\n2.%s",
            REGION_ROUTE_NAMES[route_a] or "未知路线",
            REGION_ROUTE_NAMES[route_b] or "未知路线")
    end
    if bounty_active then
        str = str .. string.format("\n通缉进度:%d/%d", bounty_progress, bounty_target)
    end
    str = str .. string.format("\n遗物数:%d  协同:%d", relic_count, relic_synergy_count)
    if challenge_active then
        str = str .. string.format("\n挑战房:%s %d/%d", CHALLENGE_KIND_NAMES[challenge_kind] or "未知", challenge_progress, challenge_target)
    end
    if season_final_night then
        str = str .. "\n终局夜进行中"
    end
    if season_phase >= 5 then
        str = str .. string.format("\n赛季结算:分数%d  排名#%d  最高%d", season_last_score, season_last_rank, season_best_score)
        str = str .. string.format("\n赛季评级:%s  勋章:%d  构筑:%s(%d)", SEASON_GRADE_NAMES[season_grade] or "未评级", season_medals, GetBuildTier(build_score), build_score)
        if season_last_style > 0 then
            str = str .. string.format("\n赛季风格:%s", SEASON_STYLE_NAMES[season_last_style] or "均衡推进")
        end
        local pb = DecodeBadges(season_last_badges, PLAYER_BADGE_NAMES)
        local tb = DecodeBadges(season_last_team_badges, TEAM_BADGE_NAMES)
        if #pb > 0 then
            str = str .. string.format("\n个人徽章:%s", table.concat(pb, "、"))
        end
        if #tb > 0 then
            str = str .. string.format("\n团队徽章:%s", table.concat(tb, "、"))
        end
    else
        str = str .. string.format("\n保底层数:%d  构筑:%s(%d)", loot_pity, GetBuildTier(build_score), build_score)
    end

    local show_history = self.history_detail_index and self.history_detail_index > 0
    if show_history then
        local hstr = ""
        
        -- 历史1
        if hist1_score > 0 or hist1_kills > 0 then
            local tag = (hist1_style > 0 and (SEASON_STYLE_NAMES[hist1_style] or "均衡推进")) or GetSeasonStyleTag(hist1_ch_done, hist1_ch_total, hist1_bo_done, hist1_bo_total, hist1_cata_days, hist1_deaths)
            hstr = hstr .. string.format("【上赛季历史】 [%s] 分:%d 排名#%d 评级:%s 徽章:%d\n", tag, hist1_score, hist1_rank, SEASON_GRADE_NAMES[hist1_grade] or "未评级", hist1_badges)
            hstr = hstr .. string.format("击杀:%d Boss:%d 死亡:%d 构筑:%d 路线偏好:%s 天灾天数:%d\n", hist1_kills, hist1_boss, hist1_deaths, hist1_build, REGION_ROUTE_NAMES[hist1_route] or "无", hist1_cata_days)
            local ch_rate = hist1_ch_total > 0 and math.floor((hist1_ch_done * 100) / hist1_ch_total + 0.5) or 0
            local bo_rate = hist1_bo_total > 0 and math.floor((hist1_bo_done * 100) / hist1_bo_total + 0.5) or 0
            hstr = hstr .. string.format("挑战:%d/%d(%d%%) 悬赏:%d/%d(%d%%)\n", hist1_ch_done, hist1_ch_total, ch_rate, hist1_bo_done, hist1_bo_total, bo_rate)
        else
            hstr = hstr .. "【上赛季历史】 暂无记录\n\n\n"
        end
        hstr = hstr .. "\n"

        -- 历史2
        if hist2_score > 0 or hist2_kills > 0 then
            local tag = (hist2_style > 0 and (SEASON_STYLE_NAMES[hist2_style] or "均衡推进")) or GetSeasonStyleTag(hist2_ch_done, hist2_ch_total, hist2_bo_done, hist2_bo_total, hist2_cata_days, hist2_deaths)
            hstr = hstr .. string.format("【历史②】 [%s] 分:%d 排名#%d 评级:%s 徽章:%d\n", tag, hist2_score, hist2_rank, SEASON_GRADE_NAMES[hist2_grade] or "未评级", hist2_badges)
            hstr = hstr .. string.format("击杀:%d Boss:%d 死亡:%d 构筑:%d 路线偏好:%s 天灾天数:%d\n", hist2_kills, hist2_boss, hist2_deaths, hist2_build, REGION_ROUTE_NAMES[hist2_route] or "无", hist2_cata_days)
            local ch_rate = hist2_ch_total > 0 and math.floor((hist2_ch_done * 100) / hist2_ch_total + 0.5) or 0
            local bo_rate = hist2_bo_total > 0 and math.floor((hist2_bo_done * 100) / hist2_bo_total + 0.5) or 0
            hstr = hstr .. string.format("挑战:%d/%d(%d%%) 悬赏:%d/%d(%d%%)\n", hist2_ch_done, hist2_ch_total, ch_rate, hist2_bo_done, hist2_bo_total, bo_rate)
        else
            hstr = hstr .. "【历史②】 暂无记录\n\n\n"
        end
        hstr = hstr .. "\n"

        -- 历史3
        if hist3_score > 0 or hist3_kills > 0 then
            local tag = (hist3_style > 0 and (SEASON_STYLE_NAMES[hist3_style] or "均衡推进")) or GetSeasonStyleTag(hist3_ch_done, hist3_ch_total, hist3_bo_done, hist3_bo_total, hist3_cata_days, hist3_deaths)
            hstr = hstr .. string.format("【历史③】 [%s] 分:%d 排名#%d 评级:%s 徽章:%d\n", tag, hist3_score, hist3_rank, SEASON_GRADE_NAMES[hist3_grade] or "未评级", hist3_badges)
            hstr = hstr .. string.format("击杀:%d Boss:%d 死亡:%d 构筑:%d 路线偏好:%s 天灾天数:%d\n", hist3_kills, hist3_boss, hist3_deaths, hist3_build, REGION_ROUTE_NAMES[hist3_route] or "无", hist3_cata_days)
            local ch_rate = hist3_ch_total > 0 and math.floor((hist3_ch_done * 100) / hist3_ch_total + 0.5) or 0
            local bo_rate = hist3_bo_total > 0 and math.floor((hist3_bo_done * 100) / hist3_bo_total + 0.5) or 0
            hstr = hstr .. string.format("挑战:%d/%d(%d%%) 悬赏:%d/%d(%d%%)\n", hist3_ch_done, hist3_ch_total, ch_rate, hist3_bo_done, hist3_bo_total, bo_rate)
        else
            hstr = hstr .. "【历史③】 暂无记录\n\n\n"
        end

        self.history_text:SetString(hstr)
    end

    str = str .. "\nF4历史"
    str = str .. string.format("\n赛季目标:%d/4", season_obj_done)
    local obj_page, page_rows = ObjectivePages(day, obj_a_cur, obj_a_tar, obj_b_cur, obj_b_tar, obj_c_cur, obj_c_tar, obj_d_cur, obj_d_tar)
    str = str .. string.format(" 页%d/2", obj_page)
    for _, row in ipairs(page_rows) do
        str = str .. string.format("\n%s %d/%d", row.name or "目标", row.cur or 0, row.tar or 0)
    end


    
    
    local new_content_hash = str
    if self.last_content_hash ~= new_content_hash then
        self.last_content_hash = new_content_hash
        
        local widgets = {}
        local widget_index = 1
        
        for raw_line in (str .. "\n"):gmatch("(.-)\n") do
            if raw_line and raw_line ~= "" then
                -- 文字颜色
                local r, g, b, a = 1, 1, 1, 1
                if season_phase >= 5 then
                    r, g, b = 0.82, 1, 0.86
                elseif raw_line:find("遗物抉择") or raw_line:find("天赋候选") or raw_line:find("夜晚补给") then
                    r, g, b = 0.85, 0.95, 1
                end
                
                -- 函数说明：创建支持自动换行的文本组件
                -- ScrollableList 会自动设置 Widget w 的位置：x = -list_width/2
                -- Widget 原点在列表左边界，Text 应从原点向右渲染
                local w = Widget("line_"..widget_index)

                local text_width = math.max(self.panel_width - 60, 30)
                local text_height = 40
                local t = w:AddChild(Text(UIFONT, 22))
                t:SetColour(r, g, b, a)
                t:SetString(raw_line)
                t:SetRegionSize(text_width, text_height)
                t:EnableWordWrap(true)
                t:SetHAlign(ANCHOR_LEFT)
                t:SetVAlign(ANCHOR_TOP)
                -- Text 盒子中心默认在 Widget 原点
                -- 向右偏移 text_width/2 让左边界对齐 Widget 原点（列表左边界）
                -- 向下偏移 text_height/2 让文字中心与滚动条滑动块对齐
                -- ScrollableList 第一项 Widget 在 y=height/2-20，滑动块在 y=height/2-40
                -- 两者差20px，所以文字需要从 Widget 原点向下偏移 text_height/2
                t:SetPosition(text_width / 2, -text_height / 2)
                
                w.focus_forward = t
                widgets[widget_index] = w
                widget_index = widget_index + 1
            end
        end
        
        self.scroll_list:SetList(widgets)
    end

end

-- 函数说明：刷新加成标签页内容，从netvar读取服务端生成的加成摘要文本
function RogueStatusDisplay:RefreshBonusTab(state)
    if not state then return end

    local bonus_text = state.rogue_bonus_text or ""
    if bonus_text == self._cached_bonus_text then
        return
    end
    self._cached_bonus_text = bonus_text

    if bonus_text == "" then
        bonus_text = "暂无加成"
    end

    local new_content_hash = bonus_text
    if self.last_bonus_hash ~= new_content_hash then
        self.last_bonus_hash = new_content_hash

        local widgets = {}
        local widget_index = 1

        for raw_line in (bonus_text .. "\n"):gmatch("(.-)\n") do
            if raw_line and raw_line ~= "" then
                local r, g, b, a = 1, 1, 1, 1
                if raw_line:find("═══攻击═══") then
                    r, g, b = 1, 0.6, 0.4
                elseif raw_line:find("═══防御═══") then
                    r, g, b = 0.4, 0.7, 1
                elseif raw_line:find("═══辅助═══") then
                    r, g, b = 0.4, 1, 0.6
                elseif raw_line:find("═══恢复═══") then
                    r, g, b = 1, 1, 0.5
                elseif raw_line:find("═══天赋═══") then
                    r, g, b = 0.8, 0.5, 1
                elseif raw_line:find("═══遗物═══") then
                    r, g, b = 1, 0.85, 0.3
                elseif raw_line:find("═══套装═══") then
                    r, g, b = 0.3, 1, 0.8
                elseif raw_line:find("═══构筑═══") then
                    r, g, b = 1, 0.7, 0.9
                elseif raw_line:find("协同:") then
                    r, g, b = 0.5, 1, 1
                elseif raw_line:find("构筑:") then
                    r, g, b = 1, 0.9, 0.7
                end

                local w = Widget("bonus_line_"..widget_index)
                local text_width = math.max(self.panel_width - 60, 30)
                local text_height = 40
                local t = w:AddChild(Text(UIFONT, 22))
                t:SetColour(r, g, b, a)
                t:SetString(raw_line)
                t:SetRegionSize(text_width, text_height)
                t:EnableWordWrap(true)
                t:SetHAlign(ANCHOR_LEFT)
                t:SetVAlign(ANCHOR_TOP)
                t:SetPosition(text_width / 2, -text_height / 2)

                w.focus_forward = t
                widgets[widget_index] = w
                widget_index = widget_index + 1
            end
        end

        self.scroll_list:SetList(widgets)
    end
end

return RogueStatusDisplay
