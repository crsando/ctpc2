local service = require "service"
local root = require "service.root"

local accounts = require "lctp2.accounts"

local inspect = require "inspect"

function root.boot(...)
    local server; do 
        local profile_name  = select(1, ...) or "gjta-3"
        server = accounts["trader"][profile_name]
    end

    print(inspect {...})

    service.spawn { 
        name = "trader", 
        source = [[return require "lctp2.templates.ctp_trader"]], 
        config = { server = server } 
    }

    service.call("trader", "start") -- blocking, until trader starts
    
    local position = service.call("trader", "query_position")
    print(inspect(position))

    service.call("trader", "quit")
    service.quit()
end 

return root
