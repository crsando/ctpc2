local service = require "service"
local root = require "service.root"

local accounts = require "lctp2.accounts"

local inspect = require "inspect"

function root.boot()

    service.spawn { 
        name = "trader", 
        source = [[return require "lctp2.templates.ctp_trader"]], 
        config = { server = accounts["trader"]["gtja-3"] } 
    }

    service.call("trader", "start") -- blocking, until trader starts
    
    local position = service.call("trader", "query_position")
    print(inspect(position))

    service.call("trader", "quit")
    service.quit()
end 

return root
