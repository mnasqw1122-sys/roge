--[[
    文件说明：modinfo.lua
    功能：定义模组的基本信息、兼容性以及配置选项。
    包含了基础设置、掉落概率、词缀、Boss阶段以及系统性能优化等配置。
]]
name = "肉鸽生存模式"
description = "一个肉鸽挑战模式，玩家将在一个资源匮乏的小岛上抵御一波又一波的敌人。"
author = "liuan"
version = "2.1.1"
forumthread = ""
api_version = 10
dst_compatible = true
dont_starve_compatible = false
all_clients_require_mod = true
client_only_mod = false
server_filter_tags = {"roguelike", "survival", "challenge"}

icon_atlas = "modicon.xml"
icon = "modicon.tex"

configuration_options = {
    -- [基础设置]
    {
        name = "WORLD_VARIANT",
        label = "玩法版本",
        hover = "海难/哈姆雷特版必须先勾选启用对应模组。切换版本，需要重新勾选启动模组。",
        options = {
            {description = "标准版", data = "standard"},
            {description = "海难版", data = "shipwrecked"},
            {description = "哈姆雷特版", data = "hamlet"},
        },
        default = "standard",
    },
    {
        name = "STARTING_DAY",
        label = "开始天数",
        hover = "开始生成敌人波次的天数。",
        options = {
            {description = "第 2 天", data = 2},
            {description = "第 5 天", data = 5},
            {description = "第 10 天", data = 10},
        },
        default = 2,
    },
    {
        name = "SEASON_PROFILE",
        label = "赛季模板",
        hover = "短赛季/标准赛季/长赛季会自动覆盖赛季关键参数；自定义使用下方手动配置。",
        options = {
            {description = "短赛季", data = "short"},
            {description = "标准赛季", data = "standard"},
            {description = "长赛季", data = "long"},
            {description = "自定义", data = "custom"},
        },
        default = "standard",
    },
    {
        name = "SEASON_DAY_LIMIT",
        label = "赛季天数上限",
        hover = "仅在“自定义赛季”生效。",
        options = {
            {description = "60天", data = 60},
            {description = "80天", data = 80},
            {description = "100天", data = 100},
            {description = "120天", data = 120},
        },
        default = 80,
    },
    {
        name = "SEASON_RESET_DELAY",
        label = "结算后重生倒计时",
        hover = "仅在“自定义赛季”生效。",
        options = {
            {description = "10秒", data = 10},
            {description = "18秒", data = 18},
            {description = "25秒", data = 25},
        },
        default = 18,
    },
    {
        name = "SEASON_GRACE_DAYS",
        label = "赛季保护天数",
        hover = "仅在“自定义赛季”生效。保护期内不启动白天波次。",
        options = {
            {description = "关闭", data = 0},
            {description = "1天", data = 1},
            {description = "2天", data = 2},
            {description = "3天", data = 3},
            {description = "5天", data = 5},
        },
        default = 0,
    },
    {
        name = "BOSS_INTERVAL",
        label = "Boss波次间隔",
        hover = "每隔多少天触发Boss波次。",
        options = {
            {description = "每4天", data = 4},
            {description = "每6天", data = 6},
            {description = "每8天", data = 8},
        },
        default = 6,
    },
    {
        name = "WAVE_START_DELAY",
        label = "白天开波延迟",
        hover = "白天开始后多少秒启动波次。",
        options = {
            {description = "3秒", data = 3},
            {description = "5秒", data = 5},
            {description = "8秒", data = 8},
        },
        default = 5,
    },
    {
        name = "WAVE_END_DELAY",
        label = "夜晚收波延迟",
        hover = "夜晚开始后多少秒结束波次。",
        options = {
            {description = "3秒", data = 3},
            {description = "5秒", data = 5},
            {description = "8秒", data = 8},
        },
        default = 5,
    },
    {
        name = "MAX_HOSTILES_NEAR_PLAYER",
        label = "玩家附近敌人上限",
        hover = "达到上限时将暂停普通怪继续刷出。",
        options = {
            {description = "16只", data = 16},
            {description = "24只", data = 24},
            {description = "32只", data = 32},
            {description = "不限制", data = 0},
        },
        default = 24,
    },

    -- [掉落与概率]
    {
        name = "NORMAL_DROP_CHANCE",
        label = "普通怪掉落率",
        hover = "普通怪被击败时的基础掉落概率。",
        options = {
            {description = "25%", data = 0.25},
            {description = "45%", data = 0.45},
            {description = "60%", data = 0.60},
        },
        default = 0.45,
    },
    {
        name = "ELITE_CHANCE",
        label = "精英怪概率",
        hover = "非Boss敌人中精英怪的生成概率。",
        options = {
            {description = "10%", data = 0.10},
            {description = "20%", data = 0.20},
            {description = "30%", data = 0.30},
        },
        default = 0.20,
    },

    -- [词缀系统]
    {
        name = "ELITE_AFFIX_CHANCE",
        label = "精英词缀概率",
        hover = "精英怪额外获得词缀强化的基础概率。",
        options = {
            {description = "35%", data = 0.35},
            {description = "65%", data = 0.65},
            {description = "90%", data = 0.90},
        },
        default = 0.65,
    },
    {
        name = "SECOND_AFFIX_CHANCE",
        label = "双词缀概率",
        hover = "精英和Boss触发双词缀的基础概率。",
        options = {
            {description = "关闭", data = 0},
            {description = "15%", data = 0.15},
            {description = "30%", data = 0.30},
        },
        default = 0.15,
    },
    {
        name = "AFFIX_ANNOUNCE_MODE",
        label = "词缀公告模式",
        hover = "控制词缀出现时的公告展示范围。",
        options = {
            {description = "关闭公告", data = 0},
            {description = "全部公告", data = 1},
            {description = "仅Boss公告", data = 2},
        },
        default = 1,
    },

    -- [Boss 设置]
    {
        name = "BOSS_PHASE_MODE",
        label = "Boss阶段强化",
        hover = "控制Boss血量阈值阶段强化强度。",
        options = {
            {description = "关闭", data = 0},
            {description = "标准", data = 1},
            {description = "激进", data = 2},
        },
        default = 1,
    },
    {
        name = "BOSS_PHASE_MINION_COUNT",
        label = "Boss召唤基数",
        hover = "Boss进入濒死阶段时召唤小怪的基础数量。",
        options = {
            {description = "1只", data = 1},
            {description = "2只", data = 2},
            {description = "3只", data = 3},
        },
        default = 2,
    },
    {
        name = "BOSS_PHASE_FX_MODE",
        label = "Boss阶段特效",
        hover = "Boss进入阶段时是否显示特效光效提示。",
        options = {
            {description = "关闭", data = 0},
            {description = "开启", data = 1},
        },
        default = 1,
    },

    -- [系统优化]
    {
        name = "GROUND_LOOT_CLEAN_ENABLED",
        label = "地面掉落清理",
        hover = "是否启用夜晚周期清理地面掉落物。",
        options = {
            {description = "开启", data = true},
            {description = "关闭", data = false},
        },
        default = true,
    },
    {
        name = "GROUND_LOOT_CLEAN_INTERVAL_DAYS",
        label = "清理间隔天数",
        hover = "每隔多少天在夜晚执行一次地面掉落清理。",
        options = {
            {description = "每1天", data = 1},
            {description = "每2天", data = 2},
            {description = "每3天", data = 3},
            {description = "每5天", data = 5},
        },
        default = 2,
    },
    {
        name = "GROUND_LOOT_CLEAN_DELAY_NIGHT",
        label = "夜晚清理延时",
        hover = "夜晚开始后多久执行地面掉落清理。",
        options = {
            {description = "15秒", data = 15},
            {description = "20秒", data = 20},
            {description = "25秒", data = 25},
            {description = "30秒", data = 30},
        },
        default = 25,
    },
    {
        name = "GROUND_LOOT_CLEAN_BATCH_SIZE",
        label = "单帧清理数量",
        hover = "每帧最多处理多少个掉落物，数值越小越流畅。",
        options = {
            {description = "30个", data = 30},
            {description = "60个", data = 60},
            {description = "100个", data = 100},
        },
        default = 60,
    },
    {
        name = "GROUND_LOOT_CLEAN_SEARCH_RADIUS",
        label = "清理半径",
        hover = "以每位玩家为中心扫描掉落物的半径。",
        options = {
            {description = "50", data = 50},
            {description = "70", data = 70},
            {description = "100", data = 100},
        },
        default = 70,
    },
    
    -- [AI NPC]
    {
        name = "AI_NPC_ENABLED",
        label = "AI小人挑战",
        hover = "是否在休息天生成具有独立AI和装备的挑战型小人。",
        options = {
            {description = "开启", data = true},
            {description = "关闭", data = false},
        },
        default = true,
    },
}
