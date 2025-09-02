-- companion.lua
-- Safe demo script to receive Job IDs from your Python service

local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

-- WebSocket (requires exploit environment with syn.websocket)
local ws = syn.websocket.connect("ws://localhost:5000/socket.io/?EIO=4&transport=websocket")

-- Toggle state
local enabled = true

-- Hotkey bindings
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.F6 then
        enabled = false
        warn("[Companion] Auto-inject paused")
    elseif input.KeyCode == Enum.KeyCode.F7 then
        enabled = true
        warn("[Companion] Auto-inject resumed")
    end
end)

-- Handle incoming messages
ws.OnMessage:Connect(function(msg)
    local ok, data = pcall(function()
        return HttpService:JSONDecode(msg)
    end)

    if ok and data.job_id then
        if enabled then
            print("[Companion] Received Job ID:", data.job_id, "| Money/sec:", data.money_per_sec or "N/A")
            -- In future: replace print() with code that autofills your panel
        else
            print("[Companion] Job received but paused:", data.job_id)
        end
    else
        warn("[Companion] Invalid message:", msg)
    end
end)

warn("[Companion] Connected to Job ID service. Use F6/F7 to pause/resume.")
