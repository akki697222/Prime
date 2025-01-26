local debug = true
local kernel_threads = {}
local s, e = xpcall(function ()

local function checkModules()
    --Checking BIOS Globals
    if bios and computer and device and fs and partition and log and monitor then
        return true
    else
        return false
    end
end

function table.deepcopy(orig, copies)
    copies = copies or {}
    if copies[orig] then return copies[orig] end

    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        copies[orig] = copy
        for orig_key, orig_value in next, orig, nil do
            copy[table.deepcopy(orig_key, copies)] = table.deepcopy(orig_value, copies)
        end
        setmetatable(copy, table.deepcopy(getmetatable(orig), copies))
    else
        copy = orig
    end
    return copy
end

---@class kernel
local kernel = {}
---@class date
local timeapi = {}
---@class eventsystem
local eventsystem = {}
---@class user
local user = {group = {}}
local user_data = {user = {}, group = {}}
---@class filesystem
local userfs = {}
---@class permission
local fperm = {}
---@class module
local module = {}
---@class device
local dev = {}
---@class stdlib
local std = {}
---@class io
local io = {}

--- @class _thread
--- @field co thread
--- @field id integer
--- @field resumes integer

--- @class process_data
--- @field co thread
--- @field threads table<_thread>
--- @field PID integer
--- @field path string
--- @field nice integer
--- @field env table
--- @field user string
--- @field arguments table
--- @field parent integer
--- @field fd table<stdout|stdin|stderr|file>
--- @field cwd string

--- @class single_permission_table
--- @field r boolean
--- @field w boolean
--- @field x boolean

--- @class multi_permission_table
--- @field owner single_permission_table
--- @field group single_permission_table
--- @field other single_permission_table

--- @class module_manifest
--- @field name string
--- @field license ?string
--- @field author ?string
--- @field desc ?string
--- @field version string
--- @field depends ?table
--- @field path string
--- @field device_table ?table

-- Kernel Globals
kernel.mode = {
    debug = debug,
}
kernel.ver = "0.1.3-0.dev"
kernel.name = "Prime version "..kernel.ver

kernel.partition = {
    root = "primeos"
}

kernel.running = true
kernel.process = {}
kernel.eventhandlers = {}
kernel.singleeventhandlers = {}
kernel.user = {}
kernel.currentHandling = -1
kernel.loaded_modules = {}
kernel.threads = 0
kernel.boottime = bios.epoch("local")
kernel.tty = {
    instances = {},
    current = 0,
}

local fb = {
    buffer = {},
    window = {
        y = 1,
        x = 1,
        width = 80,
        height = 24,
    }
}

for i = 1, fb.window.height do
    fb.buffer[i] = string.rep(" ", fb.window.width)
end

function fb.write(...)
    local text = tostring(...)
    for i = 1, #text do
        local char = text:sub(i, i)

        if char == "\n" then
            fb.window.y = fb.window.y + 1
            fb.window.x = 1
        else
            local currentLine = fb.buffer[fb.window.y]
            fb.buffer[fb.window.y] = currentLine:sub(1, fb.window.x - 1)
                .. char ..
                currentLine:sub(fb.window.x + 1)
            fb.window.x = fb.window.x + 1

            if fb.window.x > fb.window.width then
                fb.window.x = 1
                fb.window.y = fb.window.y + 1
            end
        end

        if fb.window.y > fb.window.height then
            fb.scroll()
        end
    end
end

function fb.scroll()
    table.remove(fb.buffer, 1)
    table.insert(fb.buffer, string.rep(" ", fb.window.width))
    fb.window.y = fb.window.height
end

function fb.clear()
    for i = 1, fb.window.height do
        fb.buffer[i] = string.rep(" ", fb.window.width)
    end
    fb.window.x, fb.window.y = 1, 1
end

function printf(...)
    local ctty = kernel.getTTY()
    if ctty then
        ctty:write(... .. "\n")
    else
        fb.write(... .. "\n")
        for index, value in ipairs(fb.buffer) do
            monitor.setPosition(1, index)
            monitor.write(string.rep(" ", fb.window.width))
            monitor.setPosition(1, index)
            monitor.write(value)
        end
    end
end

function error(message)
    local stderr = kernel.modules.io.stderr
    if stderr then
        stderr:write(message .. "\n")
    else
        fb.write(message .. "\n")
        for index, value in ipairs(fb.buffer) do
            monitor.setPosition(1, index)
            monitor.write(string.rep(" ", fb.window.width))
            monitor.setPosition(1, index)
            monitor.write(value)
        end
    end
end

---What happened!? ... Yes, the kernel seems to have crashed...
local function panic(message, errors)
    if errors == nil then
        printk("Kernel panic - "..message)
    else
        printk("Kernel panic - "..message)
        printf("Stack Trace:")
        printf(errors)
    end
    kernel.stop()
end

function kernel.require(modname)
    if not modname then
        return nil
    end
    local res = kernel.modules
    local normal = false
    for part in string.gmatch(modname, "[^.]+") do
        if res[part] then
            res = res[part]
        else
            normal = true
        end
    end
    if normal then
        local file, msg = package.searchpath(modname, package.path)
        if file == nil then
            printf(msg)
            return res
        else
            local fun, err = loadfile(file)
            if fun == nil then
                panic(err, "Unable to load file")
            else
                if setfenv then
                    setfenv(fun, kernel.env)
                else
                    bios.debug.setupvalue(fun, 1, kernel.env)
                end
                return fun()
            end
        end
    end
    return res
end

--EventSystem API

function eventsystem.push(event, ...)
    bios.native.os.queueEvent(event, ...)
end

function eventsystem.pull(filter)
    return bios.native.os.pullEvent(filter)
end

function eventsystem.get()
    return bios.native.os.pullEvent("kreturn_handled_event")
end

function eventsystem.pullRaw(filter)
    return bios.native.os.pullEventRaw(filter)
end

---@param func function
function eventsystem.addEventHandler(func)
    if type(func) == "function" then
        table.insert(kernel.eventhandlers, {func = func, isSingle = false, filter = nil})
    else
        printk("EventSystem", "Invalid Function")
    end
end

function eventsystem.addSingleEventHandler(func)
    if type(func) == "function" then
        table.insert(kernel.eventhandlers, {func = func, isSingle = true, filter = nil})
    else
        printk("EventSystem", "Invalid Function")
    end
end

function eventsystem.addSingleFilteredEventHandler(filter, func)
    if type(func) == "function" then
        table.insert(kernel.eventhandlers, {func = func, isSingle = true, filter = filter})
    else
        printk("EventSystem", "Invalid Function")
    end
end

-- User API

function user.init()
    if not kernel.fs.exists("/etc/passwd") then
        local file = kernel.fs.open("/etc/passwd", "w")
        if file ~= nil then
            file.write("{}")
            file.close()
        end
    else
        local file = kernel.fs.open("/etc/passwd", "r")
        if file ~= nil then
            user_data = textutils.unserialiseJSON(file.readAll() or "{}")
        end
    end
    user.save()
end

function user.save()
    local file = kernel.fs.open("/etc/passwd", "w+")
    if file ~= nil then
        file.write(textutils.serialiseJSON(user_data) or "{}")
        file.close()
    end
end

function user.getData(uid)
    for index, value in ipairs(user_data.user) do
        if value.id == uid then
            return value
        end
    end
    return nil
end

function user.getIndex(uid)
    for index, value in ipairs(user_data.user) do
        if value.id == uid then
            return index
        end
    end
    return nil
end

function user.group.getData(gid)
    for index, value in ipairs(user_data.group) do
        if value.id == gid then
            return value
        end
    end
    return nil
end

function user.group.getIndex(gid)
    for index, value in ipairs(user_data.group) do
        if value.id == gid then
            return index
        end
    end
    return nil
end

function user.create(name, password, gid, uid)
    local uid = uid or table.maxn(user_data.user) + 1
    table.insert(user_data.user, {name = name, id = uid, uid = uid, gid = gid or 100, passwd = password or ""})
    user.save()
    return uid
end

---@param uid number
---@return table|nil # if user removed, returns removed user data.
function user.delete(uid)
    if uid == 0 then
        monitor.colorPrint("UserSystem: &eCannot delete the root user.&0")
        return nil
    end
    local idx = user.getIndex(uid)
    if idx ~= nil then
        return table.remove(user_data.user, idx)
    else
        monitor.colorPrint("UserSystem: &eUser not found.&0 (UID "..uid..")")
    end
end

---@param name string
---@param gid number
function user.group.create(name, gid)
    local gid = gid or table.maxn(user_data.group) + 1
    table.insert(user_data.group, {name = name, id = gid, gid = gid})
    user.save()
    return gid
end

function user.group.delete(gid)
    if gid == 0 then
        monitor.colorPrint("&eUser Module: Cannot delete the root group.&0")
        return nil
    end
    local idx = user.group.getIndex(gid)
    if idx ~= nil then
        return table.remove(user_data.group, idx)
    else
        monitor.colorPrint("&eUser Module: Group not found. (GID "..gid..")&0")
    end
end

function user.setCurrent(uid)
    kernel.user = uid
end

function user.getCurrent()
    return kernel.user
end

function user.exists(uid)
    for index, value in ipairs(user_data.user) do
        if value.uid == uid then
            return true
        end
    end
    return false
end

-- User Filesystem API

function userfs.open(path, mode)
    local perm_table = fperm.getPermissionTable(kernel.fs.getDir(path))
    if perm_table == nil or perm_table == {} then
        printk("Filesystem", "Error: Directory Metadata not found. (in directory "..kernel.fs.getDir(path)..")")
        return nil
    end
    if kernel.fs.getFile(path) == ".meta" then
        return nil
    end
    if kernel.fs.exists(path) then
        if perm_table[kernel.fs.getFile(path)] ~= nil then
            perm_table[kernel.fs.getFile(path)].timestamp.mtime = bios.epoch("local")
        end
    elseif mode == "w" or mode == "w+" or mode == "r+" then
        if perm_table[kernel.fs.getFile(path)] ~= nil then
            perm_table[kernel.fs.getFile(path)].timestamp.mtime = bios.epoch("local")
        else
            perm_table[kernel.fs.getFile(path)] = fperm.generateMetatable(nil, false)
        end
        fperm.update(kernel.fs.getDir(path), perm_table)
    else
        return nil 
    end
    return kernel.fs.open(path, mode)
end

function userfs.delete(path)
    local perm_table = fperm.getPermissionTable(kernel.fs.getDir(path))
    if perm_table == nil or perm_table == {} then
        printk("Filesystem", "Error: Directory Metadata not found. (in directory "..kernel.fs.getDir(path)..")")
        return
    end
    if kernel.fs.exists(path) then
        if kernel.fs.getFile(path) == ".meta" then
            return 0
        end
        if perm_table[kernel.fs.getFile(path)] ~= nil then
            if perm_table[kernel.fs.getFile(path)].owner == kernel.user then
                kernel.fs.delete(path)
                return true
            elseif perm_table[kernel.fs.getFile(path)].group == user.getData(kernel.user).gid then
                kernel.fs.delete(path)
                return true
            elseif fperm.isGroupHasPermission(user.getData(kernel.user).gid, {r = true, w = true, x = false}, "other") then
                kernel.fs.delete(path)
                return true
            else
                return 0
            end
            printf(fperm.isGroupHasPermission(user.getData(kernel.user).gid, {r = true, w = true, x = false}, "group"))
            perm_table[kernel.fs.getFile(path)] = nil
            fperm.update(kernel.fs.getDir(path), perm_table)
        end
        return 2
    end
end

function userfs.list(path)
    return kernel.fs.list(path)
end

function userfs.combine(basepath, localpath)
    return kernel.fs.combine(basepath, localpath)
end

function userfs.exists(path)
    return kernel.fs.exists(path)
end

function userfs.isDir(path)
    return kernel.fs.isDir(path)
end

function userfs.chdir(path)
    kernel.getSelf().cwd = tostring(path)
end

function userfs.cwd()
    return kernel.getSelf().cwd
end

-- File permission API
function fperm.generateMetatable(permission, isDir, owner, group)
    return {
        permission = permission or {owner = {r = true, w = true, x = false}, group = {r = true, w = false, x = false}, other = {r = true, w = false, x = false}},
        owner = owner or kernel.user, 
        group = group or user.getData(kernel.user).gid, 
        isDir = isDir, 
        size = 0, 
        timestamp = {
            btime = bios.epoch("local"), 
            mtime = bios.epoch("local")
        }
    }
end

function fperm.update(path, table)
    if not kernel.fs.exists(kernel.fs.combine(path, ".meta")) then
        monitor.colorPrint("&ePermission System: Cannot find directory meta in path: "..path.."&0")
    else
        local file = kernel.fs.open(kernel.fs.combine(path, ".meta"), "w+")
        if file ~= nil then
            file.write(textutils.serialiseJSON(table))
            file.close()
        end
    end
end

---@alias user_permission_mode
---| '"owner"' #Owner
---| '"group"' #Group
---| '"other"' #Other
---@param perm multi_permission_table
---@param required_perm single_permission_table
---@param mode user_permission_mode
function fperm.hasPermission(perm, required_perm, mode)
    local actual_perm = perm[mode]

    if required_perm.r and not actual_perm.r then
        return false
    end
    if required_perm.w and not actual_perm.w then
        return false
    end
    if required_perm.x and not actual_perm.x then
        return false
    end
    
    return true
end

function fperm.init()
    local directory = {}
    local function createData(path)
        table.insert(directory, path)
    end
    local dir = {}
    local file = {}
    local list = kernel.fs.list("/")
    if list then
        for index, value in ipairs(list) do
            if kernel.fs.isDir(value.name) then
                table.insert(dir, value.name)
            else
                table.insert(file, value.name)
            end
        end
    end
    createData("/")
    local current = "/"
    for index, value in ipairs(dir) do
        local function nest(val)
            local currentback = current
            current = current .. val .. "/"
            local list_nest = kernel.fs.list(current)
            createData(current)
            for i, v in ipairs(list_nest) do
                if kernel.fs.isDir(current..v.name) then
                    nest(v.name)
                end
            end
            current = currentback
        end
        nest(value)
    end
    for index, value in ipairs(directory) do
        local permissiondata = {}
        if not kernel.fs.exists(value..".meta") then
            local file = kernel.fs.open(value..".meta", "w")
            if file ~= nil then
                file.write(textutils.serialiseJSON({[".meta"] = {permission = {owner = {r = true, w = true, x = true}, group = {r = false, w = false, x = false}, other = {r = false, w = false, x = false}}, owner = 0, group = 0, isDir = false, size = 0, timestamp = {btime = 0, mtime = 0}}}))
                file.close()
            end
        end
        local file = kernel.fs.open(value..".meta", "r")
        if file ~= nil then
            permissiondata = textutils.unserialiseJSON(file.readAll() or "{}")
            file.close()
        end
        local file = kernel.fs.open(value..".meta", "w+")
        local listdir = kernel.fs.list(value)
        for i, v in ipairs(listdir) do
            if permissiondata[v.name] == nil then
                permissiondata[v.name] = {permission = {owner = {r = true, w = true, x = true}, group = {r = true, w = false, x = false}, other = {r = true, w = false, x = false}}, owner = 0, group = 0, size = v.attributes.size or 0, timestamp = {btime = v.attributes.created / 1000, mtime = v.attributes.modified / 1000}}
            end 
            if permissiondata[v.name].timestamp == nil then
                permissiondata[v.name].timestamp = {btime = 0, mtime = 0}
            end
            if permissiondata[v.name].size == nil then
                permissiondata[v.name].size = v.attributes.size or kernel.fs.getCapacity(value..v.name) or 0
            end
        end
        if file ~= nil then
            file.write(textutils.serialiseJSON(permissiondata))
            file.close()
        end
    end
end

---@param perm multi_permission_table
function fperm.parseToString(perm)
    local res = ""
    ---@param sperm single_permission_table
    local function conc(sperm)
        if sperm.r then
            res = res .. "r"
        else
            res = res .. "-"
        end
        if sperm.w then
            res = res .. "w"
        else
            res = res .. "-"
        end
        if sperm.x then
            res = res .. "x"
        else
            res = res .. "-"
        end
    end
    conc(perm.owner)
    conc(perm.group)
    conc(perm.other)
    return res
end

---@param perm multi_permission_table
function fperm.parseToDigit(perm)
    
end

function fperm.getPermissionTable(path)
    local permissiondata = kernel.fs.open(kernel.fs.combine(path, ".meta"), "r")
    if permissiondata ~= nil then
        return textutils.unserialiseJSON(permissiondata.readAll()) or {}
    end
    return {}
end

---@param permission multi_permission_table
function fperm.setPermissionTable(path, file, permission)

end

-- Time API

function timeapi.epoch(args)
    return bios.epoch(args)
end

function timeapi.date(format, time)
    return bios.date(format, time)
end

-- Module API

---@param name string
---@return table|nil
---@return module_manifest|nil
function module.load(name)
    for index, value in ipairs(kernel.loaded_modules) do
        ---@type module_manifest
        value.manifest = value.manifest
        if value.manifest.name == name then
            printk("Module", "Loading module: "..value.manifest.name)
            setfenv(value.init, kernel.env)
            table.insert(kernel_threads, value.init)
            return value.main, value.manifest
        end
    end
    printk("Module", "Cannot find module '"..name.."'")
    return nil, nil
end

---@param name string
---@return table|nil
---@return module_manifest|nil
function module.get(name)
    for index, value in ipairs(kernel.loaded_modules) do
        if value.manifest.name == name then
            return value.main, value.manifest
        end
    end
    printk("Module", "Cannot find module '"..name.."'")
    return nil, nil
end

---@param main table
---@param init function
---@param manifest module_manifest
function module.register(main, init, manifest)
    assert(manifest ~= nil, "bad argument #3 to 'register' (table expected, got nil)")
    assert(type(manifest) == "table", "bad argument #3 to 'register' (table expected, got "..type(manifest)..")")
    if not (manifest.name and manifest.version and manifest.path) then
        printk("Module", "Invalid module manifest")
    else
        table.insert(kernel.loaded_modules, {manifest = manifest, main = main, init = init})
    end
end

---@param main table
---@param init function
---@param manifest module_manifest
function module.registerAndLoad(main, init, manifest)
    module.register(main,init,manifest)
    module.load(manifest.name)
end

---@param main table
---@param init function
---@param manifest module_manifest
function module.registerToAutoloaderAndLoad(main, init, manifest)
    module.register_autoloader(main,init,manifest)
    module.load(manifest.name)
end

---@param main table
---@param init function
---@param manifest module_manifest
function module.register_autoloader(main, init, manifest)
    if not (manifest.name and manifest.version and manifest.path) then
        printk("Module", "Invalid module")
    else
        local file = kernel.fs.open("/etc/modules", "r")
        if file ~= nil then
            local default = textutils.unserialiseJSON(file.readAll() or "") or {}
            table.insert(default, manifest)
            file.close()
            local file = kernel.fs.open("/etc/modules", "w+")
            if file ~= nil then
                file.write(textutils.serialiseJSON(default))
                file.close()
                table.insert(kernel.loaded_modules, {manifest = manifest, main = main, init = init})
            end
        else
            printk("Module", "Cannot load /etc/modules")
        end
    end
end

function module.autoload()
    local file = kernel.fs.open("/etc/modules", "r")
    if file == nil then
        printk("Module", "Cannot load /etc/modules")
        return
    end

    local loads = textutils.unserialiseJSON(file.readAll() or "") or {}
    file.close()

    local registeredModules = {}
    local initializedModules = {}

    ---@param value module_manifest
    local function registerModule(value)
        local main, init, manifest = kernel.require(value.path)
        if main and init and manifest then
            table.insert(registeredModules, manifest.name)
            module.register(main, init, manifest)
            init()
            if manifest.depends then
                for _, depName in ipairs(manifest.depends) do
                    local _, _, depManifest = kernel.require(depName)
                    if depManifest then
                        registerModule(depManifest)
                    end
                end
            end
        end
    end

    ---@param name string
    local function initializeModule(name)
        module.load(name)
    end

    for _, value in ipairs(loads) do
        registerModule(value)
    end

    for _, name in pairs(registeredModules) do
        initializeModule(name)
    end
end

-- Device API



-- Kernel API

function kernel.init()
    --Kernel init
    kernel.fs.delete("/proc/*")
    local file = kernel.fs.open("/proc/computerinfo", "w")
    if file ~= nil then
        file.write("Computer Infomation")
        file.write("\nID: "..bios.getID())
        file.write("\nName: "..bios.getName())
        file.close()
    end
    user_data.user[1] = {name = "root", id = 0, uid = 0, gid = 0, passwd = ""}
    user_data.group[1] = {name = "root", id = 0, gid = 0}
    user_data.group[2] = {name = "default", id = 100, gid = 100}
    if kernel.mode.debug == true then
        user.create("debug_user", "debug", 100, 1)
    else
        if not user.exists(1) then
            printf("First Boot.")
            user.create("akki", "akki", 100, 1)
        end
    end
    kernel.user = 0
    -- Initialize for require
    local lp = kernel.fs.getLocalPath()
    if kernel.mode.debug then
        package.path = package.path..";"..lp.."/?;"..lp.."/usr/lib/?;"..lp.."/?.lua;"..lp.."/usr/lib/?.lua;"..lp.."/usr/lib/module/"..kernel.ver.."/?;"..lp.."/usr/lib/module/"..kernel.ver.."/?.lua;"..lp.."/usr/lib/module/"..kernel.ver.."/?.ko;"
    else
        package.path = lp.."/?;"..lp.."/usr/lib/?;"..lp.."/?.lua;"..lp.."/usr/lib/?.lua;"..lp.."/usr/lib/module/"..kernel.ver.."/?;"..lp.."/usr/lib/module/"..kernel.ver.."/?.lua;"..lp.."/usr/lib/module/"..kernel.ver.."/?.ko;"
    end
    --Setting Env
    ---@class _ENV
    kernel.env = {
        table = table,
        textutils = textutils,
        colors = colors,
        coroutine = coroutine,
        math = math,
        string = string,

        printf = printf,
        printk = printk,
        write = write,
        pairs = pairs,
        ipairs = ipairs,
        tonumber = tonumber,
        tostring = tostring,
        error = error,
        pcall = pcall,
        xpcall = xpcall,
        sleep = sleep,
        setmetatable = setmetatable,
        getmetatable = getmetatable,
        next = next,
        require = kernel.require,
        type = type,
        terminal = kernel.getTTY,

        _ERR = 0,
    }
    ---@class modules
    kernel.modules = {
        ---@class system
        system = {
            user = user,
            permission = fperm,
            monitor = monitor,
            module = module,
            ---@class system_info
            system = {
                ver = kernel.ver,
                name = kernel.name,
                root = kernel.partition.root
            },
            event = eventsystem,
            filesystem = userfs,
            ---@class process
            process = {
                fork = kernel.fork,
                exec = kernel.exec,
                execve = kernel.execve,
                getTable = kernel.getProcess,
                getProcess = kernel.getProcessFromPID,
                get = kernel.getCurrentProcess,
                kill = kernel.killProcess,
                clone = kernel.clone,
                thread = kernel.thread,
                continue = kernel.continue
            },
            ---@class util
            util = {
                date = timeapi,
                argparse = bios.native.require("argparse") or function()printf("Failed to setup module 'argparse'")end,
                ---@class printUtils
                print = {
                    printOutput = kernel.printOutput,
                    colorWrite = monitor.colorWrite,
                    colorPrint = monitor.colorPrint,
                    replaceLine = monitor.replaceLine,
                },
                colors = monitor.colors
            },
            internal = {
                keys = device.keyboard.keys,
                peripheral = bios.native.peripheral
            },
            kernel = {
                createThread = kernel.addThread,
                printk = printk
            }
        }
    }  
    --Module initialize
    fperm.init()
    user.init()
    module.autoload()
    -- tty
    ---@type tty_mod
    local tty = module.get("tty")
    ---@type vt_mod
    local vt = module.get("vt")
    kernel.tty.instances[1] = vt.create(1)
    kernel.tty.current = 1
    local width, height = monitor.size()
    kernel.getTTY():transfer(fb.buffer, fb.window.x, fb.window.y, width, height)
    kernel.getTTY():setColorMode(true)
    kernel.modules.io = {
        stdin = tty.stdin.new(),
        stdout = tty.stdout.new(),
        stderr = tty.stderr.new()
    }
end

function printk(vendor, ...)
    if not ... then
        printf("["..(bios.epoch("local") - kernel.boottime) / 1000 .."] ".. vendor)
    else
        printf("["..(bios.epoch("local") - kernel.boottime) / 1000 .."] ("..vendor..") ".. ...)
    end
end

function kernel.getCurrentProcess()
    return kernel.currentHandling
end

---@param thread _thread
function kernel.continue(thread)
    assert(thread ~= nil)
    if coroutine.status(thread.co) ~= "dead" then
        thread.resumes = thread.resumes + 1
        return coroutine.resume(thread.co)
    end
end

---@return vt|nil
function kernel.getTTY(id) 

    if kernel.tty.instances[id] then
        return kernel.tty.instances[id]
    else
        if kernel.tty.current > 0 then
            return kernel.tty.instances[kernel.tty.current]
        end
    end
    return nil
end

function kernel.fork()
    local info = bios.debug.getinfo(2, "fS")
    local new_pid = table.maxn(kernel.process) + 1
    local new_process = {
        co = coroutine.create(function()
            local pid = coroutine.yield()
            if pid == 0 then
                return info.func()
            end
        end),
        threads = {},
        PID = new_pid,
        path = info.source,
        nice = 3,
        env = table.deepcopy(kernel.env),
        user = user.getData(user.getCurrent()).name,
        arguments = {},
        parent = kernel.currentHandling,
        fd = {},
        cwd = kernel.fs.getDir(info.source)
    }
    
    table.insert(kernel.process, new_process)
    
    eventsystem.push("kcall_fork_complete", new_pid)

    local parent = kernel.getProcessFromPID(kernel.currentHandling)
    if parent then
        if parent.parent > 0 then
            return 0
        end
    end
    
    return new_pid
end

function kernel.clone()
    ---@type process_data
    local new_proc = kernel.getProcessFromPID(kernel.currentHandling)
    new_proc.PID = table.maxn(kernel.process) + 1
    new_proc.env = table.deepcopy(new_proc.env)
    new_proc.parent = kernel.currentHandling
end

---@return _thread
---@param fun function
function kernel.thread(fun)
    ---@type _thread
    local newThread = {
        co = coroutine.create(fun),
        id = kernel.threads + 1,
        resumes = 0
    }
    table.insert(kernel.getProcessFromPID(kernel.currentHandling).threads, newThread)
    return newThread 
end

function kernel.exec(path, env, nice, arguments)
    if type(path) ~= "string" then
        printf("exec: bad argument #1 (Expected string, got " .. type(path) .. ")")
        return
    end
    if type(env) ~= "table" then
        env = table.deepcopy(kernel.env)
    end
    if type(nice) ~= "number" then
        nice = 3
    end
    if type(arguments) ~= "table" then
        arguments = {}
    end
    local pid = table.maxn(kernel.process) + 1
    if not kernel.fs.exists(path) then
        printk("Process " .. pid .. " failed to start: No such file")
    else
        table.insert(kernel.process, {
            threads = {},
            co = coroutine.create(bios.native.nativeRun),
            PID = pid,
            path = path,
            nice = nice,
            env = env,
            user = user.getCurrent(),
            arguments = arguments,
            parent = -1,
            fd = {},
            cwd = kernel.fs.getDir(path)
        })
    end
end

function kernel.killProcess(pid)
    eventsystem.push("kcall_kill_process", pid)
end

function kernel.getProcess()
    return kernel.process
end

function kernel.getProcessFromPID(pid)
    for index, value in ipairs(kernel.process) do
        if value.PID == pid then
            return value, index
        end
    end
    return nil, -1
end

function kernel.getSelf()
    for index, value in ipairs(kernel.process) do
        if value.PID == kernel.currentHandling then
            return value, index
        end
    end
    return nil, -1
end

function kernel.stop()
    if kernel.mode.debug == true then
        printf("/// Kernel debug ///")
        printf("User Data Table: "..textutils.serialiseJSON(user_data))
        printf("/// Kernel debug end ///")
    end
    kernel.fs.closeAll()
    kernel.running = false
    kernel.process = {}
end

function kernel.printOutput(printTable)
    local len = {}
    for index, value in ipairs(printTable) do
        for i, v in ipairs(value) do
            local strv = tostring(v)
            if len[i] == nil then
                len[i] = #strv
            else
                if len[i] < #strv then
                    len[i] = #strv
                end
            end
        end
    end
    local ctty = kernel.getTTY()
    for index, value in ipairs(printTable) do
        for i, v in ipairs(value) do
            local strv = tostring(v)
            ctty:write(strv)
            for i = 1, len[i] - #strv do
                ctty:write(" ")
            end
            ctty:write(" ")
        end
        ctty:write("\n")
    end
end

if not checkModules() and print then
    print("BIOS module is missing. This program only works on Prime BIOS.")
    return
end

monitor.reset()

printk("Booting "..kernel.name)
if kernel.mode.debug == true then
    printk("Kernel Debug Mode.")
end

printk("Initializing hardware...")

printk("Setting up file systems...")
local new_fs = filesystem.create("mount", kernel.partition.root)

if new_fs == nil then
    if not partition.exists(kernel.partition.root, "mount") then
        panic("System partition is not mounted.")
    else
        panic("Unhandled error. (Filesystem nil)")
    end
else
    ---@type filesystem
    kernel.fs = new_fs
end

if kernel.fs.isReadOnly() then
    panic("System Partition is Read-Only")
end

kernel.init()

kernel.exec("/sbin/init", kernel.env, 0)
--Kernel Main Loop
function kernel.addThread(func)
    local exits = {}
    local pos = #kernel_threads + 1
    if type(func) == "function" then
        if setfenv then
            local nenv = table.deepcopy(kernel.env)
            nenv.exit = function ()
                table.insert(exits, pos)
            end
            setfenv(func, nenv)
            table.insert(kernel_threads, pos, coroutine.create(func))
        end
    end
end
while kernel.running do 
    local e = {bios.pullEventRaw()}
    --local pp = bios.native.require("cc.pretty")
    --pp.pretty_print(e)
    if e[1] == "terminate" or e[1] == "kernel_exit" then
        kernel.stop()
    end

    table.insert(kernel_threads, coroutine.create(function ()
        local exits = {}
        for index, value in ipairs(kernel.eventhandlers) do
            if type(value.func) == "function" then
                if setfenv then
                    local nenv = table.deepcopy(kernel.env)
                    nenv.exit = function ()
                        table.insert(exits, index)
                    end
                    setfenv(value.func, nenv)
                end
                
                -- Modified event handler processing
                local shouldProcess = 
                    (not value.filter) or  -- No filter, always process
                    (value.filter and value.filter == e[1])  -- Filter matches event

                if shouldProcess then
                    if value.isSingle then
                        table.insert(exits, index)
                    end
                    value.func(table.deepcopy(e))
                end
            end
        end
        
        for index, value in ipairs(exits) do
            table.remove(kernel.eventhandlers, value)
        end
    end))
    if e[1] == "kcall_kill_process" then
        table.remove(e, 1)
        local pid = table.remove(e, 1)
        local remove = -1
        for index, value in ipairs(kernel.process) do
            if pid == value.PID then
                remove = index
            end
        end
        table.remove(kernel.process, remove)
    elseif e[1] == "kcall_panic" then
        table.remove(e, 1)
        local message = table.remove(e, 1)
        local err = table.remove(e, 1)
        panic(message, err)
    elseif e[1] == "kcall_fork_complete" then
        table.remove(e, 1)
        local new_pid = table.remove(e, 1)
        local child_process = nil
        for _, proc in ipairs(kernel.process) do
            if proc.PID == new_pid then
                child_process = proc
                break
            end
        end
    
        if child_process then
            if coroutine.status(child_process.co) ~= "dead" then
                local success, result = coroutine.resume(child_process.co, 0)
                if not success then
                    printk("Process " .. new_pid .. " failed to start: " .. tostring(result))
                    kernel.killProcess(new_pid)
                end
            else
                kernel.killProcess(new_pid)
            end
        end
    else
        table.sort(kernel.process, function (a, b)
            return a.nice < b.nice
        end)
        local function run_process_table(tbl)
            for index, value in ipairs(tbl) do
                if value.co then
                    if coroutine.status(value.co) == "dead" then
                        kernel.killProcess(value.PID)
                    else
                        kernel.currentHandling = value.PID
                        local file = kernel.fs.open("/proc/"..value.PID.."/info", "w+")
                        if file ~= nil then
                            file.write("Process Infomation")
                            file.write("\nPath: "..value.path)
                            file.write("\nPID: "..value.PID)
                            file.write("\nUser: "..value.user)
                            file.write("\nCurrent Working Directory: "..value.cwd)
                            file.close()
                        end
                        local s, e = coroutine.resume(value.co, value.env, kernel.fs.combine(kernel.fs.getLocalPath(), value.path), table.unpack(value.arguments))
                        if not s then
                            printk("Process "..value.PID.." Exited on error: "..e)
                        end
                    end
                end
            end
        end
        --Run process with nice (priority)
        run_process_table(kernel.process)
        local dead_threads = {}
        for index, value in ipairs(kernel_threads) do
            if type(value) == "thread" then
                if coroutine.status(value) == "dead" then
                    table.insert(dead_threads, index)
                else
                    local s, e = coroutine.resume(value)
                    if not s then
                        printk("Kernel Thread "..index.." Exited on error: "..(e or "No Error"))
                    end
                end
            end
        end
        for index, value in ipairs(dead_threads) do
            table.remove(kernel_threads, value)
        end
    end

    if not kernel.process[1] then
        printk("init exited")
        kernel.running = false
    end

    eventsystem.push("kreturn_handled_event", e)
end

kernel.stop()

end, bios.debug.traceback)

if not s then
    printf("Kernel has exited on error.", e)
    if debug == true then
        local file = bios.native.fs.open("/panic.txt", "w+")
        if file ~= nil then
            file.write(e or "No Error")
            file.close()
        end
    end
end