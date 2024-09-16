local log = require("bios.log")
local part = require("bios.partition")
local filesystem = {}

local function printE(...)
    term.setTextColor(colors.red)
    print(...)
    term.setTextColor(colors.white)
end

---@alias EditMode
---| '"part"' # Partition Edit Mode
---| '"device"' # Device Edit Mode
---| '"mount"' # Mounted Partition Edit Mode
---@param mode EditMode
---@param name string Name of Partition|Device
function filesystem.create(mode, name)
    local root = "/"
    local isReadOnly = false
    local info = debug.getinfo(2, "nl")
    if mode == "part" then
        local partition = part.getPartitionData(name)
        if not partition then
            printE("Partition '" .. name .. "' is not exists.")
            return
        end
        root = part.directories.disk .. partition.path
        isReadOnly = partition.readonly
    elseif mode == "device" then
        print("Device mode is WIP")
        return nil
    elseif mode == "mount" then
        local partition = part.getMountedPartitionData(name)
        if not partition then
            printE("Partition '" .. name .. "' is not mounted.")
            return
        end
        root = part.directories.mount .. partition.path
        isReadOnly = partition.readonly
    else
        if not mode then
            printE("Please specify the mode. (" .. info.name .. " line " .. info.currentline .. ")")
        else
            printE("Invalid mode '" .. mode .. "' (" .. info.name .. " line " .. info.currentline .. ")")
        end
        return nil
    end
    local filehandler = {}
    filehandler.open = function(path, mode)
        if isReadOnly then
            return nil
        end
        return fs.open(fs.combine(root, path), mode)
    end
    filehandler.exists = function(path)
        return fs.exists(fs.combine(root, path))
    end
    filehandler.isReadOnly = function()
        return isReadOnly
    end
    filehandler.mkdir = function(path)
        if isReadOnly then
            return false
        end
        fs.makeDir(fs.combine(root, path))
        return true
    end
    filehandler.getLocalPath = function()
        return root
    end
    filehandler.copyFile = function(from, to)
        if isReadOnly then
            return false
        end
        fs.copy(fs.combine(root, from), fs.combine(root, to))
        return true
    end
    filehandler.moveFile = function(from, to)
        if isReadOnly then
            return false
        end
        fs.move(from, fs.combine(root, to))
        return true
    end
    filehandler.combine = function (basepath, localpath)
        return fs.combine(basepath, localpath)
    end
    filehandler.list = function (path)
        return fs.list(fs.combine(root, path))
    end
    filehandler.delete = function (path)
        fs.delete(fs.combine(root, path))
    end
    return filehandler
end

return filesystem
