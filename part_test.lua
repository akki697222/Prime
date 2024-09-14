partition.init()

partition.create("Test Partition", "testPart")

bios.pullEvent("key")

partition.delete("Test Partition")

partition.create("Test2", "test2")

local handler = fs.create("part", "Test2")
if handler then
    handler.mkdir("testdir")
    local file = handler.open("/testdir/akki.txt", "w+")
    file.write("akki")
    file.close()
end

bios.pullEvent("key")

partition.delete("Test2")