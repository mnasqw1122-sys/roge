--[[
    文件说明：modservercreationmain.lua
    功能：在建服界面强制自动切换世界生成预设（根据用户配置切换至标准、海难或哈姆雷特肉鸽版）。
]]
GLOBAL.setmetatable(env, {__index = function(t, k) return GLOBAL.rawget(GLOBAL, k) end})

local scheduler = GLOBAL.scheduler
local TheFrontEnd = GLOBAL.TheFrontEnd
local KnownModIndex = GLOBAL.KnownModIndex
local PopupDialogScreen = GLOBAL.require("screens/redux/popupdialog")
local RETRY_COUNT = 20
local RETRY_INTERVAL = 0.25

-- 函数说明：检查指定的玩法版本是否已完整开启所有前置及其依赖模组
local function IsVariantModEnabled(variant)
    if variant == "standard" then return true end
    
    if variant == "shipwrecked" then
        -- 对于海难版本，必须同时开启主模组 (1467214795) 和 依赖核心模组 (3435352667)
        local main_mod_enabled = KnownModIndex:IsModEnabled("workshop-1467214795") or KnownModIndex:IsModEnabled("1467214795")
        local core_mod_enabled = KnownModIndex:IsModEnabled("workshop-3435352667") or KnownModIndex:IsModEnabled("3435352667")
        return main_mod_enabled and core_mod_enabled
    elseif variant == "hamlet" then
        return KnownModIndex:IsModEnabled("workshop-3322803908") or KnownModIndex:IsModEnabled("3322803908")
    end
    
    return false
end

-- 函数说明：显示缺少前置模组的提示弹窗
local function ShowVariantWarningPopup(variant, on_cancel)
    local mod_name_str = variant == "shipwrecked" and "海难(Shipwrecked) 及核心依赖(Island Adventures - Core)" or "哈姆雷特(Hamlet)"
    local popup = PopupDialogScreen(
        "缺少前置模组",
        "当前选择了 ["..mod_name_str.."] 版本，但未完整开启对应的模组！\n请先在模组列表中勾选启用对应模组及其所有依赖，否则可能会导致游戏崩溃或内容缺失。",
        {
            {
                text = "返回",
                cb = function()
                    TheFrontEnd:PopScreen()
                    if on_cancel then on_cancel() end
                end
            }
        }
    )
    TheFrontEnd:PushScreen(popup)
end

-- 函数说明：根据配置项返回当前应强制切换的世界预设 ID。
local function GetTargetPresetId()
    local variant = "standard"
    if GetModConfigData then
        local ok, value = pcall(GetModConfigData, "WORLD_VARIANT")
        if ok and (value == "shipwrecked" or value == "hamlet") then
            variant = value
        end
    end
    if variant == "shipwrecked" then
        return "ROGUE_SHIPWRECKED_SURVIVAL"
    end
    if variant == "hamlet" then
        return "ROGUE_HAMLET_SURVIVAL"
    end
    return "ROGUE_SURVIVAL"
end

-- 函数说明：在建服界面尝试切换到肉鸽预设，成功时返回 true。
local function ForceRoguePreset()
    if not TheFrontEnd then return false end
    
    local screen = TheFrontEnd:GetOpenScreenOfType("ServerCreationScreen")
    if not screen then return false end
    
    local tab = screen.world_tabs and screen.world_tabs[1]
    if not tab then return false end
    
    if tab.settings_widget and tab.settings_widget.IsNewShard and tab.settings_widget:IsNewShard() then
        local target_preset = GetTargetPresetId()
        local current_preset = tab.settings_widget:GetCurrentPresetId()
        
        -- 在尝试切换预设前，再次确认该预设是否真实存在于游戏中
        -- 避免因为前置模组刚被卸载导致预设数据丢失而崩溃
        local Levels = GLOBAL.require("map/levels")
        local is_preset_valid = false
        if Levels and Levels.GetDataForID then
            local preset_data = Levels.GetDataForID(GLOBAL.LEVELCATEGORY.SETTINGS, target_preset)
            if preset_data then
                -- 进一步校验该预设的 location 基础数据是否也已加载完毕
                -- 这是由于饥荒引擎中 GetDataForID 在返回时会调用 GetDataForLocation
                -- 若 location 数据缺失，同样会导致引擎内部报错
                if preset_data.location then
                    local Customize = GLOBAL.require("map/customize")
                    -- 这里不直接调用可能引发崩溃的引擎方法，而是安全地假设只要 preset_data 存在且没有立刻崩溃即为有效
                    is_preset_valid = true
                end
            end
        end
        
        if not is_preset_valid and target_preset ~= "ROGUE_SURVIVAL" then
            -- 如果目标预设不存在（比如海难被取消勾选了），则回退到标准版预设，以防止崩溃
            target_preset = "ROGUE_SURVIVAL"
        end

        if current_preset ~= target_preset then
            if tab.OnCombinedPresetButton then
                -- 在调用前，再做最后一次检查：如果连 ROGUE_SURVIVAL 的基础数据都因为UI状态错乱而丢失了，就直接中止
                local default_data = Levels.GetDataForID(GLOBAL.LEVELCATEGORY.SETTINGS, target_preset)
                if not default_data then
                    return false
                end
                
                tab:OnCombinedPresetButton(target_preset)
                return true
            end
            return false
        end
        return true
    end
    return false
end

-- 函数说明：在 UI 尚未完全就绪时进行有限次重试，提高预设自动切换成功率。
local function TryForceRoguePreset(tries)
    if ForceRoguePreset() then
        return true
    end
    if tries <= 0 then
        return false
    end
    scheduler:ExecuteInTime(RETRY_INTERVAL, function()
        TryForceRoguePreset(tries - 1)
    end)
    return false
end

-- 拦截模组配置界面的 Apply 按钮，在应用时检查前置模组，并在应用后自动切换预设
env.AddClassPostConstruct("screens/redux/modconfigurationscreen", function(self)
    local old_Apply = self.Apply
    self.Apply = function(self)
        if self.modname == modname then
            local selected_variant = "standard"
            for i, v in pairs(self.options) do
                if v.name == "WORLD_VARIANT" then
                    selected_variant = v.value
                    break
                end
            end
            
            -- 如果缺少前置模组，拦截应用并弹窗提示
            if not IsVariantModEnabled(selected_variant) then
                ShowVariantWarningPopup(selected_variant)
                return
            end
            
            -- 正常应用配置
            old_Apply(self)
            
            -- 应用后，延迟自动切换世界预设，以确保配置已保存
            if scheduler then
                scheduler:ExecuteInTime(0.5, function()
                    TryForceRoguePreset(RETRY_COUNT)
                end)
            end
        else
            return old_Apply(self)
        end
    end
end)

if scheduler then
    scheduler:ExecuteInTime(0, function()
        -- 只有在当前模组真正被启用时，才执行预设切换和前置检测
        if not KnownModIndex:IsModEnabled(modname) then
            return
        end

        -- 检查当前保存的配置，如果缺少前置模组，给予弹窗提示，并阻止后续的自动切换预设，以免崩溃
        local ok, variant = pcall(GetModConfigData, "WORLD_VARIANT")
        if ok and variant and variant ~= "standard" then
            if not IsVariantModEnabled(variant) then
                ShowVariantWarningPopup(variant)
                return -- 关键修复：阻止执行预设切换，避免未加载对应模组时强制切换引发崩溃
            end
        end
        
        -- 延迟1帧执行预设切换，确保地图数据已完全加载，避免和其它模组(如海难)的加载时序冲突
        scheduler:ExecuteInTime(0.1, function()
            TryForceRoguePreset(RETRY_COUNT)
        end)
    end)
end
