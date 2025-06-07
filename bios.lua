-- Minimal Dummy bios.lua for testing kernel.lua syntax load
local bios = {}

bios.debug = {
  traceback = function() return "minimal traceback via bios.debug.traceback" end,
  setupvalue = function() end -- For Lua 5.1 setfenv polyfill if used by kernel directly
}

-- Globals that kernel.lua expects at load time or very early
_G.bios = bios

_G.fs = {
  getLocalPath = function() return "/tmp/primeos_dummy_mnt" end,
  combine = function(p1,p2) return p1 .. "/" .. p2 end,
  getDir = function(path) return "/" end,
  exists = function(path) return false end,
  open = function(path, mode)
    -- print("[Minimal bios.fs.open] Path: " .. path .. " Mode: " .. mode)
    return {
      readAll = function()
        if path == "/etc/modules" then return "[]" end -- Empty list for modules
        if path == "/etc/passwd" then return "{}" end -- Empty object for passwd
        return ""
      end,
      write = function(data) end,
      close = function() end,
      lines = function() return function() end end,
      seek = function() end
    }
  end,
  delete = function(path) end,
  isReadOnly = function() return false end,
  existsWithoutRoot = function() return false end, -- for kernel.execve
  closeAll = function() end -- for kernel.stop
}

_G.textutils = {
  unserialiseJSON = function(str) if str == "" or str == "{}" or str == "[]" then return {} else print("Minimal textutils trying to unserialise: " .. str); return {} end end,
  serialiseJSON = function(tbl) return "" end
}

_G.colors = {} -- Dummy table

_G.native = {
  os = {
    pullEventRaw = function()
      if not _G.bios_terminate_signaled_raw then
        _G.bios_terminate_signaled_raw = true
        return "dummy_event_from_minimal_bios" -- Allow one cycle
      end
      return "terminate"
    end,
    queueEvent = function(...) end,
    pullEvent = function(...) return "terminate" end -- Simplified
  },
  fs = _G.fs, -- Allow native.fs to point to the dummy fs too
  peripheral = { wrap = function(side) return nil end },
  require = function(name) return nil end -- Kernel uses its own require
}

_G.monitor = {
  reset = function() end,
  size = function() return 80, 24 end,
  setPosition = function(x,y) end,
  write = function(text) end,
  clear = function() end,
  colorPrint = function(text) end,
  colorWrite = function(text) end,
  replaceLine = function(text) end,
  colors = _G.colors
}

_G.computer = {
  uptime = function() return 0 end,
  address = "minimal_test_computer_address",
  freeMemory = function() return 1024*1024 end,
  totalMemory = function() return 1024*1024 end,
  shutdown = function() end,
  reboot = function() end
}

_G.device = { keyboard = { keys = {} } }
_G.partition = { exists = function(name, mount_point) return true end }
_G.log = function(...) end
_G.sleep = function(t) end


if not _G.setfenv then
  print("[Minimal bios.lua] Defining setfenv polyfill for Lua 5.1")
  _G.setfenv = function(fn, env)
    local i = 1
    while true do
      local name = debug.getupvalue(fn, i)
      if name == '_ENV' then
        debug.setupvalue(fn, i, env)
        break
      elseif not name then
        break
      end
      i = i + 1
    end
    return fn
  end
end

_G.package = _G.package or {}
_G.package.path = (_G.package.path or "") .. ";./?.lua;./build/os/boot/?.lua"

-- print("[Minimal bios.lua] Minimal BIOS loaded and globals set.")
return bios
