-- dummy filesystem.lua
local filesystem = {}

function filesystem.create(name, root)
  print("[filesystem.lua] filesystem.create called with name: " .. name .. ", root: " .. root)
  return {
    isReadOnly = function() return false end,
    getLocalPath = function() return "/tmp/primeos_dummy_mnt" end, -- Dummy mount point
    exists = function(path) print("[kernel fs.exists] path: " .. path); return false end,
    isDir = function(path) return false end,
    open = function(path, mode)
      print("[kernel fs.open] path: " .. path .. ", mode: " .. mode)
      return {
        readAll = function() return "{}" end, -- Empty JSON for most config files
        write = function() end,
        close = function() end,
        lines = function() return function() end end, -- iterator
        seek = function() end,
      }
    end,
    list = function(path) return {} end,
    delete = function(path) end,
    getDir = function(path)
      local parts = {}
      for part in string.gmatch(path, "([^/]+)") do
        table.insert(parts, part)
      end
      if #parts > 1 then
        table.remove(parts)
        return "/" .. table.concat(parts, "/")
      end
      return "/"
    end,
    combine = function(p1, p2) return p1 .. "/" .. p2 end,
    existsWithoutRoot = function(path) return false end, -- for execve checks
    closeAll = function() print("[kernel fs.closeAll] called") end,
    getCapacity = function(path) return 0 end,
  }
end

return filesystem
