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

local s, e = xpcall(loadfile("system/kernel.lua"), debug.traceback)
if not s then
    local gpu = component.proxy(component.list("gpu")())

    local x, y = 1, 2
    local width, height = gpu.getResolution()

    gpu.setForeground(0xFFFFFF)
    gpu.setBackground(0xFF0000)
    gpu.fill(1, 1, width, height, " ")
    gpu.set(1, 1, "FATAL ERROR")

    for i = 1, #e do
        local c = e:sub(i, i)
        if c == "\n" then
            y = y + 1
            x = 1
            if y > height then
                break -- 画面外なら表示終了
            end
        else
            gpu.set(x, y, c)
            x = x + 1
            if x > width then
                x = 1
                y = y + 1
                if y > height then
                    break
                end
            end
        end
    end

    while true do
        computer.pullSignal()
    end
end
