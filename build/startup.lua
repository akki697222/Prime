local args = {...}
local ver = args[1]
if not ver then
    ver = "0.0.1-0.craftos"
end
print("Startup Test!")
if fs.exists("/boot/kernel") then
    shell.run("/boot/kernel "..ver)
else
    shell.run(args[2].." "..ver)
end