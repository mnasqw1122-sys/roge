local DeepAffixes = require("rogue/boss_mechanics_v2")
local GLOBAL = _G or GLOBAL

-- [[ 范例词缀: 领域工匠 (Arena Forge) ]]
-- 核心机制:
-- 1. 改变环境: 熊獾 (Bearger) 战斗开始时，升起 4 根无法摧毁的格罗姆雕像。
-- 2. 状态机劫持: 熊獾的普攻伤害极高（秒杀级），且不会有硬直。
-- 3. 破防机制: 玩家必须勾引熊獾使用“拍地重砸” (pound) 技能砸碎格罗姆雕像，雕像碎裂后，熊獾会陷入长达 10 秒的绝对破防眩晕，这是唯一的输出窗口。

local function SpawnObsidianPillars(boss, radius)
    boss._rogue_pillars = {}
    local pt = GLOBAL.Vector3(boss.Transform:GetWorldPosition())
    local PI = GLOBAL.PI
    local angles = {0, PI/2, PI, 3*PI/2}
    
    for _, angle in ipairs(angles) do
        local offset = GLOBAL.Vector3(math.cos(angle) * radius, 0, math.sin(angle) * radius)
        local pillar_pos = pt + offset
        
        -- 生成原版的格罗姆雕像
        local pillar = GLOBAL.SpawnPrefab("statueglommer")
        if pillar then
            pillar.Transform:SetPosition(pillar_pos:Get())
            -- 保护雕像不被普通攻击摧毁
            if pillar.components.workable then pillar:RemoveComponent("workable") end
            if pillar.components.health then pillar.components.health:SetInvincible(true) end
            
            -- 给雕像打上特殊标签，用于判断是否被 Boss 的重击命中
            pillar:AddTag("rogue_obsidian_pillar")
            table.insert(boss._rogue_pillars, pillar)
            
            -- 升起特效
            GLOBAL.SpawnPrefab("dirt_puff").Transform:SetPosition(pillar_pos:Get())
        end
    end
    
    -- 广播警告 (使用全服公告)
    if boss._rogue_deps and boss._rogue_deps.Announce then
        boss._rogue_deps.Announce("【领域工匠】格罗姆雕像已升起！引诱熊獾的“拍地重砸”击碎雕像！")
    elseif GLOBAL.TheNet then
        GLOBAL.TheNet:Announce("【领域工匠】格罗姆雕像已升起！引诱熊獾的“拍地重砸”击碎雕像！")
    end
end

local function CleanPillars(boss)
    if boss._rogue_pillars then
        for _, pillar in ipairs(boss._rogue_pillars) do
            if pillar and pillar:IsValid() then
                GLOBAL.SpawnPrefab("rock_break_fx").Transform:SetPosition(pillar.Transform:GetWorldPosition())
                pillar:Remove()
            end
        end
        boss._rogue_pillars = nil
    end
end

DeepAffixes.RegisterDeepAffix("arena_forge_bearger", {
    name = "领域工匠 (Arena Forge)",
    desc = "场地升起坚不可摧的格罗姆雕像。Boss的攻击一击致命。引诱Boss的“拍地重砸”击碎雕像使其陷入长久破防眩晕！",
    
    OnAttach = function(boss, HijackSG, InjectNewState, HijackBrain)
        if boss.prefab ~= "bearger" then return end -- 仅适用于熊獾
        
        -- 1. 改变环境: 生成格罗姆雕像
        boss:DoTaskInTime(1, function() SpawnObsidianPillars(boss, 15) end)
        
        -- 2. 数值修改: 普攻伤害调至秒杀级，迫使玩家走位
        if boss.components.combat then
            boss.components.combat:SetDefaultDamage(9999)
        end
        
        -- 3. 状态机劫持: 劫持熊獾的“拍地重砸”动作 (SG 节点名: pound)
        -- 在熊獾的重砸判定帧 (Timeline frame 22) 插入检测逻辑
        HijackSG(boss, "pound", {
            timeline_injections = {
                {
                    time = 22 * GLOBAL.FRAMES, -- 拍地发生的那一瞬间
                    fn = function(inst)
                        -- 检测周围是否有格罗姆雕像
                        local pt = GLOBAL.Vector3(inst.Transform:GetWorldPosition())
                        local ents = GLOBAL.TheSim:FindEntities(pt.x, pt.y, pt.z, 6, {"rogue_obsidian_pillar"})
                        
                        if #ents > 0 then
                            local hit_pillar = ents[1]
                            -- 击碎雕像
                            GLOBAL.SpawnPrefab("rock_break_fx").Transform:SetPosition(hit_pillar.Transform:GetWorldPosition())
                            hit_pillar:Remove()
                            
                            -- 核心机制: 熊獾因为砸中硬物，陷入绝对眩晕！
                            -- 强制改变其 StateGraph，进入长时间眩晕状态
                            inst.sg:GoToState("rogue_stunned_break")
                            
                            -- 广播
                            if inst._rogue_deps and inst._rogue_deps.Announce then
                                inst._rogue_deps.Announce("格罗姆雕像碎裂！熊獾绝对破防，快输出！")
                            elseif GLOBAL.TheNet then
                                GLOBAL.TheNet:Announce("格罗姆雕像碎裂！熊獾绝对破防，快输出！")
                            end
                        end
                    end
                }
            }
        })
        
        -- 4. 注入新动作节点: 绝对破防眩晕状态
        InjectNewState(boss, GLOBAL.State{
            name = "rogue_stunned_break",
            tags = {"busy", "stunned"},
            
            events =
            {
                GLOBAL.EventHandler("attacked", function(inst)
                    -- 在破防眩晕期间被攻击不会打断眩晕状态
                end),
            },
            
            onenter = function(inst)
                inst.Physics:Stop()
                -- 播放一个类似于睡觉或痛苦的动画循环
                inst.AnimState:PlayAnimation("sleep_loop", true)
                -- 在眩晕期间，熊獾受到额外 200% 伤害 (破防)
                if inst.components.combat and inst.components.combat.externaldamagetakenmultipliers then
                    inst.components.combat.externaldamagetakenmultipliers:SetModifier(inst, 3.0, "rogue_stunned")
                end
                
                -- 设置 10 秒定时器后恢复
                inst.sg:SetTimeout(10)
            end,
            
            ontimeout = function(inst)
                -- 必须绕开原版的 wake 状态，因为 wake 必定会触发熊獾打哈欠 (yawn) 导致全屏睡眠秒杀。
                -- 我们直接让它播放一个受击或者晃脑袋的动画，然后回到待机状态。
                inst.AnimState:PlayAnimation("hit")
                inst.AnimState:PushAnimation("idle", true)
                inst.sg:GoToState("idle")
            end,
            
            onexit = function(inst)
                -- 恢复护甲
                if inst.components.combat and inst.components.combat.externaldamagetakenmultipliers then
                    inst.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, "rogue_stunned")
                end
            end
        })
    end,
    
    OnDeath = function(boss, data)
        CleanPillars(boss)
    end
})

return DeepAffixes