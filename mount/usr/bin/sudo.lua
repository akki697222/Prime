---@type os_env
_ENV = _ENV

local args = { ... }
local cmd = table.remove(args, 1)

local usr = user.getCurrent()

if not usr then
    error("Unable to get user")
end

if not cmd then
    std.print("(sudo help)")
    return
end

local max_attempt = 3
local attempt = 1
while true do
    std.write("[sudo] password for " .. usr.username .. ": ")
    local pass = std.readline(true)
    if user.checkPasswordCorrect(usr.username, pass) then
        local exec = os.findExecutable(cmd, os.getpath())
        if not exec then
            std.print("sudo: " .. cmd .. ": command not found")
        else
            local pid, err = process.exec(exec, args)
            if pid == -1 and err then
                std.print("sudo: " .. cmd .. ": ".. err)
            else
                os.waitProcess(pid)
            end
        end
        return
    else
        if attempt >= max_attempt then
            std.print("sudo: 3 incorrect password attempts")
            return
        else
            std.print("Sorry, try again.")
        end
        attempt = attempt + 1
    end
end
