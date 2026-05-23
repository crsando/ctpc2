local ctp = require "lctp2"
local inspect = require "inspect"

-- local server = {
--             front_addr = "tcp://101.230.79.235:33205",
--             broker = "3070", 
--             user = "333307126", 
--             pass = "930706", 
--             app_id = "client_tara_241201", 
--             auth_code = 'CY2LFL92CISEEKVM',
--         }

-- local server = {
--             front_addr = "tcp://180.169.50.131:42205",
--             broker = "2071", 
--             user = "0061831885", 
--             pass = "zhy19930311", 
--             app_id = "client_tara_231031", 
--             auth_code = '20231101ZHOUYH01',
-- }

local server = {
            front_addr = "tcp://trading.openctp.cn:30001",
            broker = "9999", 
            user = "7572", 
            pass = "123456", 
            app_id = "client_tara_231031", 
            auth_code = '20231101ZHOUYH01',
}

local trader = ctp.new_trader(server):start(true)

-- trader:query_account()
trader:query_instrument("IF2607")

while true do 
    local rsp = trader:recv(true)
    print(inspect(rsp))
end

os.exit(1)