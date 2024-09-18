local entries = {
    ["PrimeOS"] = partition.directories.disk .. partition.getPartitionData("primeos").path .. "/boot/boot.lua",
    ["Exit"] = "exit",
}
local function drawEntry()
    local idx = 1
    local entries_array = {}
    monitor.reset()
    monitor.print("Prime Default Bootloader\n")
    for key, value in pairs(entries) do
        monitor.print(idx .. ". " .. key)
        table.insert(entries_array, value)
        idx = idx + 1
    end
    monitor.write("\nBoot Entry: ")
    local input = read()
    if tonumber(input) then
        input = tonumber(input)
        if entries_array[input] then
            monitor.reset()
            if entries_array[input] == "exit" then
                return
            end
            bios.execute(entries_array[input])
        else
            drawEntry()
        end
    else
        drawEntry()
    end
end
drawEntry()
