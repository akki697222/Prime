---@type os_env
_ENV = _ENV

---@class internet_mod
local internet = {}
local module_info = {
    name = "internet",
    desc = "internet driver",
    version = "1.0.0-dev-OC",
    author = "akki697222",
    depends = {}
}

local internet_card = nil

---@class net_tcp
local tcp = {}

function tcp.isEnabled()
    if internet_card then
        return internet_card.isTcpEnabled()
    else
        return false
    end
end

---@param address string
---@param port number
function tcp.connect(address, port)
    if internet_card and tcp.isEnabled() then
        return internet_card.connect(address, port)
    else
        error("internet: unable to connect tcp socket: No internet cards or tcp connection is disabled")
    end
end

---@class net_http
local http = {}

function http.isEnabled()
    if internet_card then
        return internet_card.isHttpEnabled()
    else
        return false
    end
end

---@param url string
---@param data number
---@param headers table
function http.request(url, data, headers)
    if internet_card and http.isEnabled() then
        return internet_card.request(url, data, headers)
    else
        error("internet: unable to post http_request: No internet cards or http connection is disabled")
    end
end

internet.tcp = tcp
internet.http = http

local function load()
    internet_card = device.proxy(device.list("internet")[1])
end

local function unload()

end

return internet, module_info, load, unload