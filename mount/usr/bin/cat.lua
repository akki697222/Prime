---@type os_env
_ENV = _ENV

local parser = argparse("cat")
parser:argument("file", "Files to read."):args("*")

parser:flag("-n --number", "Number all output lines.")
parser:flag("-b --number-nonblank", "Number nonempty output lines (overrides -n).")
parser:flag("-s --squeeze-blank", "Suppress repeated empty output lines.")
parser:flag("-E --show-ends", "Display $ at end of each line.")
parser:flag("-T --show-tabs", "Display TAB characters as ^I.")

local args = parser:parse({ ... })

local function output(line_num, line)
    local out = line

    if args.T then
        out = out:gsub("\t", "^I")
    end

    if args.E then
        out = out .. "$"
    end

    if args.b and line ~= "" then
        std.printf("%6d  %s\n", line_num, out)
    elseif args.n and not args.b then
        std.printf("%6d  %s\n", line_num, out)
    else
        std.print(out)
    end
end

local function cat(path)
    local lines = {}
    path = os.findExecutable(path, {}) or path
    local f, e = fs.open(path, "r")
    if not f then
        std.printf("cat: " .. path .. ": " .. e)
        return
    end
    local content = f:readAll()
    f:close()
    for line in content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local line_num = 0
    local last_blank = false
    for _, line in ipairs(lines) do
        local is_blank = (line == "")
        if args.s and is_blank and last_blank then
        else
            if args.b then
                if not is_blank then
                    line_num = line_num + 1
                    output(line_num, line)
                else
                    std.print("")
                end
            elseif args.n then
                line_num = line_num + 1
                output(line_num, line)
            else
                output(nil, line)
            end
        end
        last_blank = is_blank
    end
end

for _, path in ipairs(args.file) do
    cat(path)
end
