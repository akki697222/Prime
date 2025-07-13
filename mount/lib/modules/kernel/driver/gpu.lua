---@type os_env
_ENV = _ENV

---@class gpu_mod
local gpu = {}
local module_info = {
    name = "gpu",
    desc = "gpu driver",
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

    -- 解像度系
    function obj.getResolution()
        return gpu_dev.getResolution()
    end

    function obj.setResolution(w, h)
        return gpu_dev.setResolution(w, h)
    end

    function obj.getMaxResolution()
        return gpu_dev.maxResolution()
    end

    function obj.getViewport()
        return gpu_dev.getViewport()
    end

    function obj.setViewport(w, h)
        return gpu_dev.setViewport(w, h)
    end

    function obj.getSize()
        return gpu_dev.getSize()
    end

    -- 色系
    function obj.getForeground()
        return gpu_dev.getForeground()
    end

    function obj.setForeground(color, isPaletteIndex)
        return gpu_dev.setForeground(color, isPaletteIndex)
    end

    function obj.getBackground()
        return gpu_dev.getBackground()
    end

    function obj.setBackground(color, isPaletteIndex)
        return gpu_dev.setBackground(color, isPaletteIndex)
    end

    function obj.getDepth()
        return gpu_dev.getDepth()
    end

    function obj.setDepth(depth)
        return gpu_dev.setDepth(depth)
    end

    function obj.getPaletteColor(index)
        return gpu_dev.getPaletteColor(index)
    end

    function obj.setPaletteColor(index, value)
        return gpu_dev.setPaletteColor(index, value)
    end

    function obj.maxDepth()
        return gpu_dev.maxDepth()
    end

    -- バッファ系
    function obj.getActiveBuffer()
        return gpu_dev.getActiveBuffer()
    end

    function obj.setActiveBuffer(index)
        return gpu_dev.setActiveBuffer(index)
    end

    function obj.buffers()
        return gpu_dev.buffers()
    end

    function obj.allocateBuffer(width, height)
        return gpu_dev.allocateBuffer(width, height)
    end

    function obj.freeBuffer(index)
        return gpu_dev.freeBuffer(index)
    end

    function obj.freeAllBuffers()
        return gpu_dev.freeAllBuffers()
    end

    function obj.getBufferSize(index)
        return gpu_dev.getBufferSize(index)
    end

    function obj.totalMemory()
        return gpu_dev.totalMemory()
    end

    function obj.freeMemory()
        return gpu_dev.freeMemory()
    end

    -- 描画系
    function obj.fill(x, y, width, height, char)
        return gpu_dev.fill(x, y, width, height, char)
    end

    function obj.set(x, y, text, vertical)
        return gpu_dev.set(x, y, text, vertical)
    end

    function obj.get(x, y)
        return gpu_dev.get(x, y)
    end

    function obj.copy(x, y, width, height, tx, ty)
        return gpu_dev.copy(x, y, width, height, tx, ty)
    end

    function obj.bitblt(dst, col, row, width, height, src, fromCol, fromRow)
        return gpu_dev.bitblt(dst, col, row, width, height, src, fromCol, fromRow)
    end

    -- スクリーンバインド
    function obj.bind(screenAddress)
        return gpu_dev.bind(screenAddress)
    end

    -- 情報系
    function obj.info()
        local w, h = gpu_dev.getResolution()
        return "VRAM: " .. math.floor(gpu_dev.totalMemory() / 1024) .. "KB, Width: " .. w .. ", Height: " .. h
    end

    return obj
end

local function load()
    ---@type devfs
    local devfs = nonnil(module.getApi("devfs"))
    for index, value in ipairs(device.list("gpu")) do
        local gpu = device.proxy(value)
        gpu_devices[index] = gpu
        local gpu_info = "gpu" .. index
        gpu_info = gpu_info .. "\nVRAM: " .. math.floor(gpu.totalMemory() / 1024) .. "KB"
        devfs.register("gpu" .. index, gpu, "gpu", gpu_info)
        printk("gpu: found gpu" .. index .. " (addr " .. value .. ")")
    end
    fbcon.bindGPU()
end

local function unload()

end

return gpu, module_info, load, unload
