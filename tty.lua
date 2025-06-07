-- dummy tty.lua
local tty = {}
tty.stdin = {}
tty.stdout = {}
tty.stderr = {}
tty.screen = {} -- Can be a dummy table or functions

function tty.stdin.new()
  print("[tty.lua] stdin.new called")
  return {
    read = function(count) return nil end, -- Simulate EOF or no input
    readLine = function() return nil end,
  }
end

function tty.stdout.new()
  print("[tty.lua] stdout.new called")
  return {
    write = function(data) print("[tty.stdout] " .. tostring(data)) end,
    flush = function() end,
  }
end

function tty.stderr.new()
  print("[tty.lua] stderr.new called")
  return {
    write = function(data) print("[tty.stderr] " .. tostring(data)) end,
    flush = function() end,
  }
end

-- Mock screen object if needed by kernel.getTTY():transfer or other functions
tty.screen.write = function(text) print("[tty.screen] " .. text) end
tty.screen.clear = function() print("[tty.screen] clear") end
tty.screen.getSize = function() return 80, 24 end


-- module structure for kernel.require
local main = tty
local init = function() print("[tty.lua] init called") end
local manifest = {
    name = "tty",
    version = "0.1",
    path = "tty.lua", -- self path
    desc = "Dummy TTY module"
}

return main, init, manifest
