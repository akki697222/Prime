---------------------------------------------------------
--- OS API (replaces kernel api for usermode program) ---
---------------------------------------------------------

---@type onix_kernel_mode_env
_ENV = _ENV

local _os = os
---@class os: oc_os_lib
local os = {}

os.clock = _os.clock
os.date = _os.date
os.difftime = _os.difftime

function os.time()
    return getRealTime()
end

function os.uptime()
    return getRealTime() - bootRealTime
end

function os.difftime(a, b)
    return _os.difftime(a, b)
end

function os.date(format, time)
    return _os.date(format, time)
end

function os.clock()
    return _os.clock()
end

function os.encodeTable(tbl, noreturn)
    local buffer = {}
    local i = 0
    local function write(str)
        i = i + 1
        buffer[i] = str
    end

    local function encode(tbl)
        write("{")
        for key, value in pairs(tbl) do
            local t = type(value)
            local keystr

            if type(key) == "number" then
                keystr = "[" .. key .. "]="
            elseif type(key) == "string" then
                if key:find("[^%w_]") or key:match("^%d") then
                    keystr = "[\"" .. key .. "\"]=" 
                else
                    keystr = key .. "="
                end
            elseif key == nil then
                keystr = ""
            else
                error("Cannot encode key of type: " .. type(key))
            end

            write(keystr)

            if t == "number" then
                write(tostring(value))
            elseif t == "string" then
                write("\"" .. value .. "\"")
            elseif t == "boolean" then
                write(value and "true" or "false")
            elseif t == "table" then
                encode(value)
            else
                error("Cannot encode value of type: " .. t)
            end

            write(",")
        end
        write("}")
    end

    if not noreturn then write("return") end
    encode(tbl)

    local result = ""
    for idx = 1, i do
        result = result .. buffer[idx]
    end
    return result
end

function os.decodeTable(encoded_table)
    local f, e = load(encoded_table, "=", "bt", {})
    if not f then
        error("Failed to decode table: " .. e)
    else
        return f()
    end
end

function os.getenv(name)
    if fs.exists("/etc/environment") then
        local file, err = fs.open("/etc/environment")
        local content = file:readAll()
        file:close()

        for line in content:gmatch("[^\r\n]+") do
            line = line:match("^%s*(.-)%s*$")
            if line ~= "" and not line:match("^#") then
                local key, val = line:match('^([%w_]+)%s*=%s*"(.-)"$')
                if not key then
                    key, val = line:match('^([%w_]+)%s*=%s*(.-)$')
                end
                if key and val and key == name then
                    return val
                end
            end
        end
    end
    return nil
end

function os.getpath()
    local paths = {}
    local PATH = os.getenv("PATH")
    if PATH then
        for entry in PATH:gmatch("[^:]+") do
            table.insert(paths, entry)
        end
    end
    return paths
end

---@return integer #current tty id
function os.getty()
    if kernel.getCurrentProcess() then
        return kernel.getCurrentProcess().tty
    else
        return kernel.tty
    end
end

function os.getKernelLogBuffer()
    return kernel.log_buffer
end

function os.reboot()
    kernel.shutdown(true)
end

---@param pid integer
---@param timeout? integer
function os.waitProcess(pid, timeout)
    timeout = timeout or math.huge
    while true do
        timer.set(pid + 10000, timeout)
        if not kernel.getProcess(pid) then
            return false
        elseif timer.check(pid + 10000) then
            return true
        end
        coroutine.yield()
    end
end

function os.findExecutable(command, findpath)
    local candidates = { command, command .. ".lua" }

    if fs.exists(command) then
        return command
    elseif fs.exists(command .. ".lua") then
        return command .. ".lua"
    end

    for _, base in ipairs(findpath) do
        for _, name in ipairs(candidates) do
            local full = fs.combine(base, name)
            if fs.exists(full) then
                return full
            end
        end
    end

    local cwd = process.cwd()
    for _, name in ipairs(candidates) do
        local full = fs.combine(cwd, name)
        if fs.exists(full) then
            return full
        end
    end

    return nil
end

return os, "os"