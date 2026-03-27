local Widget = require "widgets/widget"
local Text = require "widgets/text"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
local ShopConfig = require("rogue/config") -- 如果有别的地方依赖需要修正
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

local function GetItemTextureName(prefab)
    local mapped = PREFAB_TO_IMAGE[prefab] or prefab
    return mapped .. ".tex"
end

local RogueShopPanel = Class(Widget, function(self, owner)
    Widget._ctor(self, "RogueShopPanel")
    self.owner = owner

    -- 根节点居中
    self:SetVAnchor(ANCHOR_MIDDLE)
    self:SetHAnchor(ANCHOR_MIDDLE)
    self:SetScaleMode(SCALEMODE_PROPORTIONAL)

    -- 背景
    self.bg = self:AddChild(Image("images/global.xml", "square.tex"))
    self.bg:SetSize(700, 600)
    self.bg:SetTint(0, 0, 0, 0.85)

    -- 标题
    self.title = self:AddChild(Text(TITLEFONT, 45, "肉鸽商店 & 回收站"))
    self.title:SetPosition(0, 220)
    self.title:SetColour(1, 0.8, 0.2, 1)

    -- 积分显示
    self.points_text = self:AddChild(Text(BODYTEXTFONT, 30, "当前积分: 0"))
    self.points_text:SetPosition(0, 170)
    self.points_text:SetColour(0.8, 1, 0.8, 1)

    -- 选项卡按钮
    self.buy_tab_btn = self:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_over.tex"))
    self.buy_tab_btn:SetPosition(-120, 120)
    self.buy_tab_btn:SetText("购买")
    self.buy_tab_btn:SetOnClick(function() self:ShowTab("buy") end)

    self.recycle_tab_btn = self:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_over.tex"))
    self.recycle_tab_btn:SetPosition(120, 120)
    self.recycle_tab_btn:SetText("回收")
    self.recycle_tab_btn:SetOnClick(function() self:ShowTab("recycle") end)

    -- 容器
    self.buy_container = self:AddChild(Widget("BuyContainer"))
    self.buy_container:SetPosition(0, -30)
    self.recycle_container = self:AddChild(Widget("RecycleContainer"))
    self.recycle_container:SetPosition(0, -30)

    -- 关闭按钮
    self.close_btn = self:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_over.tex"))
    self.close_btn:SetPosition(0, -230)
    self.close_btn:SetText("关闭")
    self.close_btn:SetOnClick(function() self:Hide() end)

    self:BuildBuyList()
    self:ShowTab("buy")

    self.inst:ListenForEvent("rogue_dirty", function() self:UpdatePoints() end, self.owner)
    self:UpdatePoints()
    self:StartUpdating()
end)

function RogueShopPanel:UpdatePoints()
    if not self.owner or not self.owner:IsValid() then return end
    local state = StateSchema.ReadFromNetvars(self.owner)
    local points = state.rogue_points or 0
    self.points_text:SetString("当前积分: " .. points)
end

function RogueShopPanel:ShowTab(tab)
    self.current_tab = tab
    if tab == "buy" then
        self:BuildBuyList() -- 每次切换到购买页时刷新列表
        self.buy_container:Show()
        self.recycle_container:Hide()
        self.buy_tab_btn:Select()
        self.recycle_tab_btn:Unselect()
    else
        self.buy_container:Hide()
        self.recycle_container:Show()
        self.buy_tab_btn:Unselect()
        self.recycle_tab_btn:Select()
        self:BuildRecycleList() -- 每次切换到回收页时刷新列表
    end
end

function RogueShopPanel:BuildBuyList()
    self.buy_container:KillAllChildren()
    
    local items = ShopConfig.GetDailyShopItems()
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
        
        -- 尝试加载物品贴图
        local tex_name = GetItemTextureName(def.prefab)
        local atlas = (GetInventoryItemAtlas and GetInventoryItemAtlas(tex_name)) or "images/inventoryimages.xml"
        
        local item_img = item_btn:AddChild(Image(atlas, tex_name))
        
        local item_name = STRINGS.NAMES[string.upper(def.prefab)] or def.prefab
        local text = item_name
        if def.count and def.count > 1 then
            text = text .. " x" .. def.count
        end
        text = text .. "\n" .. def.cost .. " 积分"
        
        local label = item_btn:AddChild(Text(BODYTEXTFONT, 16, text))
        label:SetPosition(0, -42)
        
        item_btn:SetOnClick(function()
            SendModRPCToServer(MOD_RPC["rogue_mode"]["buy_shop_item"], def.id)
        end)
    end
end

function RogueShopPanel:BuildRecycleList()
    self.recycle_container:KillAllChildren()

    if not self.owner or not self.owner.replica or not self.owner.replica.inventory then
        local msg = self.recycle_container:AddChild(Text(BODYTEXTFONT, 25, "无法获取背包信息"))
        msg:SetPosition(0, 0)
        return
    end

    local inv = self.owner.replica.inventory
    local recyclables = {}
    
    -- 扫描背包（只在客户端展示，实际回收由服务端验证）
    for k, v in pairs(inv:GetItems()) do
        if v and v.prefab then
            local val = ShopConfig.GetRecycleValue(v.prefab)
            if val > 0 then
                if not recyclables[v.prefab] then
                    recyclables[v.prefab] = { name = v.name or v.prefab, count = 0, val = val }
                end
                if v.replica.stackable then
                    recyclables[v.prefab].count = recyclables[v.prefab].count + v.replica.stackable:StackSize()
                else
                    recyclables[v.prefab].count = recyclables[v.prefab].count + 1
                end
            end
        end
    end

    local sorted_items = {}
    for prefab, data in pairs(recyclables) do
        table.insert(sorted_items, { prefab = prefab, name = data.name, count = data.count, val = data.val })
    end
    table.sort(sorted_items, function(a, b) return a.val > b.val end)

    if #sorted_items == 0 then
        local msg = self.recycle_container:AddChild(Text(BODYTEXTFONT, 25, "背包中没有可回收的物品"))
        msg:SetPosition(0, 0)
        return
    end

    local cols = 5
    local start_x = -250
    local start_y = 60
    local dx = 120
    local dy = -90
    
    local page = self.recycle_page or 1
    local max_items = 15
    local total_pages = math.ceil(#sorted_items / max_items)
    if page > total_pages then page = total_pages end
    self.recycle_page = page

    local start_idx = (page - 1) * max_items + 1
    local end_idx = math.min(#sorted_items, start_idx + max_items - 1)

    for i = start_idx, end_idx do
        local item = sorted_items[i]
        local idx = i - start_idx
        local row = math.floor(idx / cols)
        local col = idx % cols
        local x = start_x + col * dx
        local y = start_y + row * dy

        local item_btn = self.recycle_container:AddChild(ImageButton("images/hud.xml", "inv_slot.tex", "inv_slot_spoiled.tex", "inv_slot_spoiled.tex", "inv_slot_spoiled.tex"))
        item_btn:SetPosition(x, y)
        item_btn:SetScale(1.0, 1.0, 1.0)
        
        -- 尝试加载物品贴图
        local tex_name = GetItemTextureName(item.prefab)
        local atlas = (GetInventoryItemAtlas and GetInventoryItemAtlas(tex_name)) or "images/inventoryimages.xml"
        
        local item_img = item_btn:AddChild(Image(atlas, tex_name))
        
        local text = item.name .. " x" .. item.count .. "\n(+" .. item.val .. "分)"
        local label = item_btn:AddChild(Text(BODYTEXTFONT, 16, text))
        label:SetPosition(0, -42)
        
        item_btn:SetOnClick(function()
            SendModRPCToServer(MOD_RPC["rogue_mode"]["recycle_item"], item.prefab)
            self.owner:DoTaskInTime(0.5, function()
                if self.inst:IsValid() and self.current_tab == "recycle" then
                    self:BuildRecycleList()
                end
            end)
        end)
    end
    
    if total_pages > 1 then
        local page_text = self.recycle_container:AddChild(Text(BODYTEXTFONT, 25, page .. "/" .. total_pages))
        page_text:SetPosition(0, -150)
        
        if page > 1 then
            local prev_btn = self.recycle_container:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_onclick.tex"))
            prev_btn:SetPosition(-100, -150)
            prev_btn:SetScale(0.6, 0.6, 0.6)
            prev_btn:SetText("上一页")
            prev_btn:SetOnClick(function()
                self.recycle_page = self.recycle_page - 1
                self:BuildRecycleList()
            end)
        end
        
        if page < total_pages then
            local next_btn = self.recycle_container:AddChild(ImageButton("images/ui.xml", "button_small.tex", "button_small_over.tex", "button_small_disabled.tex", "button_small_onclick.tex"))
            next_btn:SetPosition(100, -150)
            next_btn:SetScale(0.6, 0.6, 0.6)
            next_btn:SetText("下一页")
            next_btn:SetOnClick(function()
                self.recycle_page = self.recycle_page + 1
                self:BuildRecycleList()
            end)
        end
    end
end

function RogueShopPanel:OnUpdate(dt)
    if self:IsVisible() then
        -- 阻止玩家移动，或者这里只做状态刷新
        self:UpdatePoints()
    end
end

return RogueShopPanel
