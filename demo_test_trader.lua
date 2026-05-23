local inspect = require "inspect"
local service = require "lservice2"

local root_id = service.spawn { 
    source = "@tests/root_trader.lua", 
    config = { 
        symbol = "IF2607",
    } 
}

service.send(root_id, "boot")


local uv = require "luv"
uv.new_signal():start("sigint", function(signal)
        print("on sigint, exit")
        uv.walk(function (handle) if not handle:is_closing() then handle:close() end end)
        os.exit(1)
    end)

uv.run()