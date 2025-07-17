---@type os_env
_ENV = _ENV

process.setSignalHandler(process.signals.SIGINT, function ()
    -- nop
end)

while true do
    std.write("Login: ")
    local username = std.readline()

    std.write("Password: ")
    local password = std.readline(true)
    std.print()
    local usr = user.switchuser(username, password)
    if usr then
        local shell_pid, err = process.exec(usr.shell, {usr.home}, 0)
        if shell_pid == -1 then
            std.print("login: " .. usr.shell .. ": " .. err)
        else
            os.waitProcess(shell_pid)
        end
    else
        std.print("Login failed.\n")
    end
end