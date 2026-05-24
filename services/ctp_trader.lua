local inspect = require "inspect"
local service = require "lservice2" .input(...)
local config = service.config

assert(config.account)

local ctp = require "lctp2"
local ffi = ctp.ffi
ctp.log_set_level("LOG_DEBUG")

local function slice(t, k)
    local o = {}
    for i, e in ipairs(t) do 
        o[i] = e[k]
    end
    return o
end

--
-- internal procedure management
--
local R = {} -- handle trader response
local S = {} -- handle service request/response

--
-- global(per-service) variables
--
local server, trader; S.start = function ()  
    server = config.account
    assert(server)
    print("trader account", inspect(server))

    trader = ctp.new_trader(server)
        :cond( service.get_cond() )
        :start( true ) -- blocking thread until settlement
    return true
end

--
-- warp query request/response
-- hard rule: one query at a time, a queue is used to ensure this
--
local query = {
    start_index = 1,
    last_index = 0,
    max_length = 100,
    
    reorder = function(self)
            local s, e = self.start_index, self.last_index
            local n = self.last_index - self.start_index + 1

            local i = 1 
            while i <= n do 
                local tmp = self[self.start_index + i - 1]
                self[self.start_index + i - 1] = nil
                self[i] = tmp
            end

            self.start_index = 1 
            self.last_index = n
        end,

    -- entry point
    request = function(self, name, ...)
            local entity = {
                    session = service.get_session(),
                    req_id = nil,
                    name = name,
                    body = {...},
                    cache = {},
                }

            self:enqueue(entity)
            self:process()

            local ok, rst = coroutine.yield() -- wait for response
            return ok, rst
        end,
    -- exit point
    response = function(self)
            local q = self:first()
            if q then 
                if q.session then 
                    service.resume_session(q.session, 1, q.cache)
                end
                self:dequeue()
            end
        end,

    enqueue = function(self, entity)
            -- check
            if self.start_index == 1 and self.last_index >= self.max_length then 
                return 0, "too many queries"
            end 

            if self.last_index >= self.max_length then 
                self:reorder()
            end

            -- enqueue first, then process on idle
            do 
                self.last_index = self.last_index + 1
                self[self.last_index] = entity
                -- print("query enqueued at", self.last_index, inspect(self[self.last_index]))
            end
        end,
    dequeue = function(self)
            self[self.start_index] = nil 
            self.start_index = self.start_index + 1
        end,
    first = function(self)
            if self.last_index >= self.start_index then 
                return self[self.start_index]
            else 
                return nil
            end
        end,

    -- send the real ctp request/query by trader
    process = function(self)
            local q = self:first()
            if q and (not q.req_id) then 
                local f = trader[q.name]

                if not f then 
                    return 0, "no matched query name"
                end

                local req_id = f(trader, unpack(q.body))
                q.req_id = req_id

                return 1 -- did something
            else 
                return 0 -- did nothing
            end
        end,

    update = function (self, rsp)
            local q = self:first()

            if not q then return end

            -- check request id for a match, ignore if not matched
            if not ( q.req_id == rsp.req_id ) then 
                io.stderr:write("req_id not match, ignore reponse | req_id : " .. rsp.req_id)
                return 
            end

            -- cache rst
            do 
                q.cache[#(q.cache) + 1] = rsp
            end

            -- finish query
            if rsp.is_last == true then 
                self:response()
                self:process() -- process next request
            end
        end,
} -- end query object definitions




--
-- query interfaces
--

function S.query_account()
    local ok, rst = query:request("query_account")
    print("query account: ", ok, inspect(rst))
    return rst[1]
end

--[[
/////////////////////////////////////////////////////////////////////////
///TFtdcPosiDirectionType是一个持仓多空方向类型
/////////////////////////////////////////////////////////////////////////
///净
#define THOST_FTDC_PD_Net '1'
///多头
#define THOST_FTDC_PD_Long '2'
///空头
#define THOST_FTDC_PD_Short '3'
]]
function S.query_position()
    local ok, rst = query:request("query_position")

    local pt = {}
    for _, field in ipairs(rst) do 
        if (field ~= nil) and (field.InstrumentID) then 
            local symbol = field.InstrumentID
            pt[symbol] = pt[symbol] or {}
            entry = pt[symbol]
            direction = field.PosiDirection - 49 -- an hack
            entry[direction] = (entry[direction] or 0) + field.Position

            print(symbol, direction, field.Position)
        end
    end

    position_table = pt -- update global variable

    -- return slice(T,"field")
    return position_table
end

function S.query_instrument(symbol)
    local ok, rst = query:request("query_instrument", symbol)
    print("query instrument", ok, inspect(rst))


    if rst[1] and type(rst[1] == "table") then 
        return rst[1]
    else 
        return {}
    end
end

function S.query_order()
    local ok, rst = query:request("query_order")
    return rst
end


function S.quit()
    print("trader is quitting")
    service.call(0, "notify", service.get_id(), "quit")
    service.quit()
end

-- main loop
-- process trader internal messages
function service.on_idle()
    while true do 
        local rsp = trader:recv(false) -- non-blocking
        if rsp then 
            -- process trader messages
            local handler = R[rsp.func_name] 
                                or function (rsp) query:update(rsp) end 
            handler( rsp )
        else 
            return 
        end
    end -- end while
end

service.dispatch(S)