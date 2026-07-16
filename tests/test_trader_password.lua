local ctp = require "lctp2"
local inspect = require "inspect"

-- local server = {
--             front_addr = "tcp://114.94.128.1:42205",
--             broker = "2071", 
--             user = "0061841498", 
--             pass = "bE19930706", 
--             app_id = "client_tifa_260501", 
--             auth_code = '20260527TIFATIFA',
--         }

local server = {
            front_addr = "tcp://101.230.79.235:32205",
            broker = "3070", 
            user = "333307126", 
            pass = "essential", 
            app_id = "client_tara_241201", 
            auth_code = 'CY2LFL92CISEEKVM',
        }

local trader = ctp.new_trader(server):start(true)

-- trader:query_account()
-- trader:query_instrument("IF2609")

trader:password_update("essential", "essential@07")

while true do 
    local rsp = trader:recv(true)
    print(inspect(rsp))
end

os.exit(1)