local entries = {
    {name = "PrimeOS", bootcommand = partition.directories.disk .. partition.getPartitionData("primeos").path .. "/boot/boot.lua"},
    {name = "Exit", bootcommand = "exit"}
}
local function drawEntry()
    local entries_array = {}
    monitor.reset()
    monitor.print("Prime Default Bootloader\n")
    for index, value in ipairs(entries) do
        monitor.print(index .. ". " .. value.name)
        table.insert(entries_array, value)
    end
    monitor.write("\nBoot Entry: ")
    local input = read()
    if tonumber(input) then
        input = tonumber(input)
        if entries_array[input] then
            monitor.reset()
            if entries_array[input].bootcommand == "exit" then
                return
            end
            bios.execute(entries_array[input].bootcommand)
        else
            drawEntry()
        end
    else
        drawEntry()
    end
end
drawEntry()
