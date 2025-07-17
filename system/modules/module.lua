------------------
--- Module API ---
------------------

---@type onix_kernel_mode_env
_ENV = _ENV

---@type os
os = os

---@class module
local module = {}

module.loaded = {}

local function mod_loaderror(path, msg)
    printk("Unable to load module: " .. path .. ": " .. msg)
end

function module.load(path)
    if not fs.exists(path) then
        mod_loaderror(path, "No such file or directory")
        return
    else
        local mod, info, load, unload = loadfile(path, kernel.getEnv())()
        if type(info) ~= "table" then
            mod_loaderror(path, "Invalid module information")
            return
        else
            if not info.name then
                mod_loaderror(path, "name field not set")
                return
            end
            if not info.version then
                mod_loaderror(path, "version field not set")
                return
            end
        end
        if type(load) ~= "function" then
            mod_loaderror(path, "Invalid module 'load' function")
            return
        end
        if type(unload) ~= "function" then
            mod_loaderror(path, "Invalid module 'unload' function")
            return
        end
        if module.loaded[info.name] then
            return
        end
        if info.depends and #info.depends > 0 then
            for index, value in ipairs(info.depends) do
                module.load(value)
            end
        end
        printk("module: loading module " .. info.name .. (info.desc and (" - " .. info.desc) or ""))
        ---@class module_table
        module.loaded[info.name] = {
            module = mod,
            info = info,
            load = load,
            unload = unload
        }
        local s, e = pcall(load)
        if not s then
            mod_loaderror(path, e)
            return
        end
    end
end

function module.unload(name)
    ---@type module_table
    local mod = module.loaded[name]
    local info = mod.info
    if mod then
        printk("module: unloading module " .. info.name .. (info.desc and (" - " .. info.desc) or ""))
        mod.unload()
        module.loaded[name] = nil
    end
end

function module.getAutoload()
    if not fs.exists("/etc/modules") then
        local modules_file = fs.open("/etc/modules", "w")
        modules_file:write("{}")
        modules_file:close()
    end
    local modules_file = fs.open("/etc/modules", "r")
    local modules = os.decodeTable(modules_file:readAll())
    return modules
end

function module.addAutoload(path)
    local modules = module.getAutoload()
    table.insert(modules, path)
    fs.remove("/etc/modules")
    local modules_file = fs.open("/etc/modules", "w")
    modules_file:write(os.encodeTable(modules))
    modules_file:close()
end

function module.autoload()
    local modules = module.getAutoload()
    for index, value in ipairs(modules) do
        module.load(value)
    end
end

---@return module_table|nil
function module.get(name)
    local mod = module.loaded[name]
    if mod then
        return mod
    end
    return nil
end

---@return table|nil
function module.getApi(name)
    local mod = module.loaded[name]
    if mod then
        return mod.module
    end
    return nil
end

---@return table|nil
function module.getInfo(name)
    local mod = module.loaded[name]
    if mod then
        return mod.info
    end
    return nil
end

function module.unloadAll()
    for key, value in pairs(module.loaded) do
        value.unload()
        module.loaded[key] = nil
    end
end

return module, "module"