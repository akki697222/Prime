---@type os_env
_ENV = _ENV

local ttys = {}

---@class tty_mod
local tty = {}
local module_info = {
    name = "tty",
    desc = "teletype writer",
    version = "1.0.0-dev-OC",
    author = "akki697222",
    depends = {"/lib/modules/kernel/devfs.lua"}
}

local special_keycodes = {
    CTRL_T = 46
}

function tty.create(id)
    ---@type devfs
    local devfs = nonnil(module.getApi("devfs"))
    ---@class tty 
    local obj = {
        id = id,
        buffer = "",
        pressing = {},
        reading = false,
        flags = {
            canonical = true,
            disableWriteCharInput = false
        },
        terminal = nil,
    }

    function obj:handleEvent(ev)
        local type = ev[1]
        local char_code = ev[3]
        local key_code = ev[4]

        if type == "key_down" then
            --printk("strchar: " .. string.char(char_code) .. " char: " .. char_code .. " key: " .. key_code)
            if key_code == special_keycodes.CTRL_T then
                --printk("SIGINT to " .. process.getCurrentPID())
                process.signalCurrent(process.signals.SIGINT)
            end

            if not self.pressing[key_code] then
                self.pressing[key_code] = true

                if self.flags.canonical and char_code then
                    if char_code == 13 then
                        self.reading = false
                    elseif char_code == 8 then
                        if self.buffer ~= "" then
                            self.buffer = self.buffer:sub(1, -2)
                            self.terminal:backspace()
                        end
                    elseif char_code >= 32 and char_code <= 126 then
                        self.buffer = self.buffer .. string.char(char_code)
                        if self.reading and not self.disableWriteCharInput then
                            self.terminal:write(string.char(char_code))
                        end
                    end
                elseif not self.flags.canonical and char_code and char_code ~= 0 then
                    self.buffer = self.buffer .. string.char(char_code)
                end
            end
        elseif type == "key_up" then
            if self.pressing[key_code] then
                self.pressing[key_code] = false
            end
        elseif type == "clipboard" then
            self.buffer = self.buffer .. char_code
        end
    end

    ---@param terminal terminal
    function obj:open(terminal)
        self.terminal = terminal
    end

    function obj:write(data)
        self.buffer = self.buffer .. tostring(data)
    end

    function obj:read(disableWriteCharInput)
        if self.terminal then
            fbcon.blinking = true
            self.reading = true
            self.disableWriteCharInput = disableWriteCharInput
            while self.reading do
                coroutine.yield()
            end
            local buffer_copy = self.buffer
            self.buffer = ""
            fbcon.blinking = false
            self.disableWriteCharInput = false
            self.terminal:print()
            return buffer_copy
        end
    end

    function obj:flush()
        if self.terminal then
            self.terminal:print(self.buffer)
        end
    end

    function obj:setCanonical(state)
        if self.terminal then
            self.flags.canonical = state
        end
    end

    ttys[id] = obj

    devfs.register("tty" .. id, obj, "tty", "tty" .. id)

    return obj
end

---@return tty
function tty.get(id)
    return ttys[id]
end

local function load()
    for i = 1, 16 do
        tty.create(i)
    end
    event.addEventHandler(function(ev)
        tty.get(os.getty()):handleEvent(ev)
    end)
end

local function unload()

end

return tty, module_info, load, unload
