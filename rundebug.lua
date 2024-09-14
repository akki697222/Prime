local partition = require("bios.partition")
local log = require("bios.log")
local fs_advanced = require("bios.filesystem")

local config = {}

local file = fs.open("build.json", "r")
config = textutils.unserialiseJSON(file.readAll())
file.close()

local buildversion = "0.0.1-"..config.builds..".craftos"

config.builds = config.builds + 1

local file = fs.open("build.json", "w+")
file.write(textutils.serialiseJSON(config))
file.close()

local temp_partition_name = "tmp"

log.info("Starting System Building...")

partition.init()
partition.delete(temp_partition_name)
partition.create(temp_partition_name, temp_partition_name)

local part = fs_advanced.create("part", temp_partition_name)

if not part then
    error("Build Failed. (Cannot create the filesystem partition handler.)")
end

part.copyFile("/build/*", "/")

print("Build ended. Press any key to start test.")
os.pullEvent("key")

shell.run(part.getLocalPath().."/startup "..buildversion.." "..part.getLocalPath().."/boot/kernel")

print("Test ended. Press any key to continue.")
os.pullEvent("key")

partition.delete(temp_partition_name)