---@type os_env
_ENV = _ENV

---@class vt_mod
local vt = {}
local module_info = {
    name = "vt",
    desc = "virtual terminal",
    version = "1.0.0-dev-OC",
    author = "akki697222",
    depends = {"/lib/modules/kernel/tty/tty.lua"}
}

function vt.create(tty_id)
    ---@type tty_mod
    local tty_api = nonnil(module.getApi("tty"))
    local tty = tty_api.get(tty_id)
    ---@class terminal
    local obj = {}

    function obj:print(...)
        fbcon.print(...)
    end

    ---@return std
    function obj:std()
        ---@type std
        local std = {
            print = fbcon.print,
            printf = function(fmt, ...)
                fbcon.print(string.format(fmt, ...))
            end,
            write = fbcon.write,
            read = function ()
                tty:setCanonical(true)
                local result = tty:read()
                tty:setCanonical(false)
                return result
            end,
            readline = function ()
                return tty:read()
            end
        }
        return std
    end
    
    tty:open(obj)

    return obj
end

local function load()
    
end

local function unload()

end

return vt, module_info, load, unload
