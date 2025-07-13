loadfile = function(file)
    local addr, invoke = computer.getBootAddress(), component.invoke
    local handle, reason = invoke(addr, "open", file)
    assert(handle, reason)
    local buffer = ""
    repeat
        local data, reason = invoke(addr, "read", handle, math.huge)
        assert(data or not reason, reason)
        buffer = buffer .. (data or "")
    until not data
    invoke(addr, "close", handle)
    return load(buffer, "=" .. file, "bt", _G)
end

loadfile("system/kernel.lua")()