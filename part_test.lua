local partition = require("bios.partition")
local filesystem = require("bios.filesystem")

partition.init()

partition.create("Test Partition", "testPart")

os.pullEvent("key")

partition.delete("Test Partition")

partition.create("Test2", "test2")
partition.create("Test3", "test3", true)

local handler = filesystem.create("part", "Test2")
if handler then
    handler.mkdir("testdir")
    local file = handler.open("/testdir/akki.txt", "w+")
    file.write("akki")
    file.close()
end

local handler2 = filesystem.create("part", "Test3")
if handler2 then
    handler2.mkdir("testdir")
    local file = handler2.open("/testdir/akki.txt", "w+")
    if file then
        file.write("akki")
        file.close()
    end
end

os.pullEvent("key")

partition.delete("Test2")
partition.delete("Test3")