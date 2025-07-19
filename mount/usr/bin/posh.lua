---
--- posh - PrimeOS Shell
---

---@type os_env
_ENV = _ENV

local args = {...}

local function sh_err(program, message)
    std.print("posh: " .. program .. ": " .. message)
end

local home = args[1] or "/root"
process.cwd(home)
local pwd = home

process.setSignalHandler(process.signals.SIGINT, function ()
    -- nop
end)

while true do
    local p = pwd
    if p == home then
        p = "~"
    end
    local colors = fbcon.ansicolors
    std.write(colors.green .. user.getCurrent().username .. colors.reset .. ":" .. colors.blue .. p .. colors.reset .. (user.checkRoot() and "#" or "$") .. " ")
    local input = std.readline()
    local args = {}
    for v in string.gmatch(input, "%S+") do
        table.insert(args, v)
    end
    local command = table.remove(args, 1) or ""
    if command == "cd" then
        local path = args[1] or ""
        if path:sub(1, 1) ~= "/" then
            path = fs.combine(process.cwd(), path)
        end
        if not fs.exists(path) then
            sh_err(command, path .. ": No such file or directory")
        else
            if not fs.isDirectory(path) then
                sh_err(command, path .. ": not a directory")
            else
                local newDir, err = process.cwd(path)
                if not newDir then
                    sh_err(command, path .. ": " .. err)
                else
                    pwd = path
                end
            end
        end
    elseif command ~= "" then
        local exec = os.findExecutable(command, os.getpath())
        if exec then
            if fs.isDirectory(exec) then
                sh_err(command, "is a directory")
            else
                local pid, err = process.exec(exec, args)
                if pid == -1 then
                    sh_err(command, err)
                else
                    os.waitProcess(pid)
                end
            end
        else
            sh_err(command, "No such file or directory")
        end
    end
    coroutine.yield()
end
