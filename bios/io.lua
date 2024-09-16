local native_io = io
local io = {}

function io.read(replaceChar, history, completeFunction, default)
    return read(replaceChar, history, completeFunction, default)
end

return io