---------------------------------
--- Kernel Main loop and APIs ---
---------------------------------

---@type onix_kernel_mode_env
_ENV = _ENV

---@class kernel
local kernel = {}

---@class process_entry
---@field thread thread process coroutine thread
---@field pid integer process id
---@field tid integer thread id
---@field pgid integer process group id
---@field path string process executable path
---@field env table process lua environment
---@field nice integer nice value(process priority)
---@field parent integer parent process pid
---@field arguments table process arguments
---@field uid integer user id
---@field gid integer group id
---@field euid integer effective user id
---@field suid integer saved user id
---@field cwd string current working directory
---@field signals integer[] process signal buffer
---@field sig_handlers table<integer, function> process signal handlers
---@field tty integer tty device id

kernel._version = "1.2.1-dev-OC in " .. _VERSION
---@type table<process_entry>
kernel.process = {}
kernel.threads = {}
kernel.currentProcess = 1
kernel.currentUser = 0
kernel.activeTerminal = 0
---@type table<terminal>
kernel.terminals = {}
kernel.log_buffer = {}
kernel._envs = {}

local used_pids = {}

local function kernel_get_default_signal_handlers(pid)
    local kernel_sig_handlers = {
        [2] = function()
            kernel.killProcess(pid)
        end,
        [15] = function()
            kernel.killProcess(pid)
        end
    }
    return kernel_sig_handlers
end

local function kernel_get_ignore_termination_signal_handlers()
    local kernel_sig_handlers = {
        [2] = function()
            kernel.killProcess(pid)
        end,
        [15] = function()
            kernel.killProcess(pid)
        end
    }
    return kernel_sig_handlers
end

local function kernel_get_pid()
    local pid = 1
    while true do
        if not used_pids[pid] then
            used_pids[pid] = true
            return pid
        end
        pid = pid + 1
    end
end

---@class std
---@field print fun(value: any)
---@field printf fun(fmt: string, ...)
---@field write fun(value: any)
---@field read fun(hideChars: boolean?): string
---@field readline fun(hideChars: boolean?): string
kernel.std = {}
kernel.tty = 1

---@return os_env
function kernel.getEnv()
    ---@type tty_mod|nil
    local tty_mod = module.getApi("tty")
    ---@type vt_mod|nil
    local vt_mod = module.getApi("vt")
    ---@type std
    local std
    if tty_mod and vt_mod then
        if kernel.getCurrentProcess() then
            local ttyid = kernel.getCurrentProcess().tty
            kernel.createTTY(ttyid)
            std = tty_mod.get(ttyid).terminal:std()
        else
            kernel.createTTY(1)
            std = tty_mod.get(1).terminal:std()
        end
    else
        std = fbcon.getstd()
    end
    ---@class os_env
    local env = {
        _G = {},
        _VERSION = _VERSION,
        assert = assert,
        error = error,
        getmetatable = getmetatable,
        ipairs = ipairs,
        load = load,
        next = next,
        pairs = pairs,
        pcall = pcall,
        rawequal = rawequal,
        rawget = rawget,
        rawlen = rawlen,
        rawset = rawset,
        select = select,
        setmetatable = setmetatable,
        tonumber = tonumber,
        tostring = tostring,
        nonnil = nonnil,
        type = type,
        xpcall = xpcall,
        bit32 = bit32,
        coroutine = coroutine,
        debug = {
            getinfo = debug.getinfo,
            traceback = debug.traceback,
            getlocal = debug.getlocal,
            getupvalue = debug.getupvalue
        },
        math = math,
        string = string,
        table = table,
        utf8 = utf8,
        unicode = unicode,
        checkArg = checkArg,
        -- kernel module/globals
        fs = fs,
        device = device,
        ---@type std
        std = std,
        printk = printk,
        module = module,
        ---@type fbcon
        fbcon = fbcon,
        ---@type event
        event = event,
        ---@type os
        os = os,
        ---@type timer
        timer = timer,
        ---@type process
        process = process,
        argparse = argparse,
        ---@type
        user = user,
        ---@type group
        group = group,
        ---@type permission
        permission = permission,
        json = json,
        styledPrint = function(printTable)
            local len = {}
            for _, row in ipairs(printTable) do
                for i, col in ipairs(row) do
                    local str = tostring(col)
                    len[i] = math.max(len[i] or 0, #str)
                end
            end
            local result = ""
            for _, row in ipairs(printTable) do
                for i, col in ipairs(row) do
                    local str = tostring(col)
                    result = result .. str .. (" "):rep(len[i] - #str + 1)
                end
                result = result .. "\n"
            end
            kernel.std.write(result)
        end
    }

    for key, value in pairs(kernel._envs) do
        env[key] = value
    end

    env._G = env

    return env
end

function kernel.registerEnv(name, object)
    kernel._envs[name] = object
end

---@param pid integer
---@param sig integer
function kernel.signal(pid, sig)
    ---@type process_entry
    local proc = kernel.getProcess(pid)
    ---@type signal
    local signals = process.signals
    if not proc then
        return false
    end
    if sig > 31 or sig < 1 then
        return false
    end
    if sig == signals.SIGKILL or sig == signals.SIGSTOP then
        kernel.killProcess(pid)
    else
        table.insert(proc.signals, sig)
    end
end

local function kernel_wrap_with_traceback(func)
    return coroutine.create(function(...)
        local function err_handler(err)
            return debug.traceback(err, 2)
        end
        local ok, result
        if GLOBAL_PRECISE_TRACEBACK then
            ok, result = xpcall(func, err_handler, ...)
        else
            ok, result = pcall(func, ...)
        end
        if not ok then
            error(result)
        end
        return result
    end)
end

---@param path string
---@param args table|nil
---@param nice integer|nil
---@param env table|nil
---@param pid integer|nil
function kernel.exec(path, args, nice, env, pid)
    path = fs.resolvePath(path)
    if not path then
        return -1, "resolvePath returned nil"
    end
    ---@type inode
    local attr = fs.attributes(path)
    if not fs.exists(path) then
        return -1, "No such file"
    end
    if not fs.canAction(path, "x") then
        return -1, "Permission Denied"
    end
    local func, err = loadfile(path)
    if not func then
        return -1, err
    end
    local pid = pid or kernel_get_pid()
    if not func then return end
    local cwd = "/"
    if kernel.getCurrentProcess() then
        cwd = kernel.getCurrentProcess().cwd
    end
    local parent = kernel.getCurrentProcess() or { uid = 0, gid = 0, euid = 0, suid = 0 }
    local euid = parent.euid
    local suid = parent.suid
    if permission.canSetUID(attr.mode) then
        euid = attr.uid
        euid = attr.uid
    end
    ---@type process_entry
    local entry = {
        thread = kernel_wrap_with_traceback(func),
        pid = pid,
        tid = pid,
        pgid = parent.pgid or 1,
        path = path,
        env = env or kernel.getEnv(),
        nice = nice or 3,
        parent = kernel.currentProcess,
        arguments = args or {},
        cwd = cwd,
        uid = parent.uid,
        gid = parent.gid,
        euid = euid,
        suid = suid,
        signals = {},
        sig_handlers = kernel_get_default_signal_handlers(pid),
        tty = 1
    }

    table.insert(kernel.process, entry)

    return pid
end

function kernel.shutdown(reboot)
    event.push("shutdown", reboot)
end

---@param func function
---@param name string
---@param args table|nil
---@param nice integer|nil
---@param env table|nil
---@param pid integer|nil
function kernel.execf(func, name, args, nice, env, pid)
    local pid = pid or kernel_get_pid()
    if not func then return end
    local cwd = "/"
    if kernel.getCurrentProcess() then
        cwd = kernel.getCurrentProcess().cwd
    end
    local parent = kernel.getCurrentProcess() or { uid = 0, gid = 0, euid = 0, suid = 0 }
    ---@type process_entry
    local entry = {
        thread = kernel_wrap_with_traceback(func),
        pid = pid,
        tid = pid,
        pgid = parent.pgid or 1,
        path = "[" .. name .. "]",
        env = env or kernel.getEnv(),
        nice = nice or 3,
        parent = kernel.currentProcess,
        arguments = args or {},
        cwd = cwd,
        uid = parent.uid,
        gid = parent.gid,
        euid = parent.euid,
        suid = parent.suid,
        signals = {},
        sig_handlers = kernel_get_default_signal_handlers(pid),
        tty = 1
    }

    table.insert(kernel.process, entry)

    return pid
end

function kernel.killProcess(pid)
    for index, value in ipairs(kernel.process) do
        if value.pid == pid then
            table.remove(kernel.process, index)
            return true
        end
    end
    return false
end

function kernel.getProcess(pid)
    for index, value in ipairs(kernel.process) do
        if value.pid == pid then
            return value
        end
    end
end

function kernel.getThread(pid, tid)
    for index, value in ipairs(kernel.threads) do
        if value.pid == pid and value.tid == tid then
            return value
        end
    end
end

function kernel.killThread(pid, tid)
    for index, value in ipairs(kernel.threads) do
        if value.pid == pid and value.tid == tid then
            table.remove(kernel.threads, index)
            return true
        end
    end
    return false
end

---@param func fun(ev: table)
function kernel.createEventThread(func, name, nice)
    local pid = kernel_get_pid()
    if not func then return end
    local parent = kernel.getCurrentProcess() or { uid = 0, gid = 0, euid = 0, suid = 0 }
    ---@type process_entry
    local entry = {
        thread = coroutine.create(func),
        pid = 2,
        tid = pid,
        pgid = 2,
        path = "[" .. name .. "]",
        env = kernel.getEnv(),
        nice = nice or 3,
        parent = 2,
        arguments = {},
        cwd = "/",
        uid = parent.uid,
        gid = parent.gid,
        euid = parent.euid,
        suid = parent.suid,
        signals = {},
        sig_handlers = kernel_get_ignore_termination_signal_handlers(),
        event_thread_func = func,
        tty = 1
    }

    table.insert(kernel.threads, entry)

    return pid
end

function kernel.createTTY(tty_id)
    ---@type tty_mod
    local tty_mod = nonnil(module.getApi("tty"))
    ---@type vt_mod
    local vt_mod = nonnil(module.getApi("vt"))
    local tty = tty_mod.get(tty_id)
    if not tty then
        tty = tty_mod.create(tty_id)
    end
    if not tty:isOpen() then
        vt_mod.create(tty_id)
    end
end

---@param func fun(ev: table)
function kernel.createThread(func, name, nice)
    if not user.checkRoot() then
        error("Operation not permitted")
    end
    local pid = kernel_get_pid()
    if not func then return end
    ---@type process_entry
    local entry = {
        thread = coroutine.create(func),
        pid = 2,
        tid = pid,
        pgid = 2,
        path = "[" .. name .. "]",
        env = kernel.getEnv(),
        nice = nice or 3,
        parent = 2,
        arguments = {},
        cwd = "/",
        uid = 0,
        gid = 0,
        euid = 0,
        suid = 0,
        signals = {},
        sig_handlers = kernel_get_ignore_termination_signal_handlers(),
        tty = 1
    }

    table.insert(kernel.threads, entry)

    return pid
end

function kernel.getCurrentProcess()
    for index, value in ipairs(kernel.process) do
        if value.pid == kernel.currentProcess then
            return value
        end
    end
end

function kernel.main()
    printk("starting init process...")
    kernel.currentUser = 0
    event.addEventHandler(function(ev)
        if ev[1] == "shutdown" then
            fbcon.early_output = true
            fbcon.gpu = component.proxy(component.list("gpu")())
            printk("Shutting down...")

            local process_list = {}
            for _, proc in ipairs(kernel.process) do
                table.insert(process_list, proc)
            end

            table.sort(process_list, function(a, b)
                return a.pid > b.pid
            end)

            for _, proc in ipairs(process_list) do
                printk("Sending SIGTERM to process " .. proc.pid .. " (" .. proc.path .. ")")
                kernel.signal(proc.pid, process.signals.SIGTERM)
                if os.waitProcess(proc.pid, 5) then
                    printk("Timeout process " .. proc.pid)
                    kernel.killProcess(proc.pid)
                else
                    printk("Successfully terminated process " .. proc.pid)
                end
            end

            module.unloadAll()
            fs.closeAllHandles()
            --computer.shutdown(ev[2])
        end
    end)
    fs.createLink("/usr/bin", "/bin")
    fs.createLink("/usr/sbin", "/sbin")
    fs.createLink("/usr/lib", "/lib")
    local pid, err = kernel.exec(INIT_EXEC, { GLOBAL_OS_NAME }, 0, _ENV, INIT_PID)
    if pid == -1 then
        panic("failed to start init process", err)
    end
    ---@param proc process_entry
    local function process_signals(proc, proc_idx)
        local handlers = {}
        for sig, handler in pairs(proc.sig_handlers) do
            handlers[tostring(sig)] = handler
        end
        for index, value in ipairs(proc.signals) do
            if value == 19 or value == 9 then
                table.remove(kernel.process, proc_idx)
            end
            local handle = handlers[tostring(value)]
            if type(handle) == "function" then
                handle()
            end
        end
    end
    while true do
        local ev = { computer.pullSignal(0.05) }
        table.sort(kernel.process, function(a, b)
            return a.nice < b.nice
        end)
        local dead_threads = {}
        for index, value in ipairs(kernel.threads) do
            local s, e
            if type(value.event_thread_func) == "function" then
                if coroutine.status(value.thread) == "dead" then
                    value.thread = coroutine.create(value.event_thread_func)
                end
                s, e = coroutine.resume(value.thread, ev)
            else
                if coroutine.status(value.thread) == "dead" then
                    table.insert(dead_threads, index)
                end
                s, e = coroutine.resume(value.thread, ev)
            end
            if not s then
                printk("Kernel thread " .. value.tid .. " Exited on error: " .. e)
            end
        end
        ---@type integer, process_entry
        for index, value in ipairs(kernel.process) do
            kernel.currentProcess = value.pid
            if coroutine.status(value.thread) == "dead" then
                table.remove(kernel.process, index)
            else
                process_signals(value, index)
                local s, e
                if value.pid == 2 then
                    s, e = coroutine.resume(value.thread, ev)
                else
                    s, e = coroutine.resume(value.thread, table.unpack(value.arguments))
                end
                if not s then
                    printk("Process " .. value.pid .. " Exited on error: " .. e)
                end
            end
        end
        for index, value in ipairs(dead_threads) do
            table.remove(kernel.threads, value)
        end
        fbcon.update()
    end
end

return kernel, "kernel"