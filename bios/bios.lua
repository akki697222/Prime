local requires = {
    bios = "bios.bios",
    computer = "bios.computer",
    device = "bios.device",
    filesystem = "bios.filesystem",
    log = "bios.log",
    partition = "bios.partition",
    graphics = "bios.graphics",
    io = "bios.io",
}
local part = require("bios.partition")
local w, h = term.getSize()
local bios = {native = {
    term = term,
    fs = fs,
    require = require,
    dofile = dofile,
    loadfile = loadfile,
    parallel = parallel,
    read = read,
}}

function bios.init()
    part.init()
end

function bios.uptime()
    return os.clock()
end

function bios.post()
    term.setCursorPos(1, 1)
    print("Prime BIOS (version 0.1.0)")
    term.setCursorPos(1, h)
    print("(Warning) This is a work-in-progress alpha version. It has many bugs and issues.")
    term.setCursorPos(1, 3)
    local function checkGlobal()
        if not shell or not term or not fs then return false end
        return true
    end
    if not checkGlobal() then
        error("This program can only be run on CC: Tweaked", 0)
    else
        term.setCursorBlink(true)
    end
    print("Booting from Storage...")
    if not fs.exists(part.directories.disk .. "bootsector/bootloader.lua") then
        print("Failed to boot: bootsector is not exists.")
    else
        local s, e = bios.execute(part.directories.disk .. "bootsector/bootloader.lua")
    end
end

function bios.run()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    bios.init()
    bios.post()
end

function bios.require(path)
    return require(path)
end

function bios.pullEvent(filter)
    return os.pullEvent(filter)
end

function bios.pullEventRaw(filter)
    return os.pullEventRaw(filter)
end

function bios.date(format, time)
    return os.date(format, time)
end

function bios.epoch(args)
    return os.epoch(args)
end

function bios.queueEvent(event, ...)
    os.queueEvent(event, ...)
end

function bios.getID()
    return os.getComputerID()
end

function bios.getName()
    return os.getComputerLabel() or "Unknown"
end

function bios.execute(path)
    local func, err = loadfile(path)
    if not func then
        return false, err
    end
    local computer = require(requires.computer)
    local device = require(requires.device)
    local filesystem = require(requires.filesystem)
    local monitor = require(requires.graphics)
    local input_output = require(requires.io)
    local env = setmetatable({
        bios = bios,
        computer = computer,
        device = device,
        filesystem = filesystem,
        partition = part,
        log = log,
        monitor = monitor,

        table = table,
        textutils = textutils,
        colors = colors,
        coroutine = coroutine,
        math = math,
        string = string,
        package = package,

        printf = print,
        write = io.write,
        pairs = pairs,
        ipairs = ipairs,
        tonumber = tonumber,
        tostring = tostring,
        read = read,
        pcall = pcall,
        xpcall = xpcall,
        type = type,
        sleep = sleep,
    }, {})
    if setfenv then
        setfenv(func, env)
        func()
    elseif _VERSION == "Lua 5.2" then
        _ENV = env
        local func, err
        local s, e = pcall(function ()
            func, err = load(path, path)
        end)
        if not func or not s then
            return false, err
        end
        local s, e = pcall(function ()
            func()
        end)
        if not s then
            return false, e
        end
    else
        local func, err
        local s, e = pcall(function ()
            func, err = loadfile(path, "t", env)
        end)
        if not func or not s then
            return false, err
        end
        local s, e = pcall(function ()
            func()
        end)
        if not s then
            return false, e
        end
    end
end

bios.debug = debug
bios.native.nativeRun = os.run

function bios.loadfile(path, _env, _metatable)
    local env = setmetatable(_env, _metatable)
    if setfenv then
        local func, err
        local s, e = pcall(function ()
            func, err = loadfile(path)
        end)
        if not func or func == nil then
            return nil, err
        end
        setfenv(func, env)
        return func, err
    elseif _VERSION == "Lua 5.2" then
        _ENV = env
        local func, err
        local s, e = pcall(function ()
            func, err = loadfile(path, "t", env)
        end)
        return func, err
    else
        local func, err
        local s, e = pcall(function ()
            func, err = loadfile(path, "t", env)
        end)
        return func, err
    end
end

return bios
