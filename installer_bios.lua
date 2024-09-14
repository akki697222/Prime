term.clear()
term.setCursorPos(1,1)
print("CC:Tweaked Advanced BIOS - Setup")
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

local function get(file)
    shell.run("wget ")
end

if select() then
    fs.makeDir("/bios")
    
else
    term.clear()
    term.setCursorPos(1,1)
    print("Install Canceled")
end