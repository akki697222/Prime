partition.mount("primeos")
local fs = filesystem.create("mount", "primeos")
if fs.exists("/boot/kernel.lua") then
    bios.execute(fs.getLocalPath().."/boot/kernel.lua")
else
    printf("OS not found.")
end