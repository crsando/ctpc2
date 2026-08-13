local inspect = require "inspect"
local ctp = require "lctp2"
local cjson = require "cjson.safe"
ctp.log_set_level("LOG_DEBUG")

local service = require "lservice3" .input(...)
local config = service.config; do 
        -- do nothing
    end

local S = {}

local uv = require "luv"

local function run_akquote(symbol)
    local co = service.get_session()

    -- 1. 创建用于 stdout 重定向的管道
    local stdout_pipe = uv.new_pipe(false)


    assert(symbol and (type(symbol)=="string"))
    local cmd = string.format("akquote %s", symbol)

    -- 我们需要包装成bash去运行，来解决一些环境变量的问题
    local options = {
        args = {"-c", cmd},
        stdio = {nil, stdout_pipe, nil} -- 重定向 stdout
    }

    local child
    -- 2. 启动子进程
    child, _ = uv.spawn("bash", options, function(code, signal)
            -- 3. 进程退出后，务必关闭 child 句柄
            if child and not uv.is_closing(child) then
                uv.close(child)
            end
        end)

    if not child then
        ctp.log_debug("book.lua: Failed to spawn process")
        return nil
    end

    -- 4. 异步读取 stdout 数据
    local rst = ""; do 
        local _t = {}
        uv.read_start(stdout_pipe, function(err, chunk)
            assert(not err, err)
            if chunk then
                table.insert(_t, chunk)
            else
                if not uv.is_closing(stdout_pipe) then
                    uv.close(stdout_pipe)
                end
                service.resume_session(co, table.concat(_t, ""))
            end
        end)

        rst = service.yield_session()
    end

    -- decode json
    local data, err = cjson.decode(rst)
    if not data then 
        ctp.log_debug("error in resolving akquote return value")
    end

    return data
end

function S.quote(symbol) 
    local data =  run_akquote(symbol)
    return data.price
end


return service.dispatch(S)