local service = require "service"

service.bootstrap {
    source = "@entry.lua",
    config = { profile = arg[1] },
}
