local graphics = require("bios.graphics")
local log = {}

local write = graphics.colorPrint

function log.info(...)
    write(os.clock().." &d[INFO]&0 ".. ...)
end

function log.warn(...)
    write(os.clock().." &1[WARN]&0 ".. ...)
end

function log.errorFunc(line, func, ...)
    if not func or not line then
        write(os.clock().." &e[ERROR]&0 ".. ...)
        return
    end
    write(os.clock().." &e[ERROR]&0 ".. ... .. " (in function '"..func.."' line "..line..")")
end

function log.error(...)
    write(os.clock().." &e[ERROR]&0 ".. ...)
end

function log.fatal(error, ...)
    write(os.clock().." &e[FATAL]&0 ".. error .. "\n" .. ...)
end

return log