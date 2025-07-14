---@type os_env
_ENV = _ENV

local parser = argparse("ls", "list")
parser:argument("directory", "", process.cwd())
parser:flag("-a --all", "do not ignore entries starting with .")
parser:flag("-l", "use a long listing format")
local args = parser:parse({...})
local list = fs.list(args.directory)
if not list then
    std.print("ls: cannot access '" .. args.directory .. "': No such file or directory")
    return
end
if args.l then
    for index, value in ipairs(list) do
        
    end
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
