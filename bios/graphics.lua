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

function graphics.setPosition(x, y)
    term.setCursorPos(x, y)
end

function graphics.getPosition()
    return term.getCursorPos()
end

return graphics