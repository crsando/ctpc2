local inspect = require "inspect"
local service = require "lservice3"


--
-- 从 ~/.tifa/accounts.lua 中读取服务器列表信息（包含用户名和密码）
--
local function load_accounts()
    -- 获取家目录路径（兼容 Windows 和 Linux/macOS）
    local home = os.getenv("HOME") or os.getenv("USERPROFILE")
    if not home then return nil end

    local filepath = home .. "/.tifa/accounts.lua"

    -- 加载文件（此时只编译不执行）
    local chunk, err = loadfile(filepath)
    if not chunk then
        error("failed loading: " .. tostring(err))
    end

    -- 执行文件，获取返回值
    -- 假设 accounts.lua 结尾有 return 了一个 table
    local accounts = chunk() 
    return accounts
end

local script_name = "root_test_trader"
local server = assert(load_accounts()["trader"]["gtja-3"])

print("using server", inspect(server))

local root_addr = service.new { 
    source = "@services/" .. script_name .. ".lua", 
    config = { 
        symbol = "IM2703",
        server = server,
    } 
}

service.start(root_addr)
service.send(service.get_id(root_addr), "boot")
service.join(root_addr)