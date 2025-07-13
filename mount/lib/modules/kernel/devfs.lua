---@type os_env
_ENV = _ENV

local module_info = {
    name = "devfs",
    version = "1.0.0-dev-OC",
    author = "akki697222"
}

---@class devfs
local devfs = {}
local devices = {}

function devfs.register(name, dev, value)
    local path = fs.combine("/dev", name)
    local file = fs.open(path, "w")
    file:write(value)
    file:close()
    devices[path] = dev
end

function devfs.get(name)
    return devices[fs.combine("/dev", name)]
end

function devfs.open(name)
    return devfs.get(name)
end

local function load()
    fs.remove("/dev")
    fs.makeDirectory("/dev")
end

local function unload()
    devices = {}
end

return devfs, module_info, load, unload