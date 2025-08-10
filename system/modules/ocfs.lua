-------------------------
--- Filesystem Module ---
-------------------------

---@type onix_kernel_mode_env
_ENV = _ENV

local filesystem = component.proxy(computer.getBootAddress())

---@class ocfs_inode : inode
---@class ocfs_dentry : dentry

local function qstr_hash(name)
    local h = 0
    for i = 1, #name do
        h = (h * 31 + string.byte(name, i)) & 0xFFFFFFFF
    end
    return h
end

---@param q1 qstr
---@param q2 qstr
local function qstr_equal(q1, q2)
    return q1.hash == q2.hash and q1.len == q2.len and q1.name == q2.name
end

---@class ocfs : fs
local fs = {}
fs.__index = fs

function fs.new()
    ---@class ocfs
    local self = setmetatable({}, fs)

    self._mount = nil
    self._root_dentry = nil
    self._root_inode = nil
    self.inode_table = {}

    self.root_inode = {
        i_uid = 0,
        i_gid = 0,
        i_atime = os.time(),
        i_mtime = os.time(),
        i_ctime = os.time(),
        i_btime = os.time(),
        i_ino = "root",
        i_size = 0,
        i_type = "dir",
        i_mode = 0x1FF, -- 0777
        i_openmode = "r",
        i_children = {},
        i_parent = nil,
        i_link = nil,
        i_dentries = {}
    }

    self.root_dentry = {
        d_count = 1,
        d_lock = false,
        d_mounted = false,
        d_inode = self.root_inode,
        d_parent = nil,
        d_name = {
            name = "/", 
            len = 1,
            hash = qstr_hash("/")
        },
        d_child = {},
        d_subdirs = {},
        d_alias = {},
        d_time = os.time(),
        d_op = self,
        d_sb = nil,
    }

    table.insert(self.root_inode.i_dentries, self.root_dentry)
    self.inode_table[1] = self.root_inode

    return self
end

function fs:combine(...)
    local args = { ... }
    local result = ""

    if #args == 0 then
        return ""
    end

    for i = 1, #args do
        local current = args[i]

        if not current or current == "" then
            goto continue
        end

        if type(current) ~= "string" then
            current = tostring(current)
        end

        if result == "" then
            result = current
        elseif result:sub(-1) == "/" then
            result = result .. current
        else
            result = result .. "/" .. current
        end

        ::continue::
    end

    if result == "" then
        return ""
    end

    result = result:gsub("//+", "/")

    return fs:normalize_path(result)
end

function fs:normalize_path(path)
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

function fs:add_dentry_child(parent_dentry, child_dentry)
    parent_dentry.d_child[#parent_dentry.d_child + 1] = child_dentry
    local hash_key = tostring(child_dentry.d_name.hash)
    parent_dentry.d_child_map = parent_dentry.d_child_map or {}
    if not parent_dentry.d_child_map[hash_key] then
        parent_dentry.d_child_map[hash_key] = {}
    end
    table.insert(parent_dentry.d_child_map[hash_key], child_dentry)
end

function fs:find_child_dentry_by_qstr(parent_dentry, name_qstr)
    local hash_key = tostring(name_qstr.hash)
    local candidates = parent_dentry.d_child_map and parent_dentry.d_child_map[hash_key]
    if not candidates then
        return nil
    end
    for _, candidate in ipairs(candidates) do
        if qstr_equal(candidate.d_name, name_qstr) then
            return candidate
        end
    end
    return nil
end

function fs:lookup_dentry(path)
    local normalized = self:normalize_path(path)
    if normalized == "/" then
        return self.root_dentry
    end

    local current_dentry = self.root_dentry
    local parts = {}
    for part in normalized:gmatch("[^/]+") do
        table.insert(parts, part)
    end

    for _, part in ipairs(parts) do
        local q = {
            name = part,
            len = #part,
            hash = qstr_hash(part),
        }

        local next_dentry = self:find_child_dentry_by_qstr(current_dentry, q)
        if not next_dentry then
            return nil
        end
        current_dentry = next_dentry
    end

    return current_dentry
end

function fs:lookup_inode(path)
    local dentry = self:lookup_dentry(path)
    if dentry then
        return dentry.d_inode
    end
    return nil
end

function fs:get_root_dentry()
    return self.root_dentry
end

function fs:get_root_inode()
    return self.root_inode
end

return fs, "ocfs"