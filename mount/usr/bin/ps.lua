---@type os_env
_ENV = _ENV

local process_list = process.getProcesses()

local tbl = {{"USER", "PID", "THREADS", "TTY", "STAT", "COMMAND"}}

for index, value in ipairs(process_list) do
    table.insert(tbl, {
        user.getUserByUID(value.euid).username,
        value.pid,
        #process.getProcessThreads(value.pid),
        value.tty,
        coroutine.status(value.thread),
        value.path
    })
end

styledPrint(tbl)