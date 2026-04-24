local Widget = require "widgets/widget"
local Text = require "widgets/text"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local ShopConfig = require("rogue/shop_config")
local StateSchema = require("rogue/state_schema")

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

-- 函数说明：获取物品的贴图名称。
local function GetItemTextureName(prefab)
    local mapped = PREFAB_TO_IMAGE[prefab] or prefab
    return mapped .. ".tex"
end

local RogueShopPanel = Class(Widget, function(self, owner)
    Widget._ctor(self, "RogueShopPanel")
    self.owner = owner

    self:SetVAnchor(ANCHOR_MIDDLE)
    self:SetHAnchor(ANCHOR_MIDDLE)
    self:SetScaleMode(SCALEMODE_PROPORTIONAL)

    self.title = self:AddChild(Text(TITLEFONT, 45, "肉鸽商店 & 回收站"))
    self.title:SetPosition(0, 220)
    self.title:SetColour(1, 0.8, 0.2, 1)

    self.points_text = self:AddChild(Text(BODYTEXTFONT, 30, "当前积分: 0"))
    self.points_text:SetPosition(0, 170)
    self.points_text:SetColour(0.8, 1, 0.8, 1)

    -- 选项卡按钮：购买 / 黑市 / 回收
    self.buy_tab_btn = self:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_over.tex"))
    self.buy_tab_btn:SetPosition(-180, 120)
    self.buy_tab_btn:SetText("购买")
    self.buy_tab_btn:SetOnClick(function() self:ShowTab("buy") end)

    self.black_market_tab_btn = self:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_over.tex"))
    self.black_market_tab_btn:SetPosition(0, 120)
    self.black_market_tab_btn:SetText("黑市")
    self.black_market_tab_btn.text:SetColour(0.9, 0.3, 0.3, 1)
    self.black_market_tab_btn:SetOnClick(function() self:ShowTab("black_market") end)

    self.recycle_tab_btn = self:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_over.tex"))
    self.recycle_tab_btn:SetPosition(180, 120)
    self.recycle_tab_btn:SetText("回收")
    self.recycle_tab_btn:SetOnClick(function() self:ShowTab("recycle") end)

    self.buy_container = self:AddChild(Widget("BuyContainer"))
    self.buy_container:SetPosition(0, -30)

    self.black_market_container = self:AddChild(Widget("BlackMarketContainer"))
    self.black_market_container:SetPosition(0, -30)

    self.recycle_container = self:AddChild(Widget("RecycleContainer"))
    self.recycle_container:SetPosition(0, -30)

    self.close_btn = self:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_over.tex"))
    self.close_btn:SetPosition(0, -250)
    self.close_btn:SetText("关闭")
    self.close_btn:SetOnClick(function()
        SendModRPCToServer(MOD_RPC["rogue_mode"]["close_recycle_bin"])
        self:Hide()
    end)

    self.recycle_all_btn = self.recycle_container:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_over.tex"))
    self.recycle_all_btn:SetPosition(80, -220)
    self.recycle_all_btn:SetText("一键回收")
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

-- 函数说明：更新积分显示。
function RogueShopPanel:UpdatePoints()
    if not self.owner or not self.owner:IsValid() then return end
    local state = StateSchema.ReadFromNetvars(self.owner)
    local points = state.rogue_points or 0
    self.points_text:SetString("当前积分: " .. points)
end

-- 函数说明：切换选项卡。
function RogueShopPanel:ShowTab(tab)
    self.current_tab = tab
    self.buy_container:Hide()
    self.black_market_container:Hide()
    self.recycle_container:Hide()
    self.buy_tab_btn:Unselect()
    self.black_market_tab_btn:Unselect()
    self.recycle_tab_btn:Unselect()

    if tab == "buy" then
        self:BuildBuyList()
        self.buy_container:Show()
        self.buy_tab_btn:Select()
        self.close_btn:SetPosition(0, -250)
        SendModRPCToServer(MOD_RPC["rogue_mode"]["close_recycle_bin"])
    elseif tab == "black_market" then
        self:BuildBlackMarketList()
        self.black_market_container:Show()
        self.black_market_tab_btn:Select()
        self.close_btn:SetPosition(0, -250)
        SendModRPCToServer(MOD_RPC["rogue_mode"]["close_recycle_bin"])
    else
        self.recycle_container:Show()
        self.recycle_tab_btn:Select()
        self.close_btn:SetPosition(-80, -250)
        SendModRPCToServer(MOD_RPC["rogue_mode"]["open_recycle_bin"])
    end
end

-- 函数说明：构建普通商品购买列表，含折扣标签和限购显示。
function RogueShopPanel:BuildBuyList()
    self.buy_container:KillAllChildren()

    local items = ShopConfig.GetDailyShopItems()
    local discounts = ShopConfig.GetDailyDiscounts()
    local cols = 5
    local start_x = -250
    local start_y = 60
    local dx = 120
    local dy = -90

    for i, def in ipairs(items) do
        local row = math.floor((i - 1) / cols)
        local col = (i - 1) % cols
        local x = start_x + col * dx
        local y = start_y + row * dy

        local item_btn = self.buy_container:AddChild(ImageButton("images/hud.xml", "inv_slot.tex", "inv_slot_spoiled.tex", "inv_slot_spoiled.tex", "inv_slot_spoiled.tex"))
        item_btn:SetPosition(x, y)
        item_btn:SetScale(1.0, 1.0, 1.0)

        local tex_name = GetItemTextureName(def.prefab)
        local atlas = (GetInventoryItemAtlas and GetInventoryItemAtlas(tex_name)) or "images/inventoryimages.xml"
        local item_img = item_btn:AddChild(Image(atlas, tex_name))

        local item_name = STRINGS.NAMES[string.upper(def.prefab)] or def.prefab
        local text = item_name
        if def.count and def.count > 1 then
            text = text .. " x" .. def.count
        end

        local discount_pct = discounts[def.id]
        local final_cost = def.cost
        if discount_pct and discount_pct > 0 then
            final_cost = math.ceil(def.cost * (1 - discount_pct))
            text = text .. "\n" .. final_cost .. " 积分"
            local discount_tag = item_btn:AddChild(Text(BODYTEXTFONT, 14, "-" .. math.floor(discount_pct * 100) .. "%"))
            discount_tag:SetPosition(25, 25)
            discount_tag:SetColour(0.2, 1, 0.2, 1)
        else
            text = text .. "\n" .. def.cost .. " 积分"
        end

        local limit = ShopConfig.GetPurchaseLimit(def.prefab)
        if limit < 99 then
            local limit_tag = item_btn:AddChild(Text(BODYTEXTFONT, 12, "限" .. limit))
            limit_tag:SetPosition(-25, 25)
            limit_tag:SetColour(1, 0.8, 0.2, 1)
        end

        if def.season then
            local season_tag = item_btn:AddChild(Text(BODYTEXTFONT, 12, "季节"))
            season_tag:SetPosition(25, -25)
            season_tag:SetColour(0.5, 0.8, 1, 1)
        end

        local label = item_btn:AddChild(Text(BODYTEXTFONT, 16, text))
        label:SetPosition(0, -42)

        item_btn:SetOnClick(function()
            SendModRPCToServer(MOD_RPC["rogue_mode"]["buy_shop_item"], def.id)
        end)
    end
end

-- 函数说明：构建黑市服务界面，左侧为手持物品显示格子，右侧为操作按钮。
-- 玩家从背包拿起物品后，左侧格子自动显示该物品，点击右侧按钮执行操作。
function RogueShopPanel:BuildBlackMarketList()
    self.black_market_container:KillAllChildren()

    local items = ShopConfig.GetBlackMarketItems()

    -- ===== 左侧：手持物品显示格子 =====
    local left_panel = self.black_market_container:AddChild(Widget("LeftPanel"))
    left_panel:SetPosition(-160, 10)

    -- 格子背景框
    local slot_bg = left_panel:AddChild(Image("images/hud.xml", "inv_slot.tex"))
    slot_bg:SetScale(2.2, 2.2, 1.0)

    -- 手持物品图标（动态更新）
    self.forge_slot_image = left_panel:AddChild(Image("images/hud.xml", "inv_slot.tex"))
    self.forge_slot_image:SetScale(1.8, 1.8, 1.0)
    self.forge_slot_image:Hide()

    -- 物品名称标签
    self.forge_slot_name = left_panel:AddChild(Text(BODYTEXTFONT, 14, ""))
    self.forge_slot_name:SetPosition(0, -50)
    self.forge_slot_name:SetColour(1, 1, 1, 1)

    -- ===== 右侧：操作按钮区域 =====
    local right_panel = self.black_market_container:AddChild(Widget("RightPanel"))
    right_panel:SetPosition(160, 10)

    local btn_y = 50
    local btn_dy = -130

    for i, def in ipairs(items) do
        local y = btn_y + (i - 1) * btn_dy

        local svc_btn = right_panel:AddChild(ImageButton("images/ui.xml", "button_large.tex", "button_large_over.tex", "button_large_disabled.tex", "button_large_over.tex"))
        svc_btn:SetPosition(0, y)
        svc_btn:SetScale(1.2, 1.0, 1.0)

        local svc_name = def.service == "reforge" and "重铸" or "强化"
        local name_tag = svc_btn:AddChild(Text(TITLEFONT, 22, svc_name))
        name_tag:SetPosition(0, 12)
        name_tag:SetColour(1, 0.85, 0.3, 1)

        local cost_parts = { def.cost .. " 积分" }
        if def.hp_cost and def.hp_cost > 0 then
            table.insert(cost_parts, math.floor(def.hp_cost * 100) .. "%生命")
        end
        if def.sanity_cost and def.sanity_cost > 0 then
            table.insert(cost_parts, math.floor(def.sanity_cost * 100) .. "%理智")
        end
        local cost_label = svc_btn:AddChild(Text(BODYTEXTFONT, 15, table.concat(cost_parts, " + ")))
        cost_label:SetPosition(0, -8)
        cost_label:SetColour(0.9, 0.5, 0.5, 1)

        local desc_label = svc_btn:AddChild(Text(BODYTEXTFONT, 13, def.desc or ""))
        desc_label:SetPosition(0, -26)
        desc_label:SetColour(0.75, 0.75, 0.75, 1)

        svc_btn:SetOnClick(function()
            SendModRPCToServer(MOD_RPC["rogue_mode"]["buy_black_market_item"], def.id)
        end)
    end
end

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
