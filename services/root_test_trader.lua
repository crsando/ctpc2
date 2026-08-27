local inspect = require "inspect"
local service = require "lservice3".input(...)
local scheduler = require "lservice3.scheduler"
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

local function boot_test_collector()
    local accounts = load_accounts()
    service.spawn { name = "collector", source = "@services/ctp_collector.lua", config = { 
            server = accounts["collector"]["gtja-3"],
        } }

    --[[
    service.call("collector", "start")
    service.call("collector", "subscribe", "lh2703")
    service.call("collector", "stop")


    scheduler:at(os.time() + 5, function()
            service.send("collector", "stop")
        end)
    ]]

    local now = os.time()
    print(os.date("%Y-%m-%d %H:%M:%S %z %Z", now))
    print("isdst:", tostring(os.date("*t", now).isdst))

    scheduler:at(os.time() + 5, function()
            print("scheduler:at ", os.date("%Y-%m-%d %H:%M:%S") )
        end)
    scheduler:daily("13:19:00", function()
            print("scheduler:daily")
            service.send("collector", "start")
        end)

    -- scheduler:at("2026-08-27 12:55:00", function()
            -- service.call("collector", "start")
        -- end)
end

local function boot()
    local symbol  = "IM2703"
    local accounts = load_accounts()

    ctp.log_debug("booting root")
    service.spawn { name = "collector", source = "@services/ctp_collector.lua", config = { 
            -- server = accounts["collector"]["openctp-7x24"],
            server = accounts["collector"]["gtja-3"],
            auto_disconnect = true, -- 在指定时间自动连接，释放
            -- server = accounts["collector"]["hy"],
            -- symbol = symbol
        } }

    service.call("collector", "start")
    service.call("collector", "subscribe", "sc2609")

    service.spawn { name = "trader", source = "@services/ctp_trader.lua", config = {
            -- server = accounts["trader"]["gtja-sim"],
            -- server = accounts["trader"]["gtja-3"],
            server = accounts["trader"]["hy"],
            -- server = accounts["trader"]["openctp-7x24"],
            -- symbol = symbol
        } }
    local rsp = service.call("trader", "start") -- blocking, until trader starts

    --[[
    do 
        local rst = service.call("trader", "query_account")
        ctp.log_info("query_account: %s", inspect(rst))
        local rst = service.call("trader", "query_instrument", "IM2703")
        ctp.log_info("query_instrument: %s", inspect(rst))
        local rst = service.call("trader", "query_position")
        ctp.log_info("query_position: %s", inspect(rst))
    end
    ]]

    -- service.call("trader", "quit")

    -- service.spawn { name = "bot", source = "@services/bot.lua", config = { } }

    service.spawn { name = "gateway", source = "@services/gateway.lua", config = { } }

    service.spawn { name = "book", source = "@services/book.lua", config = { } }
    service.call("book", "init")
end

local S = {}

function S.boot()
    boot_test_collector()
    -- service.send(0, "quit")
end

function S.quit()
    ctp.log_debug("root is quiting")
    service.send("collector", "quit")
    service.send("trader", "quit")
    service.quit()
end

return service.dispatch(S)