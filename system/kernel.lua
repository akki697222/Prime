local boot_time = 0
local function uptime()
    return computer.uptime()
end

---no more nil
function nonnil(value)
    if value == nil then
        error("nil")
    else
        return value
    end
end

--getting computer components
local components = {}
components.filesystem = component.proxy(computer.getBootAddress())
components.gpu = component.proxy(component.list("gpu")())

--some internal libraries
local json = loadfile("system/lib/dkjson.lua")()

--classes
---@class fs
local fs = {}
---@class fbcon
local fbcon = {}
---@class module
local module = {}
---@class device
local device = {}
---@class event
local event = {}
---@class timer
local timer = {}
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
fbcon.cx = 1
fbcon.cy = 1
fbcon.width = 0
fbcon.height = 0
fbcon.x_offset = 1
fbcon.y_scroll = 1
fbcon.buffer = {}
fbcon.gpu = nil
fbcon.blinking = false
fbcon._blinkstate = false
fbcon._blinkertid = 0
fbcon.ansi = false
fbcon.currentFG = 0xFFFFFF
fbcon.currentBG = 0x000000
fbcon._lastBuffer = {}
fbcon._lastXOffset = fbcon.x_offset
fbcon._lastYScroll = fbcon.y_scroll
fbcon.ansicolors = {
    reset   = "\27[0m",
    bold    = "\27[1m",
    black   = "\27[30m",
    red     = "\27[31m",
    green   = "\27[32m",
    yellow  = "\27[33m",
    blue    = "\27[34m",
    magenta = "\27[35m",
    cyan    = "\27[36m",
    white   = "\27[37m",

    bright_black   = "\27[90m",
    bright_red     = "\27[91m",
    bright_green   = "\27[92m",
    bright_yellow  = "\27[93m",
    bright_blue    = "\27[94m",
    bright_magenta = "\27[95m",
    bright_cyan    = "\27[96m",
    bright_white   = "\27[97m"
}

local function fbcon_pushTextSegment(bufferLine, text, fg, bg)
    local lastSegment = bufferLine[#bufferLine]
    if lastSegment and lastSegment.fg == fg and lastSegment.bg == bg then
        lastSegment.text = lastSegment.text .. text
    else
        table.insert(bufferLine, {text = text, fg = fg, bg = bg})
    end
end

local function fbcon_compareLine(line1, line2)
    if not line1 and not line2 then return true end
    if not line1 or not line2 then return false end
    if #line1 ~= #line2 then return false end

    for i = 1, #line1 do
        local seg1 = line1[i]
        local seg2 = line2[i]
        if seg1.text ~= seg2.text or seg1.fg ~= seg2.fg or seg1.bg ~= seg2.bg then
            return false
        end
    end
    return true
end

function fbcon.write(value)
    value = tostring(value or "")
    local i = 1

    if not fbcon.buffer[fbcon.y] then
        fbcon.buffer[fbcon.y] = {}
    end

    while i <= #value do
        local c = value:sub(i,i)
        if c == "\27" and value:sub(i+1,i+1) == "[" then
            local seq_end = value:find("m", i)
            if seq_end then
                local seq = value:sub(i+2, seq_end-1)
                for code in seq:gmatch("%d+") do
                    local colors = {
                        ["30"] = 0x000000,
                        ["31"] = 0xFF0000,
                        ["32"] = 0x00FF00,
                        ["33"] = 0xFFFF00,
                        ["34"] = 0x0000FF,
                        ["35"] = 0xFF00FF,
                        ["36"] = 0x00FFFF,
                        ["37"] = 0xFFFFFF,
                        ["90"] = 0x808080,
                        ["91"] = 0xFF8080,
                        ["92"] = 0x80FF80,
                        ["93"] = 0xFFFF80,
                        ["94"] = 0x8080FF,
                        ["95"] = 0xFF80FF,
                        ["96"] = 0x80FFFF,
                        ["97"] = 0xE0E0E0,
                        ["0"]  = 0xFFFFFF 
                    }
                    fbcon.currentFG = colors[code] or fbcon.currentFG
                    if code == "0" then
                        fbcon.currentBG = 0x000000
                    end
                end
                i = seq_end + 1
            else
                i = i + 1
            end
        elseif c == "\n" then
            fbcon.x = 1
            fbcon.y = fbcon.y + 1
            if not fbcon.buffer[fbcon.y] then
                fbcon.buffer[fbcon.y] = {}
            end
            i = i + 1
        elseif c == "\t" then
            local tab_width = 8
            local spaces_to_add = tab_width - ((fbcon.x - 1) % tab_width)
            fbcon_pushTextSegment(fbcon.buffer[fbcon.y], string.rep(" ", spaces_to_add), fbcon.currentFG, fbcon.currentBG)
            fbcon.x = fbcon.x + spaces_to_add
            i = i + 1
        else
            fbcon_pushTextSegment(fbcon.buffer[fbcon.y], c, fbcon.currentFG, fbcon.currentBG)
            fbcon.x = fbcon.x + 1
            i = i + 1
        end
    end
end

-- 指定位置に文字を挿入または上書きする補助関数
local function fbcon_insertOrOverwriteAtPosition(bufferLine, x, text, fg, bg)
    local currentPos = 1
    local insertIndex = 1
    local insertOffset = 0
    
    -- 挿入位置を探す
    for i, segment in ipairs(bufferLine) do
        local segmentLength = #segment.text
        if currentPos + segmentLength > x then
            -- このセグメント内に挿入位置がある
            insertIndex = i
            insertOffset = x - currentPos
            break
        elseif currentPos + segmentLength == x then
            -- セグメントの境界に挿入
            insertIndex = i + 1
            insertOffset = 0
            break
        end
        currentPos = currentPos + segmentLength
    end
    
    -- 挿入位置がバッファの末尾を超える場合
    if x > currentPos then
        fbcon_pushTextSegment(bufferLine, text, fg, bg)
        return
    end
    
    -- 指定位置での上書き処理
    if insertIndex <= #bufferLine then
        local targetSegment = bufferLine[insertIndex]
        if insertOffset == 0 then
            -- セグメントの先頭から上書き
            if targetSegment.fg == fg and targetSegment.bg == bg then
                -- 同じ色なら結合
                targetSegment.text = text .. targetSegment.text:sub(#text + 1)
            else
                -- 異なる色なら新しいセグメントを挿入
                table.insert(bufferLine, insertIndex, {text = text, fg = fg, bg = bg})
                if #targetSegment.text > #text then
                    bufferLine[insertIndex + 1].text = targetSegment.text:sub(#text + 1)
                else
                    table.remove(bufferLine, insertIndex + 1)
                end
            end
        else
            -- セグメントの途中から上書き
            local beforeText = targetSegment.text:sub(1, insertOffset)
            local afterText = targetSegment.text:sub(insertOffset + #text + 1)
            
            -- 前半部分を保持
            targetSegment.text = beforeText
            
            -- 新しいテキストを挿入
            table.insert(bufferLine, insertIndex + 1, {text = text, fg = fg, bg = bg})
            
            -- 後半部分があれば追加
            if #afterText > 0 then
                table.insert(bufferLine, insertIndex + 2, {text = afterText, fg = targetSegment.fg, bg = targetSegment.bg})
            end
        end
    else
        -- 新しいセグメントを追加
        fbcon_pushTextSegment(bufferLine, text, fg, bg)
    end
end

function fbcon.writeTo(x, y, value)
    value = tostring(value or "")
    local originalX = fbcon.x
    local originalY = fbcon.y
    
    -- 指定されたy行が存在しない場合は作成
    if not fbcon.buffer[y] then
        fbcon.buffer[y] = {}
    end
    
    local bufferLine = fbcon.buffer[y]
    
    -- 現在の行の文字数を計算
    local currentLength = 0
    for _, segment in ipairs(bufferLine) do
        currentLength = currentLength + #segment.text
    end
    
    -- 指定されたx位置まで空白で埋める必要があるかチェック
    if x > currentLength + 1 then
        local spacesToAdd = x - currentLength - 1
        fbcon_pushTextSegment(bufferLine, string.rep(" ", spacesToAdd), fbcon.currentFG, fbcon.currentBG)
        currentLength = currentLength + spacesToAdd
    end
    
    -- 書き込み位置を設定
    fbcon.x = x
    fbcon.y = y
    
    -- 指定位置から書き込み開始
    local i = 1
    local writeX = x
    
    while i <= #value do
        local c = value:sub(i,i)
        if c == "\27" and value:sub(i+1,i+1) == "[" then
            -- ANSI色コードの処理
            local seq_end = value:find("m", i)
            if seq_end then
                local seq = value:sub(i+2, seq_end-1)
                for code in seq:gmatch("%d+") do
                    local colors = {
                        ["30"] = 0x000000,
                        ["31"] = 0xFF0000,
                        ["32"] = 0x00FF00,
                        ["33"] = 0xFFFF00,
                        ["34"] = 0x0000FF,
                        ["35"] = 0xFF00FF,
                        ["36"] = 0x00FFFF,
                        ["37"] = 0xFFFFFF,
                        ["90"] = 0x808080,
                        ["91"] = 0xFF8080,
                        ["92"] = 0x80FF80,
                        ["93"] = 0xFFFF80,
                        ["94"] = 0x8080FF,
                        ["95"] = 0xFF80FF,
                        ["96"] = 0x80FFFF,
                        ["97"] = 0xE0E0E0,
                        ["0"]  = 0xFFFFFF 
                    }
                    fbcon.currentFG = colors[code] or fbcon.currentFG
                    if code == "0" then
                        fbcon.currentBG = 0x000000
                    end
                end
                i = seq_end + 1
            else
                i = i + 1
            end
        elseif c == "\n" then
            -- 改行の場合は次の行に移動
            writeX = 1
            y = y + 1
            if not fbcon.buffer[y] then
                fbcon.buffer[y] = {}
            end
            bufferLine = fbcon.buffer[y]
            i = i + 1
        elseif c == "\t" then
            -- タブの処理
            local tab_width = 8
            local spaces_to_add = tab_width - ((writeX - 1) % tab_width)
            
            -- 指定位置に上書きまたは挿入
            fbcon_insertOrOverwriteAtPosition(bufferLine, writeX, string.rep(" ", spaces_to_add), fbcon.currentFG, fbcon.currentBG)
            writeX = writeX + spaces_to_add
            i = i + 1
        else
            -- 通常の文字の処理
            fbcon_insertOrOverwriteAtPosition(bufferLine, writeX, c, fbcon.currentFG, fbcon.currentBG)
            writeX = writeX + 1
            i = i + 1
        end
    end
    
    -- 元の位置を復元
    fbcon.x = originalX
    fbcon.y = originalY
end

function fbcon.print(value)
    fbcon.write(value)
    fbcon.newline()
end

function fbcon.reset()
    fbcon.gpu = components.gpu
    fbcon.width, fbcon.height = fbcon.gpu.getResolution()
    fbcon.gpu.fill(1, 1, fbcon.width, fbcon.height, " ")
    fbcon.x = 1
    fbcon.y = 1
    fbcon.buffer = {}
    fbcon.x_offset = 1
    fbcon.y_scroll = 1
    fbcon.blinking = false
    fbcon._blinkstate = false
    fbcon._lastBuffer = {}
    fbcon._lastXOffset = fbcon.x_offset
    fbcon._lastYScroll = fbcon.y_scroll
    if fbcon._blinkertid ~= 0 then
        kernel.killThread(2, fbcon._blinkertid)
    end
    fbcon._blinkertid = kernel.createThread(function ()
        while true do
            if fbcon._blinkstate then
                timer.set(100, 35)
                if timer.check(100) then
                    fbcon._blinkstate = false
                end
            else
                timer.set(100, 35)
                if timer.check(100) then
                    fbcon._blinkstate = true
                end
            end
            coroutine.yield()
        end
    end, "fbcon cursor blinker")
end

function fbcon.newline()
    if fbcon.y > fbcon.height then
        fbcon.scroll()
    end
    fbcon.y = fbcon.y + 1
    fbcon.x = 1
end

function fbcon.scroll(n)
    n = n or 1
    fbcon.y_scroll = fbcon.y_scroll + n
end

function fbcon.bindGPU()
    ---@type gpu_mod|nil
    local mod_gpu = module.getApi("gpu")
    if mod_gpu then
        fbcon.gpu = mod_gpu.get(1)
    else
        fbcon.gpu = components.gpu
    end
end

function fbcon.update()
    local gpu = fbcon.gpu
    fbcon.width, fbcon.height = gpu.getResolution()

    local fullRefresh = false
    -- x_offset or y_scroll変化で全行再描画にする
    if fbcon._lastXOffset ~= fbcon.x_offset or fbcon._lastYScroll ~= fbcon.y_scroll then
        fullRefresh = true
        fbcon._lastXOffset = fbcon.x_offset
        fbcon._lastYScroll = fbcon.y_scroll
    end

    local yScreen = 0
    for y = fbcon.y_scroll, #fbcon.buffer do
        yScreen = yScreen + 1
        if yScreen > fbcon.height then break end

        local currentLine = fbcon.buffer[y]
        local lastLine = fbcon._lastBuffer[y]

        if fullRefresh or not fbcon_compareLine(currentLine, lastLine) then
            gpu.setForeground(0xFFFFFF)
            gpu.setBackground(0x000000)
            gpu.fill(fbcon.x_offset, yScreen, fbcon.width, 1, " ")

            fbcon.cx = fbcon.x_offset
            for _, segment in ipairs(currentLine or {}) do
                gpu.setForeground(segment.fg)
                gpu.setBackground(segment.bg)
                gpu.set(fbcon.cx, yScreen, segment.text)
                fbcon.cx = fbcon.cx + #segment.text
            end

            fbcon._lastBuffer[y] = {}
            for i, seg in ipairs(currentLine or {}) do
                fbcon._lastBuffer[y][i] = {text = seg.text, fg = seg.fg, bg = seg.bg}
            end
        end
    end

    if fbcon.blinking and fbcon._blinkstate then
        local lastLine = fbcon.buffer[#fbcon.buffer]
        if lastLine then
            local cursorX = fbcon.x_offset
            for i = 1, #lastLine do
                cursorX = cursorX + #lastLine[i].text
            end
            gpu.setForeground(0xFFFFFF)
            gpu.setBackground(0x000000)
            gpu.set(cursorX, yScreen, "_")
        end
    end
end

---@return std
function fbcon.getstd()
    ---@type std
    local std = {
        write = fbcon.write,
        printf = function(fmt, ...)
            fbcon.print(string.format(fmt, ...))
        end,
        print = fbcon.print,
        read = function() error("Unsupported") end,
        readline = function() error("Unsupported") end
    }
    return std
end

function printk(...)
    kernel.std.printf("[%8.2f] %s", uptime(), tostring(...))
end

function panic(err, reason)
    printk("Kernel panic - " .. err .. ": " .. reason)
end

------------------
--- Module API ---
------------------

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
        ---@class module_table
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

function module.unload(name)
    ---@type module_table
    local mod = module.loaded[name]
    if mod then
        mod.unload()
        module.loaded[name] = nil
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

---@return module_table|nil
function module.get(name)
    local mod = module.loaded[name]
    if mod then
        return mod
    end
    return nil
end

---@return table|nil
function module.getApi(name)
    local mod = module.loaded[name]
    if mod then
        return mod.module
    end
    return nil
end

---@return table|nil
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

-----------------
--- Event API ---
-----------------

event.eventHandlers = {}

function event.pull(filter)
    return computer.pullSignal(filter)
end

function event.push(name, ...)
    computer.pushSignal(name, ...)
end

---@param func function
function event.addEventHandler(func)
    table.insert(event.eventHandlers, func)
end

-----------------
--- Timer API ---
-----------------

timer._timers = {} 

function timer.set(id, time)
    if not timer._timers[id] then
        timer._timers[id] = {
            time = os.time() + time
        }
    end
end

function timer.check(id)
    local t = timer._timers[id]
    if not t then
        return false 
    end
    if os.time() >= t.time then
        timer._timers[id] = nil
        return true
    end
    return false
end

---------------------------------
--- Kernel Main loop and APIs ---
---------------------------------

---@class process_entry
---@field thread thread
---@field pid integer
---@field tid integer
---@field path string
---@field env table
---@field nice integer
---@field parent integer
---@field arguments table

kernel._version = "1.0.0-dev-OC"
---@type table<process_entry>
kernel.process = {}
kernel.processKill = {}
kernel.threads = {}
kernel.threadKill = {}
kernel.currentProcess = 0
kernel.activeTerminal = 0
---@type table<terminal>
kernel.terminals = {}

local used_pids = {}

local function kernel_get_pid()
    local pid = 1
    while true do
        if not used_pids[pid] then
            used_pids[pid] = true
            return pid
        end
        pid = pid + 1
    end
end

---@class std
---@field print fun(value: any)
---@field printf fun(fmt: string, ...)
---@field write fun(value: any)
---@field read fun(): string
---@field readline fun(): string
kernel.std = {}
kernel.tty = 1

---@return os_env
function kernel.getEnv()
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
        nonnil = nonnil,
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
        std = kernel.std,
        printk = printk,
        module = module,
        fbcon = fbcon,
        event = event,
        kernel = {
            exec = kernel.exec,
            execf = kernel.execf,
            createThread = kernel.createThread,
            getProcess = kernel.getProcess,
            killProcess = kernel.killProcess,
            tty = kernel.tty
        },
        timer = timer,
        json = json
    }

    env._G = env

    return env
end

---@param path string
---@param args table|nil
---@param nice integer|nil
---@param env table|nil
---@param pid integer|nil
function kernel.exec(path, args, nice, env, pid)
    local func = loadfile(path)
    local pid = pid or kernel_get_pid()
    if not func then return end
    ---@type process_entry
    local entry = {
        thread = coroutine.create(func),
        pid = pid,
        tid = pid,
        path = path,
        env = env or kernel.getEnv(),
        nice = nice or 3,
        parent = kernel.currentProcess,
        arguments = args or {}
    }

    table.insert(kernel.process, entry)

    return pid
end

---@param func function
---@param name string
---@param args table|nil
---@param nice integer|nil
---@param env table|nil
---@param pid integer|nil
function kernel.execf(func, name, args, nice, env, pid)
    local pid = pid or kernel_get_pid()
    if not func then return end
    ---@type process_entry
    local entry = {
        thread = coroutine.create(func),
        pid = pid,
        tid = pid,
        path = "[" .. name .. "]",
        env = env or kernel.getEnv(),
        nice = nice or 3,
        parent = kernel.currentProcess,
        arguments = args or {}
    }

    table.insert(kernel.process, entry)

    return pid
end

function kernel.killProcess(pid)
    for index, value in ipairs(kernel.process) do
        if value.pid == pid then
            table.insert(kernel.processKill, index)
        end
    end
end

function kernel.getProcess(pid)
    for index, value in ipairs(kernel.process) do
        if value.pid == pid then
            return value
        end
    end
end

local function kernel_thread_processor()
    while true do
        for index, value in ipairs(kernel.threads) do
            local s, e = coroutine.resume(value.thread)
            if not s then
                printk("Kernel thread " .. value.tid .. " Exited on error: " .. e)
            end
        end
        coroutine.yield()
    end
end

function kernel.killThread(pid, tid)
    for index, value in ipairs(kernel.threads) do
        if value.pid == pid and value.tid == tid then
            table.insert(kernel.threadKill, index)
        end
    end
end

---@param func function
function kernel.createThread(func, name, nice)
    local pid = kernel_get_pid()
    if not func then return end
    ---@type process_entry
    local entry = {
        thread = coroutine.create(func),
        pid = 2,
        tid = pid,
        path = "[" .. name .. "]",
        env = kernel.getEnv(),
        nice = nice or 3,
        parent = 2,
        arguments = {}
    }

    table.insert(kernel.threads, entry)

    return pid
end

function kernel.main()
    kernel.execf(kernel_thread_processor, "kthreadd", {}, -20, _ENV, 2)
    kernel.exec("/sbin/init.lua", {"PrimeOS (OpenComputers)"}, 0, _ENV, 1)

    while true do
        local ev = {computer.pullSignal(0.05)}
        for index, value in ipairs(kernel.processKill) do
            kernel.process[value] = nil
        end
        for index, value in ipairs(kernel.threadKill) do
            kernel.threads[value] = nil
        end
        table.sort(kernel.process, function(a, b)
            return a.nice < b.nice
        end)
        ---@type integer, process_entry
        for index, value in ipairs(kernel.process) do
            if coroutine.status(value.thread) == "dead" then
                kernel.killProcess(value.pid)
            else
                local s, e = coroutine.resume(value.thread, table.unpack(value.arguments))
                if not s then
                    printk("Process " .. value.pid .. " Exited on error: " .. e)
                end
            end
        end
        if ev[1] then
            for index, value in ipairs(event.eventHandlers) do
                value(ev)
            end
        end
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

    local chunk, syntaxErr = load(content, "=" .. path, "t", kernel.getEnv())
    if not chunk then
        error("Syntax error: " .. tostring(syntaxErr))
    end
    return chunk
end

local function boot()
    -- initializing devices and system component
    fs_init_inode()
    fbcon.reset()
    kernel.std = fbcon.getstd()

    -- startup message
    printk("Prime version " .. kernel._version)
    printk("Memory Avaliable: " .. math.floor(computer.totalMemory() / 1024) .. "KB")

    -- load module
    module.autoload()

    local vt = nonnil(module.getApi("vt"))
    local vt1 = vt.create(1)
    kernel.std = vt1:std()
    fbcon.ansi = true

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
