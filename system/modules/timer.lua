-----------------
--- Timer API ---
-----------------

---@type onix_kernel_mode_env
_ENV = _ENV

---@class timer
local timer = {}

timer._timers = {}

function timer.set(id, time)
    if not timer._timers[id] then
        timer._timers[id] = {
            time = os.time() + time
        }
    end
end

function timer.check(id)
    local t = timer._timers[id]
    if not t then
        return false
    end
    if os.time() >= t.time then
        timer._timers[id] = nil
        return true
    end
    return false
end

return timer, "timer"