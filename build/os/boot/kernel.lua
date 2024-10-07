local s, e = xpcall(function ()

local function checkModules()
    --Checking BIOS Globals
    if bios and computer and device and fs and partition and log and monitor then
        return true
    else
        return false
    end
end

local kernel = {}
--Kernel Globals
kernel.mode = {
    debug = true,
}
kernel.ver = "0.1.1-0.craftos"
kernel.name = "Prime version "..kernel.ver

kernel.partition = {
    root = "primeos"
}

kernel.running = true
kernel.process = {}
kernel.eventhandlers = {}
kernel.user = {}

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
local errors = {
    [-1] = true,
    [0] = "Permission Denied.",
    [1] = "File not found.",
    [2] = "No such file or directory."
}
local peripheral = {}

---What happened!? ... Yes, the kernel seems to have crashed...
function panic(message, errors)
    if errors == nil then
        kernel.log("Kernel panic - "..message)
    else
        kernel.log("Kernel panic - "..message)
        printf("Stack Trace:")
        printf(errors)
    end
    kernel.stop()
end

--EventSystem API

function eventsystem.push(event, ...)
    bios.queueEvent(event, ...)
end

function eventsystem.pull(filter)
    return bios.pullEvent(filter)
end

function eventsystem.pullRaw(filter)
    return bios.pullEventRaw(filter)
end

---@param func function
function eventsystem.addEventHandler(func)
    if type(func) == "function" then
        table.insert(kernel.eventhandlers, func)
    else
        kernel.log("EventSystem", "Invalid Function")
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
---@param permission string #rwxrwxrwx
function user.group.create(name, gid, permission)
    local gid = gid or table.maxn(user_data.group) + 1
    table.insert(user_data.group, {name = name, id = gid, permission = permission or "rwxr-xr-x", gid = gid})
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
        kernel.log("Filesystem", "Error: Directory Metadata not found. (in directory "..kernel.fs.getDir(path)..")")
        return nil
    end
    if kernel.fs.getFile(path) == ".meta" then
        return nil
    end
    if kernel.fs.exists(path) then
        if perm_table[kernel.fs.getFile(path)] ~= nil then
            perm_table[kernel.fs.getFile(path)].timestamp.mtime = timeapi.epoch("local") / 1000
        end
    elseif mode == "w" or mode == "w+" or mode == "r+" then
        if perm_table[kernel.fs.getFile(path)] ~= nil then
            perm_table[kernel.fs.getFile(path)].timestamp.mtime = timeapi.epoch("local") / 1000
        else
            perm_table[kernel.fs.getFile(path)] = fperm.generateMetatable("rwxr--r--", false)
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
        kernel.log("Filesystem", "Error: Directory Metadata not found. (in directory "..kernel.fs.getDir(path)..")")
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
            elseif fperm.isGroupHasPermission(user.getData(kernel.user).gid, "rw-", "other") then
                kernel.fs.delete(path)
                return true
            else
                return 0
            end
            printf(fperm.isGroupHasPermission(user.getData(kernel.user).gid, "rw-", "group"))
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

-- File permission API
function fperm.generateMetatable(permission, isDir, owner, group)
    return {
        permission = permission or "rwxr--r--",
        owner = owner or kernel.user, 
        group = group or user.getData(kernel.user).gid, 
        isDir = isDir, 
        size = 0, 
        timestamp = {
            btime = timeapi.epoch("local") / 1000, 
            mtime = timeapi.epoch("local") / 1000
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

function fperm.isGroupHasPermission(gid, perm, mode)
    local group_data = user.group.getData(gid)
    local group_perm = ""
    if group_data == nil then
        printf("invalid group id "..gid)
        return
    end
    if mode == "owner" then
        group_perm = string.sub(group_data.permission, 1, 3)
    elseif mode == "group" then
        group_perm = string.sub(group_data.permission, 4, 6)
    elseif mode == "other" then
        group_perm = string.sub(group_data.permission, 7, 9)
    elseif mode ~= nil then
        printf("invalid mode '"..mode.."'")
    else
        printf("please specify the mode")
    end
    printf(perm)
    printf(group_perm)
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
    --printf(textutils.serialiseJSON(directory))
    for index, value in ipairs(directory) do
        local permissiondata = {}
        if not kernel.fs.exists(value..".meta") then
            local file = kernel.fs.open(value..".meta", "w")
            if file ~= nil then
                file.write(textutils.serialiseJSON({[".meta"] = {permission = "rwx------", owner = 0, group = 0, isDir = false, size = 0, timestamp = {btime = 0, mtime = 0}}}))
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
               permissiondata[v.name] = {permission = "rwxr--r--", owner = 0, group = 0, size = v.attributes.size or 0, timestamp = {btime = v.attributes.created / 1000, mtime = v.attributes.modified / 1000}}
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
        --printf("("..value..") "..textutils.serialiseJSON(permissiondata))
    end
end

function fperm.parseDigit(permission)
    local permission_map = {["r"] = 4, ["w"] = 2, ["x"] = 1, ["-"] = 0}
    local owner, group, other = permission:sub(1, 3), permission:sub(4, 6), permission:sub(7, 9)
    local function parseSection(section)
        return (permission_map[section:sub(1, 1)] or 0) + (permission_map[section:sub(2, 2)] or 0) + (permission_map[section:sub(3, 3)] or 0)
    end
    local res = parseSection(owner) .. parseSection(group) .. parseSection(other)

    return res
end

local permissions = {
    [7] = "rwx",
    [6] = "rw-",
    [5] = "r-x",
    [4] = "r--",
    [3] = "-wx",
    [2] = "-w-",
    [1] = "--x",
    [0] = "---"
}

function fperm.parseSingleString(permission)
    return permissions[permission]
end

function fperm.parseString(permission)
    if permission < 0 or permission > 777 then
        return nil
    end

    local result = ""
    
    for i = 1, 3 do
        local digit = math.floor(permission / 10^(3-i)) % 10
        result = result .. permissions[digit]
    end
    
    return result
end

function fperm.getPermissionTable(path)
    local permissiondata = kernel.fs.open(kernel.fs.combine(path, ".meta"), "r")
    if permissiondata ~= nil then
        return textutils.unserialiseJSON(permissiondata.readAll()) or {}
    end
    return {}
end

---@param permission number|string You can use permissions like 777.
function fperm.setPermissionTable(path, file, permission)

end

-- Time API

function timeapi.epoch(args)
    return bios.epoch(args)
end

function timeapi.date(format, time)
    return bios.date(format, time)
end

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
    user_data.group[1] = {name = "root", id = 0, gid = 0, permission = "rwxrwxrwx"}
    user_data.group[2] = {name = "default", id = 100, gid = 100, permission = "rwxr-xr-x"}
    if kernel.mode.debug == true then
        user.create("debug_user", "debug", 100, 1)
    else
        if not user.exists(1) then
            printf("First Boot.")
            user.create("akki", "akki", 100, 1)
        end
    end
    kernel.user = 0
    --Module initialize
    fperm.init()
    user.init()
    
    --Setting Env
    kernel.env = {
        table = table,
        textutils = textutils,
        colors = colors,
        coroutine = coroutine,
        math = math,

        printf = printf,
        write = write,
        pairs = pairs,
        ipairs = ipairs,
        tonumber = tonumber,
        tostring = tostring,
        read = read,
        pcall = pcall,
        xpcall = xpcall,
        sleep = sleep,
        require = function (...)
            if not ... then
                return nil
            end
            local lp = kernel.fs.getLocalPath()
            package.path = lp.."/?;"..lp.."/usr/lib/?;"..lp.."/?.lua;"..lp.."/usr/lib/?.lua;"
            ---@class primeDefaultModule
            local modules = {
                system = {
                    user = user,
                    permission = fperm,
                    monitor = monitor,
                    system = {
                        ver = kernel.ver,
                        name = kernel.name,
                        root = kernel.partition.root
                    },
                    event = eventsystem,
                    filesystem = userfs,
                    process = {
                        fork = kernel.fork,
                        exec = kernel.exec,
                        get = kernel.getProcess,
                        kill = kernel.killProcess,
                    },
                    util = {
                        date = timeapi,
                        argparse = bios.native.require("argparse"),
                        print = {
                            printOutput = kernel.printOutput,
                            colorWrite = monitor.colorWrite,
                            colorPrint = monitor.colorPrint,
                            replaceLine = monitor.replaceLine,
                        },
                        key = device.keyboard.keys,
                        input = bios.native.read,
                    },
                }
            }
            local res = modules
            local normal = false
            for part in string.gmatch(..., "[^.]+") do
                if res[part] then
                    res = res[part]
                else
                    normal = true
                end
            end
            if normal then
                --[[
                local localpath = kernel.fs.getLocalPath()
                local a = localpath .. "/" .. string.gsub(..., "%.", "/")
                printf(a)
                res = bios.native.loadfile(a, "t", kernel.env)
                if not res then
                    res = bios.native.loadfile(localpath .. "/" .. a, "t", kernel.env)
                end
                if not res then
                    printf("Module '" .. ... .. "' is not found")
                else
                    if _VERSION == "Lua 5.1" then
                        setfenv(res, kernel.env)
                    end
                    return res()
                end
                ]]
                if setfenv then
                    setfenv(bios.native.require, kernel.env)
                end
                res = require(...)
            end
            return res
        end
    }
end

function kernel.log(vendor, ...)
    if not ... then
        printf("["..bios.uptime().."] ".. vendor)
    else
        printf("["..bios.uptime().."] ["..vendor.."] ".. ...)
    end
end

function kernel.fork()
    local info = debug.getinfo(2, "fS")
    eventsystem.push("kcall_fork_process", info.func, info.source)
end

function kernel.exec(path, env, priority, pid, usr, arguments)
    if env == nil then
        env = kernel.env
    end
    if priority == nil then
        priority = 3
    end
    if pid == nil then
        pid = table.maxn(kernel.process) + 1
    end
    if usr == nil then
        usr = user.getData(user.getCurrent()).name or "Unknown(Kernel bug or error)"
    end
    if arguments == nil then
        arguments = {}
    end
    eventsystem.push("kcall_start_process", path, env, priority, pid, usr, arguments)
end

function kernel.killProcess(pid)
    eventsystem.push("kcall_kill_process", pid)
end

function kernel.getProcess()
    return kernel.process
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
    for index, value in ipairs(printTable) do
        for i, v in ipairs(value) do
            local strv = tostring(v)
            write(strv)
            for i = 1, len[i] - #strv do
                write(" ")
            end
            write(" ")
        end
        printf()
    end
end

if not checkModules() and print then
    print("BIOS module is missing. This program only works on Prime BIOS.")
    return
end

monitor.reset()

kernel.log("Booting "..kernel.name)
if kernel.mode.debug == true then
    _debug_mode = true
    kernel.log("Kernel Debug Mode.")
end

kernel.log("Initializing hardware...")

kernel.log("Setting up file systems...")
kernel.fs = filesystem.create("mount", kernel.partition.root)

if kernel.fs == nil then
    if not partition.exists(kernel.partition.root, "mount") then
        panic("System partition is not mounted.")
    else
        panic("Unhandled error. (Filesystem nil)")
    end
end

if kernel.fs.isReadOnly() then
    panic("System Partition is Read-Only")
end

kernel.init()

kernel.exec("/sbin/init", kernel.env, 0, 1)
--Kernel Main Loop
while kernel.running do 
    local e = {bios.pullEvent()}
    --local pp = bios.native.require("cc.pretty")
    --pp.pretty_print(e)
    if e[1] == "terminate" or e[1] == "kernel_exit" then
        kernel.stop()
    end
    for index, value in ipairs(kernel.eventhandlers) do
        if type(value) == "function" then
            value(e)
        end
    end
    if e[1] == "kcall_fork_process" then
        table.remove(e, 1)
        local func = table.remove(e, 1)
        local path = table.remove(e, 1)
        table.insert(kernel.process, {thread = coroutine.create(func), PID = table.maxn(kernel.process) + 1, path = path, priority = 0, env = kernel.env, user = user.getCurrent(), arguments = {}})
    elseif e[1] == "kcall_start_process" then
        table.remove(e, 1)
        local path = table.remove(e, 1)
        local env = table.remove(e, 1)
        local prio = table.remove(e, 1)
        local pid = table.remove(e, 1)
        local user = table.remove(e, 1)
        local arguments = table.remove(e, 1)
        if not kernel.fs.exists(path) then
            kernel.log("Failed to start process: File not found ("..path..")")
        else
            table.insert(kernel.process, {thread = coroutine.create(bios.native.nativeRun), PID = pid, path = path, priority = prio, env = env, user = user, arguments = arguments})
        end
    elseif e[1] == "kcall_kill_process" then
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
    elseif e[1] == "filesystem_update" then
        table.remove(e, 1)
        local path = table.remove(e, 1)
        if path == kernel.partition.root then
            fperm.update()
        end
    else
        table.sort(kernel.process, function (a, b)
            return a.priority < b.priority
        end)
        local function run_process_table(tbl)
            for index, value in ipairs(tbl) do
                if value.thread then
                    if coroutine.status(value.thread) == "dead" then
                        kernel.killProcess(value.PID)
                    else
                        local file = kernel.fs.open("/proc/"..value.PID.."/info", "w+")
                        if file ~= nil then
                            file.write("Process Infomation")
                            file.write("\nPath: "..value.path)
                            file.write("\nPID: "..value.PID)
                            file.write("\nUser: "..value.user)
                            file.close()
                        end
                        local s, e = coroutine.resume(value.thread, value.env, kernel.fs.combine(kernel.fs.getLocalPath(), value.path), table.unpack(value.arguments))
                        if not s then
                            kernel.log("["..value.PID.."] (".. value.path ..") Process Exited on error: "..e)
                        end
                    end
                end
            end
        end
        --Run process with priority
        run_process_table(kernel.process)
    end

    if not kernel.process[1] then
        kernel.log("init exited")
        kernel.running = false
    end
end

kernel.stop()

end, bios.debug.traceback)

if not s then
    panic("Kernel has exited on error.", e)
    if _debug_mode == true then
        local file = bios.native.fs.open("/panic.txt", "w+")
        if file ~= nil then
            file.write(e or "No Error")
            file.close()
        end
    end
end