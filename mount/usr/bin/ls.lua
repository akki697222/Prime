---@type os_env
_ENV = _ENV

local parser = argparse("ls", "list")
parser:argument("directory", "", process.cwd())
parser:flag("-a --all", "do not ignore entries starting with .")
parser:flag("-l", "use a long listing format")
local args = parser:parse({ ... })
local list, err = fs.list(args.directory)
if not list then
    std.print("ls: cannot access '" .. args.directory .. "': " .. err)
    return
end

local function formatPermissions(mode)
    local perms = ""
    local function checkBit(bit, char)
        if bit then
            return char
        else
            return "-"
        end
    end

    -- modeはビットマスク（例: rwxr-xr-x）
    perms = perms .. checkBit(permission.canOwnerRead(mode), "r")   -- user read
    perms = perms .. checkBit(permission.canOwnerWrite(mode), "w")  -- user write
    perms = perms .. checkBit(permission.canOwnerExec(mode), "x")   -- user execute
    perms = perms .. checkBit(permission.canGroupRead(mode), "r")   -- group read
    perms = perms .. checkBit(permission.canGroupWrite(mode), "w")  -- group write
    perms = perms .. checkBit(permission.canGroupExec(mode), "x")   -- group execute
    perms = perms .. checkBit(permission.canOtherRead(mode), "r")   -- others read
    perms = perms .. checkBit(permission.canOtherWrite(mode), "w")  -- others write
    perms = perms .. checkBit(permission.canOtherExec(mode), "x")   -- others execute

    return perms
end

local function formatTime(epoch)
    local date = os.date("*t", epoch)
    return string.format("%04d-%02d-%02d %02d:%02d",
        date.year, date.month, date.day, date.hour, date.min)
end

if args.l then
    local tbl = {}
    local items = 0
    for _, name in ipairs(list) do
        if not args.all and name:sub(1, 1) == "." then
            goto continue
        end

        local fullpath = fs.combine(args.directory, name)
        local attr = fs.attributes(fullpath)
        if not attr then
            std.print("ls: cannot access '" .. name .. "': No such file or directory")
            goto continue
        end

        if name:sub(-1) == "/" then
            name = name:sub(1, -2)
        end

        -- ファイルタイプ
        local ftype = "-"
        if fs.isDirectory(fullpath) then
            ftype = "d"
        end
        if fs.isLink(fullpath) then
            ftype = "l"
            name = name .. " -> " .. fs.getLink(fullpath)
        end

        -- パーミッション（mode）
        local mode = attr.mode or 0
        local perms = formatPermissions(mode)

        -- 所有者・グループ（UID,GIDはそのまま表示、必要なら変換処理を追加）
        local uowner = user.getUserByUID(attr.uid)
        local owner = tostring(uowner and uowner.username or "-")
        local ugroup = group.getGroupByGID(attr.gid)
        local group = tostring(ugroup and ugroup.name or "-")

        -- サイズ
        local size = tostring(attr.size or 0)

        -- 更新日時
        local mtime = formatTime(attr.mtime and attr.mtime / 1000 or 0)

        table.insert(tbl, {ftype .. perms, owner, group, size, mtime, name})

        items = items + 1

        ::continue::
    end
    table.insert(tbl, 1, { "total " .. items })
    styledPrint(tbl)
else
    local result = ""
    for index, value in ipairs(list) do
        if value:sub(-1) == "/" then
            value = value:sub(1, -2)
        end
        local r = ""
        if fs.isDirectory(fs.combine(args.directory, value)) then
            r = fbcon.ansicolors.blue .. value .. fbcon.ansicolors.reset
        else
            r = value
        end
        result = result .. r .. " "
    end
    std.print(result)
end
