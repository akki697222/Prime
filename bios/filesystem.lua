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
    ---@class filesystem_handler
    local filehandler = {}
    local opened_files = {}
    ---@alias mode
    ---| '"r"' # Read mode.
    ---| '"w"' # Write mode.
    ---| '"a"' # Append mode.
    ---| '"w+"' # Update mode, all data is erased.
    ---| '"r+"' # Update mode (allows reading and writing), all data is preserved.
    ---@param mode mode
    ---@param path string The path to the file to open.
    filehandler.open = function(path, mode)
        if isReadOnly then
            return nil
        end
        local file = fs.open(fs.combine(root, path), mode)
        table.insert(opened_files, file)
        return file
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
    filehandler.rootCombine = function (basepath, localpath)
        return fs.combine(root, fs.combine(basepath, localpath))
    end
    filehandler.list = function (path)
        local fileattribute = {}
        local filelist = fs.list(fs.combine(root, path))
        if filelist ~= nil then
            for index, value in ipairs(filelist) do
                table.insert(fileattribute, {name = value, attributes = fs.attributes(fs.combine(root, path).."/"..value)})
            end
        end
        return fileattribute
    end
    filehandler.delete = function (path)
        fs.delete(fs.combine(root, path))
    end
    filehandler.find = function (path)
        return fs.find(fs.combine(root, path))
    end
    filehandler.isDir = function (path)
        return fs.isDir(fs.combine(root, path))
    end
    filehandler.getRootDir = function (path)
        if path == nil or path == "/" then
            return "/"
        end
        return fs.getDir(fs.combine(root, path))
    end
    filehandler.getDir = function (path)
        return fs.getDir(path)
    end
    filehandler.getFile = function (path)
        return fs.getName(fs.combine(root, path))
    end
    filehandler.closeAll = function ()
        for index, value in ipairs(opened_files) do
            if type(value.close) == "function" then
                pcall(value.close)
            end
        end
    end
    filehandler.getAttributes = function (path)
        return fs.attributes(fs.combine(root, path))
    end
    filehandler.getCapacity = function (path)
        print(path)
        return fs.getCapacity(fs.combine(root, path))
    end
    return filehandler
end

return filesystem
