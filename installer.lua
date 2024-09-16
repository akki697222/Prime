term.clear()
term.setCursorPos(1,1)
print("Prime - Firmware Setup")
print("!Warning! All files on the disk will be initialized. Are you sure? (Y or N)")
local function select()
    term.setCursorPos(1,3)
    local input = read()
    if input == "Y" or input == "y" then
        return true
    elseif input == "N" or input == "n" then
        return false
    else
        select()
    end
end

if select() then
    local listd = fs.list("/")
    if listd then
        for index, value in ipairs(listd) do
            print(value)
            if not value == "installer.lua" then
                fs.delete(value)
            end
        end
    end
    fs.makeDir("/bios")
    local list = {
        "bios",
        "computer",
        "device",
        "filesystem",
        "graphics",
        "io",
        "log",
        "partition"
    }
    shell.setDir("/bios")
    for index, value in ipairs(list) do
        shell.run("wget https://raw.githubusercontent.com/akki697222/Prime/main/bios/"..value..".lua")
    end
    shell.setDir("/")

else
    term.clear()
    term.setCursorPos(1,1)
    print("Install Canceled")
end