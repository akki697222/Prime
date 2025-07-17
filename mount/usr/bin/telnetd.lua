---@type os_env
_ENV = _ENV

---@type internet_mod
local inet = nonnil(module.getApi("internet"))
---@type net_tcp
local tcp = inet.tcp

local args = { ... }
local addr = args[1] or "localhost"
local port = args[2] or 200

local telnet_codes = {
    IAC = "\255",   -- Interpret As Command
    DONT = "\254",  -- Don't perform option
    DO = "\253",    -- Do perform option
    WONT = "\252",  -- Won't perform option
    WILL = "\251",  -- Will perform option
    SB = "\250",    -- Subnegotiation begin
    GA = "\249",    -- Go Ahead
    EL = "\248",    -- Erase Line
    EC = "\247",    -- Erase Character
    AYT = "\246",   -- Are You There
    AO = "\245",    -- Abort Output
    IP = "\244",    -- Interrupt Process
    BREAK = "\243", -- Break
    DM = "\242",    -- Data Mark
    NOP = "\241",   -- No Operation
    SE = "\240"     -- Subnegotiation end
}

local telnet_options = {
    BINARY = "\000",            -- Binary Transmission (RFC 856)
    ECHO = "\001",              -- Echo (RFC 857)
    RECONNECT = "\002",         -- Reconnection
    SUPPRESS_GO_AHEAD = "\003", -- Suppress Go Ahead (RFC 858)
    AMSN = "\004",              -- Approx Message Size Negotiation
    STATUS = "\005",            -- Status (RFC 859)
    TIMING_MARK = "\006",       -- Timing Mark (RFC 860)
    RCTE = "\007",              -- Remote Controlled Trans and Echo
    NAOL = "\008",              -- Output Line Width
    NAOP = "\009",              -- Output Page Size
    NAOCRD = "\010",            -- Output Carriage-Return Disposition
    NAOHTS = "\011",            -- Output Horizontal Tab Stops
    NAOHTD = "\012",            -- Output Horizontal Tab Disposition
    NAOFFD = "\013",            -- Output Formfeed Disposition
    NAOVTS = "\014",            -- Output Vertical Tabstops
    NAOVTD = "\015",            -- Output Vertical Tab Disposition
    NAOLFD = "\016",            -- Output Linefeed Disposition
    EXTEND_ASCII = "\017",      -- Extended ASCII
    LOGOUT = "\018",            -- Logout (RFC 727)
    BM = "\019",                -- Byte Macro
    DET = "\020",               -- Data Entry Terminal
    SUPDUP = "\021",            -- SUPDUP Protocol
    SUPDUP_OUTPUT = "\022",     -- SUPDUP Output
    SEND_LOC = "\023",          -- Send Location
    TERM_TYPE = "\024",         -- Terminal Type (RFC 930)
    EOR = "\025",               -- End of Record (RFC 885)
    TUID = "\026",              -- TACACS User Identification
    OUTMRK = "\027",            -- Output Marking
    TTYLOC = "\028",            -- Terminal Location Number
    REGIME_3270 = "\029",       -- Telnet 3270 Regime
    X3_PAD = "\030",            -- X.3 PAD
    NAWS = "\031",              -- Negotiate About Window Size (RFC 1073)
    TERM_SPEED = "\032",        -- Terminal Speed
    FLOW_CONTROL = "\033",      -- Remote Flow Control
    LINEMODE = "\034",          -- Linemode (RFC 1184)
    XDISPLOC = "\035",          -- X Display Location
    ENVIRON = "\036",           -- Environment Variables (RFC 1408)
    AUTH = "\037",              -- Authentication (RFC 2941)
    ENCRYPT = "\038",           -- Encryption Option (RFC 2946)
    NEW_ENVIRON = "\039",       -- New Environment Option (RFC 1572)
    TN3270E = "\040",           -- TN3270E
    XAUTH = "\041",             -- XAUTH
    CHARSET = "\042",           -- Charset (RFC 2066)
    RSP = "\043",               -- Remote Serial Port
    COM_PORT = "\044",          -- Com Port Control Option
    SLE = "\045",               -- Suppress Local Echo
    START_TLS = "\046",         -- Telnet Start TLS
    KERMIT = "\047",            -- Kermit
    SEND_URL = "\048",          -- Send URL
    FORWARD_X = "\049",         -- Forward X
    PRAGMA_LOGON = "\138",      -- Telnet Pragma Logon
    SSPI_LOGON = "\139",        -- Telnet SSPI Logon
    PRAGMA_HEARTBEAT = "\140",  -- Telnet Pragma Heartbeat
    EXOPL = "\255"              -- Extended Options List (RFC 861)
}

local function strip_telnet_commands(data)
    if not data then return "" end
    data = data:gsub("\255[\251-\254].", "")
    data = data:gsub("\255\250.-\255\240", "")
    data = data:gsub("\255.", "")
    return data
end

local server = tcp.connect(addr, port)
server:finishConnect()

server.write(telnet_codes.IAC .. telnet_codes.WILL .. telnet_options.ECHO)
server.write(telnet_codes.IAC .. telnet_codes.WILL .. telnet_options.SUPPRESS_GO_AHEAD)
server.write("ようこそ！quit で終了します。\r\n> ")

local buffer = ""
while true do
    local byte, err = server.read(1)
    if byte then
        if byte == "\8" or byte == "\127" then
            if #buffer > 0 then
                buffer = buffer:sub(1, -2)
                server.write("\b \b")
            end
        else
            buffer = buffer .. byte
            server.write(byte)
        end
        if byte == "\r" then
            local input = strip_telnet_commands(buffer):gsub("[\r\n]", "")
            printk("受信: [" .. input .. "]")
            if input == "quit" then
                server.write("\r\nさようなら\r\n")
                break
            end
            server.write("\r\n入力: " .. input .. "\r\n> ")
            buffer = ""
        end
    elseif err == "closed" then
        printk("クライアント切断")
        break
    end
end
server.close()
