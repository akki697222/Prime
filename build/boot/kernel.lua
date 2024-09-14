local args = {...}
local kernel = {}

kernel.ver = args[1]
kernel.running = false

function kernel.init()
    term.clear()
    term.setCursorPos(1,1)
    term.setCursorBlink(true)
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.black)
    print("kernelver '"..kernel.ver.."'")
end

function kernel.fork()
    
end

function kernel.exec()
    
end

kernel.init()

while kernel.running do 

end