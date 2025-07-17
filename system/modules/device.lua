------------------------------------------
--- Component API Wrapper for security ---
------------------------------------------

---@type onix_kernel_mode_env
_ENV = _ENV

---@class device
local device = {}

function device.list(name)
    local devices = {}
    for addr, dev_name in component.list(name) do
        table.insert(devices, addr)
    end
    return devices
end

function device.proxy(address)
    local type = component.type(address)
    if (type == "drive" or type == "filesystem") and kernel.currentUser ~= 0 then
        error("Cannot get any filesystem/drive devices for security reason")
    end
    return component.proxy(address)
end

function device.type(address)
    return component.type(address)
end

return device, "device"