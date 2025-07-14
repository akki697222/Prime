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
---@class process
local process = {}
---@class user
local user = {}
---@class permission
local permission = {}
---@class kernel
local kernel = {}

--some internal libraries
local json
local argparse
local sha2

local function os_time_ms()
    return os.time() * (1000 / 72)
end

-----------------------------------------
--- Basic Filesystem for Early Kernel ---
-----------------------------------------

fs.internal = {}
fs._mountpath = "/mount/"
fs._handles = {}
fs._init = false
fs._inode = {}

---@alias fs_mode
---| '"r"'   # read
---| '"rb"'  # read (binary)
---| '"w"'   # write
---| '"wb"'  # write (binary)
---| '"a"'   # append
---| '"ab"'  # append (binary)


---@alias fs_action
---| '"r"'
---| '"w"'
---| '"x"'

local function fs_update_inode_file()
    if components.filesystem.exists("root.json") then
        components.filesystem.remove("root.json")
    end
    local handle = components.filesystem.open("root.json", "w")
    components.filesystem.write(handle, json.encode(fs._inode))
    components.filesystem.close(handle)
end

local function fs_rootnize_cwd(path)
    if path:sub(1, 1) == "/" then
        return path
    else
        return fs.combine("/", process.cwd(), path)
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
    path = fs_rootnize_cwd(path)
    return fs._inode[path] or fs.createInode(path)
end

function fs.createInode(path)
    local root_path = fs_combinemount(path)
    local size = 0
    if components.filesystem.exists(root_path) then
        size = components.filesystem.size(root_path)
    end
    local u = nil
    if kernel.currentUser > -1 then
        u = user.getUserFromUID(kernel.currentUser)
    end
    ---@class inode
    local inode = {
        mode = fs.isDirectory(path) and 755 or 644,
        uid = u and u.uid or 0,
        gid = u and u.gid or 0,
        atime = os.time(),
        mtime = os.time(),
        ctime = os.time(),
        btime = os.time(),
        id = #fs._inode + 1,
        size = size
    }
    fs._inode[fs_rootnize_cwd(path)] = inode
    fs_update_inode_file()
    return inode
end

---@return integer
function fs.getPermission(path)
    local inode = fs.attributes(path)
    return inode.mode
end

---@param perm integer 777(rwxrwxrwx), 755(rwxr-xr-x)
function fs.setPermission(path, perm)
    local inode = fs.attributes(path)
    inode.mode = perm
    fs_update_inode_file()
end

function fs.isDirectory(path)
    return components.filesystem.isDirectory(fs_combinemount(path))
end

---@param mode fs_mode
function fs.open(path, mode)
    local root_path = fs_combinemount(path)
    mode = mode or "r"
    if fs.isDirectory(path) then
        return nil, "is a directory"
    end
    if not fs.exists(path) and not mode:find("w") then
        return nil, "No such file"
    end
    local handle, reason = components.filesystem.open(root_path, mode)
    if not handle then
        error("Unable to open file: " .. reason)
    end
    if not fs.checkPermission(path, mode) then
        components.filesystem.close(handle)
        return nil, "Permission Denied"
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

    return file, nil
end

---@param mode fs_mode
function fs.checkPermission(path, mode)
    if kernel.currentUser <= 0 then
        return true
    end
    ---@type inode
    local inode = fs.attributes(path)
    ---@type user_passwd
    local usr = nonnil(user.getCurrent())

    if inode.uid == usr.uid then
        if mode == "r" or mode == "rb" then
            return permission.canOwnerRead(inode.mode)
        else
            return permission.canOwnerWrite(inode.mode)
        end
    elseif inode.gid == usr.gid then
        if mode == "r" or mode == "rb" then
            return permission.canGroupRead(inode.mode)
        else
            return permission.canGroupWrite(inode.mode)
        end
    else
        if mode == "r" or mode == "rb" then
            return permission.canOtherRead(inode.mode)
        else
            return permission.canOtherWrite(inode.mode)
        end
    end
end

---@param action fs_action
function fs.canAction(path, action)
    if kernel.currentUser <= 0 then
        return true
    end
    ---@type inode
    local inode = fs.attributes(path)
    ---@type user_passwd
    local usr = nonnil(user.getCurrent())

    if inode.uid == usr.uid then
        if action == "r" then
            return permission.canOwnerRead(inode.mode)
        elseif action == "x" then
            return permission.canOwnerExec(inode.mode)
        else
            return permission.canOwnerWrite(inode.mode)
        end
    elseif inode.gid == usr.gid then
        if action == "r" then
            return permission.canGroupRead(inode.mode)
        elseif action == "x" then
            return permission.canGroupExec(inode.mode)
        else
            return permission.canGroupWrite(inode.mode)
        end
    else
        if action == "r" then
            return permission.canOtherRead(inode.mode)
        elseif action == "x" then
            return permission.canOtherExec(inode.mode)
        else
            return permission.canOtherWrite(inode.mode)
        end
    end
end

function fs.combine(...)
    return fs_concat(...)
end

function fs.getFileDir(path)
    local parts = {}
    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end

    if #parts <= 1 then
        return "/"
    end

    table.remove(parts)
    local dir = "/" .. table.concat(parts, "/")

    if fs.exists(dir) and fs.isDirectory(dir) then
        return dir
    else
        return "/"
    end
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

---@return boolean, string|nil
function fs.remove(path)
    if fs.exists(path) then
        local deny = false
        if fs.isDirectory(path) then
            deny = not fs.canAction(path, "w") or not fs.canAction(path, "x")
        else
            local dir = fs.getFileDir(path)
            deny = not fs.canAction(dir, "w") or not fs.canAction(dir, "x")
        end
        if deny then
            return false, "Permission Denied"
        end
        if components.filesystem.remove(fs_combinemount(path)) then
            fs._inode[path] = nil
            fs_update_inode_file()
            return true, nil
        end
    end
    return false, "No such file or directory"
end

function fs.list(path)
    return components.filesystem.list(fs_combinemount(path))
end

------------------------------
--- Framebuffer Controller ---
------------------------------

local fbcon_early_output = true

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
    reset          = "\27[0m",
    bold           = "\27[1m",
    black          = "\27[30m",
    red            = "\27[31m",
    green          = "\27[32m",
    yellow         = "\27[33m",
    blue           = "\27[34m",
    magenta        = "\27[35m",
    cyan           = "\27[36m",
    white          = "\27[37m",

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
        table.insert(bufferLine, { text = text, fg = fg, bg = bg })
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
        local c = value:sub(i, i)
        if c == "\27" and value:sub(i + 1, i + 1) == "[" then
            local seq_end = value:find("m", i)
            if seq_end then
                local seq = value:sub(i + 2, seq_end - 1)
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
            fbcon_pushTextSegment(fbcon.buffer[fbcon.y], string.rep(" ", spaces_to_add), fbcon.currentFG, fbcon
                .currentBG)
            fbcon.x = fbcon.x + spaces_to_add
            i = i + 1
        else
            fbcon_pushTextSegment(fbcon.buffer[fbcon.y], c, fbcon.currentFG, fbcon.currentBG)
            fbcon.x = fbcon.x + 1
            i = i + 1
        end
    end

    if fbcon_early_output then
        fbcon.update()
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
                table.insert(bufferLine, insertIndex, { text = text, fg = fg, bg = bg })
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
            table.insert(bufferLine, insertIndex + 1, { text = text, fg = fg, bg = bg })

            -- 後半部分があれば追加
            if #afterText > 0 then
                table.insert(bufferLine, insertIndex + 2,
                    { text = afterText, fg = targetSegment.fg, bg = targetSegment.bg })
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
        local c = value:sub(i, i)
        if c == "\27" and value:sub(i + 1, i + 1) == "[" then
            -- ANSI色コードの処理
            local seq_end = value:find("m", i)
            if seq_end then
                local seq = value:sub(i + 2, seq_end - 1)
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
            fbcon_insertOrOverwriteAtPosition(bufferLine, writeX, string.rep(" ", spaces_to_add), fbcon.currentFG,
                fbcon.currentBG)
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
    fbcon._blinkertid = kernel.createThread(function()
        while true do
            if fbcon._blinkstate then
                timer.set(100, 500)
                if timer.check(100) then
                    fbcon._blinkstate = false
                end
            else
                timer.set(100, 500)
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
        if yScreen > fbcon.height then
            fbcon.y_scroll = fbcon.y_scroll + 1
        end

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
                fbcon._lastBuffer[y][i] = { text = seg.text, fg = seg.fg, bg = seg.bg }
            end
        end
    end
    local lastLine = fbcon.buffer[#fbcon.buffer]
    if lastLine then
        local cursorX = fbcon.x_offset
        for i = 1, #lastLine do
            cursorX = cursorX + #lastLine[i].text
        end
        gpu.setForeground(0xFFFFFF)
        gpu.setBackground(0x000000)
        if fbcon.blinking then
            if fbcon._blinkstate then
                gpu.set(cursorX, yScreen, "_")
            else
                gpu.set(cursorX, yScreen, " ")
            end
        else
            gpu.set(cursorX, yScreen, " ")
        end
    end
end

function fbcon.removeChar(n)
    local lastLine = fbcon.buffer[#fbcon.buffer]
    if lastLine then
        fbcon.buffer[#fbcon.buffer][#lastLine].text = lastLine[#lastLine].text:sub(1, -math.abs(n) - 1)
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
        read = function(hideChars) error("Unsupported") end,
        readline = function(hideChars) error("Unsupported") end
    }
    return std
end

function printk(...)
    fbcon.print(string.format("[%8.2f] %s", uptime(), tostring(...)))
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
            time = os_time_ms() + time
        }
    end
end

function timer.check(id)
    local t = timer._timers[id]
    if not t then
        return false
    end
    if os_time_ms() >= t.time then
        timer._timers[id] = nil
        return true
    end
    return false
end

-------------------
--- Process API ---
-------------------

function process.cwd(path)
    if path then
        kernel.getCurrentProcess().cwd = path
        return kernel.getCurrentProcess().cwd
    else
        return kernel.getCurrentProcess() and kernel.getCurrentProcess().cwd or "/"
    end
end

----------------
--- User API ---
----------------

---@class user_shadow
---@field username string
---@field password string
---@field last_change number|nil
---@field min_days number|nil
---@field max_days number|nil
---@field warn_days number|nil
---@field inactive_days number|nil
---@field expire_date number|nil
---@field reserved string|nil

---@class user_passwd
---@field username string
---@field password string
---@field uid number
---@field gid number
---@field gecos string
---@field home string
---@field shell string

user._users = {}

local function user_getShadows()
    local file = fs.open("/etc/shadow")
    if not file then return nil, "cannot open /etc/shadow" end

    local content = file:readAll()
    file:close()

    local shadows = {}
    for line in content:gmatch("[^\r\n]+") do
        local u, p, last, min, max, warn, inactive, expire, reserved =
            line:match("^([^:]+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):?(.*)")

        if u then
            table.insert(shadows, {
                username = u,
                password = p,
                last_change = tonumber(last) or nil,
                min_days = tonumber(min) or nil,
                max_days = tonumber(max) or nil,
                warn_days = tonumber(warn) or nil,
                inactive_days = tonumber(inactive) or nil,
                expire_date = tonumber(expire) or nil,
                reserved = reserved ~= "" and reserved or nil
            })
        end
    end

    return shadows
end

local function user_getShadow(username)
    local shadows, err = user_getShadows()
    if not shadows then return nil, err end

    for _, entry in ipairs(shadows) do
        if entry.username == username then
            return entry
        end
    end

    return nil, "user not found"
end

function user.updateUsers()
    local file = fs.open("/etc/passwd")
    if not file then return nil, "cannot open /etc/passwd" end

    local content = file:readAll()
    file:close()

    local users = {}
    for line in content:gmatch("[^\r\n]+") do
        local username, password, uid, gid, gecos, home, shell = line:match(
        "^([^:]+):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*):([^:]*)")

        if username then
            table.insert(users, {
                username = username,
                password = password,
                uid = tonumber(uid) or nil,
                gid = tonumber(gid) or nil,
                gecos = gecos,
                home = home,
                shell = shell
            })
        end
    end

    user._users = users
end

function user.getUser(username)
    for _, entry in ipairs(user._users) do
        if entry.username == username then
            return entry
        end
    end

    return nil, "user not found"
end

function user.create(username, password, uid, gid, gecos, shell)
    uid = uid or 1000
    gid = gid or 1000
    gecos = gecos or ""
    shell = shell or "/bin/posh.lua"

    local passwd_line = table.concat({
        username,
        "x",
        tostring(uid),
        tostring(gid),
        gecos,
        "/home/" .. username,
        shell,
    }, ":")

    local hash = sha2.sha512(password)
    local last_change = math.floor(os.time() / (24 * 60 * 60))
    local min_days = 0
    local max_days = 99999
    local warn_days = 7
    local inactive_days = ""
    local expire_date = ""
    local reserved = ""

    local shadow_line = table.concat({
        username,
        hash,
        tostring(last_change),
        tostring(min_days),
        tostring(max_days),
        tostring(warn_days),
        inactive_days,
        expire_date,
        reserved,
    }, ":")


    local shadow_file, e = fs.open("/etc/shadow", "a")
    if not shadow_file then return nil, "cannot open /etc/shadow: " .. e end
    shadow_file:write(shadow_line .. "\n")
    shadow_file:close()


    local passwd_file, e = fs.open("/etc/passwd", "a")
    if not passwd_file then return nil, "cannot open /etc/passwd: " .. e end
    passwd_file:write(passwd_line .. "\n")
    passwd_file:close()

    user.updateUsers()

    fs.makeDirectory("/home/" .. username)
end

function user.getUserFromUID(uid)
    for _, entry in ipairs(user._users) do
        if entry.uid == uid then
            return entry
        end
    end

    return nil, "user not found"
end

function user.checkPasswordCorrect(username, passwd)
    local passwd_hash = sha2.sha512(passwd)
    local shadow = user_getShadow(username)
    if shadow and shadow.password == passwd_hash then
        return true
    end
    return false
end

function user.getCurrent()
    return user.getUserFromUID(kernel.currentUser)
end

function user.login(username, passwd)
    if user.checkPasswordCorrect(username, passwd) then
        ---@type user_passwd
        local user = user.getUser(username)

        kernel.currentUser = user.uid
        kernel.exec(user.shell, {user.home}, 0)

        return true
    else
        return false
    end
end

function user.init()
    user.updateUsers()
    local root_passwd_line = "root:x:0:0:root:/root:/bin/posh.lua\n"
    local root_shadow_line = "root:*:0:0:99999:7:::\n"
    if not fs.exists("/etc/passwd") then
        local file = fs.open("/etc/passwd", "w")
        file:write(root_passwd_line)
        file:close()
    end
    if not fs.exists("/etc/shadow") then
        local file = fs.open("/etc/shadow", "w")
        file:write(root_shadow_line)
        file:close()
    end
    fs.setPermission("/etc/shadow", 400)
    fs.setPermission("/etc/passwd", 644)
end

----------------------
--- Permission API ---
----------------------

local function band(a, b)
    if _VERSION == "Lua 5.3" or _VERSION == "Lua 5.4" then
        return a & b
    elseif _VERSION == "Lua 5.2" and bit32 then
        return bit32.band(a, b)
    else
        local res, bitval = 0, 1
        while a > 0 and b > 0 do
            local abit, bbit = a % 2, b % 2
            if abit == 1 and bbit == 1 then
                res = res + bitval
            end
            a = math.floor(a / 2)
            b = math.floor(b / 2)
            bitval = bitval * 2
        end
        return res
    end
end

local function splitPerm(perm)
    perm = tonumber(perm)
    if not perm then return 0, 0, 0 end
    local o = math.floor(perm / 100) % 10
    local g = math.floor(perm / 10) % 10
    local t = perm % 10
    return o, g, t
end

-- Owner
function permission.canOwnerRead(perm)
    local o = splitPerm(perm)
    return band(o, 4) ~= 0
end

function permission.canOwnerWrite(perm)
    local o = splitPerm(perm)
    return band(o, 2) ~= 0
end

function permission.canOwnerExec(perm)
    local o = splitPerm(perm)
    return band(o, 1) ~= 0
end

-- Group
function permission.canGroupRead(perm)
    local _, g = splitPerm(perm)
    return band(g, 4) ~= 0
end

function permission.canGroupWrite(perm)
    local _, g = splitPerm(perm)
    return band(g, 2) ~= 0
end

function permission.canGroupExec(perm)
    local _, g = splitPerm(perm)
    return band(g, 1) ~= 0
end

-- Other
function permission.canOtherRead(perm)
    local _, _, t = splitPerm(perm)
    return band(t, 4) ~= 0
end

function permission.canOtherWrite(perm)
    local _, _, t = splitPerm(perm)
    return band(t, 2) ~= 0
end

function permission.canOtherExec(perm)
    local _, _, t = splitPerm(perm)
    return band(t, 1) ~= 0
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
---@field cwd string

kernel._version = "1.0.1-dev-OC"
---@type table<process_entry>
kernel.process = {}
kernel.threads = {}
kernel.currentProcess = 1
kernel.currentUser = -1
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
---@field read fun(hideChars: boolean?): string
---@field readline fun(hideChars: boolean?): string
kernel.std = {}
kernel.tty = 1
kernel.fs = fs

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
        fs = kernel.fs,
        device = device,
        std = kernel.std,
        printk = printk,
        module = module,
        fbcon = fbcon,
        event = event,
        kernel = kernel,
        timer = timer,
        process = process,
        json = json,
        argparse = argparse,
        user = user,
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
    if not fs.exists(path) then
        return -1, "No such file"
    end
    if not fs.canAction(path, "x") then
        return -1, "Permission Denied"
    end
    local func = loadfile(path)
    local pid = pid or kernel_get_pid()
    if not func then return end
    local cwd = "/"
    if kernel.getCurrentProcess() then
        cwd = kernel.getCurrentProcess().cwd
    end
    ---@type process_entry
    local entry = {
        thread = coroutine.create(func),
        pid = pid,
        tid = pid,
        path = path,
        env = env or kernel.getEnv(),
        nice = nice or 3,
        parent = kernel.currentProcess,
        arguments = args or {},
        cwd = cwd
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
    local cwd = "/"
    if kernel.getCurrentProcess() then
        cwd = kernel.getCurrentProcess().cwd
    end
    ---@type process_entry
    local entry = {
        thread = coroutine.create(func),
        pid = pid,
        tid = pid,
        path = "[" .. name .. "]",
        env = env or kernel.getEnv(),
        nice = nice or 3,
        parent = kernel.currentProcess,
        arguments = args or {},
        cwd = cwd
    }

    table.insert(kernel.process, entry)

    return pid
end

function kernel.waitProcess(pid)
    while true do
        if not kernel.getProcess(pid) then
            break
        end
        coroutine.yield()
    end
end

function kernel.killProcess(pid)
    for index, value in ipairs(kernel.process) do
        if value.pid == pid then
            table.remove(kernel.process, index)
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
            table.remove(kernel.threads, index)
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
        arguments = {},
        cwd = "/"
    }

    table.insert(kernel.threads, entry)

    return pid
end

function kernel.getCurrentProcess()
    for index, value in ipairs(kernel.process) do
        if value.pid == kernel.currentProcess then
            return value
        end
    end
end

function kernel.main()
    printk("starting init process...")
    kernel.currentUser = 0
    kernel.execf(kernel_thread_processor, "kthreadd", {}, -20, _ENV, 2)
    kernel.exec("/sbin/init.lua", { "PrimeOS (OpenComputers)" }, 0, _ENV, 1)
    while true do
        local ev = { computer.pullSignal(0.05) }
        table.sort(kernel.process, function(a, b)
            return a.nice < b.nice
        end)
        ---@type integer, process_entry
        for index, value in ipairs(kernel.process) do
            kernel.currentProcess = value.pid
            if coroutine.status(value.thread) == "dead" then
                table.remove(kernel.process, index)
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

loadfile = function(file)
    local addr, invoke = computer.getBootAddress(), component.invoke
    local handle, reason = invoke(addr, "open", file)
    assert(handle, reason)
    local buffer = ""
    repeat
        local data, reason = invoke(addr, "read", handle, math.huge)
        assert(data or not reason, reason)
        buffer = buffer .. (data or "")
    until not data
    invoke(addr, "close", handle)
    return load(buffer, "=" .. file, "bt", kernel.getEnv())
end

json = loadfile("/system/lib/dkjson.lua")()
argparse = loadfile("/system/lib/argparse.lua")()
sha2 = loadfile("/system/lib/sha2for51.lua")()

loadfile = function(path)
    local file, err = fs.open(path)
    local content = file:readAll()
    file:close()

    local chunk, syntaxErr = load(content, "=" .. path, "t", kernel.getEnv())
    if not chunk then
        error("Syntax error: " .. tostring(syntaxErr))
    end
    return chunk
end

--- *********
--- FOR DEBUG
--- *********
--[[
fs.remove("/etc/init.d/firstboot")
fs.remove("/etc/passwd")
fs.remove("/etc/shadow")
]]

local function boot()
    -- initializing devices and system component
    fbcon.reset()
    fs_init_inode()
    kernel.std = fbcon.getstd()
    user.init()

    -- startup message
    printk("Prime version " .. kernel._version)
    printk("Memory Avaliable: " .. math.floor(computer.totalMemory() / 1024) .. "KB")

    -- load module
    module.autoload()

    local vt = nonnil(module.getApi("vt"))
    local vt1 = vt.create(1)
    kernel.std = vt1:std()
    fbcon.ansi = true

    -- replace fs with primefs
    --local primefs = nonnil(module.getApi("primefs"))
    --kernel.fs = primefs

    -- execute kernel main loop
    fbcon_early_output = false
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
