local inspect = require "inspect"
local service = require "lservice3".input(...)
local config = service.config
local ctp = require "lctp2"

local trader_id = nil

--
-- 从 ~/.tifa/accounts.lua 中读取服务器列表信息（包含用户名和密码）
--
local function load_accounts()
    -- 获取家目录路径（兼容 Windows 和 Linux/macOS）
    local home = os.getenv("HOME") or os.getenv("USERPROFILE")
    if not home then return nil end

    local filepath = home .. "/.tifa/accounts.lua"

    -- 加载文件（此时只编译不执行）
    local chunk, err = loadfile(filepath)
    if not chunk then
        error("failed loading: " .. tostring(err))
    end

    -- 执行文件，获取返回值
    -- 假设 accounts.lua 结尾有 return 了一个 table
    local accounts = chunk() 
    return accounts
end

local function boot()
    local symbol  = "IM2703"
    local accounts = load_accounts()

    ctp.log_debug("booting root")
    service.spawn { name = "collector", source = "@services/ctp_collector.lua", config = { 
            server = accounts["collector"]["gtja-3"],
            symbol = symbol
        } }

    service.call("collector", "start")
    service.call("collector", "subscribe", "sc2609")

    service.spawn { name = "trader", source = "@services/ctp_trader.lua", config = {
            server = accounts["trader"]["gtja-3"],
            symbol = symbol
        } }
    local rsp = service.call("trader", "start") -- blocking, until trader starts

    ctp.log_debug("start result", rsp)

    local err, rst = service.call("trader", "query_account")
    ctp.log_info("query_account: %s", inspect(rst))
    local err, rst = service.call("trader", "query_instrument", "IM2703")
    ctp.log_info("query_instrument: %s", inspect(rst))
    local err, rst = service.call("trader", "query_position")
    ctp.log_info("query_position: %s", inspect(rst))

    -- service.call("trader", "quit")

    service.spawn { name = "bot", source = "@services/bot.lua", config = { } }
end

local S = {}

function S.boot()
    boot()
    -- service.send(0, "quit")
end

function S.quit()
    ctp.log_debug("root is quiting")
    service.send("collector", "quit")
    service.send("trader", "quit")
    service.quit()
end

return service.dispatch(S)