--[[
    文件说明：rogue_shop_panel.lua（v2.3.3 · 布局重制版）
    功能：肉鸽商店界面。
    布局（参考用户设计稿）：
    - 顶部金色标题栏：左侧标题 + 右上角积分余额
    - 左侧竖排选项卡：购买 / 黑市 / 回收（选中红色文字 + 金色高亮）
    - 右侧内容区：商品网格 / 黑市服务 / 回收容器
    风格：半透明背景、深底亮字、纯文字价格、无悬浮提示
]]
local Widget = require "widgets/widget"
local Text = require "widgets/text"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local ShopConfig = require("rogue/shop_config")
local StateSchema = require("rogue/state_schema")

-- ===== 面板尺寸与配色 =====
local PANEL_W = 660
local PANEL_H = 580

local COL = {
    gold    = { 1, 0.84, 0.32, 1 },  -- 亮金
    gold_d  = { 0.9, 0.68, 0.22, 1 },-- 暗金
    title   = { 1, 0.9, 0.5, 1 },    -- 标题
    white   = { 1, 1, 1, 1 },
    grey    = { 0.85, 0.85, 0.85, 1 },
    grey_d  = { 0.68, 0.68, 0.68, 1 },
    green   = { 0.45, 1, 0.45, 1 },
    yellow  = { 1, 0.85, 0.3, 1 },
    blue    = { 0.55, 0.8, 1, 1 },
    red     = { 1, 0.35, 0.3, 1 },   -- 选中/代价红
}

local PREFAB_TO_IMAGE = {
    onion = "quagmire_onion",
    onion_cooked = "quagmire_onion_cooked",
    tomato = "quagmire_tomato",
    tomato_cooked = "quagmire_tomato_cooked",
    garlic = "quagmire_garlic",
    garlic_cooked = "quagmire_garlic_cooked",
    potato = "quagmire_potato",
    potato_cooked = "quagmire_potato_cooked",
    cursed_monkey_token = "cursed_beads1",
    bat_hide = "pigskin",
}

-- ===== 工具函数 =====

local function GetItemTextureName(prefab)
    local mapped = PREFAB_TO_IMAGE[prefab] or prefab
    return mapped .. ".tex"
end

-- 函数说明：创建半透明纯色块（SetSize 绝对像素）。
local function MakeShade(parent, w, h, r, g, b, a)
    local shade = parent:AddChild(Image("images/ui.xml", "black.tex"))
    shade:SetSize(w, h)
    shade:SetTint(r, g, b, a)
    return shade
end

-- 函数说明：创建角标（纯彩色文字，无黑底）。
local function MakeTag(parent, x, y, text, colour)
    local label = parent:AddChild(Text(BODYTEXTFONT, 12, text))
    label:SetPosition(x, y)
    label:SetColour(colour[1], colour[2], colour[3], 1)
    return label
end

-- 函数说明：创建横向金色装饰线。
local function MakeDivider(parent, y, width)
    local line = parent:AddChild(Image("images/ui.xml", "black.tex"))
    line:SetSize(width, 2)
    line:SetPosition(0, y)
    line:SetTint(COL.gold[1], COL.gold[2], COL.gold[3], 0.5)
    return line
end

-- 函数说明：创建竖向金色装饰线。
local function MakeVDivider(parent, x, y, height)
    local line = parent:AddChild(Image("images/ui.xml", "black.tex"))
    line:SetSize(2, height)
    line:SetPosition(x, y)
    line:SetTint(COL.gold[1], COL.gold[2], COL.gold[3], 0.5)
    return line
end

-- ===== 主面板 =====
local RogueShopPanel = Class(Widget, function(self, owner)
    Widget._ctor(self, "RogueShopPanel")
    self.owner = owner

    self:SetVAnchor(ANCHOR_MIDDLE)
    self:SetHAnchor(ANCHOR_MIDDLE)
    self:SetScaleMode(SCALEMODE_PROPORTIONAL)

    -- ===== 主面板（无背景，内容直接浮于游戏画面）=====
    self.frame = self:AddChild(Widget("ShopFrame"))

    -- ===== 顶部标题栏 =====
    local title_bar = MakeShade(self.frame, PANEL_W - 16, 46, 0.62, 0.45, 0.1, 0.28)
    title_bar:SetPosition(0, 225)

    self.title = self.frame:AddChild(Text(TITLEFONT, 26, "肉 鸽 商 店"))
    self.title:SetPosition(-210, 225)
    self.title:SetColour(COL.title[1], COL.title[2], COL.title[3], 1)

    -- 积分余额（标题栏右上角，纯文字）
    self.points_text = self.frame:AddChild(Text(TITLEFONT, 18, "余额：0"))
    self.points_text:SetPosition(185, 225)
    self.points_text:SetColour(COL.gold[1], COL.gold[2], COL.gold[3], 1)

    -- 关闭按钮（标题栏最右）
    self.close_btn = self.frame:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_over.tex"))
    self.close_btn:SetPosition(292, 225)
    self.close_btn:SetScale(0.8, 0.8, 1)
    self.close_btn:SetText("关闭")
    self.close_btn:SetOnClick(function()
        SendModRPCToServer(MOD_RPC["rogue_mode"]["close_recycle_bin"])
        self:Hide()
    end)

    MakeDivider(self.frame, 195, PANEL_W - 16)

    -- ===== 左侧竖排选项卡（购买 / 黑市 / 回收）=====
    local TAB_TEX = { "button_large.tex", "button_large_over.tex", "button_large_disabled.tex", "button_large_over.tex", "button_large_over.tex" }
    self.tab_buttons = {}

    local function MakeTabBtn(label, y)
        local btn = self.frame:AddChild(ImageButton("images/ui.xml", TAB_TEX[1], TAB_TEX[2], TAB_TEX[3], TAB_TEX[4], TAB_TEX[5]))
        btn:SetPosition(-245, y)
        btn:SetScale(0.7, 0.7, 1)
        btn:SetText(label)
        btn.text:SetColour(0.88, 0.88, 0.88, 1)
        return btn
    end

    self.buy_tab_btn = MakeTabBtn("购 买", 100)
    self.black_market_tab_btn = MakeTabBtn("黑 市", 35)
    self.recycle_tab_btn = MakeTabBtn("回 收", -30)

    self.buy_tab_btn:SetOnClick(function() self:ShowTab("buy") end)
    self.black_market_tab_btn:SetOnClick(function() self:ShowTab("black_market") end)
    self.recycle_tab_btn:SetOnClick(function() self:ShowTab("recycle") end)
    self.tab_buttons = { buy = self.buy_tab_btn, black_market = self.black_market_tab_btn, recycle = self.recycle_tab_btn }

    -- 左侧栏与内容区之间的竖向分隔线（保持原位，不随内容区移动）
    MakeVDivider(self.frame, -165, 0, 360)

    -- ===== 内容容器（右侧区域）=====
    self.buy_container = self.frame:AddChild(Widget("BuyContainer"))
    self.buy_container:SetPosition(85, 0)
    self.black_market_container = self.frame:AddChild(Widget("BlackMarketContainer"))
    self.black_market_container:SetPosition(85, 0)
    self.recycle_container = self.frame:AddChild(Widget("RecycleContainer"))
    -- 回收容器上移，格顶对齐最上面的分割线（y=195）
    self.recycle_container:SetPosition(85, 116)
    -- 回收容器整体缩小（25 格 5x5）
    self.recycle_container:SetScale(0.75, 0.75, 1)

    -- 底部提示条
    self.hint_text = self.frame:AddChild(Text(BODYTEXTFONT, 13, ""))
    self.hint_text:SetPosition(85, -268)
    self.hint_text:SetColour(COL.grey_d[1], COL.grey_d[2], COL.grey_d[3], 1)

    -- 一键回收按钮（回收页专用，容器下方中央）
    self.recycle_all_btn = self.recycle_container:AddChild(ImageButton("images/ui.xml", "button_large.tex", "button_large_over.tex", "button_large_disabled.tex", "button_large_over.tex"))
    self.recycle_all_btn:SetPosition(0, -370)
    self.recycle_all_btn:SetScale(0.8, 0.65, 1)
    self.recycle_all_btn:SetText("一键回收")
    self.recycle_all_btn.text:SetColour(1, 0.55, 0.4, 1)
    self.recycle_all_btn:SetOnClick(function()
        SendModRPCToServer(MOD_RPC["rogue_mode"]["recycle_all_items"])
    end)

    self:BuildBuyList()
    self:BuildBlackMarketList()
    self:ShowTab("buy")

    self.inst:ListenForEvent("rogue_dirty", function() self:UpdatePoints() end, self.owner)
    self:UpdatePoints()
    self:StartUpdating()
end)

-- 函数说明：更新积分显示（含买不起的商品价格标红）。
function RogueShopPanel:UpdatePoints()
    if not self.owner or not self.owner:IsValid() then return end
    local state = StateSchema.ReadFromNetvars(self.owner)
    local points = state.rogue_points or 0
    self.points_text:SetString("余额：" .. points)
    if self.item_price_texts then
        for _, entry in ipairs(self.item_price_texts) do
            if entry and entry.price_text then
                local need = entry.discount and entry.final_cost or entry.cost
                local affordable = points >= need
                if affordable then
                    entry.price_text:SetColour(COL.gold[1], COL.gold[2], COL.gold[3], 1)
                else
                    entry.price_text:SetColour(1, 0.42, 0.42, 1)
                end
            end
        end
    end
end

-- 函数说明：切换选项卡。
function RogueShopPanel:ShowTab(tab)
    self.current_tab = tab
    self.buy_container:Hide()
    self.black_market_container:Hide()
    self.recycle_container:Hide()
    for _, btn in pairs(self.tab_buttons) do
        btn:Unselect()
        btn.text:SetColour(0.88, 0.88, 0.88, 1)
    end

    local active = self.tab_buttons[tab]
    if active then
        active:Select()
        active.text:SetColour(COL.red[1], COL.red[2], COL.red[3], 1)
    end

    if tab == "buy" then
        self:BuildBuyList()
        self.buy_container:Show()
        self.hint_text:SetString("点击商品购买 · 按 ESC 或点击右上角关闭")
        SendModRPCToServer(MOD_RPC["rogue_mode"]["close_recycle_bin"])
    elseif tab == "black_market" then
        self:BuildBlackMarketList()
        self.black_market_container:Show()
        self.hint_text:SetString("从背包拿起物品自动预览 · 选择右侧服务")
        SendModRPCToServer(MOD_RPC["rogue_mode"]["close_recycle_bin"])
    else
        self.recycle_container:Show()
        self.hint_text:SetString("")
        SendModRPCToServer(MOD_RPC["rogue_mode"]["open_recycle_bin"])
    end
end

-- ===== 购买页 =====

-- 函数说明：构建普通商品购买网格（右侧内容区，5 列 x 4 行，共 20 件）。
function RogueShopPanel:BuildBuyList()
    self.buy_container:KillAllChildren()

    local items = ShopConfig.GetDailyShopItems()
    local discounts = ShopConfig.GetDailyDiscounts()
    self.item_price_texts = {}

    local cols = 5
    local start_x = -200
    local start_y = 133
    local dx = 100
    local dy = -86
    local SLOT = 84

    for i, def in ipairs(items) do
        local row = math.floor((i - 1) / cols)
        local col = (i - 1) % cols
        local x = start_x + col * dx
        local y = start_y + row * dy

        local item_btn = self.buy_container:AddChild(ImageButton("images/hud.xml", "inv_slot.tex", "inv_slot_spoiled.tex", "inv_slot_spoiled.tex", "inv_slot_spoiled.tex"))
        item_btn:SetPosition(x, y)
        item_btn:SetScale(1.3125, 1.3125, 1)

        -- 槽底
        local slot_bg = item_btn:AddChild(Image("images/hud.xml", "craft_slotbg.tex"))
        slot_bg:SetScale(1.35, 1.35, 1)

        -- 物品图标（略小，给底部价格文字留空间）
        local tex_name = GetItemTextureName(def.prefab)
        local atlas = (GetInventoryItemAtlas and GetInventoryItemAtlas(tex_name)) or "images/inventoryimages.xml"
        local item_img = item_btn:AddChild(Image(atlas, tex_name))
        item_img:SetScale(0.7, 0.7, 1)

        -- 价格：格子底部纯文字（无黑背景无贴图）
        local discount_pct = discounts[def.id]
        local final_cost = def.cost
        if discount_pct and discount_pct > 0 then
            final_cost = math.ceil(def.cost * (1 - discount_pct))
        end

        local price_text = item_btn:AddChild(Text(BODYTEXTFONT, 12, final_cost .. " 积分"))
        price_text:SetPosition(0, -28)
        price_text:SetColour(COL.gold[1], COL.gold[2], COL.gold[3], 1)

        table.insert(self.item_price_texts, {
            cost = def.cost,
            final_cost = final_cost,
            discount = discount_pct or 0,
            price_text = price_text,
        })

        -- 角标（左上/右上错位，纯文字）
        local tag_left, tag_right, tag_y = 20, -20, 22
        local discount_placed, limit_placed = false, false
        if discount_pct and discount_pct > 0 then
            MakeTag(item_btn, tag_left, tag_y, "-" .. math.floor(discount_pct * 100) .. "%", COL.green)
            discount_placed = true
        end
        local limit = ShopConfig.GetPurchaseLimit(def.prefab)
        if limit < 99 then
            MakeTag(item_btn, tag_right, tag_y, "限" .. limit, COL.yellow)
            limit_placed = true
        end
        if def.season then
            if not discount_placed then
                MakeTag(item_btn, tag_left, tag_y, "季节", COL.blue)
            elseif not limit_placed then
                MakeTag(item_btn, tag_right, tag_y, "季节", COL.blue)
            end
        end

        item_btn:SetOnClick(function()
            SendModRPCToServer(MOD_RPC["rogue_mode"]["buy_shop_item"], def.id)
        end)
    end
end

-- ===== 黑市页 =====

-- 函数说明：构建黑市界面（内容区内：左手持物品 / 右服务，两卡并排）。
function RogueShopPanel:BuildBlackMarketList()
    self.black_market_container:KillAllChildren()

    local items = ShopConfig.GetBlackMarketItems()
    local CARD_W, CARD_H = 225, 280

    -- ===== 左侧卡片：手持物品预览（顶部对齐内容区顶）=====
    local left_panel = self.black_market_container:AddChild(Widget("LeftCard"))
    left_panel:SetPosition(-135, -46)

    local left_bg = MakeShade(left_panel, CARD_W, CARD_H, 0, 0, 0, 0.5)
    MakeDivider(left_panel, CARD_H / 2 - 38, CARD_W - 36)

    local left_title = left_panel:AddChild(Text(TITLEFONT, 16, "手持物品"))
    left_title:SetPosition(0, 100)
    left_title:SetColour(1, 1, 1, 1)

    local slot_bg = left_panel:AddChild(Image("images/hud.xml", "inv_slot.tex"))
    slot_bg:SetPosition(0, 35)
    slot_bg:SetScale(1.8, 1.8, 1)

    self.forge_slot_image = left_panel:AddChild(Image("images/hud.xml", "inv_slot.tex"))
    self.forge_slot_image:SetPosition(0, 35)
    self.forge_slot_image:SetScale(1.4, 1.4, 1)
    self.forge_slot_image:Hide()

    self.forge_slot_name = left_panel:AddChild(Text(BODYTEXTFONT, 12, ""))
    self.forge_slot_name:SetPosition(0, -18)
    self.forge_slot_name:SetColour(COL.white[1], COL.white[2], COL.white[3], 1)

    local left_hint = left_panel:AddChild(Text(BODYTEXTFONT, 10, "拿起背包中的物品\n此处自动预览"))
    left_hint:SetPosition(0, -62)
    left_hint:SetColour(0.7, 0.7, 0.7, 1)

    -- ===== 中间箭头 =====
    local arrow = self.black_market_container:AddChild(Image("images/ui.xml", "crafting_inventory_arrow_r_idle.tex"))
    arrow:SetPosition(-2, -46)
    arrow:SetScale(0.8, 0.8, 1)

    -- ===== 右侧卡片：服务列表（顶部对齐内容区顶）=====
    local right_panel = self.black_market_container:AddChild(Widget("RightCard"))
    right_panel:SetPosition(130, -46)

    local right_bg = MakeShade(right_panel, CARD_W, CARD_H, 0, 0, 0, 0.5)
    MakeDivider(right_panel, CARD_H / 2 - 38, CARD_W - 36)

    local right_title = right_panel:AddChild(Text(TITLEFONT, 16, "服务"))
    right_title:SetPosition(0, 100)
    right_title:SetColour(1, 1, 1, 1)

    local btn_y = 52
    local btn_dy = -105

    for i, def in ipairs(items) do
        local y = btn_y + (i - 1) * btn_dy

        local svc_btn = right_panel:AddChild(ImageButton("images/ui.xml", "button_large.tex", "button_large_over.tex", "button_large_disabled.tex", "button_large_over.tex"))
        svc_btn:SetPosition(0, y)
        svc_btn:SetScale(1.15, 0.9, 1)

        -- 服务图标
        local icon_tex = def.service == "reforge" and "purplegem.tex" or "redgem.tex"
        local icon = svc_btn:AddChild(Image("images/inventoryimages.xml", icon_tex))
        icon:SetPosition(-48, 7)
        icon:SetScale(0.7, 0.7, 1)

        local svc_name = def.service == "reforge" and "重铸" or "强化"
        local name_tag = svc_btn:AddChild(Text(TITLEFONT, 17, svc_name))
        name_tag:SetPosition(-8, 17)
        name_tag:SetColour(1, 0.9, 0.55, 1)

        local cost_parts = { def.cost .. " 积分" }
        if def.hp_cost and def.hp_cost > 0 then
            table.insert(cost_parts, math.floor(def.hp_cost * 100) .. "%生命")
        end
        if def.sanity_cost and def.sanity_cost > 0 then
            table.insert(cost_parts, math.floor(def.sanity_cost * 100) .. "%理智")
        end
        local cost_label = svc_btn:AddChild(Text(BODYTEXTFONT, 11, table.concat(cost_parts, " + ")))
        cost_label:SetPosition(-8, -3)
        cost_label:SetColour(1, 0.45, 0.4, 1)

        local desc_label = svc_btn:AddChild(Text(BODYTEXTFONT, 10, def.desc or ""))
        desc_label:SetPosition(-8, -20)
        desc_label:SetColour(0.72, 0.72, 0.72, 1)

        svc_btn:SetOnClick(function()
            SendModRPCToServer(MOD_RPC["rogue_mode"]["buy_black_market_item"], def.id)
        end)
    end
end

-- ===== 回收页 =====
-- 说明：回收容器 UI 由 modmain 的 containerwidget postinit 动态挂载到 recycle_container。

-- 函数说明：更新手持物品格子的显示。
local function UpdateForgeSlot(self)
    if not self.forge_slot_image then return end

    local active_item = nil
    if self.owner and self.owner:IsValid() and self.owner.replica and self.owner.replica.inventory then
        active_item = self.owner.replica.inventory:GetActiveItem()
    end

    if active_item then
        local image_name = nil
        if active_item.replica and active_item.replica.inventoryitem then
            image_name = active_item.replica.inventoryitem:GetImage()
        end
        if image_name and image_name ~= "" then
            local atlas = (GetInventoryItemAtlas and GetInventoryItemAtlas(image_name)) or "images/inventoryimages.xml"
            self.forge_slot_image:SetTexture(atlas, image_name)
            self.forge_slot_image:Show()
        else
            self.forge_slot_image:Hide()
        end

        if self.forge_slot_name then
            local name = STRINGS.NAMES[string.upper(active_item.prefab)] or active_item.prefab
            self.forge_slot_name:SetString(name)
        end
    else
        self.forge_slot_image:Hide()
        if self.forge_slot_name then
            self.forge_slot_name:SetString("")
        end
    end
end

-- 函数说明：每帧更新回调，更新积分和手持物品显示。
function RogueShopPanel:OnUpdate(dt)
    if self:IsVisible() then
        self:UpdatePoints()
        if self.current_tab == "black_market" then
            UpdateForgeSlot(self)
        end
    end
end

return RogueShopPanel
