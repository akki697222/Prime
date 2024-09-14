local coroutines = {}

table.insert(coroutines, coroutine.create(function()
    
end))

table.insert(coroutines, coroutine.create(function()
    
end))

while true do
    local running = false
    for index, value in ipairs(coroutines) do
        coroutine.resume(value)
    end
    for index, value in ipairs(coroutines) do
        if coroutine.status(value) == "running" then
            running = true
        end
    end
    if not running then
        break
    end
end