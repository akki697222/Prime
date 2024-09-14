local log = require("unixcc.bios.log")
local disable = true
return function ()
    local file = fs.open("/unixcc/boot/bootloader_entry.json", "r")
    if not file then
        log.error("Can't found file 'bootloader_entry.json'")
        return
    end
    local entries = textutils.unserialiseJSON(file.readAll())
    file.close()
    if disable then
        print("disabled")
        shell.run("/testall.lua")
        return
    end
    log.info("Loaded entries.")
    local function drawEntry()
        local idx = 1
        local entries_array = {}
        term.clear()
        term.setCursorPos(1,1)
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.black)
        print("Simple Bootloader\n")
        for key, value in pairs(entries) do
            print(idx..". "..key)
            table.insert(entries_array, value)
            idx = idx + 1
        end
        io.write("\nBoot Entry ")
        local input = read()
        if tonumber(input) then
            input = tonumber(input)
            if entries_array[input] then
                term.clear()
                term.setCursorPos(1,1)
                term.setTextColor(colors.white)
                term.setBackgroundColor(colors.black)
                shell.run(entries_array[input])
            else
                drawEntry()
            end
        else
            drawEntry()
        end
    end
    drawEntry()
end