--[[
    文件说明：pool_catalog.lua
    功能：肉鸽模式的随机池目录，定义了不同变体（标准、海难、哈姆雷特）下的敌人、精英、Boss以及掉落物配置。
    提供基于权重的随机选择功能。
]]
local catalog = {}
catalog.world_variant = "standard"

local SHIPWRECKED_TYPE_MAP = {
    ENEMIES_NORMAL = "ENEMIES_NORMAL_SHIPWRECKED",
    ENEMIES_ELITE = "ENEMIES_ELITE_SHIPWRECKED",
    BOSSES = "BOSSES_SHIPWRECKED",
    DROPS_NORMAL = "DROPS_NORMAL_SHIPWRECKED",
    DROPS_BOSS_GEAR = "DROPS_BOSS_GEAR_SHIPWRECKED",
    DROPS_BOSS_MATS = "DROPS_BOSS_MATS_SHIPWRECKED",
}

local HAMLET_TYPE_MAP = {
    ENEMIES_NORMAL = "ENEMIES_NORMAL_HAMLET",
    ENEMIES_ELITE = "ENEMIES_ELITE_HAMLET",
    BOSSES = "BOSSES_HAMLET",
    DROPS_NORMAL = "DROPS_NORMAL_HAMLET",
    DROPS_BOSS_GEAR = "DROPS_BOSS_GEAR_HAMLET",
    DROPS_BOSS_MATS = "DROPS_BOSS_MATS_HAMLET",
}

-- [权重定义]
-- 权重越高，被选中的概率越大。
-- Count: 一次生成的数量范围 {min, max}
-- MinDay: 需要达到多少天才会进入随机池
-- Tags: 用于后续扩展的标签

catalog.POOLS = {
    -- [普通敌人池]
    -- 分组内排序规则：先按 min_day 升序，再按 weight 降序
    ENEMIES_NORMAL = {
        -- 基础群体
        { prefab = "spider",            weight = 81, count = {1, 2}, min_day = 0 },  -- 蜘蛛群
        { prefab = "bee",               weight = 43,  count = {2, 3}, min_day = 0 },  -- 杀人蜂群
        { prefab = "killerbee",         weight = 70,  count = {2, 3}, min_day = 0 },  -- 杀人蜂
        { prefab = "mosquito",          weight = 46,  count = {2, 3}, min_day = 0 },  -- 蚊子群
        { prefab = "frog",              weight = 52,  count = {1, 2}, min_day = 0 },  -- 青蛙群
        { prefab = "bat",               weight = 70,  count = {1, 2}, min_day = 3 },  -- 蝙蝠
        { prefab = "hound",             weight = 65,  count = {1, 2}, min_day = 3 },  -- 猎犬

        -- 地表与中立阵营
        { prefab = "pigman",            weight = 52,  count = {1, 1}, min_day = 0 },  -- 猪人
        { prefab = "birchnutdrake",     weight = 15,  count = {1, 2}, min_day = 5 },  -- 桦栗果精
        { prefab = "merm",              weight = 53,  count = {1, 2}, min_day = 5 },  -- 鱼人
        { prefab = "bunnyman",          weight = 37,  count = {1, 2}, min_day = 5 },  -- 兔人
        { prefab = "beefalo",           weight = 41,  count = {1, 2}, min_day = 5 },  -- 皮弗娄牛
        { prefab = "tentacle",          weight = 36,  count = {1, 1}, min_day = 5 },  -- 触手
        { prefab = "perd",              weight = 25,  count = {1, 2}, min_day = 5 },  -- 火鸡
        { prefab = "lightninggoat",     weight = 30,  count = {1, 2}, min_day = 8 },  -- 伏特羊
        { prefab = "penguin",           weight = 30,  count = {3, 5}, min_day = 10 }, -- 企鸥
        { prefab = "tallbird",          weight = 30,  count = {1, 1}, min_day = 10 }, -- 高脚鸟
        { prefab = "rocky",             weight = 48,  count = {1, 2}, min_day = 10 }, -- 石虾
        { prefab = "lureplant",         weight = 10,  count = {1, 1}, min_day = 15 }, -- 食人花
        { prefab = "eyeplant",          weight = 56,  count = {2, 3}, min_day = 15 }, -- 眼球草

        -- 蜘蛛分支
        { prefab = "spider_warrior",    weight = 60,  count = {1, 2}, min_day = 5 },  -- 蜘蛛战士
        { prefab = "spider_hider",      weight = 50,  count = {2, 3}, min_day = 10 }, -- 洞穴蜘蛛
        { prefab = "spider_dropper",    weight = 50,  count = {2, 3}, min_day = 10 }, -- 穴居悬蛛
        { prefab = "spider_water",      weight = 40,  count = {2, 3}, min_day = 10 }, -- 海黾
        { prefab = "spider_spitter",    weight = 30,  count = {1, 1}, min_day = 15 }, -- 喷射蜘蛛
        { prefab = "spider_healer",     weight = 30,  count = {1, 1}, min_day = 15 }, -- 护士蜘蛛
        { prefab = "spider_moon",       weight = 40,  count = {2, 3}, min_day = 15 }, -- 破碎蜘蛛

        -- 洞穴/机关
        { prefab = "knight",            weight = 40,  count = {1, 1}, min_day = 8 },  -- 发条骑士
        { prefab = "bishop",            weight = 20,  count = {1, 1}, min_day = 15 }, -- 发条主教
        { prefab = "rook",              weight = 15,  count = {1, 1}, min_day = 20 }, -- 发条战车
        { prefab = "slurtle",           weight = 20,  count = {1, 2}, min_day = 10 }, -- 蛞蝓龟
        { prefab = "molebat",           weight = 25,  count = {1, 2}, min_day = 10 }, -- 鼹鼠蝙蝠
        { prefab = "snurtle",           weight = 10,  count = {1, 1}, min_day = 15 }, -- 蜗牛龟
        { prefab = "worm",              weight = 10,  count = {1, 1}, min_day = 30 }, -- 洞穴蠕虫
        { prefab = "yots_worm",         weight = 10,  count = {1, 1}, min_day = 30 }, -- 镀金洞穴蠕虫

        -- 元素/变异/梦魇月相
        { prefab = "firehound",         weight = 25,  count = {1, 2}, min_day = 20 }, -- 火焰猎犬
        { prefab = "icehound",          weight = 25,  count = {1, 2}, min_day = 20 }, -- 寒冰猎犬
        { prefab = "moonhound",         weight = 25,  count = {1, 2}, min_day = 20 }, -- 月亮猎犬
        { prefab = "clayhound",         weight = 25,  count = {1, 2}, min_day = 10 }, -- 黏土猎犬
        { prefab = "mutatedhound",      weight = 20,  count = {1, 2}, min_day = 25 }, -- 恐怖猎犬
        { prefab = "hedgehound",        weight = 20,  count = {1, 2}, min_day = 15 }, -- 蔷薇狼
        { prefab = "mutated_penguin",   weight = 20,  count = {3, 5}, min_day = 25 }, -- 永冻企鸥
        { prefab = "moonbutterfly",     weight = 10,  count = {1, 2}, min_day = 5 },  -- 月蛾
        { prefab = "bird_mutant",       weight = 20,  count = {2, 3}, min_day = 20 }, -- 变异鸟
        { prefab = "lunarfrog",         weight = 40,  count = {2, 3}, min_day = 20 }, -- 明眼青蛙
        { prefab = "gestalt",           weight = 40,  count = {2, 3}, min_day = 20 }, -- 虚影
        { prefab = "crawlinghorror",    weight = 15,  count = {1, 1}, min_day = 10 }, -- 爬行恐惧
        { prefab = "terrorbeak",        weight = 10,  count = {1, 1}, min_day = 25 }, -- 恐怖尖喙
        { prefab = "bird_mutant_spitter", weight = 15, count = {1, 2}, min_day = 25 }, -- 变异喷吐鸟
        { prefab = "crawlingnightmare", weight = 12,  count = {1, 1}, min_day = 30 }, -- 爬行梦魇
        { prefab = "nightmarebeak",     weight = 10,  count = {1, 1}, min_day = 35 }, -- 梦魇尖喙
        { prefab = "fused_shadeling",   weight = 30,  count = {2, 3}, min_day = 25 }, -- 熔合暗影
    },

    -- [精英敌人池] (通常单只生成，但属性极高)
    -- 分组内排序规则：先按 min_day 升序，再按 weight 降序
    ENEMIES_ELITE = {
        -- 体型/野外首领级
        { prefab = "koalefant_summer",  weight = 35,  min_day = 10 }, -- 考拉象
        { prefab = "leif",              weight = 40,  min_day = 15 }, -- 树精守卫
        { prefab = "leif_sparse",       weight = 40,  min_day = 15 }, -- 树精守卫
        { prefab = "koalefant_winter",  weight = 35,  min_day = 20 }, -- 考拉象
        { prefab = "spiderqueen",       weight = 47,  min_day = 20 }, -- 蜘蛛女王
        { prefab = "warg",              weight = 31,  min_day = 25 }, -- 座狼
        { prefab = "beeguard",          weight = 30,  min_day = 25 }, -- 蜂群守卫
        { prefab = "spat",              weight = 30,  min_day = 30 }, -- 钢羊
        { prefab = "prime_mate",        weight = 20,  min_day = 30 }, -- 私掠海盗
        { prefab = "claywarg",          weight = 20,  min_day = 30 }, -- 黏土座狼
        { prefab = "gingerbreadwarg",   weight = 10,  min_day = 30 }, -- 姜饼座狼
        { prefab = "warglet",           weight = 18,  min_day = 35 }, -- 幼年座狼
        { prefab = "eyeofterror_mini",  weight = 25,  min_day = 40 }, -- 恐怖之眼小眼球
        { prefab = "minotaur",          weight = 20,  min_day = 40 }, -- 远古守护者

        -- 人形守卫
        { prefab = "pigguard",          weight = 30,  min_day = 15 }, -- 猪人守卫
        { prefab = "mermguard",         weight = 30,  min_day = 15 }, -- 鱼人守卫
        { prefab = "walrus",            weight = 30,  min_day = 20 }, -- 海象
        { prefab = "krampus",           weight = 20,  min_day = 15 }, -- 坎普斯
        { prefab = "slurper",           weight = 10,  min_day = 20 }, -- 啜食者

        -- 暗影/月相/变异分支
        { prefab = "shadow_rook",       weight = 18,  min_day = 35 }, -- 暗影战车
        { prefab = "shadow_knight",     weight = 17,  min_day = 35 }, -- 暗影骑士
        { prefab = "shadow_bishop",     weight = 15,  min_day = 35 }, -- 暗影主教
        { prefab = "mutatedbuzzard_gestalt", weight = 12, min_day = 35 }, -- 变异秃鹫
        { prefab = "merm_shadow",       weight = 13,  min_day = 30 }, -- 暗影鱼人
        { prefab = "mermguard_shadow",  weight = 11,  min_day = 30 }, -- 暗影鱼人守卫
        { prefab = "merm_lunar",        weight = 16,  min_day = 30 }, -- 变异鱼人
        { prefab = "mermguard_lunar",   weight = 14,  min_day = 30 }, -- 变异鱼人守卫
        { prefab = "moonpig",           weight = 24,  min_day = 25 }, -- 疯猪
    },

    -- [Boss 池]
    -- 分组内排序规则：先按 min_day 升序，再按 weight 降序
    BOSSES = {
        -- 早期季节与常驻Boss
        { prefab = "deerclops",         weight = 95, min_day = 0,  family = "deerclops" },  -- 独眼巨鹿
        { prefab = "bearger",           weight = 93, min_day = 0,  family = "bearger" },  -- 熊獾
        { prefab = "moose",             weight = 91, min_day = 0,  family = "moose" },  -- 麋鹿鹅
        { prefab = "dragonfly",         weight = 76,  min_day = 20, family = "dragonfly" }, -- 龙蝇
        { prefab = "lordfruitfly",      weight = 63,  min_day = 20 }, -- 果蝇王

        -- 中期挑战Boss
        { prefab = "eyeofterror",       weight = 60,  min_day = 30 }, -- 恐怖之眼
        { prefab = "toadstool",         weight = 50,  min_day = 40 }, -- 毒菌蟾蜍
        { prefab = "daywalker",         weight = 40,  min_day = 50, family = "daywalker" }, -- 梦魇疯猪
        { prefab = "klaus",             weight = 40,  min_day = 50, family = "klaus" }, -- 克劳斯
        { prefab = "beequeen",          weight = 40,  min_day = 50 }, -- 蜂王

        -- 后期强化与变异
        { prefab = "mutateddeerclops",  weight = 50,  min_day = 50 }, -- 晶体独眼巨鹿
        { prefab = "mutatedbearger",    weight = 50,  min_day = 50 }, -- 装甲熊獾
        { prefab = "mutatedwarg",       weight = 30,  min_day = 60 }, -- 附身座狼
        { prefab = "stalker",           weight = 20,  min_day = 60 }, -- 远古织影者
        { prefab = "twinofterror1",     weight = 40,  min_day = 60 }, -- 激光眼
        { prefab = "twinofterror2",     weight = 40,  min_day = 60 }, -- 魔焰眼
        { prefab = "toadstool_dark",    weight = 30,  min_day = 70 }, -- 悲惨的毒菌蟾蜍

        -- 终局天体Boss
        { prefab = "alterguardian_phase1", weight = 30, min_day = 80 }, -- 天体英雄 P1
        { prefab = "alterguardian_phase2", weight = 30, min_day = 80 }, -- 天体英雄 P2
        { prefab = "alterguardian_phase3", weight = 30, min_day = 80 }, -- 天体英雄 P3
        { prefab = "shadowthrall_horns",   weight = 25, min_day = 85 }, -- 暗影骑士（裂隙）
        { prefab = "shadowthrall_hands",   weight = 25, min_day = 85 }, -- 暗影主教（裂隙）
        { prefab = "shadowthrall_wings",   weight = 25, min_day = 85 }, -- 暗影战车（裂隙）
        { prefab = "shadowthrall_mouth",   weight = 20, min_day = 90 }, -- 暗影织影者（裂隙）
    },

    -- [掉落物: 基础物资]
    -- 分组内排序规则：按 weight 降序（同权重保持语义邻近）
    DROPS_NORMAL = {
        -- 基础资源与制作素材
        { prefab = "meat",              weight = 100, count = {1, 2} }, -- 肉
        { prefab = "goldnugget",        weight = 80,  count = {1, 2} }, -- 金块
        { prefab = "rocks",             weight = 80,  count = {2, 4} }, -- 石头
        { prefab = "flint",             weight = 80,  count = {2, 4} }, -- 燧石
        { prefab = "log",               weight = 80,  count = {3, 5} }, -- 木头
        { prefab = "twigs",             weight = 80,  count = {3, 5} }, -- 树枝
        { prefab = "cutgrass",          weight = 80,  count = {3, 5} }, -- 采下的草
        { prefab = "silk",              weight = 60,  count = {1, 3} }, -- 蜘蛛丝
        { prefab = "spidergland",       weight = 60,  count = {1, 2} }, -- 蜘蛛腺
        { prefab = "honey",             weight = 40,  count = {1, 2} }, -- 蜂蜜
        { prefab = "stinger",           weight = 35,  count = {1, 2} }, -- 蜂刺
        { prefab = "charcoal",          weight = 40,  count = {2, 4} }, -- 木炭
        { prefab = "papyrus",           weight = 30,  count = {1, 2} }, -- 莎草纸
        { prefab = "nitre",             weight = 20,  count = {1, 2} }, -- 硝石
        { prefab = "livinglog",         weight = 20,  count = {1, 1} }, -- 活木头

        -- 生鲜食材
        { prefab = "smallmeat",         weight = 60,  count = {1, 2} }, -- 小肉
        { prefab = "monstermeat",       weight = 50,  count = {1, 2} }, -- 怪物肉
        { prefab = "berries",           weight = 60,  count = {2, 4} }, -- 浆果
        { prefab = "carrot",            weight = 50,  count = {1, 3} }, -- 胡萝卜
        { prefab = "spoiled_food",      weight = 20,  count = {1, 2} }, -- 腐烂食物
        { prefab = "mandrake",          weight = 5,   count = {1, 1} }, -- 曼德拉草 (稀有)

        -- 熟食与烹饪成品
        { prefab = "cookedmeat",        weight = 40,  count = {1, 2} }, -- 熟肉
        { prefab = "cookedsmallmeat",   weight = 50,  count = {1, 2} }, -- 熟小肉
        { prefab = "cookedmonstermeat", weight = 40,  count = {1, 2} }, -- 熟怪物肉
        { prefab = "carrot_cooked",     weight = 40,  count = {1, 2} }, -- 烤胡萝卜
        { prefab = "corn_cooked",       weight = 30,  count = {1, 2} }, -- 爆米花
        { prefab = "pumpkin_cooked",    weight = 30,  count = {1, 1} }, -- 烤南瓜
        { prefab = "eggplant_cooked",   weight = 30,  count = {1, 1} }, -- 烤茄子
        { prefab = "potato_cooked",     weight = 30,  count = {1, 2} }, -- 烤土豆
        { prefab = "asparagus_cooked",  weight = 30,  count = {1, 2} }, -- 烤芦笋
        { prefab = "onion_cooked",      weight = 30,  count = {1, 2} }, -- 烤洋葱
        { prefab = "garlic_cooked",     weight = 30,  count = {1, 2} }, -- 烤大蒜
        { prefab = "tomato_cooked",     weight = 30,  count = {1, 2} }, -- 烤番茄
        { prefab = "pepper_cooked",     weight = 30,  count = {1, 2} }, -- 烤辣椒

        -- 锅料理
        { prefab = "meatballs",         weight = 50,  count = {1, 1} }, -- 肉丸
        { prefab = "perogies",          weight = 40,  count = {1, 1} }, -- 波兰水饺
        { prefab = "frogglebunwich",    weight = 30,  count = {1, 1} }, -- 蛙腿三明治
        { prefab = "honeyham",          weight = 20,  count = {1, 1} }, -- 蜜汁火腿
        { prefab = "dragonpie",         weight = 10,  count = {1, 1} }, -- 火龙果派
        { prefab = "baconeggs",         weight = 20,  count = {1, 1} }, -- 培根煎蛋
        { prefab = "turkeydinner",      weight = 10,  count = {1, 1} }, -- 火鸡大餐
        { prefab = "fishsticks",        weight = 30,  count = {1, 1} }, -- 炸鱼排
        { prefab = "honeynuggets",      weight = 30,  count = {1, 1} }, -- 蜜汁卤肉
        { prefab = "butterflymuffin",   weight = 30,  count = {1, 1} }, -- 蝴蝶松饼
        { prefab = "waffles",           weight = 10,  count = {1, 1} }, -- 华夫饼
        { prefab = "ratatouille",       weight = 30,  count = {1, 1} }, -- 蔬菜杂烩
        { prefab = "fruitmedley",       weight = 20,  count = {1, 1} }, -- 水果圣代
        { prefab = "stuffedeggplant",   weight = 20,  count = {1, 1} }, -- 酿茄子
        { prefab = "pumpkincookie",     weight = 20,  count = {1, 1} }, -- 南瓜饼干
        { prefab = "taffy",             weight = 20,  count = {1, 1} }, -- 太妃糖
        { prefab = "wetgoop",           weight = 5,   count = {1, 1} }, -- 潮湿黏糊
        { prefab = "monsterlasagna",    weight = 10,  count = {1, 1} }, -- 怪物千层饼
        { prefab = "monstertartare",    weight = 10,  count = {1, 1} }, -- 怪物鞑靼
        { prefab = "unagi",             weight = 10,  count = {1, 1} }, -- 鳗鱼料理
        { prefab = "flowersalad",       weight = 20,  count = {1, 1} }, -- 花沙拉
        { prefab = "icecream",          weight = 10,  count = {1, 1} }, -- 冰淇淋
        { prefab = "watermelonicle",    weight = 20,  count = {1, 1} }, -- 西瓜冰
        { prefab = "trailmix",          weight = 30,  count = {1, 1} }, -- 什锦干果
        { prefab = "hotchili",          weight = 10,  count = {1, 1} }, -- 辣椒炖肉
        { prefab = "guacamole",         weight = 20,  count = {1, 1} }, -- 鳄梨酱
        { prefab = "jellybean",         weight = 10,  count = {1, 3} }, -- 彩虹糖豆
        { prefab = "freshfruitcrepes",  weight = 10,  count = {1, 1} }, -- 鲜果可丽饼
        { prefab = "bonesoup",          weight = 20,  count = {1, 1} }, -- 骨头汤
        { prefab = "mandrakesoup",      weight = 5,   count = {1, 1} }, -- 曼德拉草汤
        { prefab = "mooseegg",          weight = 5,   count = {1, 1} }, -- 麋鹿鹅蛋
        { prefab = "powcake",           weight = 10,  count = {1, 1} }, -- 粉末蛋糕
        { prefab = "seafoodgumbo",      weight = 10,  count = {1, 1} }, -- 海鲜浓汤
        { prefab = "surfnturf",         weight = 10,  count = {1, 1} }, -- 海鲜牛排
        { prefab = "lobsterbisque",     weight = 10,  count = {1, 1} }, -- 龙虾汤
        { prefab = "lobsterdinner",     weight = 5,   count = {1, 1} }, -- 龙虾正餐
        { prefab = "ceviche",           weight = 10,  count = {1, 1} }, -- 酸橘汁腌鱼
        { prefab = "californiaroll",    weight = 10,  count = {1, 1} }, -- 加州卷
        { prefab = "mashedpotatoes",    weight = 20,  count = {1, 1} }, -- 土豆泥
        { prefab = "asparagussoup",     weight = 20,  count = {1, 1} }, -- 芦笋汤
        { prefab = "vegstinger",        weight = 20,  count = {1, 1} }, -- 蔬菜鸡尾酒
        { prefab = "potatotornado",     weight = 20,  count = {1, 1} }, -- 花式回旋块茎
        { prefab = "veggieomlet",       weight = 20,  count = {1, 1} }, -- 早餐锅
        { prefab = "salsa",             weight = 20,  count = {1, 1} }, -- 生鲜萨尔萨酱
        { prefab = "pepperpopper",      weight = 20,  count = {1, 1} }, -- 爆炒填馅辣椒
        { prefab = "bananapop",         weight = 20,  count = {1, 1} }, -- 香蕉冻

        -- 基础装备
        { prefab = "spear",             weight = 50 }, -- 长矛 
        { prefab = "footballhat",       weight = 50 }, -- 橄榄球头盔 
        { prefab = "armorwood",         weight = 50 }, -- 木甲 
        { prefab = "hambat",            weight = 25 }, -- 火腿棒 

        -- 工具与照明
        { prefab = "lantern",           weight = 20 }, -- 提灯
        { prefab = "compass",           weight = 10 }, -- 指南针
        { prefab = "umbrella",          weight = 20 }, -- 雨伞
        { prefab = "grass_umbrella",    weight = 30 }, -- 花伞
        { prefab = "bedroll_straw",     weight = 30 }, -- 草席卷
        { prefab = "bedroll_furry",     weight = 10 }, -- 毛皮铺盖
        { prefab = "birdtrap",          weight = 20 }, -- 捕鸟陷阱
        { prefab = "trap",              weight = 30 }, -- 陷阱
        { prefab = "mushroom_light",    weight = 10 }, -- 蘑菇灯
        { prefab = "mushroom_light2",   weight = 5 },  -- 菌伞灯
    },

    -- [掉落物: Boss装备/稀有]
    -- 分组内排序规则：按 weight 降序（同权重保持功能邻近）
    DROPS_BOSS_GEAR = {
        -- 核心战斗装备
        { prefab = "cane",              weight = 60, tags = {"utility", "tempo"}, tier_hint = "mid" }, -- 手杖
        { prefab = "glasscutter",       weight = 50, tags = {"burst", "crit"}, tier_hint = "mid" }, -- 玻璃刀
        { prefab = "nightsword",        weight = 50, tags = {"burst", "nightmare"}, tier_hint = "mid" }, -- 影刀
        { prefab = "ruins_bat",         weight = 40 }, -- 铥矿棒
        { prefab = "eyebrellahat",      weight = 40 }, -- 眼球伞
        { prefab = "armorruins",        weight = 40, tags = {"tank", "durability"}, tier_hint = "mid" }, -- 铥矿甲
        { prefab = "ruinshat",          weight = 40, tags = {"tank", "durability"}, tier_hint = "mid" }, -- 铥矿头
        { prefab = "panflute",          weight = 30 }, -- 排箫
        { prefab = "armordragonfly",    weight = 30, tags = {"tank", "thorns"}, tier_hint = "late" }, -- 鳞甲
        { prefab = "armor_sanity",      weight = 30, tags = {"nightmare", "shield"}, tier_hint = "late" }, -- 影甲
        { prefab = "shieldofterror",    weight = 25, tags = {"tank", "sustain"}, tier_hint = "late" }, -- 恐怖盾
        { prefab = "hivehat",           weight = 20 }, -- 蜂后头
        { prefab = "trident",           weight = 20, tags = {"burst", "utility"}, tier_hint = "late" }, -- 远古叉戟
        { prefab = "krampus_sack",      weight = 10 }, -- 坎普斯背包
        
        -- 护符与法杖
        { prefab = "amulet",            weight = 30 }, -- 重生护符
        { prefab = "firestaff",         weight = 25 }, -- 火魔杖
        { prefab = "icestaff",          weight = 25 }, -- 冰魔杖
        { prefab = "greenstaff",        weight = 20 }, -- 绿杖
        { prefab = "yellowstaff",       weight = 20 }, -- 黄杖
        { prefab = "orangestaff",       weight = 20 }, -- 橙杖
        { prefab = "blueamulet",        weight = 20 }, -- 寒冰护符
        { prefab = "purpleamulet",      weight = 20 }, -- 梦魇护符
        { prefab = "yellowamulet",      weight = 20 }, -- 魔光护符
        { prefab = "orangeamulet",      weight = 20 }, -- 懒人护符
        { prefab = "greenamulet",       weight = 20 }, -- 建造护符
        { prefab = "staff_tornado",     weight = 20 }, -- 天气风向标
        { prefab = "multitool_axe_pickaxe", weight = 20 }, -- 多用斧镐
        { prefab = "telestaff",         weight = 20 }, -- 传送魔杖
        { prefab = "voidcloth_scythe",  weight = 20, tags = {"nightmare", "burst"}, tier_hint = "endgame" }, -- 暗影收割者
        { prefab = "opalstaff",         weight = 15 }, -- 唤月者魔杖
        
        -- 头部与护甲
        { prefab = "minerhat",          weight = 40 }, -- 矿工帽
        { prefab = "flowerhat",         weight = 40 }, -- 花环
        { prefab = "beefalohat",        weight = 30 }, -- 牛角帽
        { prefab = "featherhat",        weight = 30 }, -- 羽毛帽
        { prefab = "tophat",            weight = 30 }, -- 高礼帽
        { prefab = "watermelonhat",     weight = 30 }, -- 西瓜帽
        { prefab = "bushhat",           weight = 30 }, -- 灌木丛帽
        { prefab = "earmuffshat",       weight = 30 }, -- 兔耳罩
        { prefab = "goggleshat",        weight = 30 }, -- 时髦的护目镜
        { prefab = "spear_wathgrithr",  weight = 25 }, -- 战斗长矛
        { prefab = "skeletonhat",       weight = 20 }, -- 骨头头盔
        { prefab = "armorskeleton",     weight = 20 }, -- 骨头盔甲
        { prefab = "armor_bramble",     weight = 20 }, -- 荆棘外壳
        { prefab = "walrushat",         weight = 20 }, -- 贝雷帽
        { prefab = "slurtlehat",        weight = 20 }, -- 背壳头盔
        { prefab = "icehat",            weight = 20 }, -- 冰帽
        { prefab = "catcoonhat",        weight = 20 }, -- 猫帽
        { prefab = "sweatervest",       weight = 20 }, -- 犬牙背心
        { prefab = "trunkvest_summer",  weight = 20 }, -- 透气背心
        { prefab = "trunkvest_winter",  weight = 20 }, -- 松软背心
        { prefab = "reflectivevest",    weight = 20 }, -- 清凉夏装
        { prefab = "hawaiianshirt",     weight = 20 }, -- 花衬衫
        { prefab = "raincoat",          weight = 20 }, -- 雨衣
        { prefab = "spiderhat",         weight = 20 }, -- 蜘蛛帽
        { prefab = "wathgrithrhat",     weight = 20 }, -- 战斗头盔
        { prefab = "cookiecutterhat",   weight = 20 }, -- 饼干切割机帽子
        { prefab = "kelphat",           weight = 20 }, -- 海花环
        { prefab = "deserthat",         weight = 20 }, -- 沙漠护目镜
        { prefab = "armordreadstone",   weight = 15 }, -- 绝望石盔甲
        { prefab = "dreadstonehat",     weight = 15 }, -- 绝望石头盔
        { prefab = "voidclothhat",      weight = 15 }, -- 虚空风帽
        { prefab = "lunarplanthat",     weight = 15 }, -- 亮茄头盔
        { prefab = "armor_lunarplant",  weight = 15, tags = {"lunar", "tank"}, tier_hint = "endgame" }, -- 亮茄盔甲
        { prefab = "armor_voidcloth",   weight = 15, tags = {"nightmare", "utility"}, tier_hint = "endgame" }, -- 虚空长袍
        { prefab = "alterguardianhat",  weight = 10 }, -- 启迪之冠
        { prefab = "armorsnurtleshell", weight = 10 }, -- 蜗壳护甲
        { prefab = "moonstorm_goggleshat", weight = 10 }, -- 星象护目镜
        
        -- 远程与投掷
        { prefab = "blowdart_pipe",     weight = 40, count = {3, 6} }, -- 吹箭
        { prefab = "blowdart_fire",     weight = 30, count = {2, 4} }, -- 火焰吹箭
        { prefab = "blowdart_sleep",    weight = 30, count = {2, 4} }, -- 催眠吹箭
        { prefab = "waterballoon",      weight = 30, count = {3, 6} }, -- 水球
        { prefab = "waterplant_bomb",   weight = 20, count = {1, 3}, tags = {"control", "aoe"}, tier_hint = "mid" }, -- 水草炸弹
        { prefab = "blowdart_yellow",   weight = 20, count = {2, 4} }, -- 雷电吹箭
        
        -- 功能性稀有物
        { prefab = "townportaltalisman",weight = 10, count = {1, 2} }, -- 沙之石
        { prefab = "pig_token",         weight = 10 }, -- 金腰带
        { prefab = "spider_whistle",    weight = 10 }, -- 韦伯口哨
        { prefab = "beef_bell",         weight = 10 }, -- 皮弗娄牛铃
        { prefab = "cursed_monkey_token", weight = 10 }, -- 诅咒饰币
        { prefab = "shadowheart",       weight = 5 },  -- 暗影心房
        { prefab = "thurible",          weight = 5 },  -- 暗影香炉
    },

    -- [掉落物: 稀有材料]
    -- 分组内排序规则：按 weight 降序（同权重保持语义邻近）
    DROPS_BOSS_MATS = {
        -- 矿物与宝石
        { prefab = "thulecite_pieces",  weight = 80, count = {4, 8}, tier_hint = "mid", tags = {"ruins", "craft"} }, -- 铥矿碎片
        { prefab = "gears",             weight = 80, count = {1, 2}, tier_hint = "early", tags = {"mechanic", "craft"} }, -- 齿轮
        { prefab = "thulecite",         weight = 60, count = {2, 4}, tier_hint = "late", tags = {"ruins", "craft"} }, -- 铥矿
        { prefab = "bluegem",           weight = 50, count = {1, 2} }, -- 蓝宝石
        { prefab = "redgem",            weight = 50, count = {1, 2} }, -- 红宝石
        { prefab = "moonrocknugget",    weight = 50, count = {2, 3} }, -- 月岩
        { prefab = "purplegem",         weight = 40, count = {1, 2} }, -- 紫宝石
        { prefab = "orangegem",         weight = 20, count = {1, 1} }, -- 橙宝石
        { prefab = "yellowgem",         weight = 20, count = {1, 1} }, -- 黄宝石
        { prefab = "greengem",          weight = 20, count = {1, 1} }, -- 绿宝石

        -- Boss专属组织材料
        { prefab = "walrus_tusk",       weight = 30, count = {1, 1} }, -- 海象牙
        { prefab = "deerclops_eyeball", weight = 30, count = {1, 1} }, -- 独眼巨鹿眼球
        { prefab = "bearger_fur",       weight = 30, count = {1, 1} }, -- 熊皮
        { prefab = "dragon_scales",     weight = 30, count = {1, 1} }, -- 鳞片
        { prefab = "shroom_skin",       weight = 30, count = {1, 1} }, -- 蘑菇皮
        { prefab = "steelwool",         weight = 30, count = {1, 1} }, -- 钢丝绵
        
        -- 月相与梦魇产物
        { prefab = "nightmarefuel",     weight = 60, count = {2, 4}, tier_hint = "mid", tags = {"nightmare", "craft"} }, -- 噩梦燃料
        { prefab = "horrorfuel",        weight = 50, count = {2, 4}, tier_hint = "endgame", tags = {"nightmare", "rift"} }, -- 纯粹恐惧
        { prefab = "moonglass",         weight = 40, count = {2, 4} }, -- 月亮碎片
        { prefab = "voidcloth",         weight = 25, count = {1, 2}, tier_hint = "endgame", tags = {"rift", "nightmare"} }, -- 暗影织物
        { prefab = "dreadstone",        weight = 25, count = {1, 2}, tier_hint = "endgame", tags = {"rift", "nightmare"} }, -- 绝望石
        { prefab = "purebrilliance",    weight = 20, count = {1, 2}, tier_hint = "endgame", tags = {"lunar", "rift"} }, -- 纯粹辉煌
        { prefab = "lunarplant_husk",   weight = 20, count = {1, 2}, tier_hint = "endgame", tags = {"lunar", "craft"} }, -- 亮茄外壳
        { prefab = "glassspike",       weight = 20, count = {1, 2} }, -- 玻璃尖刺
        { prefab = "moonstorm_spark",   weight = 15, count = {1, 2} }, -- 约束静电
        { prefab = "wagpunk_bits",      weight = 15, count = {1, 2} }, -- 废铁
        { prefab = "alterguardianhatshard", weight = 10, count = {1, 2} }, -- 启迪碎片
        { prefab = "moonrockcrater",    weight = 10, count = {1, 1} }, -- 带孔月岩
        { prefab = "nightmare_timepiece", weight = 10, count = {1, 1} }, -- 铥矿徽章
        
        -- 药水
        { prefab = "healingsalve",      weight = 50, count = {1, 2} }, -- 治疗药膏
        { prefab = "bandage",           weight = 40, count = {1, 2} }, -- 蜂蜜药膏
        { prefab = "lifeinjector",      weight = 20, count = {1, 1} }, -- 强心针
        { prefab = "ghostlyelixir_slowregen", weight = 15, count = {1, 1} }, -- 亡者补药
        { prefab = "ghostlyelixir_fastregen", weight = 10, count = {1, 1} }, -- 灵魂万灵药
        { prefab = "ghostlyelixir_shield",    weight = 10, count = {1, 1} }, -- 不屈药剂
        { prefab = "ghostlyelixir_retaliation", weight = 10, count = {1, 1} }, -- 蒸馏复仇
        { prefab = "ghostlyelixir_speed",     weight = 10, count = {1, 1} }, -- 强健精油
        
        -- 怪物掉落材料
        { prefab = "silk",              weight = 50, count = {2, 4} }, -- 蜘蛛丝
        { prefab = "spidergland",       weight = 50, count = {1, 3} }, -- 蜘蛛腺
        { prefab = "beefalowool",       weight = 40, count = {2, 4} }, -- 牛毛
        { prefab = "pigskin",           weight = 40, count = {1, 2} }, -- 猪皮
        { prefab = "houndstooth",       weight = 40, count = {2, 4} }, -- 犬牙
        { prefab = "beardhair",         weight = 30, count = {1, 2} }, -- 胡须
        { prefab = "boneshard",         weight = 30, count = {1, 2} }, -- 骨片
        { prefab = "goose_feather",     weight = 30, count = {2, 4} }, -- 麋鹿鹅羽毛
        { prefab = "horn",              weight = 20, count = {1, 1} }, -- 牛角
        { prefab = "tentaclespots",     weight = 20, count = {1, 1} }, -- 触手皮
        { prefab = "cookiecuttershell", weight = 20, count = {1, 2} }, -- 饼干切割机壳
        { prefab = "slurtleslime",      weight = 10, count = {1, 2} }, -- 蛞蝓龟黏液
        { prefab = "glommerwings",      weight = 10, count = {1, 1} }, -- 格罗姆翅膀
        { prefab = "glommerflower",     weight = 5,  count = {1, 1} }, -- 格罗姆花
    },

    -- [海难版普通敌人池]
    ENEMIES_NORMAL_SHIPWRECKED = {
        { prefab = "snake",             weight = 95, count = {2, 3}, min_day = 0 }, -- 蛇
        { prefab = "snake_poison",      weight = 80, count = {1, 2}, min_day = 2 }, -- 毒蛇
        { prefab = "flup",              weight = 70, count = {1, 2}, min_day = 2 }, -- 弗拉普(独眼鱼)
        { prefab = "crocodog",          weight = 85, count = {1, 2}, min_day = 3 }, -- 猎犬(海狗)
        { prefab = "mosquito_poison",   weight = 60, count = {2, 3}, min_day = 5 }, -- 毒蚊子
        { prefab = "watercrocodog",     weight = 65, count = {1, 2}, min_day = 8 }, -- 水猎犬(水海狗)
        { prefab = "sharx",             weight = 55, count = {1, 1}, min_day = 10 }, -- 猎鲨
        { prefab = "stungray",          weight = 45, count = {1, 2}, min_day = 14 }, -- 毒蝠𫚉
        { prefab = "dragoon",           weight = 55, count = {1, 2}, min_day = 16 }, -- 龙骑士
        { prefab = "pirateghost",       weight = 35, count = {1, 1}, min_day = 18 }, -- 海盗幽灵
        { prefab = "wildbore",          weight = 35, count = {1, 2}, min_day = 22 }, -- 野猪
    },

    -- [海难版精英敌人池]
    ENEMIES_ELITE_SHIPWRECKED = {
        { prefab = "ox",                weight = 55, min_day = 12 }, -- 水牛
        { prefab = "tropical_spider_warrior", weight = 50, min_day = 12 }, -- 丛林蜘蛛战士
        { prefab = "poisoncrocodog",    weight = 50, min_day = 14 }, -- 毒猎犬(毒海狗)
        { prefab = "swordfish",         weight = 50, min_day = 18 }, -- 剑鱼
        { prefab = "knightboat",        weight = 45, min_day = 20 }, -- 机械船骑士
        { prefab = "dragoon",           weight = 40, min_day = 24 }, -- 龙骑士
        { prefab = "leif_palm",         weight = 35, min_day = 28 }, -- 椰树树精
    },

    -- [海难版Boss池]
    BOSSES_SHIPWRECKED = {
        { prefab = "tigershark",        weight = 120, min_day = 0,  family = "tigershark" }, -- 虎鲨
        { prefab = "twister",           weight = 90,  min_day = 18, family = "twister" }, -- 豹卷风
        { prefab = "kraken",            weight = 80,  min_day = 28, family = "kraken" }, -- 飓风海妖
    },

    -- [海难版基础掉落]
    DROPS_NORMAL_SHIPWRECKED = {
        { prefab = "rawling",           weight = 95, count = {1, 2} }, -- 罗林
        { prefab = "limpets",           weight = 85, count = {1, 3} }, -- 帽贝
        { prefab = "solofish_dead",     weight = 80, count = {1, 2} }, -- 死狗鱼
        { prefab = "lobster_dead",      weight = 65, count = {1, 2} }, -- 死龙虾
        { prefab = "seaweed",           weight = 80, count = {2, 4} }, -- 海带
        { prefab = "bamboo",            weight = 80, count = {2, 4} }, -- 竹子
        { prefab = "vine",              weight = 80, count = {2, 4} }, -- 藤蔓
        { prefab = "coconut",           weight = 65, count = {1, 3} }, -- 椰子
        { prefab = "coral",             weight = 60, count = {1, 3} }, -- 珊瑚
        { prefab = "seashell",          weight = 60, count = {1, 3} }, -- 贝壳
        { prefab = "jellyfish_dead",    weight = 60, count = {1, 2} }, -- 死水母
        { prefab = "snakeskin",         weight = 55, count = {1, 2} }, -- 蛇皮
        { prefab = "venomgland",        weight = 45, count = {1, 2} }, -- 毒腺
        { prefab = "limestonenugget",   weight = 55, count = {2, 3} }, -- 石灰石
        { prefab = "dubloon",           weight = 35, count = {1, 3} }, -- 金币

        -- 熟食与烹饪成品 (标准 + 海难)
        { prefab = "cookedmeat",        weight = 40,  count = {1, 2} }, -- 熟肉
        { prefab = "cookedsmallmeat",   weight = 50,  count = {1, 2} }, -- 熟小肉
        { prefab = "cookedmonstermeat", weight = 40,  count = {1, 2} }, -- 熟怪物肉
        { prefab = "carrot_cooked",     weight = 40,  count = {1, 2} }, -- 熟胡萝卜
        { prefab = "corn_cooked",       weight = 30,  count = {1, 2} }, -- 熟玉米
        { prefab = "potato_cooked",     weight = 30,  count = {1, 2} }, -- 熟土豆
        { prefab = "tomato_cooked",     weight = 30,  count = {1, 2} }, -- 熟番茄
        { prefab = "fishmeat_cooked",   weight = 40,  count = {1, 2} }, -- 熟鱼肉
        { prefab = "fishmeat_small_cooked", weight = 50,  count = {1, 2} }, -- 熟小鱼肉
        { prefab = "jellyfish_cooked",  weight = 40,  count = {1, 2} }, -- 熟水母
        { prefab = "seaweed_cooked",    weight = 50,  count = {1, 2} }, -- 熟海带
        { prefab = "limpets_cooked",    weight = 50,  count = {1, 2} }, -- 熟帽贝
        { prefab = "mussel_cooked",     weight = 40,  count = {1, 2} }, -- 熟贻贝
        { prefab = "sweet_potato_cooked",weight = 40, count = {1, 2} }, -- 熟红薯
        { prefab = "coconut_cooked",    weight = 40,  count = {1, 2} }, -- 烤椰子
        { prefab = "coffeebeans_cooked",weight = 40,  count = {1, 2} }, -- 烤咖啡豆

        -- 锅料理 (标准 + 海难)
        { prefab = "meatballs",         weight = 50,  count = {1, 1} }, -- 肉丸
        { prefab = "perogies",          weight = 40,  count = {1, 1} }, -- 饺子
        { prefab = "frogglebunwich",    weight = 30,  count = {1, 1} }, -- 蛙腿汉堡
        { prefab = "honeyham",          weight = 20,  count = {1, 1} }, -- 蜜汁火腿
        { prefab = "dragonpie",         weight = 10,  count = {1, 1} }, -- 火龙果派
        { prefab = "baconeggs",         weight = 20,  count = {1, 1} }, -- 培根煎蛋
        { prefab = "fishsticks",        weight = 30,  count = {1, 1} }, -- 炸鱼条
        { prefab = "honeynuggets",      weight = 30,  count = {1, 1} }, -- 甜蜜金砖
        { prefab = "butterflymuffin",   weight = 30,  count = {1, 1} }, -- 蝴蝶松饼
        { prefab = "waffles",           weight = 10,  count = {1, 1} }, -- 华夫饼
        { prefab = "ratatouille",       weight = 30,  count = {1, 1} }, -- 蔬菜什锦
        { prefab = "fruitmedley",       weight = 20,  count = {1, 1} }, -- 水果拼盘
        { prefab = "monsterlasagna",    weight = 10,  count = {1, 1} }, -- 怪物千层面
        { prefab = "unagi",             weight = 10,  count = {1, 1} }, -- 鳗鱼卷
        { prefab = "icecream",          weight = 10,  count = {1, 1} }, -- 冰淇淋
        { prefab = "watermelonicle",    weight = 20,  count = {1, 1} }, -- 西瓜冰棍
        { prefab = "trailmix",          weight = 30,  count = {1, 1} }, -- 坚果拌道
        { prefab = "guacamole",         weight = 20,  count = {1, 1} }, -- 鳄梨酱
        { prefab = "surfnturf",         weight = 10,  count = {1, 1} }, -- 海鲜牛排
        { prefab = "seafoodgumbo",      weight = 10,  count = {1, 1} }, -- 海鲜浓汤
        { prefab = "californiaroll",    weight = 10,  count = {1, 1} }, -- 加州卷
        { prefab = "ceviche",           weight = 10,  count = {1, 1} }, -- 酸橘汁腌鱼
        { prefab = "bisque",            weight = 20,  count = {1, 1} }, -- 浓汤
        { prefab = "jellyopop",         weight = 20,  count = {1, 1} }, -- 水母冻
        { prefab = "wobsterbisque",     weight = 10,  count = {1, 1} }, -- 龙虾汤
        { prefab = "wobsterdinner",     weight = 10,  count = {1, 1} }, -- 龙虾正餐
        { prefab = "sharkfinsoup",      weight = 10,  count = {1, 1} }, -- 鱼翅汤
        { prefab = "tropicalbouillabaisse", weight = 10, count = {1, 1} }, -- 热带鱼汤
        { prefab = "caviar",            weight = 10,  count = {1, 1} }, -- 鱼子酱
        { prefab = "tiroemisu",         weight = 20,  count = {1, 1} }, -- 提拉米苏
        { prefab = "musselbouillabaise",weight = 10,  count = {1, 1} }, -- 贻贝汤
        { prefab = "sweetpotatosouffle",weight = 20,  count = {1, 1} }, -- 红薯蛋奶酥
        { prefab = "jellyfishjelly",    weight = 10,  count = {1, 1} }, -- 水母果冻
        { prefab = "rainbowjellyfishmousse", weight = 10, count = {1, 1} }, -- 彩虹水母慕斯
        { prefab = "coffee",            weight = 30,  count = {1, 1} }, -- 咖啡
    },

    -- [海难版Boss装备掉落]
    DROPS_BOSS_GEAR_SHIPWRECKED = {
        { prefab = "machete",           weight = 70, tags = {"utility", "tempo"}, tier_hint = "early" }, -- 砍刀
        { prefab = "cutlass",           weight = 60, tags = {"burst", "crit"}, tier_hint = "mid" }, -- 剑鱼剑
        { prefab = "spear_launcher",    weight = 55, tags = {"burst", "ranged"}, tier_hint = "mid" }, -- 鱼叉发射器
        { prefab = "boatrepairkit",     weight = 45, tags = {"sustain", "utility"}, tier_hint = "mid" }, -- 修船套件
        { prefab = "palmleaf_umbrella", weight = 45, tags = {"utility"}, tier_hint = "mid" }, -- 棕榈叶伞
        { prefab = "bottlelantern",     weight = 40, tags = {"utility"}, tier_hint = "mid" }, -- 玻璃瓶灯
        { prefab = "tropicalfan",       weight = 40, tags = {"control"}, tier_hint = "mid" }, -- 热带风扇
        { prefab = "boatcannon",        weight = 35, tags = {"aoe", "burst"}, tier_hint = "late" }, -- 船载加农炮
        { prefab = "piratepack",        weight = 35, tags = {"utility", "tempo"}, tier_hint = "late" }, -- 海盗背包
        { prefab = "obsidianaxe",       weight = 35, tags = {"burst", "fire"}, tier_hint = "late" }, -- 黑曜石斧
        { prefab = "obsidianmachete",   weight = 35, tags = {"burst", "fire"}, tier_hint = "late" }, -- 黑曜石砍刀
        { prefab = "spear_obsidian",    weight = 30, tags = {"burst", "fire"}, tier_hint = "late" }, -- 黑曜石长矛
        { prefab = "volcanostaff",      weight = 24, tags = {"aoe", "fire"}, tier_hint = "late" }, -- 火山法杖
        { prefab = "armorobsidian",     weight = 24, tags = {"tank", "fire"}, tier_hint = "late" }, -- 黑曜石盔甲
        { prefab = "obsidiancoconade",  weight = 24, count = {2, 4}, tags = {"aoe", "fire"}, tier_hint = "late" }, -- 黑曜石椰饼
        { prefab = "ox_flute",          weight = 30, tags = {"control"}, tier_hint = "late" }, -- 水牛角排箫
        { prefab = "ia_trident",        weight = 28, tags = {"burst", "utility"}, tier_hint = "late" }, -- 三叉戟
    },

    -- [海难版稀有材料掉落]
    DROPS_BOSS_MATS_SHIPWRECKED = {
        { prefab = "obsidian",          weight = 70, count = {2, 4}, tags = {"fire", "craft"}, tier_hint = "mid" }, -- 黑曜石
        { prefab = "dragoonheart",      weight = 55, count = {1, 2}, tags = {"fire", "craft"}, tier_hint = "late" }, -- 龙骑士之心
        { prefab = "obsidian",          weight = 55, count = {3, 5}, tags = {"fire", "craft"}, tier_hint = "late" }, -- 黑曜石
        { prefab = "shark_fin",         weight = 50, count = {1, 2}, tags = {"boss", "craft"}, tier_hint = "mid" }, -- 鲨鱼鳍
        { prefab = "shark_gills",       weight = 45, count = {1, 2}, tags = {"boss", "craft"}, tier_hint = "mid" }, -- 鲨鱼鳃
        { prefab = "fabric",            weight = 60, count = {1, 2}, tags = {"utility", "craft"}, tier_hint = "mid" }, -- 布料
        { prefab = "coffeebeans",       weight = 50, count = {1, 2}, tags = {"tempo", "craft"}, tier_hint = "mid" }, -- 咖啡豆
        { prefab = "doydoyfeather",     weight = 35, count = {1, 2}, tags = {"rare", "craft"}, tier_hint = "late" }, -- 渡渡鸟羽毛
        { prefab = "venomgland",        weight = 50, count = {1, 3}, tags = {"poison", "craft"}, tier_hint = "mid" }, -- 毒腺
        { prefab = "antivenom",         weight = 40, count = {1, 2}, tags = {"poison", "heal"}, tier_hint = "mid" }, -- 抗毒血清
        { prefab = "bandage_poison",    weight = 35, count = {1, 2}, tags = {"poison", "heal"}, tier_hint = "mid" }, -- 解毒药膏
        { prefab = "snakeskin",         weight = 45, count = {1, 2}, tags = {"poison", "craft"}, tier_hint = "mid" }, -- 蛇皮
        { prefab = "dubloon",           weight = 30, count = {2, 4}, tags = {"currency"}, tier_hint = "mid" }, -- 金币
    },

    ENEMIES_NORMAL_HAMLET = {
        { prefab = "weevole",           weight = 80, count = {2, 4}, min_day = 0 }, -- 象鼻虫
        { prefab = "snake_amphibious",  weight = 90, count = {2, 3}, min_day = 0 }, -- 蛇(哈姆雷特)
        { prefab = "antman",            weight = 80, count = {2, 3}, min_day = 2 }, -- 蚁人(类似猪人)
        { prefab = "rabid_beetle",      weight = 75, count = {2, 3}, min_day = 2 }, -- 狂犬甲虫
        { prefab = "frog_poison",       weight = 55, count = {1, 2}, min_day = 6 }, -- 毒蛙
        { prefab = "mean_flytrap",      weight = 45, count = {1, 2}, min_day = 8 }, -- 捕蝇草
        { prefab = "cork_bat",          weight = 45, count = {2, 3}, min_day = 10 }, -- 软木蝙蝠
        { prefab = "scorpion",          weight = 30, count = {1, 2}, min_day = 14 }, -- 蝎子
        { prefab = "vampirebat",        weight = 25, count = {2, 3}, min_day = 16 }, -- 吸血蝙蝠
    },

    ENEMIES_ELITE_HAMLET = {
        { prefab = "antman_warrior",    weight = 55, min_day = 12 }, -- 蚁人战士
        { prefab = "pigman_royalguard", weight = 45, min_day = 14 }, -- 猪人守卫(主动攻击或危险)
        { prefab = "pigbandit",         weight = 40, min_day = 16 }, -- 猪人强盗
        { prefab = "hippopotamoose",    weight = 35, min_day = 18 }, -- 河马
        { prefab = "spider_monkey",     weight = 30, min_day = 20 }, -- 蜘蛛猴
        { prefab = "mandrakeman",       weight = 25, min_day = 22 }, -- 曼德拉草人
        { prefab = "adult_flytrap",     weight = 25, min_day = 24 }, -- 成年捕蝇草
        { prefab = "vampirebat",        weight = 22, min_day = 24 }, -- 吸血蝙蝠
    },

    BOSSES_HAMLET = {
        { prefab = "antqueen",          weight = 80,  min_day = 0,  family = "antqueen" }, -- 蚁后
        { prefab = "pugalisk",          weight = 75,  min_day = 12, family = "pugalisk" }, -- 巨蛇
        { prefab = "ancient_hulk",      weight = 70,  min_day = 30, family = "ancient_hulk" }, -- 铁巨人
        { prefab = "ancient_herald",    weight = 60,  min_day = 45, family = "ancient_herald" }, -- 远古先驱
    },

    DROPS_NORMAL_HAMLET = {
        { prefab = "oinc",              weight = 95, count = {2, 5} }, -- 呼噜币
        { prefab = "gold_dust",         weight = 80, count = {2, 4} }, -- 金砂
        { prefab = "cutnettle",         weight = 75, count = {1, 2} }, -- 剪下的荨麻
        { prefab = "cork",              weight = 75, count = {2, 4} }, -- 软木
        { prefab = "vine",              weight = 70, count = {2, 4} }, -- 藤蔓
        { prefab = "clippings",         weight = 65, count = {2, 4} }, -- 修剪物
        { prefab = "nectar_pod",        weight = 60, count = {1, 3} }, -- 花蜜荚
        { prefab = "weevole_carapace",  weight = 60, count = {1, 2} }, -- 象鼻虫甲壳
        { prefab = "chitin",            weight = 55, count = {1, 2} }, -- 甲壳
        { prefab = "venomgland",        weight = 50, count = {1, 2} }, -- 毒腺
        { prefab = "bat_hide",          weight = 45, count = {1, 2} }, -- 蝙蝠皮
        { prefab = "iron",              weight = 45, count = {1, 2} }, -- 铁矿石
        { prefab = "bill_quill",        weight = 42, count = {1, 2} }, -- 鸭嘴兽刺
        { prefab = "fabric",            weight = 35, count = {1, 2} }, -- 布料
        { prefab = "shears",            weight = 12, count = {1, 1} }, -- 剪刀

        -- 熟食与烹饪成品 (标准 + 哈姆雷特)
        { prefab = "cookedmeat",        weight = 40,  count = {1, 2} }, -- 熟肉
        { prefab = "cookedsmallmeat",   weight = 50,  count = {1, 2} }, -- 熟小肉
        { prefab = "cookedmonstermeat", weight = 40,  count = {1, 2} }, -- 熟怪物肉
        { prefab = "carrot_cooked",     weight = 40,  count = {1, 2} }, -- 熟胡萝卜
        { prefab = "corn_cooked",       weight = 30,  count = {1, 2} }, -- 熟玉米
        { prefab = "potato_cooked",     weight = 30,  count = {1, 2} }, -- 熟土豆
        { prefab = "tomato_cooked",     weight = 30,  count = {1, 2} }, -- 熟番茄
        { prefab = "asparagus_cooked",  weight = 30,  count = {1, 2} }, -- 熟芦笋
        { prefab = "aloe_cooked",       weight = 40,  count = {1, 2} }, -- 熟芦荟
        { prefab = "radish_cooked",     weight = 40,  count = {1, 2} }, -- 熟萝卜
        { prefab = "jellybug_cooked",   weight = 40,  count = {1, 2} }, -- 熟果冻虫
        { prefab = "slugbug_cooked",    weight = 40,  count = {1, 2} }, -- 熟鼻涕虫
        { prefab = "lotus_flower_cooked",weight= 40,  count = {1, 2} }, -- 熟莲花
        { prefab = "coffeebeans_cooked",weight = 40,  count = {1, 2} }, -- 烤咖啡豆

        -- 锅料理 (标准 + 哈姆雷特)
        { prefab = "meatballs",         weight = 50,  count = {1, 1} }, -- 肉丸
        { prefab = "perogies",          weight = 40,  count = {1, 1} }, -- 饺子
        { prefab = "frogglebunwich",    weight = 30,  count = {1, 1} }, -- 蛙腿汉堡
        { prefab = "honeyham",          weight = 20,  count = {1, 1} }, -- 蜜汁火腿
        { prefab = "dragonpie",         weight = 10,  count = {1, 1} }, -- 火龙果派
        { prefab = "baconeggs",         weight = 20,  count = {1, 1} }, -- 培根煎蛋
        { prefab = "fishsticks",        weight = 30,  count = {1, 1} }, -- 炸鱼条
        { prefab = "honeynuggets",      weight = 30,  count = {1, 1} }, -- 甜蜜金砖
        { prefab = "butterflymuffin",   weight = 30,  count = {1, 1} }, -- 蝴蝶松饼
        { prefab = "waffles",           weight = 10,  count = {1, 1} }, -- 华夫饼
        { prefab = "ratatouille",       weight = 30,  count = {1, 1} }, -- 蔬菜什锦
        { prefab = "fruitmedley",       weight = 20,  count = {1, 1} }, -- 水果拼盘
        { prefab = "monsterlasagna",    weight = 10,  count = {1, 1} }, -- 怪物千层面
        { prefab = "icecream",          weight = 10,  count = {1, 1} }, -- 冰淇淋
        { prefab = "watermelonicle",    weight = 20,  count = {1, 1} }, -- 西瓜冰棍
        { prefab = "trailmix",          weight = 30,  count = {1, 1} }, -- 坚果拌道
        { prefab = "guacamole",         weight = 20,  count = {1, 1} }, -- 鳄梨酱
        { prefab = "mashedpotatoes",    weight = 20,  count = {1, 1} }, -- 土豆泥
        { prefab = "asparagussoup",     weight = 20,  count = {1, 1} }, -- 芦笋汤
        { prefab = "vegstinger",        weight = 20,  count = {1, 1} }, -- 蔬菜鸡尾酒
        { prefab = "snakebonesoup",     weight = 20,  count = {1, 1} }, -- 蛇骨汤
        { prefab = "tea",               weight = 30,  count = {1, 1} }, -- 茶
        { prefab = "icedtea",           weight = 30,  count = {1, 1} }, -- 冰茶
        { prefab = "gummy_cake",        weight = 20,  count = {1, 1} }, -- 软糖蛋糕
        { prefab = "feijoada",          weight = 20,  count = {1, 1} }, -- 豆子炖肉
        { prefab = "steamedhamsandwich",weight = 20,  count = {1, 1} }, -- 蒸火腿三明治
        { prefab = "hardshell_tacos",   weight = 20,  count = {1, 1} }, -- 硬壳玉米饼
        { prefab = "nettlelosange",     weight = 20,  count = {1, 1} }, -- 荨麻卷
        { prefab = "meated_nettle",     weight = 20,  count = {1, 1} }, -- 荨麻肉
        { prefab = "coffee",            weight = 30,  count = {1, 1} }, -- 咖啡
    },

    DROPS_BOSS_GEAR_HAMLET = {
        { prefab = "halberd",           weight = 65, tags = {"burst", "crit"}, tier_hint = "mid" }, -- 戟
        { prefab = "blunderbuss",       weight = 55, tags = {"burst", "ranged"}, tier_hint = "mid" }, -- 喇叭枪
        { prefab = "armor_metalplate",  weight = 52, tags = {"tank", "durability"}, tier_hint = "mid" }, -- 铁甲
        { prefab = "armor_weevole",     weight = 45, tags = {"tank", "utility"}, tier_hint = "mid" }, -- 象鼻虫甲
        { prefab = "antsuit",           weight = 38, tags = {"utility", "poison"}, tier_hint = "mid" }, -- 蚂蚁服
        { prefab = "disarming_kit",     weight = 35, tags = {"utility"}, tier_hint = "mid" }, -- 拆除工具
        { prefab = "gasmaskhat",        weight = 35, tags = {"utility"}, tier_hint = "mid" }, -- 防毒面具
        { prefab = "city_hammer",       weight = 30, tags = {"utility"}, tier_hint = "late" }, -- 城市锤
        { prefab = "pig_scepter",       weight = 24, tags = {"burst"}, tier_hint = "late" }, -- 猪镇权杖
        { prefab = "bonestaff",         weight = 24, tags = {"burst", "nightmare"}, tier_hint = "late" }, -- 骨杖
        { prefab = "armorvortexcloak",  weight = 20, tags = {"tank", "sustain"}, tier_hint = "late" }, -- 漩涡斗篷
        { prefab = "ox_flute",          weight = 20, tags = {"control"}, tier_hint = "late" }, -- 排箫
    },

    DROPS_BOSS_MATS_HAMLET = {
        { prefab = "oinc",              weight = 80, count = {6, 12}, tags = {"currency"} }, -- 呼噜币
        { prefab = "oinc10",            weight = 55, count = {2, 4}, tags = {"currency"} }, -- 10呼噜币
        { prefab = "oinc100",           weight = 30, count = {1, 2}, tags = {"currency"} }, -- 100呼噜币
        { prefab = "alloy",             weight = 55, count = {1, 2}, tags = {"craft"} }, -- 合金
        { prefab = "infused_iron",      weight = 50, count = {1, 2}, tags = {"craft"} }, -- 灌魔铁
        { prefab = "gears",             weight = 50, count = {1, 2}, tags = {"craft"} }, -- 齿轮
        { prefab = "iron",              weight = 50, count = {2, 4}, tags = {"craft"} }, -- 铁矿石
        { prefab = "hippo_antler",      weight = 48, count = {1, 1}, tags = {"boss", "craft"} }, -- 河马角
        { prefab = "ancient_remnant",   weight = 46, count = {1, 2}, tags = {"boss", "craft"} }, -- 远古残骸
        { prefab = "living_artifact",   weight = 45, count = {1, 2}, tags = {"craft"} }, -- 活体神器
        { prefab = "chitin",            weight = 45, count = {2, 4}, tags = {"craft"} }, -- 甲壳
        { prefab = "snake_bone",        weight = 42, count = {1, 2}, tags = {"boss", "craft"} }, -- 蛇骨
        { prefab = "bugrepellent",      weight = 35, count = {1, 2}, tags = {"utility"} }, -- 杀虫剂
        { prefab = "antivenom",         weight = 35, count = {1, 2}, tags = {"heal"} }, -- 解毒剂
        { prefab = "nectar_pod",        weight = 35, count = {2, 4}, tags = {"food"} }, -- 花蜜荚
        { prefab = "lotus_flower",      weight = 30, count = {1, 2}, tags = {"food"} }, -- 莲花
    },
}

-- 函数说明：设置世界玩法版本，决定随机池读取标准版或海难版。
function catalog.SetWorldVariant(variant)
    if variant == "shipwrecked" or variant == "hamlet" then
        catalog.world_variant = variant
    else
        catalog.world_variant = "standard"
    end
end

-- 函数说明：返回当前随机池使用的玩法版本。
function catalog.GetWorldVariant()
    return catalog.world_variant
end

-- [获取函数]
-- 根据天数和类型，动态构建当前的随机权重池
function catalog.GetRuntimePool(type, day)
    local target_type = type
    if catalog.world_variant == "shipwrecked" then
        local sw_type = SHIPWRECKED_TYPE_MAP[type]
        if sw_type and catalog.POOLS[sw_type] then
            target_type = sw_type
        end
    elseif catalog.world_variant == "hamlet" then
        local hamlet_type = HAMLET_TYPE_MAP[type]
        if hamlet_type and catalog.POOLS[hamlet_type] then
            target_type = hamlet_type
        end
    end
    local raw_list = catalog.POOLS[target_type]
    if not raw_list then return {} end

    local pool = {}
    local total_weight = 0

    for _, item in ipairs(raw_list) do
        -- 1. 检查天数门槛
        if not item.min_day or day >= item.min_day then
            table.insert(pool, item)
            total_weight = total_weight + (item.weight or 10)
        end
    end

    return pool, total_weight
end

return catalog
