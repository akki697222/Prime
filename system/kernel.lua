local boot_time = 0
local function uptime()
    return os.difftime(os.time(), boot_time) / 1000
end

--getting computer components
local components = {}
components.filesystem = component.proxy(computer.getBootAddress())
components.gpu = component.proxy(component.list("gpu")())

--some internal libraries
local json = loadfile("system/lib/dkjson.lua")()
local std

--classes
---@class fs
local fs = {}
---@class fbcon
local fbcon = {}
---@class module
local module = {}
---@class device
local device = {}
---@class kernel
local kernel = {}

-----------------------------------------
--- Basic Filesystem for Early Kernel ---
-----------------------------------------

fs.internal = {}
fs._mountpath = "/mount/"
fs._handles = {}
fs._init = false
fs._inode = {}
--[[
inode object structure:
[
    "/home": {
        "permission": [777, 777, 777],
        "atime": 0,
        "mtime": 0,
        "ctime": 0,
        "btime": 0,
        "id": 0,
        "size": 0,
    },
    "/home/akki": {
        "permission": [777, 777, 777],
        "atime": 0,
        "mtime": 0,
        "ctime": 0,
        "btime": 0,
        "id": 0,
        "size": 0,
    }
]
]]

local function fs_update_inode_file()
    if components.filesystem.exists("root.json") then
        components.filesystem.remove("root.json")
    end
    local handle = components.filesystem.open("root.json", "w")
    components.filesystem.write(handle, json.encode(fs._inode))
    components.filesystem.close(handle)
end

local function fs_rootnize(path)
    if path:sub(1, 1) == "/" then
        return path
    else
        return "/" .. path
    end
end

local function fs_concat(...)
    local args = { ... }
    local result = ""

    -- 引数が空の場合
    if #args == 0 then
        return ""
    end

    -- 左から順次結合（絶対パスによる置き換えなし）
    for i = 1, #args do
        local current = args[i]

        -- nilまたは空文字列の場合はスキップ
        if not current or current == "" then
            goto continue
        end

        -- 文字列でない場合は変換
        if type(current) ~= "string" then
            current = tostring(current)
        end

        -- 単純な左から右への結合
        if result == "" then
            result = current
        elseif result:sub(-1) == "/" then
            result = result .. current
        else
            result = result .. "/" .. current
        end

        ::continue::
    end

    -- パスの正規化処理
    if result == "" then
        return ""
    end

    -- 複数の連続するスラッシュを1つに
    result = result:gsub("//+", "/")

    -- パスの正規化（.と..の処理）
    local parts = {}
    local is_absolute = result:sub(1, 1) == "/"
    local has_trailing_slash = result:sub(-1) == "/" and result ~= "/"

    for part in result:gmatch("[^/]+") do
        if part == ".." then
            if #parts > 0 and parts[#parts] ~= ".." then
                table.remove(parts)
            elseif not is_absolute then
                -- 相対パスの場合のみ..を保持
                table.insert(parts, part)
            end
            -- 絶対パスで既に最上位の場合は..を無視
        elseif part ~= "." then
            table.insert(parts, part)
        end
    end

    local normalized = table.concat(parts, "/")

    -- 絶対パスの場合は先頭にスラッシュを追加
    if is_absolute then
        normalized = "/" .. normalized
    end

    -- 末尾のスラッシュを保持（元のパスにある場合）
    if has_trailing_slash and normalized ~= "/" then
        normalized = normalized .. "/"
    end

    -- 空のパスの場合は"."を返す（相対パスの場合のみ）
    if normalized == "" and not is_absolute then
        normalized = "."
    end

    return normalized
end

local function fs_combinemount(path)
    return fs_concat(fs._mountpath, path)
end

local function fs_lookup_inode()
    local filesystem = components.filesystem
    local function lookup(path)
        local list = filesystem.list(fs_combinemount(path))
        if not list then return end
        for index, value in ipairs(list) do
            path = fs_concat(path, value)
            if not fs._inode[path] then
                fs.createInode(path)
            end
            if filesystem.isDirectory(fs_combinemount(path)) then
                lookup(path)
            end
        end
    end
    lookup("/")
end

local function fs_init_inode()
    if not components.filesystem.exists("root.json") then
        local handle = components.filesystem.open("root.json", "w")
        components.filesystem.write(handle, "{}")
        components.filesystem.close(handle)
    end
    local handle = components.filesystem.open("root.json")
    local content = ""
    while true do
        local chunk, err = components.filesystem.read(handle, 1024)
        if not chunk then
            if err then
                error(err)
            end
            break
        end
        content = content .. chunk
    end
    components.filesystem.close(handle)
    fs._inode = json.decode(content)
    fs_lookup_inode()
end

function fs.getHandle(id)
    return fs._handles[id]
end

function fs.attributes(path)
    return fs._inode[path] or fs.createInode(path)
end

function fs.createInode(path)
    local root_path = fs_combinemount(path)
    local size = 0
    if components.filesystem.exists(root_path) then
        size = components.filesystem.size(root_path)
    end
    local inode = {
        permission = { 777, 777, 777 },
        atime = os.time(),
        mtime = os.time(),
        ctime = os.time(),
        btime = os.time(),
        id = #fs._inode + 1,
        size = size
    }
    fs._inode[fs_rootnize(path)] = inode
    fs_update_inode_file()
    return inode
end

function fs.isDirectory(path)
    return components.filesystem.isDirectory(fs_combinemount(path))
end

function fs.open(path, mode)
    local root_path = fs_combinemount(path)
    if fs.isDirectory(path) then
        error("Cannot open directory as a file")
    end
    local handle, reason = components.filesystem.open(root_path, mode)
    if not handle then
        error("Unable to open file: " .. reason)
    end
    local inode = fs.attributes(path)
    local file = {
        handle = handle,
        mode = mode,
        path = path,
        inode = inode,
        id = #fs._handles + 1
    }

    fs._handles[file.id] = file

    function file:close()
        fs_update_inode_file()
        components.filesystem.close(handle)
        fs._handles[file.id] = nil
    end

    function file:read(n)
        inode.atime = os.time()
        fs._inode[path] = inode
        return components.filesystem.read(handle, n)
    end

    function file:readAll()
        local content = ""
        while true do
            local chunk, err = components.filesystem.read(handle, 1024)
            if not chunk then
                if err then
                    error(err)
                end
                break
            end
            content = content .. chunk
        end
        return content
    end

    function file:write(value)
        inode.mtime = os.time()
        fs._inode[path] = inode
        return components.filesystem.write(handle, value)
    end

    return file
end

function fs.combine(...)
    return fs_concat(...)
end

function fs.makeDirectory(path)
    local real_path = fs_combinemount(path)
    if not components.filesystem.exists(real_path) then
        components.filesystem.makeDirectory(real_path)
        fs.createInode(path)
        fs_update_inode_file()
        return true
    end
    return false
end

function fs.exists(path)
    return path and components.filesystem.exists(fs_combinemount(path)) or false
end

function fs.remove(path)
    if fs.exists(path) then
        if components.filesystem.remove(fs_combinemount(path)) then
            fs._inode[path] = nil
            fs_update_inode_file()
            return true
        end
    end
    return false
end

function fs.list(path)
    return components.filesystem.list(fs_combinemount(path))
end

------------------------------
--- Framebuffer Controller ---
------------------------------

fbcon.x = 1
fbcon.y = 1
fbcon.width = 0
fbcon.height = 0
fbcon.x_offset = 1
fbcon.y_scroll = 1
fbcon.buffer = {}
fbcon.gpu = nil

function fbcon.write(value)
    value = tostring(value)
    for i = 1, #value do
        local char = value:sub(i, i)
        if char == "\n" then
            fbcon.newline()
        elseif char == "\t" then
            -- タブ幅分の空白を追加
            local y = fbcon.y
            if not fbcon.buffer[y] then
                fbcon.buffer[y] = ""
            end
            local line = fbcon.buffer[y]
            local current_len = #line
            local spaces_to_add = 8 - (current_len % 8)
            fbcon.buffer[y] = line .. string.rep(" ", spaces_to_add)
        else
            local y = fbcon.y
            if not fbcon.buffer[y] then
                fbcon.buffer[y] = ""
            end
            fbcon.buffer[y] = fbcon.buffer[y] .. char
        end
    end
end

function fbcon.print(value)
    fbcon.write(value)
    fbcon.newline()
end

function fbcon.reset()
    fbcon.gpu = components.gpu
    fbcon.width, fbcon.height = fbcon.gpu.getResolution()
    fbcon.gpu.fill(1, 1, fbcon.width, fbcon.height, " ")
end

function fbcon.newline()
    if fbcon.y > fbcon.height then
        fbcon.scroll()
    end
    fbcon.y = fbcon.y + 1
end

function fbcon.scroll(n)
    n = n or 1
    fbcon.y_scroll = fbcon.y_scroll + n
end

function fbcon.bindGPU()
    ---@type gpu_mod|nil
    local mod_gpu = module.get("gpu")
    if mod_gpu then
        fbcon.gpu = mod_gpu.get(1)
    else
        fbcon.gpu = components.gpu
    end
end

function fbcon.update()
    local gpu = fbcon.gpu
    fbcon.width, fbcon.height = gpu.getResolution()
    gpu.fill(1, 1, fbcon.width, fbcon.height, " ")
    local y = 1
    for i = fbcon.y_scroll, #fbcon.buffer do
        gpu.set(fbcon.x_offset, y, fbcon.buffer[i])
        y = y + 1
    end
end

function fbcon.getstd()
    local std = {}
    std.write = fbcon.write
    std.printf = function(fmt, ...)
        fbcon.print(string.format(fmt, ...))
    end
    std.print = fbcon.print
    std.read = function() error("Unsupported") end
    std.readline = function() error("Unsupported") end
    return std
end

function printk(...)
    std.printf("[%12.6f] %s", uptime(), tostring(...))
end

function panic(err, reason)
    printk("Kernel panic - " .. err .. ": " .. reason)
end

------------------
--- Module API ---
------------------

--[[

/etc/modules and module infomation structure

{
    "name": "something",
    "desc": "can do something",
    "license": "MIT",
    "author": "someone",
    "version": "1.0.0"
}

--]]

module.loaded = {}

local function mod_loaderror(path, msg)
    printk("Unable to load module: " .. path .. ": " .. msg)
end

function module.load(path)
    if not fs.exists(path) then
        mod_loaderror(path, "No such file or directory")
        return
    else
        local mod, info, load, unload = loadfile(path)()
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

function module.getAutoload()
    if not fs.exists("/etc/modules.json") then
        local modules_file = fs.open("/etc/modules.json", "w")
        modules_file:write("{}")
        modules_file:close()
    end
    local modules_file = fs.open("/etc/modules.json", "r")
    local modules = json.decode(modules_file:readAll())
    return modules
end

function module.addAutoload(path)
    local modules = module.getAutoload()
    table.insert(modules, path)
    fs.remove("/etc/modules.json")
    local modules_file = fs.open("/etc/modules.json", "w")
    modules_file:write(json.encode(modules))
    modules_file:close()
end

function module.autoload()
    local modules = module.getAutoload()
    for index, value in ipairs(modules) do
        module.load(value)
    end
end

function module.get(name)
    local mod = module.loaded[name]
    if mod then
        return mod.module
    end
    return nil
end

function module.getInfo(name)
    local mod = module.loaded[name]
    if mod then
        return mod.info
    end
    return nil
end

------------------------------------------
--- Component API Wrapper for security ---
------------------------------------------

function device.list(name)
    local devices = {}
    for addr, dev_name in component.list(name) do
        table.insert(devices, addr)
    end
    return devices
end

function device.proxy(address)
    return component.proxy(address)
end

function device.type(address)
    return component.type(address)
end

---------------------------------
--- Kernel Main loop and APIs ---
---------------------------------

kernel._version = "1.0.0-dev-OC"
--[[
std:
print
printf
write
read
readline
]]
kernel.std = {}

function kernel.main()
    while true do
        computer.pullSignal()
        fbcon.update()
    end
end

-----------------------------
--- System Initialization ---
-----------------------------

loadfile = function(path)
    if not fs.exists(path) then
        error("No such file: " .. path)
    end
    local file = fs.open(path)
    local content = file:readAll()
    file:close()

    ---@class os_env
    local env = {
        _G = {},
        _VERSION = _VERSION,
        assert = assert,
        error = error,
        getmetatable = getmetatable,
        ipairs = ipairs,
        load = load,
        next = next,
        pairs = pairs,
        pcall = pcall,
        rawequal = rawequal,
        rawget = rawget,
        rawlen = rawlen,
        rawset = rawset,
        select = select,
        setmetatable = setmetatable,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        xpcall = xpcall,
        bit32 = bit32,
        coroutine = coroutine,
        debug = {
            getinfo = debug.getinfo,
            traceback = debug.traceback,
            getlocal = debug.getlocal,
            getupvalue = debug.getupvalue
        },
        math = math,
        os = {
            clock = os.clock,
            date = os.date,
            difftime = os.difftime,
            time = os.time
        },
        string = string,
        table = table,
        utf8 = utf8,
        unicode = unicode,
        checkArg = checkArg,
        fs = fs,
        device = device,
        std = std,
        printk = printk,
        module = module,
        fbcon = fbcon,
    }

    env._G = env

    local chunk, syntaxErr = load(content, "=" .. path, "t", env or {})
    if not chunk then
        error("Syntax error: " .. tostring(syntaxErr))
    end
    return chunk
end

local function boot()
    -- initializing devices and system component
    fs_init_inode()
    fbcon.reset()
    std = fbcon.getstd()

    boot_time = os.time()

    -- startup message
    printk("Prime version " .. kernel._version)
    printk("Memory Avaliable: " .. math.floor(computer.totalMemory() / 1024) .. "KB")

    -- load module
    module.autoload()

    -- execute kernel main loop
    kernel.main()
end

local s, e = xpcall(boot, debug.traceback)
if not s then
    panic("system error", e)
    fbcon.update()
    while true do
        computer.pullSignal()
    end
end
