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
        local rsp = trader:recv(false) -- non-blocking
        if rsp ~= nil then 
            local func_name = ffi.string(rsp.func_name)
            local handler = S[func_name] or S.OnRsp

            -- print("process message", rsp.req_id, func_name, rsp.is_last)

            if handler then 
                handler {
                    req_id = tonumber(rsp.req_id),
                    field = ffi.cast( "struct " .. ffi.string(rsp.field_name) .. "*", rsp.field),
                    field_name = ffi.string(rsp.field_name),
                    func_name = ffi.string(rsp.func_name),
                    is_last = rsp.is_last,
                }
            end
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

local function wait_request(req_id)
    R[req_id] = {} -- store results
    local T = R[req_id]
    local job = coroutine.create(function() 
            while true do
                local is_last = (T[#T] or {}).is_last or false
                print("wait request", #T, is_last)
                if is_last then break end
                coroutine.resume(process_message)
                coroutine.yield()
            end
        end)
    while coroutine.resume(job) do 
        -- do nothing
    end
    return T
end


local rst = wait_request(trader:query_instrument("SHFE"))
local futures = {}

do
    for i, entry in ipairs(rst) do 
        print(inspect(entry))
        print(entry.func_name, entry.field_name)
        local field = entry.field
        local c = { 
                symbol = ffi.string(field.InstrumentID),
                exchange_id = ffi.string(field.ExchangeID),
                product = ffi.string(field.ProductID),
                expire_date = ffi.string(field.ExpireDate),
            }
        futures[i] = c
    end
end

trader:logout()

print(inspect(futures))

-- while true do 
--     coroutine.resume(process_message)
-- end

print("task over, exit")