local inspect = require "inspect"


function load(fn_type, fn_struct)

-- file names
print("parse", fn_type, fn_struct)

local prefix = "/usr/local/include/ctpc2"
-- data types

local fn = fn_type or (prefix .. "/ThostFtdcUserApiDataType.h")

local function parse_datatype(line)
    local pattern = "typedef (%w+) (%w+)([%[]*%d*[%]]*);"
    local type, name, sz = string.match(line, pattern)
    if type then 
        -- print(type,name,sz)
        local label
        if type == "double" then 
            o = type
        elseif (type == "int") or (type == "short") then 
            o = "integer"
        elseif (type == "char") and (sz == nil) then 
            o = "char"
        elseif (type == "char") and (sz ~= nil) then 
            o = "string"
        else
            print("mismatch", line)
        end
    end
    return name, o
end

local function char_rep_to_int(rep)
    local char = string.match(rep, "'([%p%w])'")
    if not char then return nil end
    return string.byte(char)
end

--  #define THOST_FTDC_EXP_Normal '0'
local function parse_constant(line)
    -- local pattern = "%#define (%w+) ([%p]*[%w]*[%p]*)"
    local pattern = "%#define ([%w%_]+) ([%p%w]+)"
    local name, value = string.match(line, pattern)
    if name then 
        local rst = char_rep_to_int(value)
        if not rst then 
            -- unmatched
            -- print(name, value)
        end
        return name, rst
    end
end

local datatypes = {}
local constants = {}
for line in io.open(fn):lines() do 
    local name, type = parse_datatype(line)
    if name then datatypes[name] = type end

    local name, value = parse_constant(line)
    if name then constants[name] = value end
end

-- print(inspect(datatypes))


local fn2 = (fn_struct) or (prefix .. "/ThostFtdcUserApiStruct.h")
local content = io.open(fn2):read("*all")

local structs = {}
for name, body in string.gmatch(content,  "struct (%w+)[%s%c]*{(.-)%}") do 
    local o = {}
    for type, attr in string.gmatch(body, "([%w%p]+)%s+([%w%p]+)%;") do
        o[attr] = type
    end
    structs[name] = o
end

-- print(inspect(structs))

return datatypes, constants, structs

end

return load