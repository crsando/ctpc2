local ffi = require "ffi"

-- wechat robot 

local ctp_ver = "ctp-6.6.9"
local prefix = "/usr/local"
local include_path = prefix .. "/include"

function ffi_load_header_file(fn)
    local content = io.open(fn):read("*a")
    local txt = content .. "\n"
    local txt = string.gsub(txt, "%#define(.-)\n", "")
    local txt = string.gsub(txt, "%#if(.-)\n", "")
    local txt = string.gsub(txt, "%#end(.-)\n", "")
    local txt = string.gsub(txt, "%#include(.-)\n", "")
    ffi.cdef(txt)
end

-- ffi_load_header_file(ctp_ver .. "/ThostFtdcUserApiDataType.h")
-- ffi_load_header_file(ctp_ver .. "/ThostFtdcUserApiStruct.h")
-- ffi_load_header_file("src/position.h") -- place this line above ctpc.h
-- ffi_load_header_file("src/ctpc.h")
-- ffi_load_header_file("src/util.h")

ffi_load_header_file(include_path .. "/ctpc2/ThostFtdcUserApiDataType.h")
ffi_load_header_file(include_path .. "/ctpc2/ThostFtdcUserApiStruct.h")
ffi_load_header_file(include_path .. "/ctpc2/position.h") -- place this line above ctpc.h
ffi_load_header_file(include_path .. "/ctpc2/ctpc2.h")
ffi_load_header_file(include_path .. "/ctpc2/util.h")

ffi.cdef[[
    ctp_reg_t * ctp_reg_get(ctp_reg_t ** reg, int req_id);
    ctp_reg_t * ctp_reg_put(ctp_reg_t ** reg, int req_id, void * data, size_t size);
    ctp_reg_t * ctp_reg_del(ctp_reg_t ** reg, int req_id);
]]


local ctpc = ffi.load("ctpc2")

-- configurations

local servers = {
    md = {
        ["sim"] = { front_addr =  'tcp://121.37.80.177:20004', broker = "7090", user = "7572" },
        ["openctp"] = { front_addr =  'tcp://121.37.80.177:20004', broker = "7090", user = "7572" },
        ["gtja-1"] = { front_addr =  "tcp://180.169.75.18:61213", broker = "7090", user = "85194065" }
    },
    trader = {
        ["openctp"] = {
            front_addr = "tcp://121.37.80.177:20002", 
            broker = "7090", 
            user = "7572", 
            pass = "123456", 
            app_id = "client_tara_060315", 
            auth_code = "20221011TARA000",
        }
    }
}


-- function new_collector(server, symbols, on_tick)
function new_collector(server)
    server = server or servers.md['sim']

    local md = ctpc.ctp_md_new()
    ctpc.ctp_md_init(md, server.front_addr, server.broker, server.user)

    local _mt = {
        subscribe = function (self, symbols) 
                for _, symbol in ipairs(symbols) do 
                    ctpc.ctp_md_subscribe(self.md, symbol) 
                end
                return self
            end,
        start = function (self) 
                ctpc.ctp_md_start(self.md)
                return self 
            end,
        recv = function (self)
                return ffi.gc(ctpc.ctp_md_recv(self.md), ctpc.ctp_md_tick_free)
            end,
    }
    local collector = { md = md }
    setmetatable(collector, { __index = _mt } )

    return collector
end

function new_trader(server)
    -- local trader = ctpc.ctp_trader_init(nil, "tcp://121.37.80.177:20002", "7090", "7572", "123456", "client_tara_060315", "20221011TARA000");
    local trader = ctpc.ctp_trader_new()
    ctpc.ctp_trader_init(trader, server.front_addr, 
        server.broker,
        server.user,
        server.pass,
        server.app_id,
        server.auth_code
    )
    local _mt = {
        start = function(self)  
                ctpc.ctp_trader_start(self.trader)
                ctpc.ctp_trader_wait_for_settle(self.trader)
                return self
            end,
        -- is_ready = function(self) return (self.trader.connected >= 4) end,
        recv = function (self)
                return ffi.gc(ctpc.ctp_trader_recv(self.trader), ctpc.ctp_rsp_free)
            end,
        
        query_account = function(self) return ctpc.ctp_trader_query_account(self.trader) end,
        -- fetch_account = function(self, req_id) return ctpc.ctp_trader_fetch_account(self.trader, req_id) end,
    }

    local T = { trader = trader }
    setmetatable(T, { __index = _mt } )
    return T
end

return {
    new_collector = new_collector,
    new_trader = new_trader,
    servers = servers,
    ffi = ffi,
    ctpc = ctpc,
}