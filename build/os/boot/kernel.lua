local s, e = xpcall(function ()

local function checkModules()
    --Checking BIOS Globals
    if bios and computer and device and fs and partition and log and monitor then
        return true
    else
        return false
    end
end

---@alias state
---| '"TASK_RUNNING"'
---| '"TASK_INTERRUPTIBLE"'
---| '"TASK_UNINTERRUPTIBLE"'
---| '"TASK_ZOMBIE"'
---| '"TASK_STOPPED"'
---@param state state
local function set_task_state(state)
    
end

local function create_task_table()
    return {
        state = "TASK_RUNNING",
        priority = -1,
        pid = -1,

    }
end

local kernel = {}
--Kernel Globals
kernel.ver = "0.0.1-0.craftos"
kernel.name = "Prime "..kernel.ver
kernel.running = true
kernel.process = {}
kernel.eventhandlers = {}
kernel.users = {{
    name = "root",
    group = {"root"},
    login = true,
}}

function panic(message, errors)
    if errors == nil then
        kernel.log("Kernel panic - "..message)
    else
        kernel.log("Kernel panic - "..message)
        printf("Stack Trace:")
        printf(errors)
    end
    eventsystem.push("kernel_exit")
end

local eventsystem = {}

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

local user = {}

function user.create(name, group)
    if type(group) ~= "table" then return end
    table.insert(kernel.users, {
        name = name,
        group = group or {},
        login = false,
    })
end

function user.setLoginUser(name)
    for index, value in ipairs(kernel.users) do
        if value.name == name then
            value.login = true
        else
            value.login = false
        end
    end
end

function user.delete(name)
    local del = 0
    for index, value in ipairs(kernel.users) do
        if value.name == name then
            del = index
        end
    end
    if del == 0 then
        return false
    else
        table.remove(kernel.users, del)
        return true
    end
end

function user.getCurrentUser()
    for index, value in ipairs(kernel.users) do
        if value.login == true then
            return value.name
        end
    end
end

local permission = {}

function permission.setUser(name, perm)
    
end

function kernel.log(vendor, ...)
    if not ... then
        printf("["..bios.uptime().."] ".. vendor)
    else
        printf("["..bios.uptime().."] ["..vendor.."] ".. ...)
    end
end

function kernel.fork(name, func, priority)
    eventsystem.push("kcall_fork_process", name, func, priority)
end

function kernel.exec(path, env, priority, pid, user)
    if env == nil then
        env = _ENV
    end
    if priority == nil then
        priority = 0
    end
    eventsystem.push("kcall_start_process", path, env, priority, pid, user)
end

function kernel.killProcess(pid)
    eventsystem.push("kcall_kill_process", pid)
end

function kernel.getProcess()
    return kernel.process
end

if not checkModules() and print then
    print("BIOS module is missing. This program only works on Prime BIOS.")
    return
end

monitor.reset()

printf("Starting Kernel ("..kernel.ver..")\n")

kernel.log("Creating Filesystem handler...")
kernel.fs = filesystem.create("mount", "primeos")

if kernel.fs == nil then
    if not partition.exists("primeos", "mount") then
        panic("Not mounted")
    else
        panic("Unhandled error. (Created filesystem handler is returned nil)")
    end
end
kernel.log("Created Filesystem handler.")

local userfs = {permission_table = {}}
local perm_table = {}

function userfs.init()
    
end

function userfs.open(path, mode)
    
    kernel.fs.open(path, mode)
end

function userfs.makeDir(path)
    kernel.fs.mkdir(path)
    local file = kernel.fs.open(path, "w")
    if file ~= nil then
        file.write("{}")
        file.close()
    end
end

kernel.fs.delete("/proc/*")
local file = kernel.fs.open("/proc/computerinfo", "w")
if file ~= nil then
    file.write("Computer Infomation")
    file.write("\nID: "..bios.getID())
    file.write("\nName: "..bios.getName())
    file.close()
end

if kernel.fs.isReadOnly() then
    panic("System Partition is Read-Only")
end

_ENV["kernel"] = kernel
_ENV["eventsystem"] = eventsystem
_ENV["_panic"] = panic
_ENV["user"] = user

kernel.exec("/sbin/init", _ENV, 3, 1)
--Kernel Main Loop
while kernel.running do 
    local e = {bios.pullEvent()}
    if e[1] == "terminate" or e[1] == "kernel_exit" then
        kernel.running = false
        kernel.process = {}
    end
    for index, value in ipairs(kernel.eventhandlers) do
        value(e)
    end
    if e[1] == "kcall_fork_process" then
        table.remove(e, 1)
        local name = table.remove(e, 1)
        local prio = table.remove(e, 1)
        local pid = table.maxn(kernel.process)
        table.insert(kernel.process, {thread = coroutine.create(bios.native.nativeRun), PID = pid, path = name, priority = prio, env = _ENV})
    elseif e[1] == "kcall_start_process" then
        table.remove(e, 1)
        local path = table.remove(e, 1)
        local env = table.remove(e, 1)
        local prio = table.remove(e, 1)
        local pid = table.remove(e, 1) or table.maxn(kernel.process) + 1
        local user = table.remove(e, 1) or user.getCurrentUser()
        if not kernel.fs.exists(path) then
            kernel.log("Failed to start process: File not found ("..path..")")
        else
            table.insert(kernel.process, {thread = coroutine.create(bios.native.nativeRun), PID = pid, path = path, priority = prio, env = env, user = user})
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
    else
        local level_0 = {}
        local level_1 = {}
        local level_2 = {}
        local level_3 = {}
        for index, value in ipairs(kernel.process) do
            if value.priority >= 3 then
                table.insert(level_3, value)
            elseif value.priority == 2 then
                table.insert(level_2, value)
            elseif value.priority == 1 then
                table.insert(level_1, value)
            elseif value.priority <= 0 then
                table.insert(level_0, value)
            end
        end
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
                        local s, e = coroutine.resume(value.thread, value.env, kernel.fs.combine(kernel.fs.getLocalPath(), value.path))
                        if not s then
                            kernel.log("["..value.PID.."] (".. value.path ..") Exited on error: "..e)
                        end
                    end
                end
            end
        end
        --Run process with priority
        run_process_table(level_3)
        run_process_table(level_2)
        run_process_table(level_1)
        run_process_table(level_0)
    end

    if not kernel.process[1] then
        kernel.log("init exited")
        kernel.running = false
    end
end

end, bios.debug.traceback)

if not s then
    panic("Kernel has exited on error."..e)
end