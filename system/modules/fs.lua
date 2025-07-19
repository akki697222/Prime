-------------------------
--- Filesystem Module ---
-------------------------

---@type onix_kernel_mode_env
_ENV = _ENV

local filesystem = component.proxy(computer.getBootAddress())

---@class fs
local fs = {}

fs.internal = {}
fs._handles = {}
fs._init = false
---@type table<string, inode>
fs._inode = { index = 0 }
fs._lookup_table = {}
fs._reserved_lookup_table = {}
fs.save_inode_lookup = true

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

---@alias inode_type
---| '"dir"'
---| '"file"'
---| '"symlink"'

---@class inode
---@field mode integer
---@field uid integer
---@field gid integer
---@field atime integer
---@field mtime integer
---@field ctime integer
---@field btime integer
---@field id string
---@field size integer
---@field type inode_type
---@field children string[]
---@field parent string
---@field link string|nil

local function fs_update_inode_file()
    if filesystem.exists(FS_INODE_FILE) then
        filesystem.remove(FS_INODE_FILE)
    end
    local handle = filesystem.open(FS_INODE_FILE, "w")
    filesystem.write(handle, os.encodeTable(fs._inode))
    filesystem.close(handle)
    if fs.save_inode_lookup then
        if filesystem.exists(FS_INODE_LOOKUP_FILE) then
            filesystem.remove(FS_INODE_LOOKUP_FILE)
        end
        local handle = filesystem.open(FS_INODE_LOOKUP_FILE, "w")
        filesystem.write(handle, os.encodeTable(fs._lookup_table))
        filesystem.close(handle)
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

    return fs.normalizePath(result)
end

local function fs_combinemount(path)
    return fs_concat(FS_MOUNT_PATH, path)
end

local function fs_lookup_inode()
    local filesystem = filesystem
    local stack = { { path = "/", parent = "1" } }
    if not fs._inode["1"] then
        fs.createInode("/")
    end
    fs._lookup_table["/"] = "1"
    while #stack > 0 do
        local current = table.remove(stack)
        local path, parent = current.path, current.parent
        local list = filesystem.list(fs_combinemount(path))
        if not list then goto continue end
        for _, value in ipairs(list) do
            local fullpath = fs_concat(path, value)
            if not fs._lookup_table[fullpath] then
                fs.createInode(fullpath)
            end
            if filesystem.isDirectory(fs_combinemount(fullpath)) then
                table.insert(stack, { path = fullpath, parent = fs._lookup_table[fullpath] })
            end
        end
        ::continue::
    end
    for path, ino_id in pairs(fs._lookup_table) do
        fs._reserved_lookup_table[ino_id] = path
    end
    fs_update_inode_file()
end

local function fs_init_inode()
    local function readall(path, luainit)
        if not filesystem.exists(path) then
            local handle = filesystem.open(path, "w")
            filesystem.write(handle, "return{" .. luainit .. "}")
            filesystem.close(handle)
        end
        local handle = filesystem.open(path)
        local content = ""
        while true do
            local chunk, err = filesystem.read(handle, 1024)
            if not chunk then
                if err then
                    error("fs: " .. err)
                end
                break
            end
            content = content .. chunk
        end
        filesystem.close(handle)
        return content
    end
    fs._inode = os.decodeTable(readall(FS_INODE_FILE, "index=0")) or {}
    if FS_SAVE_LOOKUP_TABLE then
        fs._lookup_table = os.decodeTable(readall(FS_INODE_LOOKUP_FILE, "")) or {}
    end
    fs_lookup_inode()
end

function fs.normalizePath(path)
    local parts = {}
    local is_absolute = path:sub(1, 1) == "/"
    local has_trailing_slash = path:sub(-1) == "/" and path ~= "/"

    for part in path:gmatch("[^/]+") do
        if part == ".." then
            if #parts > 0 and parts[#parts] ~= ".." then
                table.remove(parts)
            elseif not is_absolute then
                table.insert(parts, part)
            end
        elseif part ~= "." then
            table.insert(parts, part)
        end
    end

    local normalized = table.concat(parts, "/")

    if is_absolute then
        normalized = "/" .. normalized
    end

    if has_trailing_slash and normalized ~= "/" then
        normalized = normalized .. "/"
    end

    if normalized == "" and not is_absolute then
        normalized = "."
    end

    return normalized
end

function fs.createLink(path, targetPath)
    local inode, err = fs.createLinkInode(path, targetPath)
    if not inode then
        return nil, err
    else
        return targetPath
    end
end

function fs.init()
    fs_init_inode()
end

function fs.getHandle(id)
    return fs._handles[id]
end

function fs.closeAllHandles()
    for key, value in pairs(fs._handles) do
        filesystem.close(value.handle)
    end
end

function fs.getParent(path)
    path = fs.resolvePath(path)

    if path ~= "/" and path:sub(-1) == "/" then
        path = path:sub(1, -2)
    end

    local last_slash = path:match("^.*()/")
    if not last_slash then
        return "/"
    end

    local parent = path:sub(1, last_slash - 1)
    if parent == "" then
        parent = "/"
    end
    return parent
end

function fs.resolvePath(path)
    local is_absolute = path:sub(1, 1) == "/"
    local parts = {}

    for part in path:gmatch("[^/]+") do
        table.insert(parts, part)
    end

    local resolved_parts = {}
    local visited = {}

    for i = 1, #parts do
        table.insert(resolved_parts, parts[i])
        local current_path = (is_absolute and "/" or "") .. table.concat(resolved_parts, "/")

        if visited[current_path] then
            return nil, "Circular symlink detected"
        end
        visited[current_path] = true

        local inode = fs._inode[fs._lookup_table[current_path]]
        if inode and inode.type == "symlink" and inode.link then
            local link_path = fs.normalizePath(inode.link)
            local remaining_parts = {}
            for j = i + 1, #parts do
                table.insert(remaining_parts, parts[j])
            end

            if link_path:sub(1, 1) ~= "/" then
                local parent_parts = { table.unpack(resolved_parts, 1, #resolved_parts - 1) }
                link_path = fs.normalizePath("/" .. table.concat(parent_parts, "/") .. "/" .. link_path)
            end

            local new_path = link_path
            if #remaining_parts > 0 then
                new_path = fs_concat(link_path, table.unpack(remaining_parts))
            end
            return fs.resolvePath(new_path)
        end
    end

    return (is_absolute and "/" or "") .. table.concat(resolved_parts, "/")
end

---@return inode|nil,nil|string
function fs.attributes(path)
    path = fs.resolvePath(path)
    local ino_id = fs._lookup_table[path]
    if ino_id then
        return fs._inode[ino_id] or nil, "No such file or directory"
    elseif fs.exists(path) then
        return fs.createInode(path)
    else
        return nil, "No such file or directory"
    end
end

function fs.createInode(path)
    path = fs.resolvePath(path)
    local root_path = fs_combinemount(path)
    local size = 0
    local time = os.time()
    if filesystem.exists(root_path) then
        size = filesystem.size(root_path)
    end
    local ino_id = tostring(fs._inode.index + 1)
    local u = nil
    if kernel.currentUser > -1 then
        u = user.getUserByUID(kernel.currentUser)
    end
    local parent = fs._inode[fs._lookup_table[fs.resolvePath(fs.getParent(path))]]
    local parent_id = parent and parent.id or "1"
    if parent then
        local f = false
        for index, value in ipairs(parent.children) do
            if value == ino_id then
                f = true
            end
        end
        if not f then
            table.insert(parent.children, ino_id)
        end
    end
    ---@type inode
    local inode = {
        mode = filesystem.isDirectory(root_path) and 755 or 644,
        uid = u and u.uid or 0,
        gid = u and u.gid or 0,
        atime = time,
        mtime = time,
        ctime = time,
        btime = time,
        id = ino_id,
        size = size,
        type = filesystem.isDirectory(root_path) and "dir" or "file",
        children = {},
        parent = parent_id or "1"
    }
    if not fs._reserved_lookup_table[ino_id] then
        fs._reserved_lookup_table[ino_id] = path
    end
    if fs._lookup_table[path] then
        return fs._inode[fs._lookup_table[path]]
    else
        fs._inode[ino_id] = inode
        fs._lookup_table[path] = ino_id
        fs._inode.index = fs._inode.index + 1
        return inode
    end
end

function fs.createLinkInode(path, targetPath)
    path = fs.resolvePath(path)
    targetPath = fs.resolvePath(targetPath)
    local root_path = fs_combinemount(path)
    local size = 0
    local time = os.time()
    if filesystem.exists(root_path) then
        size = filesystem.size(root_path)
    end
    local ino_id = tostring(fs._inode.index + 1)
    local u = nil
    if kernel.currentUser > -1 then
        u = user.getUserByUID(kernel.currentUser)
    end
    local parent_path = fs.getParent(targetPath)
    printk(parent_path)
    local parent = fs.attributes(parent_path)
    local parent_id = parent and parent.id or "1"
    if parent then
        local f = false
        for index, value in ipairs(parent.children) do
            if value == ino_id then
                f = true
            end
        end
        if not f then
            table.insert(parent.children, ino_id)
        end
    end
    ---@type inode
    local inode = {
        mode = 777,
        uid = u and u.uid or 0,
        gid = u and u.gid or 0,
        atime = time,
        mtime = time,
        ctime = time,
        btime = time,
        id = ino_id,
        size = size,
        type = "symlink",
        children = {},
        parent = parent_id or "1",
        link = path
    }
    if not fs._reserved_lookup_table[ino_id] then
        fs._reserved_lookup_table[ino_id] = path
    end
    if fs._lookup_table[targetPath] then
        return fs._inode[fs._lookup_table[targetPath]]
    else
        fs._inode[ino_id] = inode
        fs._lookup_table[targetPath] = ino_id
        fs._inode.index = fs._inode.index + 1
        return inode
    end
end

---@return integer|nil, string|nil
function fs.getPermission(path)
    local inode, err = fs.attributes(path)
    return inode and inode.mode or nil, err
end

---@param perm integer 777(rwxrwxrwx), 755(rwxr-xr-x)
---@return string|nil
function fs.setPermission(path, perm)
    local inode, err = fs.attributes(path)
    if inode then
        local uid = kernel.getCurrentProcess() and kernel.getCurrentProcess().euid or 0
        if uid == 0 or inode.uid == uid then
            inode.mode = perm
            fs_update_inode_file()
        else
            return "Permission Denied"
        end
    else
        return err
    end
end

---@param newOwner integer uid
---@return string|nil
function fs.changeOwner(path, newOwner)
    local inode, err = fs.attributes(path)
    if inode then
        local uid = kernel.getCurrentProcess() and kernel.getCurrentProcess().euid or 0
        if uid == 0 or inode.uid == uid then
            inode.uid = newOwner
            fs_update_inode_file()
        else
            return "Permission Denied"
        end
    else
        return err
    end
end

function fs.isLink(path)
    path = fs.normalizePath(path)
    local inode = fs._inode[fs._lookup_table[path]]
    if inode then
        return inode.type == "symlink"
    else
        return false
    end
end

function fs.isDirectory(path)
    local inode = fs.attributes(path)
    if inode then
        return inode.type == "dir"
    else
        return false
    end
end

---@param mode? fs_mode
function fs.open(path, mode)
    path = fs.resolvePath(path)
    local root_path = fs_combinemount(path)
    mode = mode or "r"
    if not fs.exists(path) and not mode:find("w") then
        return nil, "No such file"
    elseif mode:find("w") then
        local parentFolder = fs.getDir(path)
        if not fs.exists(parentFolder) then
            fs.makeDirectory(parentFolder)
        end
        if not fs.exists(path) then
            fs.createInode(path)
            fs_update_inode_file()
        end
    end
    if fs.isDirectory(path) then
        return nil, "is a directory"
    end
    local handle, reason = filesystem.open(root_path, mode)
    if not handle then
        error("Unable to open file: " .. reason)
    end
    if not fs.checkPermission(path, mode) then
        filesystem.close(handle)
        return nil, "Permission Denied"
    end

    local inode = fs.attributes(path)

    ---@class file
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
        filesystem.close(handle)
        table.remove(fs._handles, file.id)
    end

    function file:read(n)
        local inode = fs.attributes(path)
        inode.atime = os.time()

        return filesystem.read(handle, n)
    end

    function file:readAll()
        local inode = fs.attributes(path)
        inode.atime = os.time()
        
        local content = ""
        while true do
            local chunk, err = filesystem.read(handle, FS_READ_CHUNK_SIZE)
            if not chunk then
                if err then
                    error("fs: error " .. err .. " in reading from file " .. path .. " (handle " .. handle .. ")")
                end
                break
            end
            content = content .. chunk
        end
        return content
    end

    function file:write(value)
        local inode = fs.attributes(path)
        inode.mtime = os.time()
        return filesystem.write(handle, value)
    end

    return file, nil
end

--- @param mode fs_mode
function fs.checkPermission(path, mode)
    local proc = kernel.getCurrentProcess() or { suid = 0, euid = 0, uid = 0 }
    if proc.euid == 0 then
        return true
    end
    --- @type inode|nil
    local inode, err = fs.attributes(path)
    if not inode then
        error("fs: " .. err)
    end
    --- @type user_passwd
    local usr = nonnil(user.getCurrent())
    if permission.canSetUID(inode.mode) and inode.uid == proc.euid then
        return true
    elseif permission.canSetGID(inode.mode) and inode.gid == usr.gid then
        return true
    end
    if inode.uid == proc.euid then
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
    local proc = kernel.getCurrentProcess() or { suid = 0, euid = 0, uid = 0 }
    if proc.euid == 0 then
        return true
    end
    --- @type inode|nil
    local inode, err = fs.attributes(path)
    if not inode then
        error("fs: " .. err)
    end
    if inode.uid == proc.uid then
        if action == "r" then
            return permission.canOwnerRead(inode.mode)
        elseif action == "x" then
            return permission.canOwnerExec(inode.mode)
        else
            return permission.canOwnerWrite(inode.mode)
        end
    elseif inode.gid == proc.gid then
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

function fs.getDir(path)
    return fs.getParent(path)
end

function fs.makeDirectory(path)
    path = fs.resolvePath(path)
    local real_path = fs_combinemount(path)
    if not filesystem.exists(real_path) then
        local parentDir = fs.getDir(path)
        if not fs.exists(parentDir) then
            fs.makeDirectory(parentDir)
        end
        filesystem.makeDirectory(real_path)
        fs.createInode(path)
        fs_update_inode_file()
        return true
    end
    return false
end

function fs.exists(path)
    path = fs.resolvePath(path)
    local ino_id = fs._lookup_table[path]
    if not ino_id then
        if filesystem.exists(fs_combinemount(path)) then
            fs.createInode(path)
            fs_update_inode_file()
            return true
        else
            return false
        end
    elseif fs._inode[ino_id] then
        return true
    end
end

---@return boolean, string|nil
function fs.remove(path)
    path = fs.resolvePath(path)
    if path and fs.exists(path) then
        local deny = false
        if fs.isDirectory(path) then
            deny = not fs.canAction(path, "w") or not fs.canAction(path, "x")
        else
            local dir = fs.getDir(path)
            deny = not fs.canAction(dir, "w") or not fs.canAction(dir, "x")
        end
        if deny then
            return false, "Permission Denied"
        end
        local inode = fs.attributes(path)
        if inode and filesystem.remove(fs_combinemount(path)) then
            for index, value in ipairs(inode.children) do
                fs._inode[value] = nil
                if fs._reserved_lookup_table[value] then
                    fs._lookup_table[fs._reserved_lookup_table[value]] = nil
                end
                fs._reserved_lookup_table[value] = nil
            end
            fs._inode[fs._lookup_table[path]] = nil
            fs._reserved_lookup_table[fs._lookup_table[path]] = nil
            fs._lookup_table[path] = nil
            fs_update_inode_file()
            return true, nil
        end
    end
    return false, "No such file or directory"
end

function fs.list(path)
    if fs.canAction(path, "r") then
        local inode = fs.attributes(path)
        if not inode then
            return nil, "No such file or directory"
        end
        if inode.type == "file" then
            return nil, "Not a directory"
        end
        local list = {}
        for index, value in ipairs(inode.children) do
            local p = fs._reserved_lookup_table[value]
            if p then
                table.insert(list, fs.getName(p))
            end
        end
        return list
    else
        return nil, "Permission Denied"
    end
end

function fs.getName(path)
    path = fs.resolvePath(path)
    if path == "/" then return "/" end

    local name = path:match("([^/]+)/?$")
    return name or path
end

return fs, "fs"
