-----------------
--- Group API ---
-----------------

---@type onix_kernel_mode_env
_ENV = _ENV

---@class group
local group = {}

---@class user_group
---@field name string
---@field gid integer
---@field members string[]

---@type user_group[]
group._groups = {}

local function group_load_group()
    local file, err = fs.open("/etc/group")
    if not file and err then
        panic("group initialize error", err)
    end
    local content = file:readAll()
    file:close()
    local groups = {}
    for line in content:gmatch("[^\r\n]+") do
        local groupname, groupid, member_str = line:match("^([^:]+):([^:]*):([^:]*)$")
        if not groupname or not groupid then
            return nil
        end

        local members = {}
        for member in member_str:gmatch("([^,]+)") do
            table.insert(members, member)
        end
        if group then
            table.insert(groups, {
                name = groupname,
                gid = tonumber(groupid),
                members = members
            })
        end
    end

    group._groups = groups
end

function group.updateGroups()
    if not fs.exists("/etc/group") then
        return nil, "/etc/group does not exist"
    end

    local file = fs.open("/etc/group", "r")
    if not file then
        return nil, "cannot open /etc/group for reading"
    end

    local content = file:readAll()
    file:close()

    local groups = {}
    for line in content:gmatch("[^\r\n]+") do
        local groupname, groupid, member_str = line:match("^([^:]+):([^:]*):([^:]*)$")
        if groupname and groupid then
            local members = {}
            for member in member_str:gmatch("([^,]+)") do
                if member ~= "" then
                    table.insert(members, member)
                end
            end

            table.insert(groups, {
                name = groupname,
                gid = tonumber(groupid),
                members = members
            })
        end
    end

    group._groups = groups
    return true
end

function group.addUser(groupname, username)
    if not user.getUser(username) then
        error("User " .. username .. " does not exists.")
    else
        local gr = group.getGroup(groupname)
        table.insert(gr.members, username)
        group.updateGroups()
    end
end

function group.create(groupname, gid, users)
    gid = gid or 1000

    local group_line = table.concat({
        groupname,
        gid,
        table.concat(users, ",")
    }, ":")

    local passwd_file, e = fs.open("/etc/group", "a")
    if not passwd_file then return nil, "cannot open /etc/group: " .. e end
    passwd_file:write(group_line .. "\n")
    passwd_file:close()

    group_load_group()
end

function group.getGroup(groupname)
    for index, value in ipairs(group._groups) do
        if value.name == groupname then
            return value
        end
    end
end

function group.getGroupByGID(gid)
    for _, value in ipairs(group._groups) do
        if value.gid == gid then
            return value
        end
    end
end

function group.init()
    user.updateUsers()
    local root_group_line = "root:0:root\n"
    if not fs.exists("/etc/group") then
        local file = fs.open("/etc/group", "w")
        file:write(root_group_line)
        file:close()
    end
    group_load_group()
    fs.setPermission("/etc/group", 644)
end

return group, "group"