----------------------
--- Permission API ---
----------------------

---@type onix_kernel_mode_env
_ENV = _ENV

---@class permission
local permission = {}

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

local function splitFullPerm(perm)
    perm = tonumber(perm)
    if not perm then return 0, 0, 0, 0 end
    local s = math.floor(perm / 1000) % 10
    local o = math.floor(perm / 100) % 10
    local g = math.floor(perm / 10) % 10
    local t = perm % 10
    return o, g, t, s
end

-- Owner
function permission.canOwnerRead(perm)
    local o = splitFullPerm(perm)
    return band(o, 4) ~= 0
end

function permission.canOwnerWrite(perm)
    local o = splitFullPerm(perm)
    return band(o, 2) ~= 0
end

function permission.canOwnerExec(perm)
    local o = splitFullPerm(perm)
    return band(o, 1) ~= 0
end

-- Group
function permission.canGroupRead(perm)
    local _, g = splitFullPerm(perm)
    return band(g, 4) ~= 0
end

function permission.canGroupWrite(perm)
    local _, g = splitFullPerm(perm)
    return band(g, 2) ~= 0
end

function permission.canGroupExec(perm)
    local _, g = splitFullPerm(perm)
    return band(g, 1) ~= 0
end

-- Other
function permission.canOtherRead(perm)
    local _, _, t = splitFullPerm(perm)
    return band(t, 4) ~= 0
end

function permission.canOtherWrite(perm)
    local _, _, t = splitFullPerm(perm)
    return band(t, 2) ~= 0
end

function permission.canOtherExec(perm)
    local _, _, t = splitFullPerm(perm)
    return band(t, 1) ~= 0
end

function permission.canSetUID(perm)
    local _, _, _, s = splitFullPerm(perm)
    return band(s, 4) ~= 0
end

function permission.canSetGID(perm)
    local _, _, _, s = splitFullPerm(perm)
    return band(s, 2) ~= 0
end

function permission.canSticky(perm)
    local _, _, _, s = splitFullPerm(perm)
    return band(s, 1) ~= 0
end

return permission, "permission"