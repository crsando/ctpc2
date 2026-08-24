local inspect = require "inspect"
local ctp = require "lctp2"

local service = require "lservice3" .input(...)
local config = service.config; do 
        -- do nothing
    end

local HOST = "0.0.0.0"
local PORT = 8431

local clients= {}

local S = {}

--[[
    这里用了自己vibe coding的库luvtcp来实现网络连接功能
    通讯协议是length-prefix json

    链路是 on_connection -> S.on_tcp_json_msg(session) -> call XXX -> ...
]]
local uv = require "luv"
local tcp = require("luvtcp")

local server = assert(tcp.create_server {
    protocol = tcp.protocol.length_prefixed_json(),

    on_connection = function(server, conn)
        -- register
        clients[conn.id] = conn

        -- route to message loop
        service.send(service.get_id(), "on_client", conn and conn.id)
    end,

    on_message = function(conn, message)
        -- 转发到一个coroutine(session)中去处理
        if message and (message.type == "request") then 
            service.send(service.get_id(), "on_prompt", conn.id, message.prompt)
        end
    end,

    on_error = function(target, err)
        ctp.log_debug("tcp error : %s | %s", err.code, err.message)
    end,

    on_close = function(conn, reason)
        clients[conn.id] = nil
        ctp.log_debug("tcp conn closed : %s | %s", conn.id, reason and reason.code)
    end,
})

assert(server:listen(HOST, PORT))

local CMD = {}

function CMD.debug(rsp, ...)
    -- 这是一个特殊的用于给ctp_trader测试用的
    ctp.log_debug("on_prompt | debug | %s", table.concat({...}, " "))
    local rst = service.call(...)
    rsp(inspect(rst))
end

function CMD.shutdown(rsp, ...)
    local rst = service.call("root", "quit")
    rsp(rst)
end

function CMD.account(rsp, ...)
    local act = service.call("trader", "query_account")
    local keys = { "BrokerID", "AccountID", "Balance", "Available", "PositionProfit" }

    local str = ""

    for _, k in ipairs(keys) do 
        str = str .. string.format("Account %s : %f\n", k, act[k] or 0.0)
    end

    rsp(str)
end

function CMD.position(rsp, ...)
    local pos = service.call("trader", "query_position")

    local lines = {}
    for _, entry in ipairs(pos) do 
        local direction; do 
            if entry.PosiDirection == ctp.THOST_FTDC_PD_Long then
                direction = '+'
            else 
                direction = '-'
            end
        end -- end direction

        local info = service.call("trader", "query_instrument", entry.InstrumentID)
        local quote = service.call("book", "quote", entry.InstrumentID) -- get last price

        table.insert(lines, string.format( "%s | %s | %d | %d | %f | %f",
            entry.InstrumentID,
            direction,
            entry.Position,
            (info and info.VolumeMultiple or 0),
            quote,
            entry.Position * (info and info.VolumeMultiple or 0) * quote -- Nominal Value
        ))

    end

    rsp(table.concat(lines, "\n"))
end

-- 每次有新的tui连接的时候，触发这里
function S.on_client(conn_id)
    local conn = assert(clients[conn_id])
    local peer = conn:peername()
    conn:send {
        text = string.format("server connected | %d | %s | %s", conn.id, peer and peer.ip, peer and peer.port)
    }
end

function S.on_prompt(conn_id, prompt)
    assert(prompt and (type(prompt) == "string"))

    local conn = clients[conn_id]
    
    -- 简单直接的用空格分割
    local cmd, args = nil, {}; do
        for _word in string.gmatch(prompt, "%S+") do
            if not cmd then 
                cmd = _word 
            else 
                table.insert(args, _word)
            end
        end
    end -- end init cmd, args

    ctp.log_debug("on_prompt : %s", cmd)
    
    local rsp = function (...)
            conn:send {
                type = "response", 
                text = string.format(...)
            }
        end

    local cmd_not_found = function (rsp) rsp("command not found") end

    -- run command
    local ok, rst = xpcall(CMD[cmd] or cmd_not_found, debug.traceback, rsp, unpack(args))
end

return service.dispatch(S)