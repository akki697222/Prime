local eventsystem = require("system.event")
local graphics = require("system.monitor")
local ENTER_CODE = 28;
local BACKSPACE_CODE = 14;
local function read()
    local text = "";
    local close = false;
    graphics.setBlink(true)
    eventsystem.addEventHandler(function(e)
        if close then return end;
        local character = e[2]
        if e[1] == "char" then
            text = text .. character;
            write(character)
        elseif e[1] == "key" then
            if character == ENTER_CODE then
                printf();
                graphics.setBlink(false);
                close = true;
            end
        end
    end)
    return text;
end

return read
