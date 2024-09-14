local log = require("bios.log")
local part = require("bios.partition")
local filesystem = {}

---@alias EditMode
---| '"part"' # Partition Edit Mode
---| '"device"' # Device Edit Mode
---@param mode EditMode
---@param name string Name of Partition|Device
function filesystem.create(mode, name)
    local root = "/"
    local info = debug.getinfo(2, "nl")
    if mode == "part" then
        local partition = part.getData(name)
        if not partition then return end
        root = partition.path
    elseif mode == "device" then
        log.warn("Device mode is WIP")
        return nil
    else
        if not mode then
            log.errorFunc(info.currentline, info.name, "Please specify the mode.")
        else
            log.errorFunc(info.currentline, info.name, "Invalid mode '"..mode.."'")
        end
        return nil
    end
    log.info("Created filesystem handler in "..root)
    local filehandler = {}
    filehandler.open = function (path, mode)
        log.info("Opening file in ".. path.." (Mode: "..mode..")")
        return fs.open(fs.combine(root, path), mode)
    end
    filehandler.exists = function (path)
        return fs.exists(fs.combine(root, path))
    end
    filehandler.mkdir = function (path)
        log.info("Creating directory in ".. path)
        fs.makeDir(fs.combine(root, path))
    end
    filehandler.getLocalPath = function ()
        return root
    end
    filehandler.copyFile = function (from, to)
        fs.copy(from, fs.combine(root, to))
    end
    filehandler.moveFile = function (from, to)
        fs.move(from, fs.combine(root, to))
    end
    return filehandler
end

return filesystem