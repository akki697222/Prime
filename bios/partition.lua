local disk_data = "/.local_disk/"
local mounted_disk_data = "/.mount/"
local part = {
    ---Partition/Mounted Partition Directory Path
    directories = {
        ---Partition data directory
        disk = disk_data,
        ---Mounted Partition data directory
        mount = mounted_disk_data
    }
}

---Partition initialize
function part.init()
    if not fs.exists(disk_data) then
        fs.makeDir(disk_data)
    end
    if not fs.exists(mounted_disk_data) then
        fs.makeDir(mounted_disk_data)
    end
    if not fs.exists(disk_data .. "partitions.json") then
        local file = fs.open(disk_data .. "partitions.json", "w")
        file.write("{}")
        file.close()
    end
    if not fs.exists(mounted_disk_data .. "mounts.json") then
        local file = fs.open(mounted_disk_data .. "mounts.json", "w")
        file.write("{}")
        file.close()
    end
end

local function getPartitions()
    local file = fs.open(disk_data .. "partitions.json", "r")
    if not file then
        file = fs.open(disk_data .. "partitions.json", "w")
        file.write("{}")
    end
    local data = textutils.unserialiseJSON(file.readAll())
    file.close()
    if not data then
        data = {}
    end
    return data
end

local function getMounts()
    local file = fs.open(mounted_disk_data .. "mounts.json", "r")
    if not file then
        file = fs.open(mounted_disk_data .. "mounts.json", "w")
        file.write("{}")
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
    return {}, 1
end

local function getMount(name)
    local data = getMounts()
    for index, value in ipairs(data) do
        if value.name == name then
            return value, index
        end
    end
    return {}, 1
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

local function checkMountExists(name)
    local data = getMounts()
    for index, value in ipairs(data) do
        if value.name == name then
            return true
        end
    end
    return false
end

local function printE(...)
    term.setTextColor(colors.red)
    print(...)
    term.setTextColor(colors.white)
end

local function addPartitionToInfo(name, path, readonly)
    local data = getPartitions()
    if checkPartitionExists(name) then
        local info = debug.getinfo(2, "nl")
        printE("A partition with that name already exists. ("..info.name.." line "..info.currentline..")")
        return false
    end
    table.insert(data, { name = name, path = path, readonly = readonly})
    local file = fs.open(disk_data .. "partitions.json", "w+")
    file.write(textutils.serialiseJSON(data))
    file.close()
    return true
end

local function addMountToInfo(name, path)
    local data = getMounts()
    if checkMountExists(name) then
        local info = debug.getinfo(2, "nl")
        printE("A mounted partition with that name already exists. ("..info.name.." line "..info.currentline..")")
        return false
    end
    table.insert(data, { name = name, path = path })
    local file = fs.open(mounted_disk_data .. "mounts.json", "w+")
    file.write(textutils.serialiseJSON(data))
    file.close()
    return true
end

local function overWritePartitionInfo(tables)
    local file = fs.open(disk_data .. "partitions.json", "w+")
    file.write(textutils.serialiseJSON(tables))
    file.close()
end

local function overWriteMountInfo(tables)
    local file = fs.open(mounted_disk_data .. "mounts.json", "w+")
    file.write(textutils.serialiseJSON(tables))
    file.close()
end

---Get partition infomation by name
---@param name string
---@return table
function part.getPartitionData(name)
    local data, _ = getPartition(name)
    return data
end

---Get mounted partition infomation by name
---@param name string
---@return table
function part.getMountedPartitionData(name)
    local data, _ = getMount(name)
    return data
end

---Mounting partition
---@param name string
function part.mount(name)
    if not getPartition(name) then
        local info = debug.getinfo(2, "nl")
        printE("Partition '"..name.."' is not exists. ("..info.name.." line "..info.currentline..")")
        return
    elseif checkMountExists(name) then
        local info = debug.getinfo(2, "nl")
        printE("Partition '"..name.."' is already mounted. ("..info.name.." line "..info.currentline..")")
        return
    else
        local partition, partitionIndex = getPartition(name)
        local fullpath = mounted_disk_data..partition.path
        if fs.exists(fullpath) then
            fs.delete(fullpath)
        end
        fs.makeDir(fullpath)
        fs.copy(disk_data..partition.path, fullpath)
        addMountToInfo(name, partition.path)
    end
end

---Unmounting partition
---@param name string
function part.unmount(name)
    if not getPartition(name) then
        local info = debug.getinfo(2, "nl")
        printE("Partition '"..name.."' is not exists. ("..info.name.." line "..info.currentline..")")
        return
    elseif checkMountExists(name) then
        local data = getMounts()
        local mount, mountIndex = getMount(name)
        if mount.path ~= nil and mount.name ~= nil then
            fs.delete(disk_data..mount.path)
            fs.copy(mounted_disk_data..mount.path, disk_data..mount.path)
            fs.delete(mounted_disk_data..mount.path)
            table.remove(data, mountIndex)
        end
        overWriteMountInfo(data)
    else
        local info = debug.getinfo(2, "nl")
        printE("Partition '"..name.."' is not mounted. ("..info.name.." line "..info.currentline..")")
        return
    end
end

---@alias OpenMode
---| '"part"' # Partition
---| '"mount"' # Mounted Partition
--- if mode is nil, mode is part mode.
---@param mode OpenMode
---@param drive string Name of Partition|Mounted Partition
function part.exists(drive, mode)
    if mode == "part" or not mode or mode == "" then
        return checkPartitionExists(drive)
    elseif mode == "mount" then
        return checkMountExists(mode)
    end
end

---Creates Partition
---@param name string
---@param path string
---@param readonly ?boolean
function part.create(name, path, readonly)
    if readonly == nil then
        readonly = false
    end
    local fullpath = disk_data .. path
    if path:match("[^a-zA-Z0-9]") then
        printE("Partition paths must contain only alphanumeric characters (a-z, A-Z, 0-9)")
        return
    end
    if not name or name == "" then
        printE("Partition name cannot be empty.")
        return
    end
    if addPartitionToInfo(name, path, readonly) then
        fs.makeDir(fullpath)
    end
end

---Deletes Partition
---@param name string
function part.delete(name)
    if not getPartition(name) then
        local info = debug.getinfo(2, "nl")
        printE("Partition '"..name.."' is not exists. ("..info.name.." line "..info.currentline..")")
        return
    else
        local mount = getMount(name)
        if mount.path ~= nil and mount.name ~= nil then
            part.unmount(name)
        end
        local data = getPartitions()
        local partition, partitionIndex = getPartition(name)
        if partition.path ~= nil and partition.name ~= nil and partition.readonly ~= nil then
            fs.delete(disk_data..partition.path)
            table.remove(data, partitionIndex)
        end
        overWritePartitionInfo(data)
    end
end

return part
