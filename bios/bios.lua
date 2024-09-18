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
local bios = {native = {
    term = term
}}

function bios.init()
    part.init()
end

function bios.uptime()
    return os.clock()
end

function bios.post()
    local function checkGlobal()
        if not shell or not term or not fs then return false end
        return true
    end
    if not checkGlobal() then
        print("This program can only be run on CC: Tweaked", 0)
    else
        term.setCursorBlink(true)
    end
    print("Booting from Storage...")
    bios.execute(part.directories.disk .. "bootsector/bootloader.lua")
end

function bios.run()
    term.clear()
    term.setCursorPos(1, 1)
    print("Prime BIOS (version 0.0.1-0.craftos)\n")
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
        print("Failed to load file: "..err)
        return
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

        printf = print,
        write = io.write,
        pairs = pairs,
        ipairs = ipairs,
        tonumber = tonumber,
        tostring = tostring,
        read = read,
        pcall = pcall,
        xpcall = xpcall,
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
            print(err.."Failed to load file.")
            return
        end
        func()
    else
        local func, err
        local s, e = pcall(function ()
            func, err = loadfile(path, "t", env)
        end)
        if not func or not s then
            print(err.."Failed to load file.")
            return
        end
        func()
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
