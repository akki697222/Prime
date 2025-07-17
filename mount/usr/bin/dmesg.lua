---@type os_env
_ENV = _ENV

for _, value in ipairs(os.getKernelLogBuffer()) do
    std.print(value)
end