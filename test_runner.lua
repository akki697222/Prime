-- Pre-load bios and other necessary globals for kernel testing

-- Set up package path to find our dummy modules if not already set
package.path = package.path .. ";./?.lua;./build/os/boot/?.lua"

-- Load bios to make it and its members (like bios.debug.traceback) globally available
local bios_loaded, bios_module = pcall(require, "bios")
if not bios_loaded then
  print("Failed to load bios.lua: " .. tostring(bios_module))
  -- Define a minimal dummy bios if require fails, to allow kernel's xpcall to be defined
  _G.bios = { debug = { traceback = function() return "Fallback traceback: bios.lua not loaded." end } }
  -- also define other critical globals kernel might access early
    _G.textutils = { unserialiseJSON = function() return {} end, serialiseJSON = function() return "" end }
    _G.colors = {}
    _G.native = {}
    _G.monitor = { reset=function() end, size=function() return 80,24 end, setPosition=function() end, write=function() end,clear=function() end }
    _G.fs = { combine=function(p1,p2) return p1.."/"..p2 end, getDir=function() return "/" end, exists=function() return false end, open=function() return {readAll=function() return "{}" end, write=function() end, close=function() end} end, getLocalPath=function() return "/tmp" end} -- very minimal fs
    _G.computer = { uptime = function() return 0 end }
    _G.device = { keyboard = { keys = {} } }
    _G.partition = { exists = function() return true end }
    _G.log = function() end
    _G.sleep = function() end
    if not _G.setfenv then _G.setfenv = function(fn, env) debug.setupvalue(fn, 1, env) return fn end end


  print("Continuing with fallback bios...")
else
  print("[test_runner.lua] bios.lua loaded successfully.")
  -- Ensure bios is global if bios.lua didn't do it (it should via _G.bios = bios)
  if not _G.bios then _G.bios = bios_module end
end

-- Now, load and execute the kernel script
print("[test_runner.lua] Attempting to load and run kernel.lua...")
local kernel_func, err = loadfile("build/os/boot/kernel.lua")
if not kernel_func then
  print("Error loading kernel.lua: " .. tostring(err))
else
  print("[test_runner.lua] kernel.lua loaded, executing...")
  local success, error_msg = xpcall(kernel_func, function(err_obj)
    -- Custom error handler for the kernel execution itself
    print("[test_runner.lua] Kernel execution error: " .. tostring(err_obj))
    if _G.bios and _G.bios.debug and _G.bios.debug.traceback then
      return _G.bios.debug.traceback(err_obj) -- Use bios traceback if available
    else
      return debug.traceback(err_obj) -- Fallback to standard debug.traceback
    end
  end)

  if success then
    print("[test_runner.lua] Kernel execution finished.")
  else
    print("[test_runner.lua] Kernel xpcall failed. Error message was: ")
    print(error_msg) -- This will print the traceback from the error handler
  end
end
