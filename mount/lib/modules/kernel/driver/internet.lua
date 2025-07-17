---@type os_env
_ENV = _ENV

local internet = {}
local module_info = {
    name = "internet",
    desc = "internet card driver",
    version = "1.0.0-dev-OC",
    author = "akki697222",
    depends = {"/lib/modules/kernel/devfs.lua"}
}

local internet_cards = {}
local tcp = {}


local http = {}



internet.tcp = tcp
internet.http = http

local function load()
    ---@type devfs
    local devfs = nonnil(module.getApi("devfs"))
    for index, value in ipairs(device.list("internet")) do
        local dev = device.proxy(value)
        table.insert(internet_cards, dev)
        devfs.register("inet" .. index, dev, "internet", "")
        printk("internet: found internet card inet" .. index .. " (addr " .. value .. ")")
    end
    
end

local function unload()

end

return internet, module_info, load, unload