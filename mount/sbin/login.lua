---@type os_env
_ENV = _ENV

while true do
    std.write("Login: ")
    local username = std.readline()

    std.write("Password: ")
    local password = std.readline(true)
    std.print()
    local usr = user.switchuser(username, password)
    if usr then
        local shell_pid = process.exec(usr.shell, { usr.home }, 0)
        os.waitProcess(shell_pid)
    else
        std.print("Login failed.\n")
    end
end