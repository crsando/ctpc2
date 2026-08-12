local inspect = require "inspect"
local ctp = require "lctp2"

local service = require "lservice3" .input(...)
local config = service.config; do 
        -- do nothing
    end

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
        local peer = conn:peername()
        print("connected", conn.id, peer and peer.ip, peer and peer.port)
    end,

    on_message = function(conn, message)
        ctp.log_debug("on_tcp_message | from : %s | message: %s", inspect(conn:peername(), {newline=""}), inspect(message, {newline=""}))
        service.send(service.get_id(), "on_tcp_json_msg", conn:peername(), message)
    end,

    on_error = function(target, err)
        ctp.log_debug("tcp error : %s | %s", err.code, err.message)
    end,

    on_close = function(conn, reason)
        ctp.log_debug("tcp conn closed : %s | %s", conn.id, reason and reason.code)
    end,
})

assert(server:listen("0.0.0.0", 8431))

function S.on_tcp_json_msg(peer, msg)
    ctp.log_debug("on_tcp_message | from : %s | message: %s", inspect(peer, {newline=""}), inspect(msg, {newline=""}))
end


return service.dispatch(S)