local args = {...}
local os_name = args[1]

---@type os_env
_ENV = _ENV

local init = {}
init._VERSION = "0.1.0"

local colors = fbcon.ansicolors

std.print()
std.print("   " .. colors.green .. "OpenOC " .. colors.cyan .. init._VERSION .. colors.reset .. " is starting up " .. colors.bright_blue .. os_name .. colors.reset)
std.print()

---@class openoc_service
---@field name string
---@field desc string
---@field path string
---@field arguments table

--[[
level:
0 info
1 error
2 log
]]
function init.log(level, msg)
    local prefix = ""
    if level == 0 then
        prefix = " " .. colors.green .. "*" .. colors.reset .. " "
    elseif level == 1 then
        prefix = " " .. colors.red .. "*" .. colors.reset .. " "
    elseif level == 2 then
        prefix = "   "
    end
    std.write(prefix .. msg)
end

local ok = colors.bright_blue .. "[" .. colors.green .. " ok " .. colors.bright_blue .. "]" .. colors.reset
local fail = colors.bright_blue .. "[" .. colors.red .. "fail" .. colors.bright_blue .. "]" .. colors.reset

---@param service openoc_service
function init.start(service)
    init.log(0, "Starting " .. service.name .. " ...")

    local s, e = pcall(kernel.exec, service.path, service.arguments or nil)
    if not s then
        fbcon.writeTo(fbcon.width - 6, fbcon.y, fail)
        std.print()
        init.log(1, service.name .. " failed: " .. e)
    else
        fbcon.writeTo(fbcon.width - 6, fbcon.y, ok)
        std.print()
    end
end

function init.initd()
    local services = {}
    for index, value in ipairs(fs.list("/etc/init.d")) do
        if value:sub(-8) == ".service" then
            local file = fs.open(fs.combine("/etc/init.d", value))
            services[#services + 1] = json.decode(file:readAll())
            file:close()
        end
    end
    for index, value in ipairs(services) do
        init.start(value)
    end
end

init.initd()