------------------------------
--- Framebuffer Controller ---
------------------------------

---@type onix_kernel_mode_env
_ENV = _ENV

---@class fbcon
local fbcon = {}

fbcon.early_output = true
fbcon.x = 1
fbcon.y = 1
fbcon.cx = 1
fbcon.cy = 1
fbcon.width = 0
fbcon.height = 0
fbcon.x_offset = 1
fbcon.y_scroll = 1
fbcon.buffer = {}
fbcon.gpu = nil
fbcon.blinking = false
fbcon._blinkstate = false
fbcon._blinkertid = 0
fbcon.ansi = false
fbcon.currentFG = 0xFFFFFF
fbcon.currentBG = 0x000000
fbcon._lastBuffer = {}
fbcon._lastXOffset = fbcon.x_offset
fbcon._lastYScroll = fbcon.y_scroll
fbcon.ansicolors = {
    reset          = "\27[0m",
    bold           = "\27[1m",
    black          = "\27[30m",
    red            = "\27[31m",
    green          = "\27[32m",
    yellow         = "\27[33m",
    blue           = "\27[34m",
    magenta        = "\27[35m",
    cyan           = "\27[36m",
    white          = "\27[37m",

    bright_black   = "\27[90m",
    bright_red     = "\27[91m",
    bright_green   = "\27[92m",
    bright_yellow  = "\27[93m",
    bright_blue    = "\27[94m",
    bright_magenta = "\27[95m",
    bright_cyan    = "\27[96m",
    bright_white   = "\27[97m"
}

local function fbcon_pushTextSegment(bufferLine, text, fg, bg)
    local lastSegment = bufferLine[#bufferLine]
    if lastSegment and lastSegment.fg == fg and lastSegment.bg == bg then
        lastSegment.text = lastSegment.text .. text
    else
        table.insert(bufferLine, { text = text, fg = fg, bg = bg })
    end
end

local function fbcon_compareLine(line1, line2)
    if not line1 and not line2 then return true end
    if not line1 or not line2 then return false end
    if #line1 ~= #line2 then return false end

    for i = 1, #line1 do
        local seg1 = line1[i]
        local seg2 = line2[i]
        if seg1.text ~= seg2.text or seg1.fg ~= seg2.fg or seg1.bg ~= seg2.bg then
            return false
        end
    end
    return true
end

function fbcon.write(value)
    value = tostring(value or "")
    local i = 1

    if not fbcon.buffer[fbcon.y] then
        fbcon.buffer[fbcon.y] = {}
    end

    while i <= #value do
        local c = value:sub(i, i)
        if c == "\27" and value:sub(i + 1, i + 1) == "[" then
            local seq_end = value:find("m", i)
            if seq_end then
                local seq = value:sub(i + 2, seq_end - 1)
                for code in seq:gmatch("%d+") do
                    local colors = {
                        ["30"] = 0x000000,
                        ["31"] = 0xFF0000,
                        ["32"] = 0x00FF00,
                        ["33"] = 0xFFFF00,
                        ["34"] = 0x0000FF,
                        ["35"] = 0xFF00FF,
                        ["36"] = 0x00FFFF,
                        ["37"] = 0xFFFFFF,
                        ["90"] = 0x808080,
                        ["91"] = 0xFF8080,
                        ["92"] = 0x80FF80,
                        ["93"] = 0xFFFF80,
                        ["94"] = 0x8080FF,
                        ["95"] = 0xFF80FF,
                        ["96"] = 0x80FFFF,
                        ["97"] = 0xE0E0E0,
                        ["0"]  = 0xFFFFFF
                    }
                    fbcon.currentFG = colors[code] or fbcon.currentFG
                    if code == "0" then
                        fbcon.currentBG = 0x000000
                    end
                end
                i = seq_end + 1
            else
                i = i + 1
            end
        elseif c == "\n" then
            fbcon.x = 1
            fbcon.y = fbcon.y + 1
            if not fbcon.buffer[fbcon.y] then
                fbcon.buffer[fbcon.y] = {}
            end
            i = i + 1
        elseif c == "\t" then
            local tab_width = 8
            local spaces_to_add = tab_width - ((fbcon.x - 1) % tab_width)
            fbcon_pushTextSegment(fbcon.buffer[fbcon.y], string.rep(" ", spaces_to_add), fbcon.currentFG, fbcon
                .currentBG)
            fbcon.x = fbcon.x + spaces_to_add
            i = i + 1
        else
            fbcon_pushTextSegment(fbcon.buffer[fbcon.y], c, fbcon.currentFG, fbcon.currentBG)
            fbcon.x = fbcon.x + 1
            i = i + 1
        end
    end

    if fbcon.early_output then
        fbcon.update()
    end
end

local function fbcon_create_blinker_thread()
    if fbcon._blinkertid == 0 or not kernel.getThread(2, fbcon._blinkertid) then
        fbcon._blinkertid = kernel.createThread(function()
            while true do
                if fbcon._blinkstate then
                    timer.set(100, 5)
                    if timer.check(100) then
                        fbcon._blinkstate = false
                    end
                else
                    timer.set(100, 5)
                    if timer.check(100) then
                        fbcon._blinkstate = true
                    end
                end
                coroutine.yield()
            end
        end, "fbcon cursor blinker")
    end
end

-- 指定位置に文字を挿入または上書きする補助関数
local function fbcon_insertOrOverwriteAtPosition(bufferLine, x, text, fg, bg)
    local currentPos = 1
    local insertIndex = 1
    local insertOffset = 0

    -- 挿入位置を探す
    for i, segment in ipairs(bufferLine) do
        local segmentLength = #segment.text
        if currentPos + segmentLength > x then
            -- このセグメント内に挿入位置がある
            insertIndex = i
            insertOffset = x - currentPos
            break
        elseif currentPos + segmentLength == x then
            -- セグメントの境界に挿入
            insertIndex = i + 1
            insertOffset = 0
            break
        end
        currentPos = currentPos + segmentLength
    end

    -- 挿入位置がバッファの末尾を超える場合
    if x > currentPos then
        fbcon_pushTextSegment(bufferLine, text, fg, bg)
        return
    end

    -- 指定位置での上書き処理
    if insertIndex <= #bufferLine then
        local targetSegment = bufferLine[insertIndex]
        if insertOffset == 0 then
            -- セグメントの先頭から上書き
            if targetSegment.fg == fg and targetSegment.bg == bg then
                -- 同じ色なら結合
                targetSegment.text = text .. targetSegment.text:sub(#text + 1)
            else
                -- 異なる色なら新しいセグメントを挿入
                table.insert(bufferLine, insertIndex, { text = text, fg = fg, bg = bg })
                if #targetSegment.text > #text then
                    bufferLine[insertIndex + 1].text = targetSegment.text:sub(#text + 1)
                else
                    table.remove(bufferLine, insertIndex + 1)
                end
            end
        else
            -- セグメントの途中から上書き
            local beforeText = targetSegment.text:sub(1, insertOffset)
            local afterText = targetSegment.text:sub(insertOffset + #text + 1)

            -- 前半部分を保持
            targetSegment.text = beforeText

            -- 新しいテキストを挿入
            table.insert(bufferLine, insertIndex + 1, { text = text, fg = fg, bg = bg })

            -- 後半部分があれば追加
            if #afterText > 0 then
                table.insert(bufferLine, insertIndex + 2,
                    { text = afterText, fg = targetSegment.fg, bg = targetSegment.bg })
            end
        end
    else
        -- 新しいセグメントを追加
        fbcon_pushTextSegment(bufferLine, text, fg, bg)
    end
end

function fbcon.writeTo(x, y, value)
    value = tostring(value or "")
    local originalX = fbcon.x
    local originalY = fbcon.y

    -- 指定されたy行が存在しない場合は作成
    if not fbcon.buffer[y] then
        fbcon.buffer[y] = {}
    end

    local bufferLine = fbcon.buffer[y]

    -- 現在の行の文字数を計算
    local currentLength = 0
    for _, segment in ipairs(bufferLine) do
        currentLength = currentLength + #segment.text
    end

    -- 指定されたx位置まで空白で埋める必要があるかチェック
    if x > currentLength + 1 then
        local spacesToAdd = x - currentLength - 1
        fbcon_pushTextSegment(bufferLine, string.rep(" ", spacesToAdd), fbcon.currentFG, fbcon.currentBG)
        currentLength = currentLength + spacesToAdd
    end

    -- 書き込み位置を設定
    fbcon.x = x
    fbcon.y = y

    -- 指定位置から書き込み開始
    local i = 1
    local writeX = x

    while i <= #value do
        local c = value:sub(i, i)
        if c == "\27" and value:sub(i + 1, i + 1) == "[" then
            -- ANSI色コードの処理
            local seq_end = value:find("m", i)
            if seq_end then
                local seq = value:sub(i + 2, seq_end - 1)
                for code in seq:gmatch("%d+") do
                    local colors = {
                        ["30"] = 0x000000,
                        ["31"] = 0xFF0000,
                        ["32"] = 0x00FF00,
                        ["33"] = 0xFFFF00,
                        ["34"] = 0x0000FF,
                        ["35"] = 0xFF00FF,
                        ["36"] = 0x00FFFF,
                        ["37"] = 0xFFFFFF,
                        ["90"] = 0x808080,
                        ["91"] = 0xFF8080,
                        ["92"] = 0x80FF80,
                        ["93"] = 0xFFFF80,
                        ["94"] = 0x8080FF,
                        ["95"] = 0xFF80FF,
                        ["96"] = 0x80FFFF,
                        ["97"] = 0xE0E0E0,
                        ["0"]  = 0xFFFFFF
                    }
                    fbcon.currentFG = colors[code] or fbcon.currentFG
                    if code == "0" then
                        fbcon.currentBG = 0x000000
                    end
                end
                i = seq_end + 1
            else
                i = i + 1
            end
        elseif c == "\n" then
            -- 改行の場合は次の行に移動
            writeX = 1
            y = y + 1
            if not fbcon.buffer[y] then
                fbcon.buffer[y] = {}
            end
            bufferLine = fbcon.buffer[y]
            i = i + 1
        elseif c == "\t" then
            -- タブの処理
            local tab_width = 8
            local spaces_to_add = tab_width - ((writeX - 1) % tab_width)

            -- 指定位置に上書きまたは挿入
            fbcon_insertOrOverwriteAtPosition(bufferLine, writeX, string.rep(" ", spaces_to_add), fbcon.currentFG,
                fbcon.currentBG)
            writeX = writeX + spaces_to_add
            i = i + 1
        else
            -- 通常の文字の処理
            fbcon_insertOrOverwriteAtPosition(bufferLine, writeX, c, fbcon.currentFG, fbcon.currentBG)
            writeX = writeX + 1
            i = i + 1
        end
    end

    -- 元の位置を復元
    fbcon.x = originalX
    fbcon.y = originalY
end

function fbcon.print(value)
    fbcon.write(value)
    fbcon.newline()
end

function fbcon.reset()
    fbcon.gpu = component.proxy(component.list("gpu")())
    fbcon.width, fbcon.height = fbcon.gpu.getResolution()
    fbcon.gpu.setForeground(0xFFFFFF)
    fbcon.gpu.setBackground(0x000000)
    fbcon.gpu.fill(1, 1, fbcon.width, fbcon.height, " ")
    fbcon.x = 1
    fbcon.y = 1
    fbcon.buffer = {}
    fbcon.x_offset = 1
    fbcon.y_scroll = 1
    fbcon.blinking = false
    fbcon._blinkstate = false
    fbcon._lastBuffer = {}
    fbcon._lastXOffset = fbcon.x_offset
    fbcon._lastYScroll = fbcon.y_scroll
    if fbcon._blinkertid ~= 0 then
        kernel.killThread(2, fbcon._blinkertid)
    end
    fbcon_create_blinker_thread()
end

function fbcon.newline()
    if fbcon.y > fbcon.height then
        fbcon.scroll()
    end
    fbcon.y = fbcon.y + 1
    fbcon.x = 1
end

function fbcon.scroll(n)
    n = n or 1
    fbcon.y_scroll = fbcon.y_scroll + n
end

function fbcon.bindGPU()
    ---@type gpu_mod|nil
    local mod_gpu = module.getApi("gpu")
    if mod_gpu then
        fbcon.gpu = mod_gpu.get(1)
    else
        fbcon.gpu = component.proxy(component.list("gpu")())
    end
end

function fbcon.update()
    local gpu = fbcon.gpu
    fbcon.width, fbcon.height = gpu.getResolution()


    local fullRefresh = false
    -- x_offset or y_scroll変化で全行再描画にする
    if fbcon._lastXOffset ~= fbcon.x_offset or fbcon._lastYScroll ~= fbcon.y_scroll then
        fullRefresh = true
        fbcon._lastXOffset = fbcon.x_offset
        fbcon._lastYScroll = fbcon.y_scroll
    end

    local yScreen = 0
    for y = fbcon.y_scroll, #fbcon.buffer do
        yScreen = yScreen + 1
        if yScreen > fbcon.height then
            fbcon.y_scroll = fbcon.y_scroll + 1
        end

        local currentLine = fbcon.buffer[y]
        local lastLine = fbcon._lastBuffer[y]

        if fullRefresh or not fbcon_compareLine(currentLine, lastLine) then
            gpu.setForeground(0xFFFFFF)
            gpu.setBackground(0x000000)
            gpu.fill(fbcon.x_offset, yScreen, fbcon.width, 1, " ")

            fbcon.cx = fbcon.x_offset
            for _, segment in ipairs(currentLine or {}) do
                local segmentLength = #segment.text
                if fbcon.cx + segmentLength > fbcon.width then
                    yScreen = yScreen + 1
                    fbcon.cx = fbcon.x_offset
                    if yScreen > fbcon.height then
                        fbcon.y_scroll = fbcon.y_scroll + 1
                        break
                    end
                    gpu.fill(fbcon.x_offset, yScreen, fbcon.width, 1, " ")
                end
                gpu.setForeground(segment.fg)
                gpu.setBackground(segment.bg)
                gpu.set(fbcon.cx, yScreen, segment.text)
                fbcon.cx = fbcon.cx + segmentLength
            end

            fbcon._lastBuffer[y] = {}
            for i, seg in ipairs(currentLine or {}) do
                fbcon._lastBuffer[y][i] = { text = seg.text, fg = seg.fg, bg = seg.bg }
            end
        end
    end
    local lastLine = fbcon.buffer[#fbcon.buffer]
    if lastLine then
        local cursorX = fbcon.x_offset
        for i = 1, #lastLine do
            cursorX = cursorX + #lastLine[i].text
        end
        gpu.setForeground(0xFFFFFF)
        gpu.setBackground(0x000000)
        if fbcon.blinking then
            if fbcon._blinkstate then
                gpu.set(cursorX, yScreen, "_")
            else
                gpu.set(cursorX, yScreen, " ")
            end
        else
            gpu.set(cursorX, yScreen, " ")
        end
    end
end

function fbcon.removeChar(n)
    local lastLine = fbcon.buffer[#fbcon.buffer]
    if lastLine then
        fbcon.buffer[#fbcon.buffer][#lastLine].text = lastLine[#lastLine].text:sub(1, -math.abs(n) - 1)
    end
end

---@return std
function fbcon.getstd()
    ---@type std
    local std = {
        write = fbcon.write,
        printf = function(fmt, ...)
            fbcon.print(string.format(fmt, ...))
        end,
        print = fbcon.print,
        read = function(hideChars) error("Unsupported") end,
        readline = function(hideChars) error("Unsupported") end
    }
    return std
end

return fbcon, "fbcon"