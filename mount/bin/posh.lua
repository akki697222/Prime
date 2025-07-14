---
--- posh - PrimeOS Shell
---

---@type os_env
_ENV = _ENV

local args = {...}

local function sh_err(program, message)
    std.print("posh: " .. program .. ": " .. message)
end

local env = {}
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
            if key and val then
                env[key] = val
            end
        end
    end
end

local paths = {}
if env["PATH"] then
    for entry in env["PATH"]:gmatch("[^:]+") do
        table.insert(paths, entry)
    end
end

local home = args[1] or "/root"
process.cwd(home)

local function findExecutable(command)
    local candidates = {command, command .. ".lua"}

    if fs.exists(command) then
        return command
    elseif fs.exists(command .. ".lua") then
        return command .. ".lua"
    end

    for _, base in ipairs(paths) do
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

while true do
    local p = process.cwd()
    if p == home then
        p = "~"
    end
    local colors = fbcon.ansicolors
    std.write(colors.green .. user.getCurrent().username .. colors.reset .. ":" .. colors.blue .. p .. colors.reset .. (kernel.currentUser == 0 and "#" or "$") .. " ")
    local input = std.readline()
    local args = {}
    for v in string.gmatch(input, "%S+") do
        table.insert(args, v)
    end
    local command = table.remove(args, 1) or ""
    if command == "cd" then
        local path = args[1] or ""
        if path:sub(1, 1) ~= "/" then
            path = fs.combine(kernel.getCurrentProcess().cwd, path)
        end
        if not fs.exists(path) then
            sh_err(command, path .. ": No such file or directory")
        else
            if not fs.isDirectory(path) then
                sh_err(command, path .. ": not a directory")
            else
                process.cwd(path)
            end
        end
    elseif command ~= "" then
        local exec = findExecutable(command)
        if exec then
            if fs.isDirectory(exec) then
                sh_err(command, "is a directory")
            else
                local pid, err = kernel.exec(exec, args)
                if pid == -1 then
                    sh_err(command, err)
                else
                    kernel.waitProcess(pid)
                end
            end
        else
            sh_err(command, "No such file or directory")
        end
    end
    coroutine.yield()
end
