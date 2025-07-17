---@type oc_env
_ENV = _ENV

---@param env? table
loadfile = function(file, env)
    local addr, invoke = computer.getBootAddress(), component.invoke
    local handle, reason = invoke(addr, "open", file)
    if not handle then
        return nil, reason
    end

    local buffer = ""
    while true do
        local data, reason = invoke(addr, "read", handle, math.huge)
        if not data then
            if reason then
                invoke(addr, "close", handle)
                return nil, reason
            else
                break
            end
        end
        buffer = buffer .. data
    end
    invoke(addr, "close", handle)

    local chunk, err = load(buffer, "=" .. file, "bt", env or _G)
    if not chunk then
        return nil, err
    end
    return chunk
end

function dofile(file, env)
    local f, e = loadfile(file, env)
    if not f then
        error(e)
    end
    return f()
end

local s, e = xpcall(loadfile("system/main.lua"), debug.traceback)
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
