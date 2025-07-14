---@type os_env
_ENV = _ENV

local max_attempts = 3
local attempts = 0

while attempts < max_attempts do
    std.write("Login: ")
    local username = std.readline()

    std.write("Password: ")
    local password = std.readline(true)
    std.print()

    if not user.login(username, password) then
        std.print("Login failed.\n")
        attempts = attempts + 1
    else
        break
    end
end