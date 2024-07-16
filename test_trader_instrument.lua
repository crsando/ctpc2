-- jit.off(true, true)

local inspect = require "inspect"

local ctp = require "lctp2"
local ffi = ctp.ffi

-- ctp.log_set_level("LOG_ERROR")
-- ctp.log_set_level("LOG_INFO")
ctp.log_set_level("LOG_DEBUG")

local server = ctp.servers.trader["openctp-7x24"] 

-- prompt
if not server.pass then 
    io.write("user: ", server.user, "\n")
    io.write("password: ")
    server.pass = io.read("*line")
end

local trader = ctp.new_trader(server):start()
local R = {}
local S = {}

print("---")
print "testing start"
print("---")


function S.OnRsp(rsp)
    local req_id = tonumber(rsp.req_id)
    if not req_id then return nil end
    local T = R[req_id]

    if T then 
        T[#T+1] = rsp
    end
end


local process_message = coroutine.create(function ()
    local default_handler = S.OnRsp
    while true do 
        local rsp = trader:recv()
        local field = ffi.cast( "struct " .. ffi.string(rsp.field_name) .. "*", rsp.field)
        local func_name = ffi.string(rsp.func_name)
        local handler = S[func_name] or S.OnRsp

        print("process message", rsp.req_id, func_name, rsp.is_last)

        if handler then 
            print("handler", func_name)
            handler(rsp)
        end

        coroutine.yield()
    end
end)

local function wrap_query(req_id) 
    R[req_id] = {} -- store results
    local T = R[req_id]
    while true do
        assert(coroutine.resume(process_message))
        local is_last = (T[#T] or {}).is_last or false
        if is_last then break end
        coroutine.yield()
    end
    return T
end

local get_futures_list = coroutine.create(function()
    local futures = wrap_query(trader:query_instrument())
    local res = {}

    for i, entry in ipairs(futures) do 
        local field = entry.field
        local c = { 
                symbol = ffi.string(field.InstrumentID),
                exchange_id = ffi.string(field.ExchangeID),
                product = ffi.string(field.ProductID),
                expire_date = ffi.string(field.ExpireDate),
            }
        res[i] = c
    end

    return res
end)

while coroutine.resume(get_futures_list) do 
end

print("task over, exit")

os.exit(0)

--[[
while true do 
    local rsp = trader:recv()
    local field = ffi.cast( "struct " .. ffi.string(rsp.field_name) .. "*", rsp.field)

    if tonumber(field.ProductClass) == 49 then -- Futures
        local c = { 
                symbol = ffi.string(field.InstrumentID),
                exchange_id = ffi.string(field.ExchangeID),
                product = ffi.string(field.ProductID),
                expire_date = ffi.string(field.ExpireDate),
            }

        print("future", inspect(c))
        futures[#futures + 1] = c
    end

    if rsp.last == 1 then 
        break 
    end
end
]]