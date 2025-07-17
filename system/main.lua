---@type onix_kernel_mode_env
_ENV = _ENV

bootRealTime = 0
function getRealTime()
    return bootRealTime + computer.uptime()
end

function nonnil(value)
    if value == nil then
        error("nil")
    else
        ---@cast value -?
        return value
    end
end

function printk(...)
    local msg = string.format("[%8.2f] %s", os.uptime(), tostring(...))
    fbcon.print(msg)
    table.insert(kernel.log_buffer, msg)
end

function panic(err, reason)
    printk("Kernel panic - " .. err .. ": " .. reason)
    while true do
        computer.pullSignal()
    end
end

-----------------------------
--- System Initialization ---
-----------------------------

argparse = loadfile("/system/lib/argparse.lua", _ENV)()
sha2 = loadfile("/system/lib/sha2for51.lua", _ENV)()
json = loadfile("/system/lib/dkjson.lua", _ENV)()
LibDeflate = loadfile("/system/lib/LibDeflate.lua", _ENV)()

loadfile("/system/config.lua", _ENV)()

local filesystem = component.proxy(computer.getBootAddress())
for index, value in ipairs(filesystem.list("/system/modules")) do
    local mod, name = loadfile("/system/modules/" .. value, _ENV)()
    if mod and name then
        _ENV[name] = mod
    end
end

loadfile = function(path)
    local file, err = fs.open(path)
    if not file and err then
        return nil, err
    end
    local content = file:readAll()
    file:close()

    local chunk, syntaxErr = load(content, "=" .. path, "t", kernel.getEnv())
    if not chunk then
        return nil, tostring(syntaxErr)
    end
    return chunk
end

local function boot()
    local proxy, path = component.proxy(computer.tmpAddress()), "timestamp"
    proxy.close(proxy.open(path, "wb"))
    bootRealTime = math.floor(proxy.lastModified(path) / 1000)
    proxy.remove(path)

    -- initialize fbcon first for showing boot message 
    fbcon.reset()

    -- boot message
    printk("Onix version " .. kernel._version)
    printk("Memory Avaliable: " .. math.floor(computer.totalMemory() / 1024) .. "KB")

    -- initializing devices and system component
    fs.init()
    kernel.std = fbcon.getstd()
    group.init()
    user.init()

    -- load module
    module.autoload()

    local vt = nonnil(module.getApi("vt"))
    local vt1 = vt.create(1)
    kernel.std = vt1:std()
    fbcon.ansi = true

    _ENV["tcp"] = tcp
    _ENV["http"] = http

    -- execute kernel main loop
    fbcon.early_output = false
    kernel.main()
end

local s, e = xpcall(boot, debug.traceback)
if not s then
    panic("system error", e)
    if GLOBAL_DETAILED_PANIC_STACK_TRACE then
        fbcon.print("Memory usage: " .. (computer.totalMemory() - computer.freeMemory()) / 1024 .. "KB")
        fbcon.print("Global Table: ")
        for key, value in pairs(_ENV) do
            fbcon.print(key .. " (" .. type(value) .. ")")
        end
    end
    fbcon.update()
    while true do
        computer.pullSignal()
    end
end