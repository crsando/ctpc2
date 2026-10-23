local service = require "service"
local root = require "service.root"

local accounts = require "lctp2.accounts"

local inspect = require "inspect"

local ffi = require("ffi")

-- redirect stderr to /dev/null to avoid printing error messages from C libraries
do 
    ffi.cdef[[
      void* freopen(const char *filename, const char *mode, void *stream);
      extern void *stderr;
    ]]

    -- 重定向整个进程的 stderr 到 /dev/null
    local ok = ffi.C.freopen("/dev/null", "w", ffi.C.stderr)
    assert(ok ~= nil, "freopen failed")
end

function root.boot(...)
    local server; do 
        local profile_name  = select(1, ...)
        server = accounts["trader"][profile_name]
    end

    if not server then 
        print("no server given")
    else 
        service.call(0, "run", server)
    end

    service.quit()
end

function root.run(server)
    service.spawn { 
        name = "trader", 
        source = [[return require "lctp2.templates.ctp_trader"]], 
        config = { server = server } 
    }

    service.call("trader", "start") -- blocking, until trader starts
    
    local position = service.call("trader", "query_position")
    print(inspect(position))

    service.call("trader", "quit")
end 

return root
