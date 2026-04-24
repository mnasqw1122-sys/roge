local Widget = require "widgets/widget"
local Text = require "widgets/text"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local RogueConfig = require("rogue/config")

-- 遗物稀有度颜色配置
local RARITY_COLORS = {
    common = { 0.75, 0.75, 0.75, 1 },
    rare = { 0.26, 0.63, 1, 1 },
    epic = { 0.64, 0.21, 0.93, 1 },
    legendary = { 1, 0.5, 0, 1 },
}

-- 遗物稀有度边框颜色（更亮）
local RARITY_BORDER_COLORS = {
    common = { 0.5, 0.5, 0.5, 0.8 },
    rare = { 0.2, 0.5, 0.9, 0.9 },
    epic = { 0.5, 0.15, 0.7, 0.9 },
    legendary = { 0.9, 0.4, 0, 0.9 },
}

local RELIC_DEFS = RogueConfig.RELIC_DEFS or {}

-- 根据ID查找遗物定义
local function GetRelicDef(id)
    for _, def in ipairs(RELIC_DEFS) do
        if def.id == id then return def end
    end
    return nil
end

local RogueRelicPanel = Class(Widget, function(self, owner)
    Widget._ctor(self, "RogueRelicPanel")
    self.owner = owner
    self.shown = false

    -- 根节点居中
    self:SetVAnchor(ANCHOR_MIDDLE)
    self:SetHAnchor(ANCHOR_MIDDLE)
    self:SetScaleMode(SCALEMODE_PROPORTIONAL)

    -- 标题
    self.title = self:AddChild(Text(TITLEFONT, 42, "遗物抉择"))
    self.title:SetPosition(0, 195)
    self.title:SetColour(1, 0.84, 0, 1)

    -- 倒计时提示
    self.timer_text = self:AddChild(Text(BODYTEXTFONT, 24, ""))
    self.timer_text:SetPosition(0, 160)
    self.timer_text:SetColour(0.8, 0.8, 0.8, 1)

    -- 三个遗物卡片
    self.cards = {}
    for i = 1, 3 do
        local card = self:CreateCard(i)
        table.insert(self.cards, card)
    end

    -- 初始隐藏
    self:Hide()

    -- 启用每帧更新
    self:StartUpdating()
end)

-- 创建单个遗物卡片
function RogueRelicPanel:CreateCard(index)
    local x_offset = (index - 2) * 260

    -- 卡片背景
    local card = self:AddChild(Image("images/global.xml", "square.tex"))
    card:SetPosition(x_offset, -20)
    card:SetSize(230, 320)
    card:SetTint(0.1, 0.1, 0.15, 0.85)

    -- 卡片边框
    card.border = card:AddChild(Image("images/global.xml", "square.tex"))
    card.border:SetPosition(0, 0)
    card.border:SetSize(236, 326)
    card.border:SetTint(0.4, 0.4, 0.5, 0.6)

    -- 确保边框在背景后面
    card.border:MoveToBack()

    -- 稀有度标签
    card.rarity_label = card:AddChild(Text(BODYTEXTFONT, 20, ""))
    card.rarity_label:SetPosition(0, 130)

    -- 遗物图标区域
    card.icon_bg = card:AddChild(Image("images/global.xml", "square.tex"))
    card.icon_bg:SetPosition(0, 50)
    card.icon_bg:SetSize(120, 120)
    card.icon_bg:SetTint(0.15, 0.15, 0.2, 0.9)

    -- 遗物图标（使用问号占位）
    card.icon_text = card:AddChild(Text(TITLEFONT, 60, "?"))
    card.icon_text:SetPosition(0, 50)

    -- 遗物名称
    card.name_label = card:AddChild(Text(TITLEFONT, 26, ""))
    card.name_label:SetPosition(0, -30)

    -- 遗物描述
    card.desc_label = card:AddChild(Text(BODYTEXTFONT, 18, ""))
    card.desc_label:SetPosition(0, -80)
    card.desc_label:SetRegionSize(200, 80)
    card.desc_label:EnableWordWrap(true)
    card.desc_label:SetVAlign(ANCHOR_TOP)

    -- 选择按钮
    card.select_btn = card:AddChild(ImageButton(
        "images/ui.xml", "button_small.tex", "button_small_over.tex",
        "button_small_disabled.tex", "button_small_over.tex"
    ))
    card.select_btn:SetPosition(0, -135)
    card.select_btn:SetText("选择")
    card.select_btn:SetTextSize(20)
    card.select_btn:SetOnClick(function()
        self:PickRelic(index)
    end)

    -- 悬停时按钮放大效果
    card.select_btn:SetFocusScale(1.1, 1.1, 1.1)

    card.index = index
    card.relic_id = nil

    return card
end

-- 更新卡片显示
function RogueRelicPanel:UpdateCard(card, relic_id)
    if not relic_id or relic_id == 0 then
        card:Hide()
        card.relic_id = nil
        return
    end

    card:Show()
    card.relic_id = relic_id

    local def = GetRelicDef(relic_id)
    if not def then
        card.name_label:SetString("未知遗物")
        card.desc_label:SetString("")
        card.rarity_label:SetString("普通")
        card.icon_text:SetString("?")
        return
    end

    -- 设置名称
    card.name_label:SetString(def.name or "未知遗物")

    -- 设置描述
    card.desc_label:SetString(def.desc or "")

    -- 设置稀有度
    local rarity = def.rarity or "common"
    local rarity_name = def.rarity_name or "普通"
    card.rarity_label:SetString("【" .. rarity_name .. "】")

    -- 设置颜色
    local color = RARITY_COLORS[rarity] or RARITY_COLORS.common
    local border_color = RARITY_BORDER_COLORS[rarity] or RARITY_BORDER_COLORS.common
    card.rarity_label:SetColour(unpack(color))
    card.name_label:SetColour(unpack(color))
    card.icon_text:SetColour(unpack(color))
    card.border:SetTint(unpack(border_color))

    -- 设置图标文字（使用遗物名称首字）
    local name_str = def.name or "?"
    local first_char = string.sub(name_str, 1, 3)
    card.icon_text:SetString(first_char)
end

-- 选择遗物
function RogueRelicPanel:PickRelic(slot)
    if not self.owner or not self.owner:IsValid() then return end
    if not (self.owner.rogue_relic_pending and self.owner.rogue_relic_pending:value()) then return end
    if not (MOD_RPC and MOD_RPC["rogue_mode"] and MOD_RPC["rogue_mode"]["pick_relic"]) then return end
    SendModRPCToServer(MOD_RPC["rogue_mode"]["pick_relic"], slot)
    self:Hide()
end

-- 每帧更新
function RogueRelicPanel:OnUpdate(dt)
    if not self.owner or not self.owner:IsValid() then
        self:Hide()
        return
    end

    local pending = self.owner.rogue_relic_pending and self.owner.rogue_relic_pending:value()

    if pending then
        -- 读取遗物选项
        local relic_a = self.owner.rogue_relic_a and self.owner.rogue_relic_a:value() or 0
        local relic_b = self.owner.rogue_relic_b and self.owner.rogue_relic_b:value() or 0
        local relic_c = self.owner.rogue_relic_c and self.owner.rogue_relic_c:value() or 0

        -- 更新卡片
        self:UpdateCard(self.cards[1], relic_a)
        self:UpdateCard(self.cards[2], relic_b)
        self:UpdateCard(self.cards[3], relic_c)

        -- 更新倒计时
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

return RogueRelicPanel
