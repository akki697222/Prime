---@type os_env
_ENV = _ENV

local parser = argparse("chmod", "Change file permissions")
parser:argument("mode", "Permission mode (e.g. 755)"):convert(tonumber)
parser:argument("path", "Target file or directory path")

local args = parser:parse({...})

local err = fs.setPermission(args.path, args.mode)
if err then
    std.print("chmod: " .. err)
end