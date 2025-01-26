local partition = require("bios.partition")
local log = require("bios.log")
local fs_advanced = require("bios.filesystem")
local bios = require("bios.bios")

local temp_partition_name = "primeos"
local temp_bootsector_name = "bootsector"

log.info("Starting System Building...")

partition.init()

partition.delete(temp_partition_name)
partition.delete(temp_bootsector_name)

partition.create(temp_partition_name, temp_partition_name, false)
partition.create(temp_bootsector_name, temp_bootsector_name, true)

local boot = fs_advanced.create("part", temp_bootsector_name)
local part = fs_advanced.create("part", temp_partition_name)

if not part or not boot then
    error("Build Failed. (Cannot create the filesystem partition handler.)")
end
local function copyDir(sourceDir, destDir)
    local files = fs.list(sourceDir)

local function copyFolder(source, dest)
    if not fs.exists(dest) then
        fs.makeDir(dest)
    end

    local files = fs.list(source)

    for _, file in ipairs(files) do
        local sourcePath = fs.combine(source, file)
        local destPath = fs.combine(dest, file)

        if fs.isDir(sourcePath) then
            copyFolder(sourcePath, destPath)
        else
            if fs.exists(sourcePath) then
                fs.copy(sourcePath, destPath)
            end
        end
    end
end

for _, file in ipairs(files) do
    local sourcePath = fs.combine(sourceDir, file)
    local destPath = fs.combine(destDir, file)

    if fs.isDir(sourcePath) then
        fs.makeDir(destPath)
        copyFolder(sourcePath, destPath)
    else
        if fs.exists(sourcePath) then
            fs.copy(sourcePath, destPath)
        end
    end
end
    
end
local s, e = pcall(function ()
    fs.copy("/build/bootloader/bootloader.lua", boot.getLocalPath().."/bootloader.lua")
    copyDir("/build/os", part.getLocalPath())
end)
if not s then
    partition.delete(temp_partition_name)
    partition.delete(temp_bootsector_name)
    local file = fs.open("error", "w+")
    file.write(e)
    file.close()
    error(e, 0)
end

print("Build ended. Press any key to start test.")
os.pullEvent("key")

local s, e = xpcall(function ()
    bios.run()
end, debug.traceback)

if not s then
    print("Exited on Error")
    print(e)
end

print()
print("Test ended. Press any key to continue.")
os.pullEvent("key")

partition.delete(temp_partition_name)
partition.delete(temp_bootsector_name)