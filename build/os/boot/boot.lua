partition.mount("primeos")
---@type filesystem_handler|nil
local fs = filesystem.create("mount", "primeos")
if fs == nil then
    printf("System partition not found.")
else
    if fs.exists("/boot/kernel.lua") then
        bios.execute(fs.getLocalPath().."/boot/kernel.lua")
    else
        printf("System not found.")
    end
end