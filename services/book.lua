--[[

*Everything in the Book*

这个service保存的是所有重要的公共的，持久化的，外部的数据

- 期货代码列表 book.instrument

]]
local inspect = require "inspect"
local ctp = require "lctp2"
local cjson = require "cjson.safe"
ctp.log_set_level("LOG_DEBUG")

local service = require "lservice3" .input(...)
local config = service.config; do 
        local PREFIX = os.getenv("HOME")
        config.data_dir = assert(config.data_dir or (PREFIX .. "/.local/share/tifa"))
        config.cache_dir = assert(config.cache_dir or (PREFIX .. "/.cache/tifa"))
    end

local S = {}

-- aka. service.uv
local uv = require "luv"

--
-- cached tables
--

local book = {
    instrument = {},
}

--
-- internal functions
--

local function init_instrument()
    local function exam_and_load(path)
        local stat = assert(uv.fs_stat(path))
        if stat then
            -- 我们判断一下是不是今天的缓存
            -- luv 的 mtime 通常是 { sec = ..., nsec = ... }
            local mtime = type(stat.mtime) == "table"
                and stat.mtime.sec
                or stat.mtime
            local modified = os.date("*t", mtime)
            local today = os.date("*t")
            -- 对于今天的缓存，直接读取
            if (modified.year == today.year) and (modified.yday == today.yday) then
                local file = assert(io.open(path, "r"))
                local content = file:read("*a")
                file:close()

                -- load json
                ctp.log_debug("load book.instrument from cache file")
                book.instrument = cjson.decode(content)
                return true
            end
        end
        return nil
    end

    local path = config.cache_dir .. "/instrument.json"
    local ok, rst = pcall(exam_and_load, path)

    -- 有错误或者是未能加载成功，则重新处理
    if (not ok) or (not rst) then 
        ctp.log_debug("instrument: load from ctp_trader")
        book.instrument = {}; do 
            local T = service.call("trader", "query_instrument")
            for _, entry in ipairs(T) do
                local symbol = entry.InstrumentID
                book.instrument[symbol] = entry
            end
        end -- end init book.instrument
        
        -- save to cache file
        ctp.log_debug("instrument: write to file")
        do 
            local file = assert(io.open(path, "w"))
            file:write(cjson.encode(book.instrument))
            file:close()
        end
    end

    return book.instrument
end

-- 
-- 临时方案，我们启动一个外部进程来在非交易时间获取数据
--
local function run_akquote(symbol)
    local co = service.get_session()

    -- 1. 创建用于 stdout 重定向的管道
    local stdout_pipe = uv.new_pipe(false)


    assert(symbol and (type(symbol)=="string"))
    local cmd = string.format("akquote.lua %s", symbol)

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

function S.init()
    init_instrument()
    return true
end

function S.instrument(symbol)
    if not book.instrument then 
        service.call(service.get_id(), "init_instrument")
    end
    assert(book.instrument)
    return book.instrument[symbol]
end


return service.dispatch(S)