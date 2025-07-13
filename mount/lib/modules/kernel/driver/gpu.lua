---@type os_env
_ENV = _ENV

---@class gpu_mod
local gpu = {}
local module_info = {
    name = "gpu",
    desc = "OC GPU Driver",
    version = "1.0.0-dev-OC",
    author = "akki697222",
    depends = {"/lib/modules/kernel/devfs.lua"}
}

local gpu_devices = {}

---@return string
function gpu.info(id)
    local gpu_dev = gpu_devices[id] or gpu_devices[1]
    local w, h = gpu_dev.getResolution()
    return "VRAM: " .. (gpu_dev.totalMemory() / 1024) .. ", Width: " .. w .. ", Height: " .. h
end

---@return gpu
function gpu.get(id)
    local gpu_dev = gpu_devices[id] or gpu_devices[1]
    ---@class gpu
    local obj = {}

    function obj.getResolution()
        return gpu_dev.getResolution()
    end

    function obj.setResolution(w, h)
        return gpu_dev.setResolution(w, h)
    end

    function obj.fill(x, y, w, h, char)
        return gpu_dev.fill(x, y, w, h, char)
    end

    function obj.set(x, y, text)
        return gpu_dev.set(x, y, text)
    end

    function obj.bind(screenAddress)
        return gpu_dev.bind(screenAddress)
    end

    return obj
end

local function load()
    ---@type devfs
    local devfs = module.get("devfs")
    for index, value in ipairs(device.list("gpu")) do
        local gpu = device.proxy(value)
        gpu_devices[index] = gpu
        local gpu_info = "gpu" .. index
        gpu_info = gpu_info .. "\nVRAM: " .. math.floor(gpu.totalMemory() / 1024) .. "KB"
        devfs.register("gpu" .. index, gpu, gpu_info)
        printk("gpu: found gpu" .. index .. " (addr " .. value .. ")")
    end
    fbcon.bindGPU()
end

local function unload()

end

return gpu, module_info, load, unload
