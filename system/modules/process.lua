-------------------
--- Process API ---
-------------------

---@type onix_kernel_mode_env
_ENV = _ENV

---@class process
local process = {}

---@class signal
process.signals = {
    SIGHUP    = 1,  -- Hangup detected on controlling terminal or death of controlling process
    SIGINT    = 2,  -- Interrupt from keyboard (Ctrl+C)
    SIGQUIT   = 3,  -- Quit from keyboard
    SIGILL    = 4,  -- Illegal Instruction
    SIGTRAP   = 5,  -- Trace/breakpoint trap
    SIGABRT   = 6,  -- Abort signal from abort(3)
    SIGBUS    = 7,  -- Bus error (bad memory access)
    SIGFPE    = 8,  -- Floating point exception
    SIGKILL   = 9,  -- Kill signal (cannot be caught or ignored)
    SIGUSR1   = 10, -- User-defined signal 1
    SIGSEGV   = 11, -- Invalid memory reference
    SIGUSR2   = 12, -- User-defined signal 2
    SIGPIPE   = 13, -- Broken pipe: write to pipe with no readers
    SIGALRM   = 14, -- Timer signal from alarm(2)
    SIGTERM   = 15, -- Termination signal
    SIGSTKFLT = 16, -- Stack fault on coprocessor (obsolete)
    SIGCHLD   = 17, -- Child stopped or terminated
    SIGCONT   = 18, -- Continue if stopped
    SIGSTOP   = 19, -- Stop process (cannot be caught or ignored)
    SIGTSTP   = 20, -- Stop typed at tty (Ctrl+Z)
    SIGTTIN   = 21, -- tty input for background process
    SIGTTOU   = 22, -- tty output for background process
    SIGURG    = 23, -- Urgent condition on socket
    SIGXCPU   = 24, -- CPU time limit exceeded
    SIGXFSZ   = 25, -- File size limit exceeded
    SIGVTALRM = 26, -- Virtual alarm clock
    SIGPROF   = 27, -- Profiling timer expired
    SIGWINCH  = 28, -- Window resize signal
    SIGIO     = 29, -- I/O now possible
    SIGPWR    = 30, -- Power failure (System V)
    SIGSYS    = 31, -- Bad system call (SVr4)
}

function process.createKernelThread(func, name, nice)
    return kernel.createThread(func, name, nice)
end

function process.kill(pid)
    return kernel.killProcess(pid)
end

function process.cwd(path)
    if path then
        path = fs.resolvePath(path)
        if fs.canAction(path, "r") then
            kernel.getCurrentProcess().cwd = path
            return kernel.getCurrentProcess().cwd
        else
            return nil, "Permission Denied"
        end
    else
        return kernel.getCurrentProcess() and kernel.getCurrentProcess().cwd or "/"
    end
end

function process.getProcessThreads(pid)
    local procs = {}
    for index, value in ipairs(kernel.process) do
        if value.pid == pid and value.tid ~= pid then
            table.insert(procs, value)
        end
    end
    return procs
end

function process.getCurrent()
    return kernel.getCurrentProcess()
end

function process.getCurrentPID()
    return kernel.currentProcess
end

function process.getProcesses()
    return kernel.process
end

function process.seteuid(euid)
    ---@type process_entry
    local proc = kernel.getCurrentProcess()
    local inode = fs.attributes(proc.path)
    if not proc then
        return nil, "No current process"
    end
    if permission.canSetUID(inode.mode) and inode.uid == 0 or inode.gid == 0 then
        return true
    end
    if euid == proc.uid or euid == proc.suid then
        proc.euid = euid
        return true
    else
        return nil, "Permission denied"
    end
end

function process.geteuid()
    local proc = kernel.getCurrentProcess()
    if not proc then
        return nil, "No current process"
    end
    return proc.euid
end

function process.exec(path, args, nice, env, pid)
    return kernel.exec(path, args, nice, env, pid)
end

function process.execf(func, name, args, nice, env, pid)
    return kernel.execf(func, name, args, nice, env, pid)
end

---@param sig integer
---@param handler fun()
function process.setSignalHandler(sig, handler)
    local proc = kernel.getCurrentProcess()
    if not proc then
        error("No current process")
    end
    if type(sig) ~= "number" then
        error("Signal must be a number")
    end
    if type(handler) ~= "function" then
        error("Handler must be a function")
    end
    proc.sig_handlers[tostring(sig)] = handler
end

function process.signal(pid, sig)
    return kernel.signal(pid, sig)
end

---send signal to current process
function process.signalCurrent(sig)
    return kernel.signal(kernel.currentProcess, sig)
end

return process, "process"