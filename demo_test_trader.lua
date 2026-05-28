local inspect = require "inspect"
local service = require "lservice3"

local script_name = arg[1] or "root_test_trader"

local root_addr = service.new { 
    source = "@services/" .. script_name .. ".lua", 
    config = { 
        symbol = "IF2607",
    } 
}

service.start(root_addr)
service.send(service.get_id(root_addr), "boot")
service.join(root_addr)