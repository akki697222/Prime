local disk_data = "/.local_disk/"
local log = require("bios.log")
local part = {}

function part.init()
    log.info("Starting Partition initialize...")
    if not fs.exists(disk_data) then
        fs.makeDir(disk_data)
    end
    if not fs.exists(disk_data .. "partitions.json") then
        local file = fs.open(disk_data .. "partitions.json", "w")
        file.write(textutils.serialiseJSON({}))
        file.close()
    end
    log.info("Partition initialized.")
end

local function getPartitions()
    local file = fs.open(disk_data .. "partitions.json", "r")
    if not file then
        file = fs.open(disk_data .. "partitions.json", "w")
        file.write("[]")
    end
    local data = textutils.unserialiseJSON(file.readAll())
    file.close()
    if not data then
        data = {}
    end
    return data
end

local function getPartition(name)
    local data = getPartitions()
    for index, value in ipairs(data) do
        if value.name == name then
            return value, index
        end
    end
end

local function checkPartitionExists(name)
    local data = getPartitions()
    for index, value in ipairs(data) do
        if value.name == name then
            return true
        end
    end
    return false
end

local function addPartitionToInfo(name, path)
    local data = getPartitions()
    if checkPartitionExists(name) then
        local info = debug.getinfo(2, "nl")
        log.errorFunc(info.currentline, info.name, "A partition with that name already exists.")
        return false
    end
    table.insert(data, { name = name, path = path })
    local file = fs.open(disk_data .. "partitions.json", "w+")
    file.write(textutils.serialiseJSON(data))
    file.close()
    return true
end

local function overWritePartitionInfo(tables)
    local file = fs.open(disk_data .. "partitions.json", "w+")
    file.write(textutils.serialiseJSON(tables))
    file.close()
end

function part.getData(name)
    local data, _ = getPartition(name)
    return data
end

function part.create(name, path)
    local fullpath = disk_data .. path
    log.info("Creating Partition '" .. name .. "' in path '" .. fullpath .. "'")
    if path:match("[^a-zA-Z0-9]") then
        log.error("Partition paths must contain only alphanumeric characters (a-z, A-Z, 0-9)")
        return
    end
    if not name or name == "" then
        log.error("Partition name cannot be empty.")
        return
    end
    if addPartitionToInfo(name, fullpath) then
        fs.makeDir(fullpath)
    end
    log.info("Created Partition '" .. name .. "'")
end

function part.delete(name)
    log.info("Deleting Partition '" .. name .. "'")
    if not getPartition(name) then
        local info = debug.getinfo(2, "nl")
        log.errorFunc(info.currentline, info.name, "Partition '"..name.."' is not exists.")
        return
    else
        local data = getPartitions()
        local partition, partitionIndex = getPartition(name)
        if partition then
            fs.delete(data[partitionIndex].path)
            table.remove(data, partitionIndex)
        end
        overWritePartitionInfo(data)
        log.info("Deleted Partition '" .. name.."'")
    end
end

return part
