-- companion.lua (production-ready)
-- Safe companion: receives Job IDs from a local websocket and provides UI + filter
-- Requirements: an exploit environment with websocket support (e.g., syn.websocket)
-- NOTE: This script does NOT auto-inject into third-party clients. It only displays and optionally copies to clipboard.

local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

-- CONFIG
local WS_HOST = "localhost"
local WS_PORT = 5000
local WS_PATH = "/"  -- if your server uses a specific path, change this
local WS_URL = ("ws://%s:%d%s"):format(WS_HOST, WS_PORT, WS_PATH)
local DEFAULT_MIN_MONEY = 10_000_000  -- 10M default threshold

-- Runtime state
local enabled = true
local min_money = DEFAULT_MIN_MONEY
local last_job = nil
local ws = nil
local should_connect = true

-- UI creation helper
local function makeGui()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "JobIDCompanionGui"
    screenGui.ResetOnSpawn = false

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 420, 0, 140)
    frame.Position = UDim2.new(0, 16, 0, 16)
    frame.BackgroundColor3 = Color3.fromRGB(18, 24, 38)
    frame.BorderSizePixel = 0
    frame.Parent = screenGui
    frame.AnchorPoint = Vector2.new(0,0)
    frame.ClipsDescendants = true
    frame.Name = "Main"

    local title = Instance.new("TextLabel", frame)
    title.Size = UDim2.new(1, -16, 0, 28)
    title.Position = UDim2.new(0, 8, 0, 8)
    title.BackgroundTransparency = 1
    title.Text = "Job ID Companion"
    title.TextColor3 = Color3.fromRGB(235, 240, 250)
    title.Font = Enum.Font.SourceSansBold
    title.TextSize = 18
    title.TextXAlignment = Enum.TextXAlignment.Left

    local status = Instance.new("TextLabel", frame)
    status.Name = "Status"
    status.Size = UDim2.new(0, 120, 0, 20)
    status.Position = UDim2.new(1, -8 - 120, 0, 10)
    status.BackgroundTransparency = 1
    status.Font = Enum.Font.SourceSans
    status.TextSize = 14
    status.TextColor3 = Color3.fromRGB(160, 170, 190)
    status.Text = "Connecting..."
    status.TextXAlignment = Enum.TextXAlignment.Right

    local jidBox = Instance.new("TextBox", frame)
    jidBox.Name = "JobIDBox"
    jidBox.PlaceholderText = "Waiting for Job ID..."
    jidBox.ReadOnly = true
    jidBox.ClearTextOnFocus = false
    jidBox.Size = UDim2.new(1, -140, 0, 36)
    jidBox.Position = UDim2.new(0, 8, 0, 44)
    jidBox.BackgroundColor3 = Color3.fromRGB(11, 18, 30)
    jidBox.TextColor3 = Color3.fromRGB(235, 240, 250)
    jidBox.Font = Enum.Font.SourceSans
    jidBox.TextSize = 16
    jidBox.TextXAlignment = Enum.TextXAlignment.Left
    jidBox.TextWrapped = false
    jidBox.BorderSizePixel = 0

    local copyBtn = Instance.new("TextButton", frame)
    copyBtn.Name = "CopyButton"
    copyBtn.Size = UDim2.new(0, 64, 0, 36)
    copyBtn.Position = UDim2.new(1, -64 - 8, 0, 44)
    copyBtn.Text = "Copy"
    copyBtn.Font = Enum.Font.SourceSansBold
    copyBtn.TextSize = 14
    copyBtn.TextColor3 = Color3.fromRGB(255,255,255)
    copyBtn.BackgroundColor3 = Color3.fromRGB(91,140,255)
    copyBtn.BorderSizePixel = 0
    copyBtn.AutoButtonColor = true

    local mpsLabel = Instance.new("TextLabel", frame)
    mpsLabel.Name = "Mps"
    mpsLabel.Size = UDim2.new(0, 200, 0, 22)
    mpsLabel.Position = UDim2.new(0, 8, 0, 90)
    mpsLabel.BackgroundTransparency = 1
    mpsLabel.Font = Enum.Font.SourceSans
    mpsLabel.TextSize = 14
    mpsLabel.TextColor3 = Color3.fromRGB(200,200,210)
    mpsLabel.Text = "Money/sec: —"

    local playersLabel = Instance.new("TextLabel", frame)
    playersLabel.Name = "Players"
    playersLabel.Size = UDim2.new(0, 120, 0, 22)
    playersLabel.Position = UDim2.new(0, 220, 0, 90)
    playersLabel.BackgroundTransparency = 1
    playersLabel.Font = Enum.Font.SourceSans
    playersLabel.TextSize = 14
    playersLabel.TextColor3 = Color3.fromRGB(200,200,210)
    playersLabel.Text = "Players: —"

    local toggleBtn = Instance.new("TextButton", frame)
    toggleBtn.Name = "PauseBtn"
    toggleBtn.Size = UDim2.new(0, 84, 0, 28)
    toggleBtn.Position = UDim2.new(1, -8 - 84, 0, 88)
    toggleBtn.Text = "Pause (F6)"
    toggleBtn.Font = Enum.Font.SourceSansBold
    toggleBtn.TextSize = 13
    toggleBtn.TextColor3 = Color3.fromRGB(255,255,255)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(37,49,74)
    toggleBtn.BorderSizePixel = 0

    local filterLabel = Instance.new("TextLabel", frame)
    filterLabel.Name = "FilterLabel"
    filterLabel.Size = UDim2.new(0, 100, 0, 20)
    filterLabel.Position = UDim2.new(0, 8, 1, -28)
    filterLabel.BackgroundTransparency = 1
    filterLabel.Font = Enum.Font.SourceSans
    filterLabel.TextSize = 13
    filterLabel.TextColor3 = Color3.fromRGB(180,190,210)
    filterLabel.Text = "Min Money/sec:"

    local filterBox = Instance.new("TextBox", frame)
    filterBox.Name = "FilterBox"
    filterBox.Size = UDim2.new(0, 120, 0, 20)
    filterBox.Position = UDim2.new(0, 112, 1, -30)
    filterBox.BackgroundColor3 = Color3.fromRGB(10,16,26)
    filterBox.TextColor3 = Color3.fromRGB(240,240,240)
    filterBox.Font = Enum.Font.SourceSans
    filterBox.TextSize = 13
    filterBox.ClearTextOnFocus = false
    filterBox.PlaceholderText = tostring(DEFAULT_MIN_MONEY)

    -- Put GUI in PlayerGui (works in Studio and live)
    local player = game:GetService("Players").LocalPlayer
    if player then
        screenGui.Parent = player:WaitForChild("PlayerGui")
    else
        -- fallback for non-local contexts (rare)
        screenGui.Parent = game:GetService("StarterGui")
    end

    return {
        Gui = screenGui,
        Status = status,
        JobIDBox = jidBox,
        CopyButton = copyBtn,
        Mps = mpsLabel,
        Players = playersLabel,
        PauseBtn = toggleBtn,
        FilterBox = filterBox,
        Frame = frame,
    }
end

-- Clipboard helper (exploit API fallback)
local function safeCopyToClipboard(text)
    local ok, err
    if setclipboard then
        ok, err = pcall(setclipboard, tostring(text))
        return ok
    end
    -- some executors provide 'write_clipboard' or 'clipboard' - try common alternatives
    if syn and syn.set_thread_identity then
        -- no standard fallback; return false
        return false
    end
    return false
end

-- Logging helpers
local function info(...)
    print("[Companion][INFO]", ...)
end
local function warnMsg(...)
    warn("[Companion][WARN]", ...)
end
local function errMsg(...)
    warn("[Companion][ERROR]", ...)
end

-- Parse money value into integer (supports numbers and strings like "1.2k", "$1,234", etc.)
local function parse_money(val)
    if not val then return nil end
    if type(val) == "number" then return math.floor(val) end
    local s = tostring(val)
    s = s:lower():gsub("%$", ""):gsub(",", ""):gsub("%s+", "")
    -- handle k,m suffix
    local mul = 1
    local last = s:sub(-1)
    if last == "k" then mul = 1000; s = s:sub(1, -2)
    elseif last == "m" then mul = 1000000; s = s:sub(1, -2)
    end
    local n = tonumber(s)
    if not n then return nil end
    return math.floor(n * mul)
end

-- Apply job (only prints and updates UI; no auto-injection)
local function handle_job(data, ui)
    if not data or type(data) ~= "table" then return end
    local job_id = data.job_id or data.job_id_pc or data.jobID or data.jobId
    local money_raw = data.money_per_sec or data.money or data.mps
    local players = data.players or data.player_count

    local mps = parse_money(money_raw)
    if mps == nil then
        -- if money missing, treat as 0 (you may change this)
        mps = 0
    end

    -- Filter: require mps >= min_money
    if mps < min_money then
        info("Filtered out job:", job_id, "money/sec:", mps)
        return
    end

    last_job = { job_id = job_id, money = mps, players = players }

    -- Update UI
    if ui and ui.JobIDBox then
        ui.JobIDBox.Text = tostring(job_id or "—")
        ui.Mps.Text = "Money/sec: " .. tostring(mps)
        ui.Players.Text = "Players: " .. tostring(players or "—")
    end

    -- Print to output
    info("Accepted Job => ID:", job_id, "| Money/sec:", mps, "| Players:", players)
end

-- WebSocket connection with reconnection/backoff
local function start_ws(ui)
    -- require websocket API
    local ws_api = nil
    if syn and syn.websocket then
        ws_api = syn.websocket
    elseif websocket then
        ws_api = websocket -- some envs export 'websocket'
    elseif (typeof and typeof(http) == "table") then
        -- nothing standard we can use; we'll notify user
        warnMsg("No websocket API found (syn.websocket required). WebSocket features will not work in vanilla Roblox.")
        return
    else
        warnMsg("No known websocket API found - cannot connect.")
        return
    end

    spawn(function()
        local backoff = 1
        while should_connect do
            local ok, connOrErr = pcall(function()
                -- many executors expect Socket.IO query params; our server earlier used plain websockets.
                -- if your Python uses socket.io, you may need to use a socket.io compatible client instead.
                return ws_api.connect(WS_URL)
            end)
            if not ok or not connOrErr then
                errMsg("WebSocket connect failed:", connOrErr)
                backoff = math.min(backoff * 2, 60) -- exponential backoff up to 60s
                ui.Status.Text = "Reconnecting in " .. tostring(backoff) .. "s..."
                wait(backoff)
                goto continue
            end

            ws = connOrErr
            backoff = 1
            ui.Status.Text = "Connected"
            info("WebSocket connected to", WS_URL)

            -- connect handlers (patterns differ per exploit; we try common ones)
            local connected = true

            -- OnMessage handler
            if ws.OnMessage then
                -- syn.websocket style
                ws.OnMessage:Connect(function(msg)
                    local ok2, payload = pcall(function() return HttpService:JSONDecode(msg) end)
                    if not ok2 then
                        warnMsg("Bad JSON from WS:", msg)
                        return
                    end
                    if payload.type == "new_job" and payload.data then
                        handle_job(payload.data, ui)
                    elseif payload.type and payload.data then
                        -- other types
                    else
                        -- some servers send bare objects
                        if payload.job_id or payload.job_id_pc then
                            handle_job(payload, ui)
                        end
                    end
                end)
            elseif ws.onmessage then
                -- alternative naming
                ws.onmessage = function(msg) 
                    local ok2, payload = pcall(function() return HttpService:JSONDecode(msg) end)
                    if ok2 then
                        if payload.type == "new_job" then handle_job(payload.data, ui) end
                    end
                end
            end

            -- OnClose / OnClose event
            local closed = false
            if ws.OnClose then
                ws.OnClose:Connect(function()
                    closed = true
                    info("WebSocket closed")
                end)
            elseif ws.onclose then
                ws.onclose = function() closed = true end
            end

            -- Keep loop alive while connection is open
            while should_connect and not closed do
                wait(1)
            end

            info("WebSocket disconnected, will attempt reconnect")
            ui.Status.Text = "Disconnected - reconnecting..."
            if ws and (ws.Close or ws.close) then
                pcall(function()
                    if ws.Close then ws:Close() end
                    if ws.close then ws:close() end
                end)
            end

            ::continue::
            wait(backoff)
        end
    end)
end

-- Attach UI behavior
local ui = makeGui()

-- Copy button behavior
ui.CopyButton.MouseButton1Click:Connect(function()
    if not last_job then
        warnMsg("No job to copy")
        return
    end
    local did = safeCopyToClipboard(last_job.job_id)
    if did then
        ui.CopyButton.Text = "Copied!"
        wait(0.8)
        ui.CopyButton.Text = "Copy"
    else
        -- fallback: put job id into selection for manual copy
        ui.JobIDBox.Text = tostring(last_job.job_id)
        warnMsg("Clipboard API not available. Job ID set in box for manual copy.")
    end
end)

-- Pause button behavior
local function refreshPauseButton()
    if enabled then
        ui.PauseBtn.Text = "Pause (F6)"
        ui.Status.Text = (ui.Status.Text == "Paused") and "Live" or ui.Status.Text
    else
        ui.PauseBtn.Text = "Resume (F7)"
        ui.Status.Text = "Paused"
    end
end

ui.PauseBtn.MouseButton1Click:Connect(function()
    enabled = not enabled
    refreshPauseButton()
end)

-- Filter box behavior (apply on Enter)
ui.FilterBox.FocusLost:Connect(function(enterPressed)
    if not enterPressed then return end
    local val = tonumber(ui.FilterBox.Text)
    if val and val >= 0 then
        min_money = math.floor(val)
        info("Min money/sec set to", min_money)
    else
        -- try parsing strings like 10M, 1.2k etc.
        local parsed = parse_money(ui.FilterBox.Text)
        if parsed then
            min_money = parsed
            info("Min money/sec set to", min_money)
        else
            ui.FilterBox.Text = tostring(min_money)
            warnMsg("Invalid filter value; reverted to", min_money)
        end
    end
end)

-- Hotkeys: F6 = pause, F7 = resume
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.F6 then
        enabled = false
        refreshPauseButton()
        warnMsg("Paused (F6)")
    elseif input.KeyCode == Enum.KeyCode.F7 then
        enabled = true
        refreshPauseButton()
        warnMsg("Resumed (F7)")
    end
end)

-- Initialize filter box text
ui.FilterBox.Text = tostring(min_money)
refreshPauseButton()

-- Start websocket connection
start_ws(ui)

-- Expose some debug functions on the global to let you control from command bar if needed
_G.JobIDCompanion = {
    GetLastJob = function() return last_job end,
    SetMinMoney = function(v) min_money = tonumber(v) or min_money; ui.FilterBox.Text = tostring(min_money) end,
    Pause = function() enabled = false; refreshPauseButton() end,
    Resume = function() enabled = true; refreshPauseButton() end,
    Stop = function() should_connect = false; if ws and (ws.Close or ws.close) then pcall(function() if ws.Close then ws:Close() end if ws.close then ws:close() end end) end end,
}

info("JobID Companion initialized. Use F6/F7 to pause/resume. Min money/sec =", min_money)
