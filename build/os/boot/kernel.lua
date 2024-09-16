local s, e = xpcall(function ()

local function checkModules()
    --Checking BIOS Globals
    if bios and computer and device and fs and partition and log and monitor and __print then
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
    table.insert(kernel.eventhandlers, func)
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

function kernel.exec(path, env, priority, pid)
    if env == nil then
        env = _ENV
    end
    if priority == nil then
        priority = 0
    end
    eventsystem.push("kcall_start_process", path, env, priority, pid)
end

function kernel.killProcess(pid)
    eventsystem.push("kcall_kill_process", pid)
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
    panic("Failed to create Filesystem handler")
end

kernel.log("Created Filesystem handler.")
local rfs = kernel.fs
rfs.delete("/proc/*")
local file = rfs.open("/proc/computerinfo", "w")
if file ~= nil then
    file.write(kernel.name)
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

kernel.exec("/sbin/init", _ENV, 3, 1)

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
        if not kernel.fs.exists(path) then
            kernel.log("Failed to start process: File not found ("..path..")")
        else
            table.insert(kernel.process, {thread = coroutine.create(bios.native.nativeRun), PID = pid, path = path, priority = prio, env = env})
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
 
kernel.log("kernel_exit")

end, bios.debug.traceback)

if not s then
    panic("Kernel has exited on error."..e)
end