local Widget = require "widgets/widget"
local Text = require "widgets/text"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local RogueConfig = require("rogue/config")

local SUPPLY_DEFS = RogueConfig.SUPPLY_DEFS or {}

local function GetSupplyDef(id)
    for _, def in ipairs(SUPPLY_DEFS) do
        if def.id == id then return def end
    end
    return nil
end

local RogueSupplyPanel = Class(Widget, function(self, owner)
    Widget._ctor(self, "RogueSupplyPanel")
    self.owner = owner
    self.shown = false

    self:SetVAnchor(ANCHOR_MIDDLE)
    self:SetHAnchor(ANCHOR_MIDDLE)
    self:SetScaleMode(SCALEMODE_PROPORTIONAL)

    -- 标题
    self.title = self:AddChild(Text(TITLEFONT, 42, "夜间补给"))
    self.title:SetPosition(0, 195)
    self.title:SetColour(0.4, 0.7, 1, 1)

    -- 倒计时提示
    self.timer_text = self:AddChild(Text(BODYTEXTFONT, 24, ""))
    self.timer_text:SetPosition(0, 160)
    self.timer_text:SetColour(0.8, 0.8, 0.8, 1)

    -- 三个补给卡片
    self.cards = {}
    for i = 1, 3 do
        local card = self:CreateCard(i)
        table.insert(self.cards, card)
    end

    self:Hide()
    self:StartUpdating()
end)

-- 创建单个补给卡片
function RogueSupplyPanel:CreateCard(index)
    local x_offset = (index - 2) * 260

    local card = self:AddChild(Image("images/global.xml", "square.tex"))
    card:SetPosition(x_offset, -20)
    card:SetSize(230, 320)
    card:SetTint(0.06, 0.1, 0.18, 0.85)

    card.border = card:AddChild(Image("images/global.xml", "square.tex"))
    card.border:SetPosition(0, 0)
    card.border:SetSize(236, 326)
    card.border:SetTint(0.15, 0.25, 0.5, 0.6)
    card.border:MoveToBack()

    -- 补给图标区域
    card.icon_bg = card:AddChild(Image("images/global.xml", "square.tex"))
    card.icon_bg:SetPosition(0, 60)
    card.icon_bg:SetSize(120, 120)
    card.icon_bg:SetTint(0.08, 0.12, 0.22, 0.9)

    -- 补给图标文字
    card.icon_text = card:AddChild(Text(TITLEFONT, 50, "?"))
    card.icon_text:SetPosition(0, 60)
    card.icon_text:SetColour(0.4, 0.7, 1, 1)

    -- 补给名称
    card.name_label = card:AddChild(Text(TITLEFONT, 26, ""))
    card.name_label:SetPosition(0, -20)
    card.name_label:SetColour(0.4, 0.7, 1, 1)

    -- 补给描述
    card.desc_label = card:AddChild(Text(BODYTEXTFONT, 18, ""))
    card.desc_label:SetPosition(0, -70)
    card.desc_label:SetRegionSize(200, 80)
    card.desc_label:EnableWordWrap(true)
    card.desc_label:SetVAlign(ANCHOR_TOP)
    card.desc_label:SetColour(0.8, 0.85, 0.95, 1)

    -- 选择按钮
    card.select_btn = card:AddChild(ImageButton(
        "images/ui.xml", "button_small.tex", "button_small_over.tex",
        "button_small_disabled.tex", "button_small_over.tex"
    ))
    card.select_btn:SetPosition(0, -135)
    card.select_btn:SetText("领取")
    card.select_btn:SetTextSize(20)
    card.select_btn:SetOnClick(function()
        self:PickSupply(index)
    end)
    card.select_btn:SetFocusScale(1.1, 1.1, 1.1)

    card.index = index
    card.supply_id = nil

    return card
end

-- 更新卡片显示
function RogueSupplyPanel:UpdateCard(card, supply_id)
    if not supply_id or supply_id == 0 then
        card:Hide()
        card.supply_id = nil
        return
    end

    card:Show()
    card.supply_id = supply_id

    local def = GetSupplyDef(supply_id)
    if not def then
        card.name_label:SetString("未知补给")
        card.desc_label:SetString("")
        card.icon_text:SetString("?")
        return
    end

    card.name_label:SetString(def.name or "未知补给")
    card.desc_label:SetString(def.desc or "")

    local name_str = def.name or "?"
    card.icon_text:SetString(string.sub(name_str, 1, 3))
end

-- 选择补给
function RogueSupplyPanel:PickSupply(slot)
    if not self.owner or not self.owner:IsValid() then return end
    if not (self.owner.rogue_supply_pending and self.owner.rogue_supply_pending:value()) then return end
    if not (MOD_RPC and MOD_RPC["rogue_mode"] and MOD_RPC["rogue_mode"]["pick_supply"]) then return end
    SendModRPCToServer(MOD_RPC["rogue_mode"]["pick_supply"], slot)
    self:Hide()
end

-- 每帧更新
function RogueSupplyPanel:OnUpdate(dt)
    if not self.owner or not self.owner:IsValid() then
        self:Hide()
        return
    end

    local pending = self.owner.rogue_supply_pending and self.owner.rogue_supply_pending:value()

    if pending then
        local supply_a = self.owner.rogue_supply_a and self.owner.rogue_supply_a:value() or 0
        local supply_b = self.owner.rogue_supply_b and self.owner.rogue_supply_b:value() or 0
        local supply_c = self.owner.rogue_supply_c and self.owner.rogue_supply_c:value() or 0

        self:UpdateCard(self.cards[1], supply_a)
        self:UpdateCard(self.cards[2], supply_b)
        self:UpdateCard(self.cards[3], supply_c)

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

return RogueSupplyPanel
