-- jit.off(true, true)

local ctp = require "lctp2"
local ffi = ctp.ffi
local uv = require "luv"

-- ctp.log_set_level("LOG_ERROR")
ctp.log_set_level("LOG_DEBUG")

local server = {
            front_addr = "tcp://101.230.79.235:33205",
            broker = "3070", 
            user = "333307126", 
            pass = "930706", 
            app_id = "client_tara_241201", 
            auth_code = 'CY2LFL92CISEEKVM',
        }

-- prompt
if not server.pass then 
    io.write("user: ", server.user, "\n")
    io.write("password: ")
    server.pass = io.read("*line")
end

local trader = ctp.new_trader(server):start()

-- trader:query_account()

uv.sleep(1000)

trader:order_insert("IF2501", 0, 1, ctp.THOST_FTDC_OFEN_Open)

while true do 
    -- update_position_info()
    uv.sleep(1000)    
end

os.exit(1)