local requires = {
    bios = "bios.bios",
    computer = "bios.computer",
    device = "bios.device",
    filesystem = "bios.filesystem",
    log = "bios.log",
    partition = "bios.partition",
}
local log = require(requires.log)
local part = require(requires.partition)
local bios = {}

function bios.init()
    log.info("Initializing BIOS...")
    part.init()
    log.info("BIOS Initialize Complete.")
end

function bios.post()
    print()
    local function checkGlobal()
        if not shell or not term or not fs then return false end
        return true
    end
    if not checkGlobal() then
        log.error("This program can only be run on CC: Tweaked", 0)
    else
        term.setCursorBlink(true)
    end
    local function fail(...)
        log.error(...)
        print("BIOS Startup Check Failed. Press any key to exit...")
        local event, key = os.pullEvent("key")
        error("",0)
    end

end

function bios.run()
    term.clear()
    term.setCursorPos(1,1)
    print("CC:T Advanced BIOS")
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

function bios.execute(path)
    local func, err = loadfile(path)
    if not func then
        log.fatal(err, "Failed to load file.")
        return
    end
    local env = setmetatable({
        bios = bios,
        computer = require(requires.computer),
        device = require(requires.device),
        fs = require(requires.filesystem),
        partition = require(requires.partition),
        syslog = require(requires.log)
    }, {})
    if setfenv then
        setfenv(func, env)
        func()
    elseif _VERSION == "Lua 5.2" then
        _ENV = env
        local func, err = loadfile(path)
        if not func then
            log.fatal(err, "Failed to load file.")
            return
        end
        func()
    else
        local func, err = loadfile(path, "t", env)
        if not func then
            log.fatal(err, "Failed to load file.")
            return
        end
        func()
    end
end

return bios