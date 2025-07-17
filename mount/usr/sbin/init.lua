local args = { ... }
local os_name = args[1]

---@type os_env
_ENV = _ENV

process.setSignalHandler(process.signals.SIGINT, function()
    -- nop
end)

if process.getCurrentPID() ~= 1 then
    std.print("init already running")
    return
end

local init = {}
init._VERSION = "0.1.0"

local colors = fbcon.ansicolors

std.print()
std.print("   " ..
    colors.green ..
    "OpenOC " ..
    colors.cyan .. init._VERSION .. colors.reset .. " is starting up " .. colors.bright_blue .. os_name .. colors.reset)
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

    local pid, err = process.exec(service.path, service.arguments or nil)
    if pid == -1 then
        fbcon.writeTo(fbcon.width - 6, fbcon.y, fail)
        std.print()
        init.log(1, service.name .. " failed: " .. err .. "\n")
    else
        fbcon.writeTo(fbcon.width - 6, fbcon.y, ok)
        std.print()
    end
end

function init.initd()
    local services = {}
    for index, value in ipairs(fs.list("/etc/init.d/")) do
        if value:sub(-8) == ".service" then
            local file, err = fs.open(fs.combine("/etc/init.d", value))
            if not file then
                printk("init: failed to start service: " .. err)
            else
                services[#services + 1] = json.decode(file:readAll())
                file:close()
            end
        end
    end
    for index, value in ipairs(services) do
        init.start(value)
    end
end

function init.loginSetup()
    std.print()
    std.write("Please enter the username: ")
    local username = std.readline()

    local function readPassword()
        std.write("Please enter the password for the new user: ")
        local pass1 = std.readline(true)
        std.write("Please retype the password to verify: ")
        local pass2 = std.readline(true)
        return pass1, pass2
    end

    local pass = ""
    while true do
        local pass1, pass2 = readPassword()
        if pass1 == "" then
            std.print("Password cannot be empty. Please try again.")
        elseif pass1 ~= pass2 then
            std.print("Passwords do not match. Please try again.")
        elseif pass1 == pass2 then
            pass = pass1
            break
        end
    end

    user.create(username, pass, 100, 100, "", "/bin/posh.lua")

    std.print("User '" .. username .. "' created successfully.")
end

function init.makeBinExecutable()
    for index, value in ipairs(fs.list("/usr/bin")) do
        if value == "sudo.lua" or value == "sudo" then
            fs.setPermission(fs.combine("/usr/bin", value), 4755)
        else
            fs.setPermission(fs.combine("/usr/bin", value), 755)
        end
    end
end

function init.setupDirectory()
    local dirs = {
        ["/root"] = 700,
        ["/tmp"] = 777,
    }
    for key, value in pairs(dirs) do
        fs.setPermission(key, value)
    end
end

if not fs.exists("/etc/init.d") then
    fs.makeDirectory("/etc/init.d")
end

init.setupDirectory()
if not fs.exists("/etc/init.d/firstboot") then
    fs.open("/etc/init.d/firstboot", "w"):close()
    std.print("Starting setup...")
    init.loginSetup()
end

init.makeBinExecutable()
init.initd()

init.start({
    name = "login",
    desc = "login prompt",
    path = "/usr/sbin/login.lua",
    arguments = {}
})

while true do
    coroutine.yield()
end
