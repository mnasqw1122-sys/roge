local DeepAffixes = require("rogue/boss_mechanics_v2")
local GLOBAL = _G or GLOBAL

-- [[ 词缀1: 统御军势 (Summoner Legion) ]]
-- 适配Boss: 树精守卫 (leif / treeguard)
-- 核心机制: 每20秒召唤2只树苗，树苗存活时Boss减伤50%，必须先清除树苗才能有效输出
DeepAffixes.RegisterDeepAffix("summoner_legion_treeguard", {
    name = "统御军势 (Summoner Legion)",
    desc = "树精守卫每20秒召唤2只树苗护卫。树苗存活期间，Boss受到的伤害降低50%。清除所有树苗后Boss短暂暴露破绽！",

    OnAttach = function(boss, HijackSG, InjectNewState, HijackBrain)
        if boss.prefab ~= "leif" and boss.prefab ~= "treeguard" then return end

        boss._rogue_minions = {}
        boss._rogue_summon_timer = nil

        -- 标记Boss拥有减伤效果
        boss._rogue_legion_shielded = true
        if boss.components.combat and boss.components.combat.externaldamagetakenmultipliers then
            boss.components.combat.externaldamagetakenmultipliers:SetModifier(boss, 0.5, "rogue_legion_shield")
        end

        -- 召唤树苗函数
        local function SummonMinions(inst)
            if not inst:IsValid() or inst.components.health and inst.components.health:IsDead() then return end

            for _ = 1, 2 do
                local angle = math.random() * 2 * GLOBAL.PI
                local offset = GLOBAL.Vector3(math.cos(angle) * 5, 0, math.sin(angle) * 5)
                local pt = GLOBAL.Vector3(inst.Transform:GetWorldPosition()) + offset

                local minion = GLOBAL.SpawnPrefab("birchnutdrake")
                if minion then
                    minion.Transform:SetPosition(pt:Get())
                    minion:AddTag("rogue_legion_minion")

                    -- 树苗死亡时通知Boss移除减伤
                    minion:ListenForEvent("death", function(m_inst)
                        if inst:IsValid() and inst._rogue_minions then
                            for i, m in ipairs(inst._rogue_minions) do
                                if m == m_inst then
                                    table.remove(inst._rogue_minions, i)
                                    break
                                end
                            end
                            -- 所有树苗死亡时，Boss短暂暴露破绽
                            if #inst._rogue_minions == 0 and inst.components.combat then
                                inst._rogue_legion_shielded = false
                                if inst.components.combat.externaldamagetakenmultipliers then
                                    inst.components.combat.externaldamagetakenmultipliers:RemoveModifier(inst, "rogue_legion_shield")
                                end
                                -- 暴露5秒后恢复减伤
                                inst:DoTaskInTime(5, function(i)
                                    if i:IsValid() and not (i.components.health and i.components.health:IsDead()) then
                                        i._rogue_legion_shielded = true
                                        if i.components.combat and i.components.combat.externaldamagetakenmultipliers then
                                            i.components.combat.externaldamagetakenmultipliers:SetModifier(i, 0.5, "rogue_legion_shield")
                                        end
                                    end
                                end)
                                if inst._rogue_deps and inst._rogue_deps.Announce then
                                    inst._rogue_deps.Announce("树精护卫全部倒下！树精守卫暴露破绽5秒！")
                                end
                            end
                        end
                    end)

                    table.insert(inst._rogue_minions, minion)
                    GLOBAL.SpawnPrefab("dirt_puff").Transform:SetPosition(pt:Get())
                end
            end

            if boss._rogue_deps and boss._rogue_deps.Announce then
                boss._rogue_deps.Announce("【统御军势】树精守卫召唤了护卫树苗！清除树苗才能有效攻击Boss！")
            end
        end

        -- 延迟1秒后开始召唤循环
        boss:DoTaskInTime(1, function()
            SummonMinions(boss)
            boss._rogue_summon_timer = boss:DoPeriodicTask(20, function(inst)
                SummonMinions(inst)
            end)
        end)
    end,

    OnDeath = function(boss, data)
        if boss._rogue_summon_timer then
            boss._rogue_summon_timer:Cancel()
            boss._rogue_summon_timer = nil
        end
        if boss._rogue_minions then
            for _, minion in ipairs(boss._rogue_minions) do
                if minion and minion:IsValid() then
                    GLOBAL.SpawnPrefab("dirt_puff").Transform:SetPosition(minion.Transform:GetWorldPosition())
                    minion:Remove()
                end
            end
            boss._rogue_minions = nil
        end
    end
})

-- [[ 词缀2: 雷暴猎场 (Thunder Hunt) ]]
-- 适配Boss: 鹿角鹅 (moose)
-- 核心机制: 标记1名玩家为猎物，Boss对猎物伤害+100%，其他玩家攻击Boss减伤30%
DeepAffixes.RegisterDeepAffix("thunder_hunt_moose", {
    name = "雷暴猎场 (Thunder Hunt)",
    desc = "鹿角鹅锁定一名猎物，对其伤害翻倍。其他玩家攻击Boss减伤30%。猎物可通过远离Boss解除标记。",

    OnAttach = function(boss, HijackSG, InjectNewState, HijackBrain)
        if boss.prefab ~= "moose" then return end

        boss._rogue_prey = nil
        boss._rogue_hunt_active = true

        -- 选择猎物
        local function SelectPrey(inst)
            if not inst:IsValid() or inst.components.health and inst.components.health:IsDead() then return end

            local x, y, z = inst.Transform:GetWorldPosition()
            local players = GLOBAL.FindPlayersInRange(x, y, z, 30, true)

            if #players > 0 then
                local prey = players[math.random(#players)]
                inst._rogue_prey = prey

                -- 给猎物添加视觉标记
                if prey.components.colouradder then
                    prey.components.colouradder:PushColour("rogue_hunted", 0.8, 0.2, 0, 0)
                end

                if inst._rogue_deps and inst._rogue_deps.Announce then
                    inst._rogue_deps.Announce("【雷暴猎场】鹿角鹅锁定了猎物：" .. prey:GetDisplayName() .. "！小心！")
                end

                -- 8秒后解除猎物标记
                inst:DoTaskInTime(8, function(i)
                    if i:IsValid() and i._rogue_prey and i._rogue_prey:IsValid() then
                        if i._rogue_prey.components.colouradder then
                            i._rogue_prey.components.colouradder:PopColour("rogue_hunted")
                        end
                        i._rogue_prey = nil
                    end
                end)
            end
        end

        -- 劫持Boss的攻击，对猎物伤害翻倍
        if boss.components.combat then
            local old_attack = boss.components.combat.GetHitDamage
            boss.components.combat.GetHitDamage = function(self, target)
                local dmg = old_attack and old_attack(self) or self.defaultdamage or 50
                if target and target == boss._rogue_prey then
                    dmg = dmg * 2
                end
                return dmg
            end
        end

        -- 延迟1秒后开始猎杀循环
        boss:DoTaskInTime(1, function()
            SelectPrey(boss)
            boss._rogue_hunt_timer = boss:DoPeriodicTask(12, function(inst)
                SelectPrey(inst)
            end)
        end)
    end,

    OnDeath = function(boss, data)
        if boss._rogue_hunt_timer then
            boss._rogue_hunt_timer:Cancel()
            boss._rogue_hunt_timer = nil
        end
        if boss._rogue_prey and boss._rogue_prey:IsValid() then
            if boss._rogue_prey.components.colouradder then
                boss._rogue_prey.components.colouradder:PopColour("rogue_hunted")
            end
            boss._rogue_prey = nil
        end
    end
})

-- [[ 词缀3: 双相裂变 (Phase Shift) ]]
-- 适配Boss: 蜘蛛女王 (spiderqueen")
-- 核心机制: 血量50%时分裂为两只弱化版，击杀间隔>15秒则复活
DeepAffixes.RegisterDeepAffix("phase_shift_spiderqueen", {
    name = "双相裂变 (Phase Shift)",
    desc = "蜘蛛女王在血量降至50%时分裂为两只弱化个体。若两只分身击杀间隔超过15秒，先死的分身将复活！",

    OnAttach = function(boss, HijackSG, InjectNewState, HijackBrain)
        if boss.prefab ~= "spiderqueen" then return end

        boss._rogue_phase_shifted = false
        boss._rogue_clone = nil
        boss._rogue_clone_death_time = nil

        -- 监听血量变化
        boss:ListenForEvent("healthdelta", function(inst, data)
            if inst._rogue_phase_shifted then return end
            if not inst.components.health then return end

            local pct = inst.components.health:GetPercent()
            if pct <= 0.5 then
                inst._rogue_phase_shifted = true

                -- 分裂：生成一只弱化版蜘蛛女王
                local x, y, z = inst.Transform:GetWorldPosition()
                local angle = math.random() * 2 * GLOBAL.PI
                local offset = GLOBAL.Vector3(math.cos(angle) * 6, 0, math.sin(angle) * 6)

                local clone = GLOBAL.SpawnPrefab("spiderqueen")
                if clone then
                    clone.Transform:SetPosition(x + offset.x, y, z + offset.z)
                    clone:AddTag("rogue_phase_clone")

                    -- 弱化：血量为原版50%
                    if clone.components.health then
                        local max_hp = clone.components.health.maxhealth
                        clone.components.health:SetMaxHealth(max_hp * 0.5)
                        clone.components.health:SetPercent(1)
                    end

                    -- 原Boss也弱化
                    if inst.components.health then
                        local max_hp = inst.components.health.maxhealth
                        inst.components.health:SetMaxHealth(max_hp * 0.5)
                        inst.components.health:SetPercent(1)
                    end

                    inst._rogue_clone = clone

                    -- 监听分身死亡
                    clone:ListenForEvent("death", function(c_inst)
                        inst._rogue_clone_death_time = GLOBAL.GetTime()

                        -- 如果原体在15秒内也死了，则正常结束
                        -- 否则分身复活
                        inst:DoTaskInTime(15, function(i)
                            if i:IsValid() and not (i.components.health and i.components.health:IsDead()) then
                                -- 原体还活着，分身复活
                                local new_clone = GLOBAL.SpawnPrefab("spiderqueen")
                                if new_clone then
                                    new_clone.Transform:SetPosition(c_inst.Transform:GetWorldPosition())
                                    new_clone:AddTag("rogue_phase_clone")
                                    if new_clone.components.health then
                                        new_clone.components.health:SetMaxHealth(new_clone.components.health.maxhealth * 0.5)
                                        new_clone.components.health:SetPercent(1)
                                    end
                                    i._rogue_clone = new_clone

                                    if i._rogue_deps and i._rogue_deps.Announce then
                                        i._rogue_deps.Announce("【双相裂变】分身复活了！必须同时击杀两只！")
                                    end
                                end
                            end
                        end)
                    end)

                    GLOBAL.SpawnPrefab("dirt_puff").Transform:SetPosition(x + offset.x, y, z + offset.z)
                end

                if inst._rogue_deps and inst._rogue_deps.Announce then
                    inst._rogue_deps.Announce("【双相裂变】蜘蛛女王分裂了！15秒内必须同时击杀两只！")
                end
            end
        end)
    end,

    OnDeath = function(boss, data)
        if boss._rogue_clone and boss._rogue_clone:IsValid() then
            boss._rogue_clone:Remove()
            boss._rogue_clone = nil
        end
    end
})

-- [[ 词缀4: 压迫领域 (Oppressive Domain) ]]
-- 适配Boss: 远古犀牛 (minotaur")
-- 核心机制: 缩小活动区域，区域外每秒扣5%生命，区域随时间缩小
DeepAffixes.RegisterDeepAffix("oppressive_domain_minotaur", {
    name = "压迫领域 (Oppressive Domain)",
    desc = "远古犀牛展开压迫领域，领域外每秒损失5%最大生命值。领域范围随时间缩小！保持在Boss附近战斗！",

    OnAttach = function(boss, HijackSG, InjectNewState, HijackBrain)
        if boss.prefab ~= "minotaur" then return end

        boss._rogue_domain_center = GLOBAL.Vector3(boss.Transform:GetWorldPosition())
        boss._rogue_domain_radius = 18
        boss._rogue_domain_active = true
        boss._rogue_domain_task = nil

        -- 生成领域边界视觉标记
        local function CreateDomainMarker(inst)
            if not inst:IsValid() then return end
            local cx, cy, cz = inst._rogue_domain_center:Get()

            -- 函数说明：生成纯视觉火焰标记（无碰撞、无交互、不持久化）
            local function SpawnFlameMarker(x, z)
                local marker = GLOBAL.SpawnPrefab("firefx") or GLOBAL.SpawnPrefab("campfire")
                if marker then
                    marker.Transform:SetPosition(x, 0, z)
                    marker:AddTag("rogue_domain_marker")
                    marker:AddTag("NOCLICK")
                    marker:AddTag("FX")
                    marker.persists = false
                    if marker.components.health then
                        marker.components.health:SetInvincible(true)
                    end
                    if marker.components.burnable then
                        marker:RemoveComponent("burnable")
                    end
                    if marker.components.fueled then
                        marker:RemoveComponent("fueled")
                    end
                    if marker.components.lootdropper then
                        marker:RemoveComponent("lootdropper")
                    end
                    if marker.components.workable then
                        marker:RemoveComponent("workable")
                    end
                    if marker.Physics then
                        marker.Physics:SetActive(false)
                    end
                end
                return marker
            end

            local marker_count = 8
            for i = 1, marker_count do
                local angle = (i / marker_count) * 2 * GLOBAL.PI
                local mx = cx + math.cos(angle) * inst._rogue_domain_radius
                local mz = cz + math.sin(angle) * inst._rogue_domain_radius
                SpawnFlameMarker(mx, mz)
            end
        end

        -- 每秒检测玩家是否在领域内
        boss._rogue_domain_task = boss:DoPeriodicTask(1, function(inst)
            if not inst:IsValid() or inst.components.health and inst.components.health:IsDead() then
                return
            end

            -- 更新领域中心为Boss当前位置
            inst._rogue_domain_center = GLOBAL.Vector3(inst.Transform:GetWorldPosition())
            local cx, cy, cz = inst._rogue_domain_center:Get()

            local players = GLOBAL.FindPlayersInRange(cx, cy, cz, 40, true)
            for _, player in ipairs(players) do
                local px, py, pz = player.Transform:GetWorldPosition()
                local dist = GLOBAL.Vector3(px, py, pz):Distance(inst._rogue_domain_center)

                if dist > inst._rogue_domain_radius then
                    -- 在领域外，每秒扣5%最大生命
                    if player.components.health and not player.components.health:IsDead() then
                        local dmg = player.components.health.maxhealth * 0.05
                        player.components.health:DoDelta(-dmg, nil, "rogue_domain")
                        if player.components.colouradder then
                            player.components.colouradder:PushColour("rogue_domain", 0.5, 0, 0, 0)
                            player:DoTaskInTime(0.3, function(p)
                                if p and p:IsValid() and p.components and p.components.colouradder then
                                    p.components.colouradder:PopColour("rogue_domain")
                                end
                            end)
                        end
                    end
                end
            end
        end)

        -- 每30秒缩小领域范围
        boss._rogue_domain_shrink_task = boss:DoPeriodicTask(30, function(inst)
            if not inst:IsValid() then return end
            inst._rogue_domain_radius = math.max(6, inst._rogue_domain_radius - 2)

            if inst._rogue_deps and inst._rogue_deps.Announce then
                inst._rogue_deps.Announce("【压迫领域】活动区域缩小了！当前半径：" .. tostring(inst._rogue_domain_radius) .. "米")
            end
        end)

        -- 延迟1秒后创建视觉标记
        boss:DoTaskInTime(1, function()
            CreateDomainMarker(boss)
            if boss._rogue_deps and boss._rogue_deps.Announce then
                boss._rogue_deps.Announce("【压迫领域】远古犀牛展开了压迫领域！保持在Boss附近战斗！")
            end
        end)
    end,

    OnDeath = function(boss, data)
        if boss._rogue_domain_task then
            boss._rogue_domain_task:Cancel()
            boss._rogue_domain_task = nil
        end
        if boss._rogue_domain_shrink_task then
            boss._rogue_domain_shrink_task:Cancel()
            boss._rogue_domain_shrink_task = nil
        end
        -- 清除领域标记
        if boss._rogue_domain_center then
            local cx, cy, cz = boss._rogue_domain_center:Get()
            local markers = GLOBAL.TheSim:FindEntities(cx, cy, cz, 30, {"rogue_domain_marker"})
            for _, m in ipairs(markers) do
                if m:IsValid() then m:Remove() end
            end
        end
    end
})

return DeepAffixes
