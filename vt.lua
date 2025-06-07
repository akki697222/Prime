-- dummy vt.lua (Virtual Terminal)
local vt = {}

function vt.create(id)
  print("[vt.lua] vt.create called for id: " .. tostring(id))
  return {
    id = id,
    write = function(...)
      local args = {...}
      local out = ""
      for i,v in ipairs(args) do out = out .. tostring(v) end
      print("[vt " .. id .. "] " .. out)
    end,
    clear = function() print("[vt " .. id .. "] clear") end,
    getSize = function() return 80, 24 end,
    getPosition = function() return 1, 1 end,
    setPosition = function(x, y) print("[vt " .. id .. "] setPosition(" .. x .. "," .. y .. ")") end,
    transfer = function(buffer, x, y, width, height)
      print("[vt " .. id .. "] transfer called, buffer size: " .. #buffer .. " x:"..x.." y:"..y)
    end,
    setColorMode = function(enabled) print("[vt " .. id .. "] setColorMode: " .. tostring(enabled)) end,
    getTTY = function() return "tty" .. id end, -- dummy TTY identifier
    -- any other functions the kernel might call on a TTY object
  }
end

-- module structure for kernel.require
local main = vt
local init = function() print("[vt.lua] init called") end
local manifest = {
    name = "vt",
    version = "0.1",
    path = "vt.lua", -- self path
    desc = "Dummy VT module"
}

return main, init, manifest
