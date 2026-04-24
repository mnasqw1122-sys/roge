local Widget = require "widgets/widget"
local Text = require "widgets/text"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local RogueConfig = require("rogue/config")

local TALENT_DEFS = RogueConfig.TALENT_DEFS or {}
local BRANCH_COLORS = RogueConfig.TALENT_BRANCH_COLORS or {}
local BRANCH_NAMES = RogueConfig.TALENT_BRANCH_NAMES or {}

-- 函数说明：根据ID查找天赋定义
local function GetTalentDef(id)
    for _, def in ipairs(TALENT_DEFS) do
        if def.id == id then return def end
    end
    return nil
end

local RogueTalentPanel = Class(Widget, function(self, owner)
    Widget._ctor(self, "RogueTalentPanel")
    self.owner = owner
    self.shown = false

    self:SetVAnchor(ANCHOR_MIDDLE)
    self:SetHAnchor(ANCHOR_MIDDLE)
    self:SetScaleMode(SCALEMODE_PROPORTIONAL)

    -- 标题
    self.title = self:AddChild(Text(TITLEFONT, 42, "天赋觉醒"))
    self.title:SetPosition(0, 195)
    self.title:SetColour(0.3, 0.9, 0.3, 1)

    -- 倒计时提示
    self.timer_text = self:AddChild(Text(BODYTEXTFONT, 24, ""))
    self.timer_text:SetPosition(0, 160)
    self.timer_text:SetColour(0.8, 0.8, 0.8, 1)

    -- 三个天赋卡片
    self.cards = {}
    for i = 1, 3 do
        local card = self:CreateCard(i)
        table.insert(self.cards, card)
    end

    self:Hide()
    self:StartUpdating()
end)

-- 函数说明：创建单个天赋卡片（支持分支颜色）
function RogueTalentPanel:CreateCard(index)
    local x_offset = (index - 2) * 260

    local card = self:AddChild(Image("images/global.xml", "square.tex"))
    card:SetPosition(x_offset, -20)
    card:SetSize(230, 320)
    card:SetTint(0.08, 0.15, 0.08, 0.85)

    card.border = card:AddChild(Image("images/global.xml", "square.tex"))
    card.border:SetPosition(0, 0)
    card.border:SetSize(236, 326)
    card.border:SetTint(0.15, 0.4, 0.15, 0.6)
    card.border:MoveToBack()

    -- 分支标签
    card.branch_label = card:AddChild(Text(BODYTEXTFONT, 16, ""))
    card.branch_label:SetPosition(0, 140)
    card.branch_label:SetColour(0.7, 0.7, 0.7, 1)

    -- 天赋图标区域
    card.icon_bg = card:AddChild(Image("images/global.xml", "square.tex"))
    card.icon_bg:SetPosition(0, 60)
    card.icon_bg:SetSize(120, 120)
    card.icon_bg:SetTint(0.1, 0.2, 0.1, 0.9)

    -- 天赋图标文字
    card.icon_text = card:AddChild(Text(TITLEFONT, 50, "?"))
    card.icon_text:SetPosition(0, 60)
    card.icon_text:SetColour(0.3, 0.9, 0.3, 1)

    -- 天赋名称
    card.name_label = card:AddChild(Text(TITLEFONT, 26, ""))
    card.name_label:SetPosition(0, -20)
    card.name_label:SetColour(0.3, 0.9, 0.3, 1)

    -- 天赋描述
    card.desc_label = card:AddChild(Text(BODYTEXTFONT, 18, ""))
    card.desc_label:SetPosition(0, -70)
    card.desc_label:SetRegionSize(200, 80)
    card.desc_label:EnableWordWrap(true)
    card.desc_label:SetVAlign(ANCHOR_TOP)
    card.desc_label:SetColour(0.8, 0.9, 0.8, 1)

    -- 等级/前置提示
    card.level_label = card:AddChild(Text(BODYTEXTFONT, 14, ""))
    card.level_label:SetPosition(0, -115)
    card.level_label:SetColour(0.6, 0.6, 0.6, 1)

    -- 选择按钮
    card.select_btn = card:AddChild(ImageButton(
        "images/ui.xml", "button_small.tex", "button_small_over.tex",
        "button_small_disabled.tex", "button_small_over.tex"
    ))
    card.select_btn:SetPosition(0, -135)
    card.select_btn:SetText("觉醒")
    card.select_btn:SetTextSize(20)
    card.select_btn:SetOnClick(function()
        self:PickTalent(index)
    end)
    card.select_btn:SetFocusScale(1.1, 1.1, 1.1)

    card.index = index
    card.talent_id = nil

    return card
end

-- 函数说明：更新卡片显示（支持分支颜色和等级信息）
function RogueTalentPanel:UpdateCard(card, talent_id)
    if not talent_id or talent_id == 0 then
        card:Hide()
        card.talent_id = nil
        return
    end

    card:Show()
    card.talent_id = talent_id

    local def = GetTalentDef(talent_id)
    if not def then
        card.name_label:SetString("未知天赋")
        card.desc_label:SetString("")
        card.icon_text:SetString("?")
        card.branch_label:SetString("")
        card.level_label:SetString("")
        return
    end

    card.name_label:SetString(def.name or "未知天赋")
    card.desc_label:SetString(def.desc or "")

    local name_str = def.name or "?"
    card.icon_text:SetString(string.sub(name_str, 1, 3))

    -- 设置分支标签和颜色
    local branch = def.branch or "offense"
    local branch_name = BRANCH_NAMES[branch] or branch
    local branch_color = BRANCH_COLORS[branch] or { 0.3, 0.9, 0.3, 1 }
    card.branch_label:SetString("【" .. branch_name .. "】")
    card.branch_label:SetColour(unpack(branch_color))
    card.name_label:SetColour(unpack(branch_color))
    card.icon_text:SetColour(unpack(branch_color))
    card.border:SetTint(branch_color[1] * 0.4, branch_color[2] * 0.4, branch_color[3] * 0.4, 0.6)

    -- 显示等级和前置信息
    local level_text = ""
    if def.max_level and def.max_level > 1 then
        level_text = "最大等级: " .. tostring(def.max_level)
    end
    if def.prereq then
        local prereq_def = GetTalentDef(def.prereq)
        local prereq_name = prereq_def and prereq_def.name or ("#" .. tostring(def.prereq))
        level_text = level_text .. (level_text ~= "" and " | " or "") .. "前置: " .. prereq_name .. " Lv" .. tostring(def.prereq_level or 1)
    end
    card.level_label:SetString(level_text)
end

-- 函数说明：选择天赋
function RogueTalentPanel:PickTalent(slot)
    if not self.owner or not self.owner:IsValid() then return end
    if not (self.owner.rogue_talent_pending and self.owner.rogue_talent_pending:value()) then return end
    if not (MOD_RPC and MOD_RPC["rogue_mode"] and MOD_RPC["rogue_mode"]["pick_talent"]) then return end
    SendModRPCToServer(MOD_RPC["rogue_mode"]["pick_talent"], slot)
    self:Hide()
end

-- 函数说明：每帧更新
function RogueTalentPanel:OnUpdate(dt)
    if not self.owner or not self.owner:IsValid() then
        self:Hide()
        return
    end

    local pending = self.owner.rogue_talent_pending and self.owner.rogue_talent_pending:value()

    if pending then
        local talent_a = self.owner.rogue_talent_a and self.owner.rogue_talent_a:value() or 0
        local talent_b = self.owner.rogue_talent_b and self.owner.rogue_talent_b:value() or 0
        local talent_c = self.owner.rogue_talent_c and self.owner.rogue_talent_c:value() or 0

        self:UpdateCard(self.cards[1], talent_a)
        self:UpdateCard(self.cards[2], talent_b)
        self:UpdateCard(self.cards[3], talent_c)

        if self._show_time then
            local elapsed = GetTime() - self._show_time
            local remaining = math.max(0, 20 - math.floor(elapsed))
            self.timer_text:SetString("自动选择倒计时: " .. tostring(remaining) .. "秒")
        end

        if not self.shown then
            self.shown = true
            self._show_time = GetTime()
            self:Show()
        end
    else
        if self.shown then
            self.shown = false
            self._show_time = nil
            self:Hide()
        end
    end
end

return RogueTalentPanel
