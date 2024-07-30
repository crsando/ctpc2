local ffi = require "ffi"
local inspect = require "inspect"


--
-- ctpc api using FFI
--
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

local fn_type = include_path .. "/ctpc2/ThostFtdcUserApiDataType.h"
local fn_struct = include_path .. "/ctpc2/ThostFtdcUserApiStruct.h"

ffi_load_header_file(fn_type)
ffi_load_header_file(fn_struct)
ffi_load_header_file(include_path .. "/ctpc2/position.h") -- place this line above ctpc.h
ffi_load_header_file(include_path .. "/ctpc2/ctpc2.h")
ffi_load_header_file(include_path .. "/ctpc2/util.h")

ffi.cdef[[
    enum { LOG_TRACE, LOG_DEBUG, LOG_INFO, LOG_WARN, LOG_ERROR, LOG_FATAL };
    void log_set_level(int level);

    void free(void *p);
]]

local ctpc = ffi.load("ctpc2")


--
-- parse C header files 
--
local datatypes, constants, structs = require "lctp2.parse" ( fn_type, fn_struct )

--

-- set log level
function log_set_level(lvl_str)
    local lvl = ffi.C[lvl_str]
    lvl = lvl or ffi.C.LOG_INFO
    ctpc.log_set_level(lvl)
end

-- configurations

local servers = {
    md = {
        ["sim"] = { front_addr =  'tcp://121.37.80.177:20004', broker = "7090", user = "7572" },
        ["openctp"] = { front_addr =  'tcp://121.37.80.177:20004', broker = "7090", user = "7572" },
        ["gtja-1"] = { front_addr =  "tcp://180.169.75.18:61213", broker = "7090", user = "85194065" }
    },
    trader = {
        ["openctp-7x24"] = {
            front_addr = "tcp://121.37.80.177:20002", 
            broker = "7090", 
            user = "7572", 
            pass = "123456", 
            app_id = "client_tara_060315", 
            auth_code = "20221011TARA000",
        },
        ["openctp"] = {
            front_addr = "tcp://121.37.90.193:20002", 
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
        hook = function (self, hook)
                ctpc.ctp_md_hook(self.md, hook)
                return self
            end,
        cond = function(self, cond)
                self.md.ext_cond = ffi.new("void*", cond)
                print("setting cond", cond, self.md.ext_cond)
                return self
            end,
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
                -- return ffi.gc(ctpc.ctp_md_recv(self.md), ctpc.ctp_md_tick_free)
                return ctpc.ctp_md_recv(self.md)
            end,
    }
    _mt.__index = _mt
    local collector = { md = md }
    setmetatable(collector, _mt)

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
        start = function(self, wait)  
                ctpc.ctp_trader_start(self.trader)
                if wait then
                    ctpc.ctp_trader_wait_for_settle(self.trader)
                end
                return self
            end,

        cond = function(self, cond)
                self.trader.ext_cond = ffi.new("void*", cond)
                print("setting cond", cond, self.trader.ext_cond)
                return self
            end,

        logout = function(self)
                ctpc.ctp_trader_logout(self.trader)
                return self
            end,
        -- is_ready = function(self) return (self.trader.connected >= 4) end,

        recv = function (self, blocking)
                -- raw receive
                return ctpc.ctp_trader_recv(self.trader, blocking)
            end,
        
        fetch = function (self, blocking)
                local rsp = ffi.gc(ctpc.ctp_trader_recv(self.trader, blocking), ctpc.ctp_rsp_free) 
                if rsp.desc == "error" then 
                    return nil, rsp
                else
                    local ptr_type = "struct " .. ffi.string(rsp.desc) .. " * "
                    local ptr = assert(ffi.cast(ptr_type, rsp.field))
                    if ptr ~= nil then 
                        ffi.gc(ptr, ffi.C.free)
                    end
                    return ptr, rsp
                end
            end,
        
        query_account = function(self) return ctpc.ctp_trader_query_account(self.trader) end,
        query_position = function(self) return ctpc.ctp_trader_query_position(self.trader) end,

        query_instrument = function(self, exchange_id) return ctpc.ctp_trader_query_instrument(self.trader, exchange_id) end,
        -- query_marketdata = function(self, symbol) return ctpc.ctp_trader_query_marketdata(self.trader, symbol) end,
        -- fetch_account = function(self, req_id) return ctpc.ctp_trader_fetch_account(self.trader, req_id) end,
    }

    local T = { trader = trader }
    setmetatable(T, { __index = _mt } )
    return T
end

function position_keeper(ptr)
    local o = {}
    if ptr ~= nil then 
        o.core = ffi.cast("ctp_position_keeper_t *", ptr)
    else 
        o.core = ctpc.ctp_position_keeper_new()
    end
    local _mt = {
        update = function (self, rsp)
                assert(self.core)
                if rsp == nil then return nil, "empty response message" end 
                local pos = ffi.new("struct CThostFtdcInvestorPositionField *", rsp.field)
                ctpc.ctp_position_keeper_update(self.core, pos, rsp.last)
                return (rsp.last == 1)
            end,
        localcopy = function (self)
                local pos = ctpc.ctp_position_keeper_localcopy(self.core)
                ffi.gc(pos, ctpc.ctp_position_free)
                self._localcopy = pos
                return pos
            end,
        table = function (self)
                self:localcopy() -- this will update self._localcopy
                local p = self._localcopy
                local T = {}
                while p ~= nil do 
                    local symbol = ffi.string(p.field.InstrumentID)
                    local num = p.field.Position
                    local direction = (p.field.PosiDirection == 50) and "long" or "short"
                    T[#T+1] = { symbol = symbol, direction = direction, num = num, }
                    p = p.nxt
                end
                return T
            end,
    }
    _mt.__index = _mt
    setmetatable(o, _mt)
    return o
end

local function check_struct(cdata, struct_name)
    local rst = string.match(tostring(ffi.typeof(cdata)), "struct ([%w_]+)")
    if rst then 
        if struct_name then 
            return (rst == struct_name) and rst or nil
        else 
            return rst 
        end
    end 
    return rst
end

-- finish module loading
local function totable(cdata)
    -- todo
    -- local field_name = string.match(tostring(ffi.typeof(cdata)), "struct ([%w_]+)")
    local field_name = assert(check_struct(cdata), "cdata is not a struct")

    local s = structs[field_name] 
    if not s then return nil end

    -- if matched
    local o = {}
    for attr, type in pairs(s) do 
        -- io.stderr:write("totable", field_name, attr, type, datatypes[type], cdata[attr], "\n")
        if not datatypes[type] then 
            o[attr] = nil
        elseif datatypes[type] == "string" then
            o[attr] = ffi.string(cdata[attr])
        else -- int, short, char
            o[attr] = tonumber(cdata[attr])
        end
    end -- end for
    return o
end

local M = {
    new_collector = new_collector,
    new_trader = new_trader,
    servers = servers,
    ffi = ffi,
    ctpc = ctpc,

    check_struct = check_struct,
    totable = totable,

    log_set_level = log_set_level,

    position_keeper = position_keeper,
}

-- load constants directly to the module
for k, v in pairs(constants) do 
    M[k] = v 
end

M.order_book = require "lctp2.order_book"

return M