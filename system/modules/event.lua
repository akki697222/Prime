-----------------
--- Event API ---
-----------------

---@type onix_kernel_mode_env
_ENV = _ENV

---@class event
local event = {}

function event.pull(filter)
    return computer.pullSignal(filter)
end

function event.push(name, ...)
    computer.pushSignal(name, ...)
end

---@param func fun(ev: table)
function event.addEventHandler(func)
    return kernel.createEventThread(func, "event_handler", 3)
end

return event, "event"