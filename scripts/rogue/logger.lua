--[[
    文件说明：logger.lua
    功能：统一日志系统。
    替代散落的 print() 调用，支持分级日志（DEBUG/INFO/WARN/ERROR/OFF），
    受模组配置项 DEBUG_MODE 控制，DEBUG级别仅开发模式输出。
]]
local M = {}

local LEVELS = { DEBUG = 0, INFO = 1, WARN = 2, ERROR = 3, OFF = 4 }
local LEVEL_NAMES = { [0] = "DBG", [1] = "INF", [2] = "WRN", [3] = "ERR" }
M.LEVELS = LEVELS

local _current_level = LEVELS.INFO
local _tag_prefix = "[Rogue]"

function M.SetLevel(level)
    _current_level = level
end

function M.SetDebugMode(enabled)
    _current_level = enabled and LEVELS.DEBUG or LEVELS.INFO
end

function M.SetTagPrefix(prefix)
    _tag_prefix = prefix or "[Rogue]"
end

local function _log(level, tag, msg)
    if level < _current_level then return end
    local level_name = LEVEL_NAMES[level] or "???"
    print(string.format("%s[%s][%s] %s", _tag_prefix, level_name, tostring(tag), tostring(msg)))
end

function M.Debug(tag, msg)
    _log(LEVELS.DEBUG, tag, msg)
end

function M.Info(tag, msg)
    _log(LEVELS.INFO, tag, msg)
end

function M.Warn(tag, msg)
    _log(LEVELS.WARN, tag, msg)
end

function M.Error(tag, msg)
    _log(LEVELS.ERROR, tag, msg)
end

return M
