--[[
    文件说明：rogue_status_display.lua
    功能：肉鸽模式的状态显示UI组件。
    负责在客户端屏幕右上角渲染玩家的当前击杀、连击、赛季状态、天灾、遗物、悬赏等信息。
    支持按键响应（F1-F4）来进行天赋/补给/路线的选择，以及历史战报的开关。
]]
local Widget = require "widgets/widget"
local Text = require "widgets/text"
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
local CATASTROPHE_NAMES = RogueConfig.CATASTROPHE_NAMES
local REGION_ROUTE_NAMES = RogueConfig.REGION_ROUTE_NAMES
local PLAYER_BADGE_NAMES = RogueConfig.PLAYER_BADGE_NAMES
local TEAM_BADGE_NAMES = RogueConfig.TEAM_BADGE_NAMES
local SEASON_STYLE_NAMES = RogueConfig.SEASON_STYLE_NAMES

local CATASTROPHE_TIER_NAMES = {
    [1] = "初阶",
    [2] = "中阶",
    [3] = "末阶",
}

local CATASTROPHE_EFFECT_TEXTS = {
    [1] = "降雨增湿+腐蚀，敌人附带潮湿压制",
    [2] = "暗影扰动+理智压制，敌人追猎更频繁",
    [3] = "红月落雷+场地压迫，敌人周期冲刺爆发",
}

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
    -- 函数说明：初始化右上角状态面板，避免遮挡左侧制作栏交互
    Widget._ctor(self, "RogueStatusDisplay")
    self.owner = owner
    
    self:SetPosition(0, 0, 0)
    
    -- 背景 (可选，简单点先只用文字)
    -- self.bg = self:AddChild(Image("images/global.xml", "square.tex"))
    
    -- 文字显示
    self.text = self:AddChild(Text(BODYTEXTFONT, 30))
    self.text:SetHAlign(ANCHOR_LEFT)
    self.text:SetVAlign(ANCHOR_TOP)
    self.text:SetPosition(0, 0, 0) -- 相对父节点 (0,0)，位置由父节点控制
    self.text:SetColour(1, 1, 1, 1)
    
    self.history_bg = self:AddChild(Image("images/global.xml", "square.tex"))
    self.history_bg:SetSize(800, 400)
    self.history_bg:SetTint(0, 0, 0, 0.85)
    self.history_bg:SetPosition(-600, -350, 0)
    self.history_bg:Hide()

    self.history_title = self.history_bg:AddChild(Text(TITLEFONT, 45))
    self.history_title:SetPosition(0, 160, 0)
    self.history_title:SetString("肉 鸽 历 史 战 报")
    self.history_title:SetColour(1, 0.8, 0.1, 1)

    self.history_text = self.history_bg:AddChild(Text(BODYTEXTFONT, 25))
    self.history_text:SetPosition(0, -30, 0)
    self.history_text:SetHAlign(ANCHOR_MIDDLE)
    self.history_text:SetVAlign(ANCHOR_MIDDLE)
    
    -- 强制设置锚点，确保其相对于屏幕右上角
    self:SetHAnchor(ANCHOR_RIGHT)
    self:SetVAnchor(ANCHOR_TOP)
    
    self.text:SetClickable(false)
    self.history_bg:SetClickable(false)

    self.history_detail_index = 0
    self.key_handlers = {
        TheInput:AddKeyUpHandler(KEY_F1, function() self:TryPickAction(1) end),
        TheInput:AddKeyUpHandler(KEY_F2, function() self:TryPickAction(2) end),
        TheInput:AddKeyUpHandler(KEY_F3, function() self:TryPickAction(3) end),
        TheInput:AddKeyDownHandler(KEY_F4, function() self:CycleHistoryDetail() end),
    }
    
    local ImageButton = require "widgets/imagebutton"

    self.shop_btn = self:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_over.tex"))
    self.shop_btn:SetPosition(-150, -450) -- 避开上方文字UI，避免重叠
    self.shop_btn:SetText("商店")
    
    -- 函数说明：动态获取并生成商店图标的悬浮提示信息（包含鼠标左右键图标与对应操作说明）
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
    
    -- 实现右键长按拖动功能
    local old_OnControl = self.shop_btn.OnControl
    self.shop_btn.OnControl = function(btn, control, down)
        if control == CONTROL_SECONDARY then
            if down then
                btn.dragging = true
                btn.drag_start_pos = btn:GetPosition()
                btn.drag_start_mouse = TheInput:GetScreenPosition()
                return true
            else
                if btn.dragging then
                    btn.dragging = false
                    return true
                end
            end
        end
        return old_OnControl(btn, control, down)
    end
    
    -- 启动更新循环
    self:StartUpdating()
end)

-- 尝试通过 RPC 向服务端发送选择天赋的请求
function RogueStatusDisplay:TryPickTalent(slot)
    if not self.owner or not self.owner:IsValid() then return false end
    if not (self.owner.rogue_talent_pending and self.owner.rogue_talent_pending:value()) then return false end
    if not (MOD_RPC and MOD_RPC["rogue_mode"] and MOD_RPC["rogue_mode"]["pick_talent"]) then return false end
    SendModRPCToServer(MOD_RPC["rogue_mode"]["pick_talent"], slot)
    return true
end

-- 尝试通过 RPC 向服务端发送选择补给的请求
function RogueStatusDisplay:TryPickSupply(slot)
    if not self.owner or not self.owner:IsValid() then return false end
    if not (self.owner.rogue_supply_pending and self.owner.rogue_supply_pending:value()) then return false end
    if not (MOD_RPC and MOD_RPC["rogue_mode"] and MOD_RPC["rogue_mode"]["pick_supply"]) then return false end
    SendModRPCToServer(MOD_RPC["rogue_mode"]["pick_supply"], slot)
    return true
end

-- 尝试通过 RPC 向服务端发送选择遗物的请求
function RogueStatusDisplay:TryPickRelic(slot)
    if not self.owner or not self.owner:IsValid() then return false end
    if not (self.owner.rogue_relic_pending and self.owner.rogue_relic_pending:value()) then return false end
    if not (MOD_RPC and MOD_RPC["rogue_mode"] and MOD_RPC["rogue_mode"]["pick_relic"]) then return false end
    SendModRPCToServer(MOD_RPC["rogue_mode"]["pick_relic"], slot)
    return true
end

function RogueStatusDisplay:TryPickRoute(slot)
    if not self.owner or not self.owner:IsValid() then return false end
    if not (self.owner.rogue_route_pending and self.owner.rogue_route_pending:value()) then return false end
    if slot < 1 or slot > 2 then return false end
    if not (MOD_RPC and MOD_RPC["rogue_mode"] and MOD_RPC["rogue_mode"]["pick_route"]) then return false end
    SendModRPCToServer(MOD_RPC["rogue_mode"]["pick_route"], slot)
    return true
end

-- 根据优先级（遗物 > 天赋 > 补给）尝试执行操作
function RogueStatusDisplay:TryPickAction(slot)
    if self:TryPickRoute(slot) then return end
    if self:TryPickRelic(slot) then return end
    if self:TryPickTalent(slot) then return end
    self:TryPickSupply(slot)
end

function RogueStatusDisplay:OnRemoveFromEntity()
    if self.key_handlers then
        for _, handler in ipairs(self.key_handlers) do
            if handler and handler.Remove then
                handler:Remove()
            end
        end
        self.key_handlers = nil
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
    -- 处理按钮拖拽
    if self.shop_btn and self.shop_btn.dragging then
        local current_mouse = TheInput:GetScreenPosition()
        local dx = current_mouse.x - self.shop_btn.drag_start_mouse.x
        local dy = current_mouse.y - self.shop_btn.drag_start_mouse.y
        local scale = TheFrontEnd and TheFrontEnd:GetHUDScale() or 1
        self.shop_btn:SetPosition(self.shop_btn.drag_start_pos.x + dx / scale, self.shop_btn.drag_start_pos.y + dy / scale, 0)
    end

    -- 函数说明：按帧刷新文本，使用精简布局避免长文本超出屏幕
    if not self.owner or not self.owner:IsValid() then return end
    
    -- 获取网络变量值
    -- 注意：这些变量需要在 modmain.lua 中通过 net_ushortint 等定义
    local state = StateSchema.ReadFromNetvars(self.owner)
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
    local catastrophe_active = state.rogue_catastrophe_active == true
    local catastrophe_id = state.rogue_catastrophe_id or 0
    local catastrophe_tier = state.rogue_catastrophe_tier or 0
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
    if catastrophe_active then
        local cname = CATASTROPHE_NAMES[catastrophe_id] or "未知"
        local ctier = CATASTROPHE_TIER_NAMES[catastrophe_tier] or "未知"
        local ceffect = CATASTROPHE_EFFECT_TEXTS[catastrophe_id] or "环境异常强化中"
        str = str .. string.format("\n异变天灾:%s [%s]\n危险提示:%s", cname, ctier, ceffect)
    end
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

    str = str .. "\nF4打开/关闭历史战报"
    str = str .. string.format("\n赛季目标:%d/4", season_obj_done)
    local obj_page, page_rows = ObjectivePages(day, obj_a_cur, obj_a_tar, obj_b_cur, obj_b_tar, obj_c_cur, obj_c_tar, obj_d_cur, obj_d_tar)
    str = str .. string.format(" 页%d/2", obj_page)
    for _, row in ipairs(page_rows) do
        str = str .. string.format("\n%s %d/%d", row.name or "目标", row.cur or 0, row.tar or 0)
    end

    if talent_pending then
        local adef = TALENT_LOOKUP[talent_a] or {}
        local bdef = TALENT_LOOKUP[talent_b] or {}
        local cdef = TALENT_LOOKUP[talent_c] or {}
        local a = adef.name or "未知"
        local b = bdef.name or "未知"
        local c = cdef.name or "未知"
        local ad = adef.desc or "无说明"
        local bd = bdef.desc or "无说明"
        local cd = cdef.desc or "无说明"
        str = str .. string.format(
            "\n天赋候选(F1/F2/F3):\n1.%s【%s】\n2.%s【%s】\n3.%s【%s】",
            a, ad, b, bd, c, cd
        )
    end
    if supply_pending then
        local sadef = SUPPLY_LOOKUP[supply_a] or {}
        local sbdef = SUPPLY_LOOKUP[supply_b] or {}
        local scdef = SUPPLY_LOOKUP[supply_c] or {}
        local sa = sadef.name or "未知"
        local sb = sbdef.name or "未知"
        local sc = scdef.name or "未知"
        local sad = sadef.desc or "无说明"
        local sbd = sbdef.desc or "无说明"
        local scd = scdef.desc or "无说明"
        str = str .. string.format(
            "\n夜晚补给(F1/F2/F3):\n1.%s【%s】\n2.%s【%s】\n3.%s【%s】",
            sa, sad, sb, sbd, sc, scd
        )
    end
    if relic_pending then
        local radef = RELIC_LOOKUP[relic_a] or {}
        local rbdef = RELIC_LOOKUP[relic_b] or {}
        local rcdef = RELIC_LOOKUP[relic_c] or {}
        local ra = radef.name or "未知"
        local rb = rbdef.name or "未知"
        local rc = rcdef.name or "未知"
        local rad = (radef.rarity_name or "普通") .. "·" .. (radef.desc or "无说明")
        local rbd = (rbdef.rarity_name or "普通") .. "·" .. (rbdef.desc or "无说明")
        local rcd = (rcdef.rarity_name or "普通") .. "·" .. (rcdef.desc or "无说明")
        str = str .. string.format(
            "\n遗物抉择(F1/F2/F3):\n1.%s【%s】\n2.%s【%s】\n3.%s【%s】",
            ra, rad, rb, rbd, rc, rcd
        )
    end
    
    local display_str, display_lines = PaginateTextByLines(str, MAX_VISIBLE_LINES, INFO_PAGE_SECONDS)
    self.text:SetString(display_str)
    local y_offset = math.max(0, ((display_lines or 0) - 12) * 9)
    self.text:SetPosition(0, -y_offset, 0)

    local r, g, b, a = 1, 1, 1, 1
    if season_phase >= 5 then
        r, g, b = 0.82, 1, 0.86
    elseif catastrophe_active then
        if catastrophe_tier >= 3 then
            local t = (GetTime and GetTime() or 0)
            local pulse = 0.5 + 0.5 * math.sin(t * 7.5)
            r = 1
            g = 0.25 + 0.28 * pulse
            b = 0.22 + 0.18 * pulse
        elseif catastrophe_tier == 2 then
            r, g, b = 1, 0.72, 0.32
        else
            r, g, b = 0.98, 0.9, 0.52
        end
    elseif relic_pending or talent_pending or supply_pending then
        r, g, b = 0.85, 0.95, 1
    end
    self.text:SetColour(r, g, b, a)
end

return RogueStatusDisplay
