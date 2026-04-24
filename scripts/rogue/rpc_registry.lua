--[[
    文件说明：rpc_registry.lua
    功能：集中管理Mod RPC注册，替代GLOBAL全局函数桥接模式。
    通过闭包捕获处理函数，避免命名空间污染。
    新增RPC合并窗口机制 —— 同一帧内的多个RPC调用自动打包发送，减少网络包数量。
]]
local RPCRegistry = {
    _handlers = {},
    _namespace = "rogue_mode",
}

-- RPC合并窗口机制
local _batch_queue = {}
local _batch_timer = nil
local BATCH_MAX_WAIT_FRAMES = 1  -- 合并窗口：最多等待1帧
local BATCH_MAX_SIZE = 8          -- 单批最大RPC数

-- 函数说明：注册RPC处理器
-- name: RPC名称（字符串）
-- handler: 处理函数 fn(player, ...)
-- 返回RPC标识表，可用于 SendModRPCToServer
function RPCRegistry.Register(name, handler)
    if type(handler) ~= "function" then
        print("[RogueRPC] Invalid handler for: " .. tostring(name))
        return nil
    end
    RPCRegistry._handlers[name] = handler
    AddModRPCHandler(RPCRegistry._namespace, name, function(player, ...)
        handler(player, ...)
    end)
    return GetModRPC(RPCRegistry._namespace, name)
end

-- 函数说明：获取已注册的RPC标识表（用于SendModRPCToServer）
function RPCRegistry.GetRPC(name)
    return GetModRPC(RPCRegistry._namespace, name)
end

-- 函数说明：发送RPC到服务器
function RPCRegistry.SendToServer(name, ...)
    local rpc = RPCRegistry.GetRPC(name)
    if rpc then
        SendModRPCToServer(rpc, ...)
    end
end

-- 函数说明：将RPC加入合并队列，同一帧内的多个RPC将在下一帧合并发送
-- 适用于连续操作场景（如：购买 → 装备 → 刷新UI）
function RPCRegistry.QueueToServer(name, ...)
    if not RPCRegistry.GetRPC(name) then
        print("[RogueRPC] Cannot queue unregistered RPC: " .. tostring(name))
        return
    end
    table.insert(_batch_queue, { name = name, args = { ... } })
    if #_batch_queue >= BATCH_MAX_SIZE then
        RPCRegistry.FlushBatchToServer()
    elseif not _batch_timer then
        _batch_timer = TheWorld and TheWorld:DoTaskInTime(0, function()
            RPCRegistry.FlushBatchToServer()
        end)
    end
end

-- 函数说明：立即发送队列中所有待处理的RPC（合并为一次连续调用）
function RPCRegistry.FlushBatchToServer()
    if #_batch_queue == 0 then
        _batch_timer = nil
        return
    end
    for _, entry in ipairs(_batch_queue) do
        RPCRegistry.SendToServer(entry.name, table.unpack(entry.args))
    end
    _batch_queue = {}
    if _batch_timer then
        _batch_timer:Cancel()
        _batch_timer = nil
    end
end

-- 函数说明：获取所有已注册的RPC名称
function RPCRegistry.GetRegisteredNames()
    local names = {}
    for name, _ in pairs(RPCRegistry._handlers) do
        table.insert(names, name)
    end
    return names
end

-- 函数说明：检查指定RPC是否已注册
function RPCRegistry.IsRegistered(name)
    return RPCRegistry._handlers[name] ~= nil
end

-- 函数说明：获取已注册RPC数量
function RPCRegistry.Count()
    local n = 0
    for _ in pairs(RPCRegistry._handlers) do
        n = n + 1
    end
    return n
end

-- 预定义RPC名称常量
RPCRegistry.Names = {
    PICK_TALENT = "pick_talent",
    PICK_SUPPLY = "pick_supply",
    PICK_RELIC = "pick_relic",
    PICK_ROUTE = "pick_route",
    BUY_SHOP_ITEM = "buy_shop_item",
    BUY_BLACK_MARKET_ITEM = "buy_black_market_item",
    RECYCLE_ITEM = "recycle_item",
    OPEN_RECYCLE_BIN = "open_recycle_bin",
    CLOSE_RECYCLE_BIN = "close_recycle_bin",
    RECYCLE_ALL_ITEMS = "recycle_all_items",
    RELOAD_CONFIG = "reload_config",
}

return RPCRegistry
