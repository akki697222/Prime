---@class graphics
local graphics = {}

--- &x (16bit color code) to change color. (Special codes: &r(Reset colors to default))
--- example: graphics.colorPrint("&eRed Color&0")
function graphics.colorWrite(...)
    local i = 1
    while i <= #... do
        local char = (...):sub(i, i)

        if char == "&" then
            local nextChar = (...):sub(i + 1, i + 1)
            if nextChar:match("%x") then
                term.setTextColor(colors.fromBlit(tostring(nextChar)))
                i = i + 1
            end
        else
            io.write(char)
        end
        i = i + 1
    end
end

--- &x (16bit color code) to change color. (Special codes: &r(Reset colors to default))
--- example: graphics.colorPrint("&eRed Color&0")
function graphics.colorPrint(...)
    local i = 1
    while i <= #... do
        local char = (...):sub(i, i)

        if char == "&" then
            local nextChar = (...):sub(i + 1, i + 1)
            if nextChar:match("%x") then
                term.setTextColor(colors.fromBlit(tostring(nextChar)))
                i = i + 1
            elseif nextChar == "r" then
                term.setTextColor(colors.white)
                i = i + 1
            end
        else
            io.write(char)
        end
        i = i + 1
    end
    print()
end

function graphics.print(...)
    print(...)
end

function graphics.write(...)
    io.write(...)
end

function graphics.replaceLine(line, ...)
    local x, y = term.getCursorPos()
    term.setCursorPos(1, line)
    term.clearLine()
    io.write(...)
    term.setCursorPos(x, y)
end

function graphics.setPosition(x, y)
    term.setCursorPos(x, y)
end

function graphics.setTextColor(color)
    term.setTextColor(color)
end

function graphics.setBackgroundColor(color)
    term.setBackgroundColor(color)
end

function graphics.setPaletteColor(color, code)
    term.setPaletteColor(color, code)
end

function graphics.clear()
    term.clear()
end

function graphics.reset()
    term.clear()
    term.setCursorPos(1,1)
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
end

---@return number cursorX, number cursorY 
---Same as term.getCursorPos()
function graphics.getPosition()
    return term.getCursorPos()
end

return graphics