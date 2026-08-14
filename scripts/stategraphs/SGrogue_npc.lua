require("stategraphs/commonstates")

local actionhandlers = {
    ActionHandler(ACTIONS.EAT, "eat"),
    ActionHandler(ACTIONS.PLAY, "play"),
    ActionHandler(ACTIONS.CASTSPELL, "castspell"),
}

local events = {
    CommonHandlers.OnLocomote(false, true),
    CommonHandlers.OnAttack(),
    CommonHandlers.OnAttacked(),
    CommonHandlers.OnDeath(),
    EventHandler("rogue_dodge", function(inst, data)
        if not inst.sg:HasStateTag("busy") and not inst.components.health:IsDead() then
            inst.sg:GoToState("dodge", data and data.direction)
        end
    end),
    EventHandler("rogue_taunt", function(inst)
        if not inst.sg:HasStateTag("busy") and not inst.components.health:IsDead() then
            inst.sg:GoToState("taunt")
        end
    end),
    EventHandler("rogue_charge_attack", function(inst)
        if not inst.sg:HasStateTag("busy") and not inst.components.health:IsDead() then
            inst.sg:GoToState("charge_attack")
        end
    end),
    EventHandler("rogue_combo_attack", function(inst)
        if not inst.sg:HasStateTag("busy") and not inst.components.health:IsDead() then
            inst.sg:GoToState("combo_attack")
        end
    end),
}

local states = {
    State{
        name = "idle",
        tags = {"idle", "canrotate"},
        onenter = function(inst, pushanim)
            inst.Physics:Stop()
            if pushanim then
                inst.AnimState:PushAnimation("idle", true)
            else
                inst.AnimState:PlayAnimation("idle", true)
            end
        end,
    },

    State{
        name = "run_start",
        tags = {"moving", "running", "canrotate"},
        onenter = function(inst)
            inst.components.locomotor:RunForward()
            inst.AnimState:PlayAnimation("run_pre")
        end,
        events = {
            EventHandler("animover", function(inst) inst.sg:GoToState("run") end),
        },
    },

    State{
        name = "run",
        tags = {"moving", "running", "canrotate"},
        onenter = function(inst)
            inst.components.locomotor:RunForward()
            if not inst.AnimState:IsCurrentAnimation("run_loop") then
                inst.AnimState:PlayAnimation("run_loop", true)
            end
            local anim_len = inst.AnimState:GetCurrentAnimationLength()
            inst.sg:SetTimeout(anim_len > 0 and anim_len or 0.5)
        end,
        timeline = {
            TimeEvent(4*FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/maxwell/footstep") end),
            TimeEvent(12*FRAMES, function(inst) inst.SoundEmitter:PlaySound("dontstarve/maxwell/footstep") end),
        },
        ontimeout = function(inst)
            inst.sg:GoToState("run")
        end,
    },

    State{
        name = "run_stop",
        tags = {"canrotate", "idle"},
        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("run_pst")
        end,
        events = {
            EventHandler("animover", function(inst) inst.sg:GoToState("idle") end),
        },
    },

    State{
        name = "walk_start",
        tags = {"moving", "canrotate"},
        onenter = function(inst)
            inst.components.locomotor:WalkForward()
            inst.AnimState:PlayAnimation("run_pre")
        end,
        events = {
            EventHandler("animover", function(inst) inst.sg:GoToState("walk") end),
        },
    },

    State{
        name = "walk",
        tags = {"moving", "canrotate"},
        onenter = function(inst)
            inst.components.locomotor:WalkForward()
            if not inst.AnimState:IsCurrentAnimation("run_loop") then
                inst.AnimState:PlayAnimation("run_loop", true)
            end
            local anim_len = inst.AnimState:GetCurrentAnimationLength()
            inst.sg:SetTimeout(anim_len > 0 and anim_len or 0.5)
        end,
        ontimeout = function(inst)
            inst.sg:GoToState("walk")
        end,
    },

    State{
        name = "walk_stop",
        tags = {"canrotate", "idle"},
        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("run_pst")
        end,
        events = {
            EventHandler("animover", function(inst) inst.sg:GoToState("idle") end),
        },
    },

    -- 函数说明：普通攻击状态（极短后摇设计）
    State{
        name = "attack",
        tags = {"attack", "busy", "abouttoattack"},
        onenter = function(inst)
            if inst.components.combat.target then
                inst.sg.statemem.target = inst.components.combat.target
                inst:ForceFacePoint(inst.components.combat.target:GetPosition())
            end
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("atk_pre")
            inst.AnimState:PushAnimation("atk", false)
            inst.components.combat:StartAttack()
            local min_period = inst.components.combat.min_attack_period or 0.4
            inst.sg:SetTimeout(math.max(2 * FRAMES, min_period))
        end,
        timeline = {
            TimeEvent(2 * FRAMES, function(inst)
                inst.components.combat:DoAttack(inst.sg.statemem.target)
                inst.sg:RemoveStateTag("abouttoattack")
            end),
            TimeEvent(4 * FRAMES, function(inst)
                inst.sg:RemoveStateTag("busy")
            end),
        },
        ontimeout = function(inst)
            inst.sg:GoToState("idle")
        end,
        events = {
            EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },
    },

    -- 函数说明：闪避状态（快速侧移，带无敌帧）
    State{
        name = "dodge",
        tags = {"busy", "dodging", "noattack"},
        onenter = function(inst, direction)
            inst.sg.statemem.direction = direction or (math.random() > 0.5 and 1 or -1)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("run_pre")

            local level = inst._ai_level and inst._ai_level:value() or 1
            local dodge_speed = 10 + math.min(5, (level - 1) * 0.3)
            local angle = inst.Transform:GetRotation() * DEGREES
            local dodge_angle = angle + inst.sg.statemem.direction * PI / 2
            local vx = math.cos(dodge_angle) * dodge_speed
            local vz = math.sin(dodge_angle) * dodge_speed
            inst.Physics:SetMotorVel(vx, 0, vz)

            if inst.components.health then
                inst.components.health:SetInvincible(true)
            end

            if inst.components.colouradder then
                inst.components.colouradder:PushColour("rogue_dodge", 0.5, 0.5, 1, 0)
            end

            inst.sg:SetTimeout(8 * FRAMES)
        end,
        timeline = {
            TimeEvent(4 * FRAMES, function(inst)
                inst.Physics:SetMotorVel(0, 0, 0)
                inst.Physics:Stop()
            end),
        },
        ontimeout = function(inst)
            if inst.components.health then
                inst.components.health:SetInvincible(false)
            end
            if inst.components.colouradder then
                inst.components.colouradder:PopColour("rogue_dodge")
            end
            inst.sg:GoToState("idle")
        end,
        onexit = function(inst)
            if inst.components.health then
                inst.components.health:SetInvincible(false)
            end
            if inst.components.colouradder then
                inst.components.colouradder:PopColour("rogue_dodge")
            end
        end,
    },

    -- 函数说明：蓄力攻击状态（高伤害但需蓄力）
    State{
        name = "charge_attack",
        tags = {"attack", "busy", "charging"},
        onenter = function(inst)
            if inst.components.combat.target then
                inst.sg.statemem.target = inst.components.combat.target
                inst:ForceFacePoint(inst.components.combat.target:GetPosition())
            end
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("atk_pre")
            inst.AnimState:PushAnimation("atk_pre", false)

            if inst.components.colouradder then
                inst.components.colouradder:PushColour("rogue_charge", 1, 0.3, 0, 0)
            end

            local level = inst._ai_level and inst._ai_level:value() or 1
            local charge_time = math.max(0.3, 0.8 - (level - 1) * 0.03)
            inst.sg:SetTimeout(charge_time)
        end,
        ontimeout = function(inst)
            inst.sg:GoToState("charge_attack_release")
        end,
        onexit = function(inst)
            if inst.components.colouradder then
                inst.components.colouradder:PopColour("rogue_charge")
            end
        end,
    },

    -- 函数说明：蓄力攻击释放状态
    State{
        name = "charge_attack_release",
        tags = {"attack", "busy", "abouttoattack"},
        onenter = function(inst)
            if inst.sg.statemem.target and inst.sg.statemem.target:IsValid() then
                inst:ForceFacePoint(inst.sg.statemem.target:GetPosition())
            end
            inst.AnimState:PlayAnimation("atk", false)

            local level = inst._ai_level and inst._ai_level:value() or 1
            local charge_mult = 1.5 + (level - 1) * 0.1
            inst.sg.statemem.charge_mult = charge_mult
            inst.components.combat:StartAttack()
        end,
        timeline = {
            TimeEvent(2 * FRAMES, function(inst)
                local target = inst.sg.statemem.target
                if target and target:IsValid() then
                    local mult = inst.sg.statemem.charge_mult or 1.5
                    local base_dmg = inst.components.combat.defaultdamage or 34
                    local charged_dmg = math.floor(base_dmg * mult)
                    if target.components.health and not target.components.health:IsDead() then
                        target.components.health:DoDelta(-charged_dmg, nil, "rogue_charge_attack", nil, inst)
                    end
                    if target.components.colouradder then
                        target.components.colouradder:PushColour("rogue_charge_hit", 1, 0.2, 0, 0)
                        target:DoTaskInTime(0.3, function(t)
                            if t and t:IsValid() and t.components and t.components.colouradder then
                                t.components.colouradder:PopColour("rogue_charge_hit")
                            end
                        end)
                    end
                end
                inst.sg:RemoveStateTag("abouttoattack")
            end),
            TimeEvent(6 * FRAMES, function(inst)
                inst.sg:RemoveStateTag("busy")
            end),
        },
        events = {
            EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },
    },

    -- 函数说明：连击攻击状态（快速多段攻击）
    State{
        name = "combo_attack",
        tags = {"attack", "busy", "abouttoattack"},
        onenter = function(inst)
            if inst.components.combat.target then
                inst.sg.statemem.target = inst.components.combat.target
                inst:ForceFacePoint(inst.components.combat.target:GetPosition())
            end
            inst.Physics:Stop()
            inst.sg.statemem.combo_count = 0
            inst.sg.statemem.max_combo = 3
            inst.AnimState:PlayAnimation("atk_pre")
        end,
        timeline = {
            TimeEvent(2 * FRAMES, function(inst)
                inst.sg.statemem.combo_count = inst.sg.statemem.combo_count + 1
                local target = inst.sg.statemem.target
                if target and target:IsValid() and target.components.health and not target.components.health:IsDead() then
                    local base_dmg = inst.components.combat.defaultdamage or 34
                    local combo_mult = 0.6 + inst.sg.statemem.combo_count * 0.2
                    target.components.health:DoDelta(-math.floor(base_dmg * combo_mult), nil, "rogue_combo_attack", nil, inst)
                end
                if inst.sg.statemem.combo_count < inst.sg.statemem.max_combo then
                    inst.AnimState:PlayAnimation("atk", false)
                end
            end),
            TimeEvent(6 * FRAMES, function(inst)
                if inst.sg.statemem.combo_count < inst.sg.statemem.max_combo then
                    inst.sg.statemem.combo_count = inst.sg.statemem.combo_count + 1
                    local target = inst.sg.statemem.target
                    if target and target:IsValid() and target.components.health and not target.components.health:IsDead() then
                        local base_dmg = inst.components.combat.defaultdamage or 34
                        local combo_mult = 0.6 + inst.sg.statemem.combo_count * 0.2
                        target.components.health:DoDelta(-math.floor(base_dmg * combo_mult), nil, "rogue_combo_attack", nil, inst)
                    end
                    if inst.sg.statemem.combo_count < inst.sg.statemem.max_combo then
                        inst.AnimState:PlayAnimation("atk", false)
                    end
                end
            end),
            TimeEvent(10 * FRAMES, function(inst)
                if inst.sg.statemem.combo_count < inst.sg.statemem.max_combo then
                    inst.sg.statemem.combo_count = inst.sg.statemem.combo_count + 1
                    local target = inst.sg.statemem.target
                    if target and target:IsValid() and target.components.health and not target.components.health:IsDead() then
                        local base_dmg = inst.components.combat.defaultdamage or 34
                        local combo_mult = 0.6 + inst.sg.statemem.combo_count * 0.2
                        target.components.health:DoDelta(-math.floor(base_dmg * combo_mult), nil, "rogue_combo_attack", nil, inst)
                    end
                end
                inst.sg:RemoveStateTag("abouttoattack")
            end),
            TimeEvent(14 * FRAMES, function(inst)
                inst.sg:RemoveStateTag("busy")
            end),
        },
        events = {
            EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },
    },

    -- 函数说明：嘲讽状态（吸引仇恨，短暂减伤）
    State{
        name = "taunt",
        tags = {"busy", "taunting"},
        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("emoteXL_happy", true)

            if inst.components.health then
                inst.sg.statemem.original_absorb = inst.components.health.absorb
            end

            local level = inst._ai_level and inst._ai_level:value() or 1
            local taunt_duration = 1.0 + math.min(1.0, (level - 1) * 0.05)

            local x, y, z = inst.Transform:GetWorldPosition()
            local ents = TheSim:FindEntities(x, y, z, 10, {"player"})
            for _, player in ipairs(ents) do
                if player.components.combat then
                    player.components.combat:SetTarget(inst)
                end
            end

            inst.sg:SetTimeout(taunt_duration)
        end,
        ontimeout = function(inst)
            inst.sg:GoToState("idle")
        end,
    },

    -- 函数说明：受击状态（完全霸体设计）
    State{
        name = "hit",
        tags = {"hit", "busy"},
        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("hit")
            inst.sg:SetTimeout(1 * FRAMES)
        end,
        ontimeout = function(inst)
            inst.sg:GoToState("idle")
        end,
        events = {
            EventHandler("animover", function(inst) inst.sg:GoToState("idle") end),
        },
    },

    State{
        name = "death",
        tags = {"busy", "dead"},
        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("death")
        end,
    },

    State{
        name = "eat",
        tags = {"busy"},
        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("eat_pre")
            inst.AnimState:PushAnimation("eat", false)
        end,
        timeline = {
            TimeEvent(28 * FRAMES, function(inst)
                inst:PerformBufferedAction()
            end),
        },
        events = {
            EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },
    },

    State{
        name = "play",
        tags = {"doing", "busy"},
        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("action_uniqueitem_pre")
            inst.AnimState:PushAnimation("action_uniqueitem_lag", false)
        end,
        timeline = {
            TimeEvent(10 * FRAMES, function(inst)
                inst:PerformBufferedAction()
            end),
        },
        events = {
            EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },
    },

    State{
        name = "castspell",
        tags = {"doing", "busy"},
        onenter = function(inst)
            inst.Physics:Stop()
            inst.AnimState:PlayAnimation("staff_pre")
            inst.AnimState:PushAnimation("staff", false)
        end,
        timeline = {
            TimeEvent(13 * FRAMES, function(inst)
                inst:PerformBufferedAction()
            end),
        },
        events = {
            EventHandler("animqueueover", function(inst)
                if inst.AnimState:AnimDone() then
                    inst.sg:GoToState("idle")
                end
            end),
        },
    },
}

return StateGraph("rogue_npc", states, events, "idle", actionhandlers)
