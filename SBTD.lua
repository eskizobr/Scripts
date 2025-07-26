-- ... (previous code as you wrote up to waitUntilVoteStart)
local function waitUntilVoteStart()
    while not (getVoteStartButton() and getVoteStartButton().Visible) do
        if not PlaybackToggle.CurrentValue then
            return false
        end
        task.wait(0.2)
    end
    return true
end

local function waitForWave(targetWave)
    targetWave = tostring(targetWave)
    while true do
        local curr = getCurrentWaveText()
        if curr == targetWave then return true end
        if not PlaybackToggle.CurrentValue then return false end
        task.wait(0.15)
    end
end

local function playMacro()
    if macroIsPlaying then return end
    macroIsPlaying = true
    macroStatusLabel:Set("Status: Waiting for VoteStart...")

    task.spawn(function()
        if not waitUntilVoteStart() then
            macroIsPlaying = false
            macroStatusLabel:Set("Status: Ready")
            return
        end
        macroStatusLabel:Set("Status: Playing Macro")
        local macroName = getPlaybackMacroName()
        if not macroName then
            Rayfield:Notify({
                Title = "No Macro Selected",
                Content = "No macro is currently selected or assigned for playback!",
                Duration = 3,
                Image = 4483362458,
            })
            macroIsPlaying = false
            macroStatusLabel:Set("Status: Ready")
            return
        end

        while PlaybackToggle.CurrentValue do
            local actions, macroData = loadMacroActions(macroName)
            if #actions == 0 then
                Rayfield:Notify({
                    Title = "Empty Macro",
                    Content = "Selected macro has no actions!",
                    Duration = 3,
                    Image = 4483362458,
                })
                macroIsPlaying = false
                macroStatusLabel:Set("Status: Ready")
                return
            end

            local labelToNewId = {}
            local noBuildZones = workspace:FindFirstChild("Map")
                and workspace.Map:FindFirstChild("Zones")
                and workspace.Map.Zones:FindFirstChild("NoBuildZones")
            if not noBuildZones then
                Rayfield:Notify({
                    Title = "NoBuildZones Missing",
                    Content = "NoBuildZones folder missing, can't play macro.",
                    Duration = 3,
                    Image = 4483362458,
                })
                macroIsPlaying = false
                macroStatusLabel:Set("Status: Ready")
                return
            end

            local placeTowerRF = ReplicatedStorage.Packages._Index["acecateer_knit@1.7.1"].knit.Services.TowerService.RF.PlaceTower
            local upgradeTowerRF = ReplicatedStorage.Packages._Index["acecateer_knit@1.7.1"].knit.Services.GameService.RF.UpgradeTower
            local voteStartRemote = ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("acecateer_knit@1.7.1"):WaitForChild("knit"):WaitForChild("Services"):WaitForChild("GameService"):WaitForChild("RF"):WaitForChild("VoteStartRound")

            local existingIds = {}
            for _, part in ipairs(noBuildZones:GetChildren()) do
                if part:IsA("BasePart") then
                    existingIds[part.Name] = true
                end
            end

            local playbackStartTime = tick()
            print("[Playback] Starting playback of " .. #actions .. " actions (accurate per-wave timing)")

            local actionsByWave = {}
            local waveOrder = {}
            for i, action in ipairs(actions) do
                local wave = tostring(action.wave or "1")
                if not actionsByWave[wave] then
                    actionsByWave[wave] = {}
                    table.insert(waveOrder, wave)
                end
                table.insert(actionsByWave[wave], action)
            end

            for _, wave in ipairs(waveOrder) do
                if not PlaybackToggle.CurrentValue then
                    Rayfield:Notify({
                        Title = "Playback Stopped",
                        Content = "Playback stopped.",
                        Duration = 3,
                        Image = 4483362458,
                    })
                    macroIsPlaying = false
                    macroStatusLabel:Set("Status: Ready")
                    return
                end

                Rayfield:Notify({
                    Title = "Waiting For Wave",
                    Content = "Waiting for Wave " .. tostring(wave),
                    Duration = 3,
                    Image = 4483362458,
                })
                local ok = waitForWave(wave)
                if not ok then
                    macroIsPlaying = false
                    macroStatusLabel:Set("Status: Ready")
                    return
                end

                local waveActions = actionsByWave[wave]
                local waveStartTick = tick()
                table.sort(waveActions, function(a, b) return (a.waveOffset or 0) < (b.waveOffset or 0) end)

                for _, action in ipairs(waveActions) do
                    if not PlaybackToggle.CurrentValue then
                        Rayfield:Notify({
                            Title = "Playback Stopped",
                            Content = "Playback stopped.",
                            Duration = 3,
                            Image = 4483362458,
                        })
                        macroIsPlaying = false
                        macroStatusLabel:Set("Status: Ready")
                        return
                    end
                    local waitFor = (action.waveOffset or 0)
                    while tick() - waveStartTick < waitFor do
                        task.wait(0.02)
                        if not PlaybackToggle.CurrentValue then
                            macroIsPlaying = false
                            macroStatusLabel:Set("Status: Ready")
                            return
                        end
                    end

                    if action.type == "place" then
                        -- Find the slot that has the recorded unitName
                        local slot2unit = getHotbarSlotUnitNames()
                        local slotId = nil
                        for slot, name in pairs(slot2unit) do
                            if name == action.unitName then
                                slotId = slot
                                break
                            end
                        end
                        if slotId then
                            local cf = tableToCFrame(action.cframe)
                            pcall(function()
                                placeTowerRF:InvokeServer(cf, slotId)
                            end)
                            local bestPart, bestDist
                            for waitTry = 1, 30 do
                                bestPart, bestDist = nil, math.huge
                                for _, part in ipairs(noBuildZones:GetChildren()) do
                                    if part:IsA("BasePart") and not existingIds[part.Name] then
                                        local matched, dist = isClose(part.CFrame, cf, 0.01)
                                        if matched and dist < bestDist then
                                            bestDist = dist
                                            bestPart = part
                                        end
                                    end
                                end
                                if bestPart then break end
                                task.wait(0.1)
                            end
                            if bestPart then
                                labelToNewId[action.label] = bestPart.Name
                                existingIds[bestPart.Name] = true
                            else
                                print("[Macro] WARNING: Could not map tower for label " .. action.label)
                            end
                        else
                            Rayfield:Notify({
                                Title = "Unit Not Found",
                                Content = "Unit '" .. tostring(action.unitName) .. "' not found in hotbar! Placement skipped.",
                                Duration = 3,
                                Image = 4483362458,
                            })
                        end
                    elseif action.type == "upgrade" then
                        local newId = labelToNewId[action.label]
                        if newId then
                            pcall(function()
                                upgradeTowerRF:InvokeServer(newId)
                            end)
                        else
                            print("[Macro] WARNING: No mapped tower for label " .. action.label .. " at " .. action.timeString)
                        end
                    elseif action.type == "votestart" then
                        pcall(function()
                            voteStartRemote:InvokeServer()
                        end)
                    end
                end
            end

            local totalPlaybackTime = tick() - playbackStartTime
            Rayfield:Notify({
                Title = "Macro Complete",
                Content = string.format("Macro complete (%ds). Waiting for next round (VoteStart)...", math.floor(totalPlaybackTime)),
                Duration = 4,
                Image = 4483362458,
            })
            macroStatusLabel:Set("Status: waiting for new round")

            macroStatusLabel:Set("Status: Waiting for VoteStart...")
            if not waitUntilVoteStart() then
                macroIsPlaying = false
                macroStatusLabel:Set("Status: Ready")
                return
            end
            macroStatusLabel:Set("Status: Playing Macro")
        end
        macroIsPlaying = false
        macroStatusLabel:Set("Status: Ready")
    end)
end
-- Spongebob Tower Defense Macro Script (Rayfield UI Version)
-- Macro now only starts playing when the VoteStart button is visible
wait(3)

-- === BEGIN: Rayfield Library Setup ===
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- === COMBINED CONFIGURATION (userSettings + stageMacroMap in one JSON file) ===
local configFolder = "SBTD_Config"
if not isfolder(configFolder) then makefolder(configFolder) end
local playerName = "Default"
pcall(function()
    playerName = LocalPlayer.Name
    playerName = playerName:gsub("[^%w_]", "_")
end)
local mainConfigFile = configFolder .. "/main_config_" .. playerName .. ".txt"

-- Default userSettings and stageMacroMap
local userSettings = {
    selectedMacro = nil,
    playbackToggle = false,
    autoReplayToggle = false,
    gameSpeed = "1x",
    autobuyToggles = {},
}
local stageMacroMap = {}

-- Autobuy toggles global (sync with userSettings.autobuyToggles)
local autobuyToggles = userSettings.autobuyToggles or {}

-- Save/load settings and macro assignments
local function saveConfig()
    userSettings.autobuyToggles = autobuyToggles
    local mainConfig = {
        userSettings = userSettings,
        stageMacroMap = stageMacroMap,
    }
    writefile(mainConfigFile, HttpService:JSONEncode(mainConfig))
end

local function loadConfig()
    if isfile(mainConfigFile) then
        local ok, data = pcall(function() return readfile(mainConfigFile) end)
        if ok and data then
            local ok2, parsed = pcall(function() return HttpService:JSONDecode(data) end)
            if ok2 and type(parsed) == "table" then
                if type(parsed.userSettings) == "table" then
                    for k, v in pairs(parsed.userSettings) do
                        userSettings[k] = v
                    end
                    if type(userSettings.autobuyToggles) == "table" then
                        autobuyToggles = userSettings.autobuyToggles
                    end
                end
                if type(parsed.stageMacroMap) == "table" then
                    stageMacroMap = parsed.stageMacroMap
                end
            end
        end
    end
end

loadConfig()

local placedTowers, placementCount, recordedActions = {}, 0, {}
local recording = false
local selectedMacro = userSettings.selectedMacro
local macroName = "" -- Only for current session

-- --- Utility: Close CFrame comparison
local function isClose(cframe1, cframe2, tolerance)
    tolerance = tolerance or 0.01
    local pos1, pos2 = cframe1.Position, cframe2.Position
    local dist = (pos1 - pos2).Magnitude
    return dist < tolerance, dist
end

local function cframeToTable(cf) return {cf:GetComponents()} end
local function tableToCFrame(tbl) return CFrame.new(unpack(tbl)) end
local function formatTime(seconds)
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    local milliseconds = math.floor((seconds % 1) * 1000)
    return string.format("%02d:%02d.%03d", minutes, secs, milliseconds)
end

local function getCurrentWaveText()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then return nil end
    local gameUI = gui:FindFirstChild("GameUI")
    if not gameUI then return nil end
    local top = gameUI:FindFirstChild("Top")
    if not top then return nil end
    local main = top:FindFirstChild("Main")
    if not main then return nil end
    local stageInfo = main:FindFirstChild("StageInfo")
    if not stageInfo then return nil end
    local inner = stageInfo:FindFirstChild("Inner")
    if not inner then return nil end
    local inner2 = inner:FindFirstChild("Inner")
    if not inner2 then return nil end
    local currentWave = inner2:FindFirstChild("CurrentWave")
    if not currentWave then return nil end
    return tostring(currentWave.Text or "")
end

local function fetchCurrentWaveSafe()
    for _ = 1, 10 do
        local waveText = getCurrentWaveText()
        if waveText and waveText ~= "" and waveText ~= "--" then
            return waveText
        end
        task.wait(0.05)
    end
    return "1"
end

local function getVoteStartButton()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if gui then
        local gameUI = gui:FindFirstChild("GameUI")
        if gameUI then
            local voteStart = gameUI:FindFirstChild("VoteStart")
            if voteStart then
                local main = voteStart:FindFirstChild("Main")
                if main then
                    return main:FindFirstChild("Button")
                end
            end
        end
    end
    return nil
end

local function getRoundSummaryScreen()
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if gui then
        local roundSummary = gui:FindFirstChild("RoundSummary")
        if roundSummary then
            return roundSummary
        end
    end
    return nil
end

local function isGameSummaryVisible()
    local screen = getRoundSummaryScreen()
    return screen and screen.Enabled
end

-- === Hotbar utility: Get slot -> unit name mapping
local function getHotbarSlotUnitNames()
    local hotbar = Players.LocalPlayer.PlayerGui.HUD.Bottom.Hotbar
    local slot2unit = {}
    for slot = 1, 6 do
        local slotFrame = hotbar:FindFirstChild(tostring(slot))
        if slotFrame then
            local content = slotFrame:FindFirstChild("Content")
            if content then
                local towerInfo = content:FindFirstChild("TowerInfo")
                if towerInfo then
                    local viewportFrame = towerInfo:FindFirstChild("ViewportFrame")
                    if viewportFrame then
                        local worldModel = viewportFrame:FindFirstChild("WorldModel")
                        if worldModel then
                            local children = worldModel:GetChildren()
                            if #children > 0 then
                                local unitModel = children[1]
                                slot2unit[slot] = unitModel.Name
                            end
                        end
                    end
                end
            end
        end
    end
    return slot2unit
end

local function refreshMacroList()
    local macroFolder = "SBTD_Macros"
    if not isfolder(macroFolder) then makefolder(macroFolder) end
    local files = listfiles(macroFolder)
    local macroFiles = {}
    for _, path in ipairs(files) do
        if path:sub(-4) == ".txt" then
            table.insert(macroFiles, path:match("([^/\\]+)%.txt$"))
        end
    end
    table.sort(macroFiles)
    return macroFiles
end

local function saveMacroAsTxt(macroName, recordedActions, macroData)
    local macroFolder = "SBTD_Macros"
    if not isfolder(macroFolder) then makefolder(macroFolder) end
    local filePath = macroFolder .. "/" .. macroName .. ".txt"
    local lines = {}
    table.insert(lines, "-- Spongebob Tower Defense Macro")
    table.insert(lines, "-- Macro Name: " .. macroName)
    table.insert(lines, "-- Player: " .. (macroData and macroData.player or "?"))
    table.insert(lines, "-- Recorded: " .. os.date("%Y-%m-%d %H:%M:%S", macroData and macroData.timestamp or os.time()))
    table.insert(lines, "-- Total time: " .. string.format("%.1fs", macroData and macroData.recordingTime or 0))
    table.insert(lines, "--")
    for i, action in ipairs(recordedActions) do
        local waveOffsetStr = string.format("WaveOffset:%.3f", action.waveOffset or 0)
        if action.type == "place" then
            table.insert(lines, string.format(
                "PLACE\t%s\tSlot:%d\tUnitName:%s\tWave:%s\tTime:%s\tCF:[%s]\tUID:%s\t%s",
                action.label,
                action.slotId,
                tostring(action.unitName or ""),
                action.wave or "1",
                action.timeString,
                table.concat(action.cframe, ", "),
                tostring(action.unitId or ""),
                waveOffsetStr
            ))
        elseif action.type == "upgrade" then
            table.insert(lines, string.format(
                "UPGRADE\t%s\tWave:%s\tTime:%s\tUID:%s\t%s",
                action.label,
                action.wave or "1",
                action.timeString,
                tostring(action.unitId or ""),
                waveOffsetStr
            ))
        elseif action.type == "votestart" then
            table.insert(lines, string.format(
                "VOTESTART\tWave:%s\tTime:%s\t%s",
                action.wave or "1",
                action.timeString,
                waveOffsetStr
            ))
        end
    end
    local txt = table.concat(lines, "\n")
    writefile(filePath, txt)
    return filePath
end

local function loadMacroActions(macroName)
    local macroFolder = "SBTD_Macros"
    if not isfolder(macroFolder) then makefolder(macroFolder) end
    local filePath = macroFolder .. "/" .. macroName .. ".txt"
    if isfile(filePath) then
        local txt = readfile(filePath)
        local actions = {}
        for line in txt:gmatch("[^\r\n]+") do
            if not line:find("^%-%-") and #line > 0 then
                local actionType = line:match("^(%u+)")
                local waveOffset = tonumber(line:match("WaveOffset:([%d%.%-]+)")) or 0
                if actionType == "PLACE" then
                    local label, slot, unitName, wave, timeString, cfString, uid = line:match("PLACE\t([^\t]+)\tSlot:(%d+)\tUnitName:([^\t]*)\tWave:([^\t]+)\tTime:([%d%:%d%.]+)\tCF:%[(.-)%]\tUID:([^\t]*)")
                    if label and slot and wave and timeString and cfString then
                        local cframe = {}
                        for num in cfString:gmatch("[-%d%.]+") do
                            table.insert(cframe, tonumber(num))
                        end
                        table.insert(actions, {
                            type = "place",
                            label = label,
                            slotId = tonumber(slot),
                            unitName = unitName ~= "" and unitName or nil,
                            wave = wave,
                            timeString = timeString,
                            cframe = cframe,
                            unitId = uid ~= "" and uid or nil,
                            timestamp = nil,
                            waveOffset = waveOffset
                        })
                    end
                elseif actionType == "UPGRADE" then
                    local label, wave, timeString, uid = line:match("UPGRADE\t([^\t]+)\tWave:([^\t]+)\tTime:([%d%:%d%.]+)\tUID:([^\t]*)")
                    if label and wave and timeString then
                        table.insert(actions, {
                            type = "upgrade",
                            label = label,
                            wave = wave,
                            timeString = timeString,
                            unitId = uid ~= "" and uid or nil,
                            timestamp = nil,
                            waveOffset = waveOffset
                        })
                    end
                elseif actionType == "VOTESTART" then
                    local wave, timeString = line:match("VOTESTART\tWave:([^\t]+)\tTime:([%d%:%d%.]+)")
                    if wave and timeString then
                        table.insert(actions, {
                            type = "votestart",
                            wave = wave,
                            timeString = timeString,
                            timestamp = nil,
                            waveOffset = waveOffset
                        })
                    end
                end
            end
        end
        for _, action in ipairs(actions) do
            if action.timeString then
                local min, sec, ms = action.timeString:match("(%d+):(%d+)%.(%d+)")
                action.timestamp = tonumber(min) * 60 + tonumber(sec) + tonumber(ms) / 1000
            end
        end
        return actions, {}
    end
    return {}, nil
end

-- Real-time NoBuildZones watcher for mapping unique tower IDs on placement
local knownUnitIds = {}
local unitIdToCFrame = {}

local function startNoBuildZonesWatcher()
    task.spawn(function()
        while true do
            local noBuildZones = workspace:FindFirstChild("Map")
                and workspace.Map:FindFirstChild("Zones")
                and workspace.Map.Zones:FindFirstChild("NoBuildZones")
            if noBuildZones then
                for _, part in ipairs(noBuildZones:GetChildren()) do
                    if part:IsA("BasePart") then
                        local uid = part.Name
                        local cf = part.CFrame
                        if not knownUnitIds[uid] then
                            knownUnitIds[uid] = true
                            unitIdToCFrame[uid] = cf
                        else
                            unitIdToCFrame[uid] = cf
                        end
                    end
                end
            end
            task.wait(0.05)
        end
    end)
end
startNoBuildZonesWatcher()

local function matchNewUnitIdByCFrame(cframe, placedIds)
    local bestId, bestDist = nil, math.huge
    for uid, cf in pairs(unitIdToCFrame) do
        if not placedIds[uid] then
            local close, dist = isClose(cf, cframe, 0.01)
            if close and dist < bestDist then
                bestId = uid
                bestDist = dist
            end
        end
    end
    return bestId
end

-- Robust Namecall hook for recording placements/upgrades
local mt = getrawmetatable(game)
local oldNamecall = mt.__namecall
local hookActive = false
local recordingStartTime = 0

local labelToUnitId = {}
local unitIdToLabel = {}
local placedIds = {}

-- Track wave start times for relative per-wave timings
local currentWaveNumber = "1"
local waveStartTimestamps = {}

local function updateWaveStart()
    local waveNow = fetchCurrentWaveSafe()
    if waveNow ~= currentWaveNumber then
        currentWaveNumber = waveNow
        waveStartTimestamps[waveNow] = tick()
    end
end

local pollWavesThread = nil
local function startWavePolling()
    if pollWavesThread then return end
    pollWavesThread = task.spawn(function()
        while recording do
            updateWaveStart()
            task.wait(0.05)
        end
    end)
end

local function stopWavePolling()
    if pollWavesThread then
        task.cancel(pollWavesThread)
        pollWavesThread = nil
    end
end

local function hookNamecallForRecording()
    if hookActive then return end
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        local result = oldNamecall(self, ...)
        if recording and method == "InvokeServer" then
            local objName = tostring(self)
            updateWaveStart()
            local wave = fetchCurrentWaveSafe()
            local waveTick = waveStartTimestamps[wave] or recordingStartTime
            local currentTime = tick()
            local waveOffset = currentTime - waveTick
            local relativeTime = currentTime - recordingStartTime
            if objName == "PlaceTower" then
                local cframe = args[1]
                local slotId = args[2] or 1
                local label = "unit" .. tostring(placementCount + 1)
                placementCount = placementCount + 1
                local cframeTable = cframeToTable(cframe)
                local foundUnitId = nil
                for attempt = 1, 40 do
                    foundUnitId = matchNewUnitIdByCFrame(cframe, placedIds)
                    if foundUnitId then break end
                    task.wait(0.05)
                end
                if foundUnitId then
                    labelToUnitId[label] = foundUnitId
                    unitIdToLabel[foundUnitId] = label
                    placedIds[foundUnitId] = true
                else
                    warn("[WARN] Could not find uniqueId for new tower placement!")
                end
                -- Hotbar slot to unit mapping
                local slot2unit = getHotbarSlotUnitNames()
                local unitName = slot2unit[slotId] or "UnknownUnit"
                table.insert(recordedActions, {
                    type = "place",
                    cframe = cframeTable,
                    slotId = slotId,
                    label = label,
                    unitId = foundUnitId,
                    unitName = unitName,
                    timestamp = relativeTime,
                    timeString = formatTime(relativeTime),
                    wave = wave,
                    waveOffset = waveOffset
                })
            elseif objName == "UpgradeTower" then
                local unitId = args[1]
                local label = unitIdToLabel[unitId] or unitId or "unknown"
                table.insert(recordedActions, {
                    type = "upgrade",
                    label = label,
                    unitId = unitId,
                    timestamp = relativeTime,
                    timeString = formatTime(relativeTime),
                    wave = wave,
                    waveOffset = waveOffset
                })
            end
        end
        return result
    end)
    setreadonly(mt, true)
    hookActive = true
end

function unhookNamecall()
    if not hookActive then return end
    setreadonly(mt, false)
    mt.__namecall = oldNamecall
    setreadonly(mt, true)
    hookActive = false
end

local voteStartBtnConn = nil
local function connectVoteStartForRecording()
    local btn = getVoteStartButton()
    if btn then
        if voteStartBtnConn then voteStartBtnConn:Disconnect() end
        voteStartBtnConn = btn.Activated:Connect(function()
            if recording then
                updateWaveStart()
                local wave = fetchCurrentWaveSafe()
                local waveTick = waveStartTimestamps[wave] or recordingStartTime
                local currentTime = tick()
                local waveOffset = currentTime - waveTick
                local relativeTime = currentTime - recordingStartTime
                table.insert(recordedActions, {
                    type = "votestart",
                    timestamp = relativeTime,
                    timeString = formatTime(relativeTime),
                    wave = wave,
                    waveOffset = waveOffset
                })
            end
        end)
    end
end

-- === RAYFIELD UI SETUP ===
local Window = Rayfield:CreateWindow({
    Name = "Spongebob Tower Defense - (BETA) ♥",
    LoadingTitle = "SBTD Macro Script",
    LoadingSubtitle = "by Your Script Creator",
    ConfigurationSaving = {
        Enabled = false,
    },
    Discord = {
        Enabled = false,
    },
    KeySystem = false,
})

-- Macro Tab
local MacroTab = Window:CreateTab("🎯 Macro", nil)

-- Recording Section
local RecordingSection = MacroTab:CreateSection("MACRO RECORDING 💕")

local macroStatusLabel = RecordingSection:CreateLabel("Status: Not Recording")

local MacroNameInput = RecordingSection:CreateInput({
    Name = "Macro Name (before you record)",
    PlaceholderText = "Enter macro name...",
    RemoveTextAfterFocusLost = false,
    Callback = function(Text)
        macroName = tostring(Text):gsub("[^%w_%-]", "_")
        Rayfield:Notify({
            Title = "Macro Name Set",
            Content = "Macro name set to: " .. macroName,
            Duration = 3,
            Image = 4483362458,
        })
    end,
})

local macroList = refreshMacroList()
local MacroDropdown = RecordingSection:CreateDropdown({
    Name = "Select Macro for Management",
    Options = macroList,
    CurrentOption = userSettings.selectedMacro,
    MultipleOptions = false,
    Flag = "MacroDropdown",
    Callback = function(Option)
        selectedMacro = Option
        userSettings.selectedMacro = Option
        saveConfig()
        if Option then
            Rayfield:Notify({
                Title = "Macro Selected",
                Content = "Selected macro: " .. tostring(Option),
                Duration = 3,
                Image = 4483362458,
            })
        else
            Rayfield:Notify({
                Title = "No Macro Selected",
                Content = "No macro selected.",
                Duration = 3,
                Image = 4483362458,
            })
        end
    end
})

local function updateMacroDropdown(selectMacro)
    local macros = refreshMacroList()
    MacroDropdown:Refresh(macros)
    if selectMacro and table.find(macros, selectMacro) then
        MacroDropdown:Set(selectMacro)
        selectedMacro = selectMacro
        userSettings.selectedMacro = selectMacro
        saveConfig()
    elseif #macros == 1 then
        MacroDropdown:Set(macros[1])
        selectedMacro = macros[1]
        userSettings.selectedMacro = macros[1]
        saveConfig()
    elseif #macros > 0 then
        MacroDropdown:Set(macros[1])
        selectedMacro = macros[1]
        userSettings.selectedMacro = macros[1]
        saveConfig()
    else
        MacroDropdown:Set(nil)
        selectedMacro = nil
        userSettings.selectedMacro = nil
        saveConfig()
    end
end

local DeleteMacroButton = RecordingSection:CreateButton({
    Name = "Delete Selected Macro",
    Callback = function()
        if selectedMacro then
            local macroFolder = "SBTD_Macros"
            if not isfolder(macroFolder) then makefolder(macroFolder) end
            local filePath = macroFolder .. "/" .. selectedMacro .. ".txt"
            if isfile(filePath) then
                delfile(filePath)
                Rayfield:Notify({
                    Title = "Macro Deleted",
                    Content = "Deleted macro: " .. selectedMacro,
                    Duration = 3,
                    Image = 4483362458,
                })
            else
                Rayfield:Notify({
                    Title = "File Not Found",
                    Content = "Macro file not found: " .. selectedMacro,
                    Duration = 3,
                    Image = 4483362458,
                })
            end
            updateMacroDropdown()
        else
            Rayfield:Notify({
                Title = "No Macro Selected",
                Content = "No macro selected.",
                Duration = 3,
                Image = 4483362458,
            })
            updateMacroDropdown()
        end
    end,
})

local ShowTimelineButton = RecordingSection:CreateButton({
    Name = "Show Macro Timeline (Console)",
    Callback = function()
        local macroToShow = selectedMacro
        if not macroToShow then
            Rayfield:Notify({
                Title = "No Macro Selected",
                Content = "Please select a macro first!",
                Duration = 3,
                Image = 4483362458,
            })
            return
        end
        local actions, macroData = loadMacroActions(macroToShow)
        if not actions or #actions == 0 then
            Rayfield:Notify({
                Title = "Empty Macro",
                Content = "Selected macro has no actions!",
                Duration = 3,
                Image = 4483362458,
            })
            return
        end
        print("\n=== MACRO TIMELINE: " .. macroToShow .. " ===")
        if macroData then
            print(string.format("  Player: %s", tostring(macroData.player or "?")))
            print(string.format("  Recorded: %s", os.date("%Y-%m-%d %H:%M:%S", macroData.timestamp or os.time())))
            print(string.format("  Total time: %s", macroData.recordingTime and string.format("%.1fs", macroData.recordingTime) or "?"))
            print(string.format("  Actions: %d", #actions))
            print("----")
        end
        for i, action in ipairs(actions) do
            if action.type == "place" then
                print(string.format("%2d. [%s] (Wave %s, @%.2fs) Place %s (Slot %d, Unit: %s) [UID: %s]", i, action.timeString, tostring(action.wave or "1"), action.waveOffset or 0, action.label, action.slotId, tostring(action.unitName or "?"), tostring(action.unitId or "?")))
            elseif action.type == "upgrade" then
                print(string.format("%2d. [%s] (Wave %s, @%.2fs) Upgrade %s [UID: %s]", i, action.timeString, tostring(action.wave or "1"), action.waveOffset or 0, action.label, tostring(action.unitId or "?")))
            elseif action.type == "votestart" then
                print(string.format("%2d. [%s] (Wave %s, @%.2fs) VoteStart Button Pressed", i, action.timeString, tostring(action.wave or "1"), action.waveOffset or 0))
            else
                print(string.format("%2d. [%s] (Wave %s) [UNKNOWN ACTION]", i, tostring(action.timeString or "?"), tostring(action.wave or "?")))
            end
        end
        print("=== END OF TIMELINE ===\n")
        Rayfield:Notify({
            Title = "Timeline Displayed",
            Content = "Check console for detailed timeline",
            Duration = 3,
            Image = 4483362458,
        })
    end,
})

local RecordToggle = RecordingSection:CreateToggle({
    Name = "Record",
    CurrentValue = false,
    Flag = "RecordToggle",
    Callback = function(Value)
        if Value then
            if not recording then
                recording = true
                placedTowers = {}
                placementCount = 0
                recordedActions = {}
                labelToUnitId = {}
                unitIdToLabel = {}
                placedIds = {}
                currentWaveNumber = fetchCurrentWaveSafe() or "1"
                waveStartTimestamps = {[currentWaveNumber] = tick()}
                recordingStartTime = tick()
                macroStatusLabel:Set("Status: Recording...")
                connectVoteStartForRecording()
                hookNamecallForRecording()
                startWavePolling()
                Rayfield:Notify({
                    Title = "Recording Started",
                    Content = "Recording started. Place towers, upgrade, and press VoteStart to record.",
                    Duration = 3,
                    Image = 4483362458,
                })
                print("[Recording] Started recording tower placements, upgrades, and VoteStart presses with timestamps.")
            end
        else
            if recording then
                recording = false
                unhookNamecall()
                if voteStartBtnConn then voteStartBtnConn:Disconnect() end
                stopWavePolling()
                local totalRecordingTime = tick() - recordingStartTime
                macroStatusLabel:Set(string.format("Status: Recorded %d actions in %.1fs", #recordedActions, totalRecordingTime))
                Rayfield:Notify({
                    Title = "Recording Stopped",
                    Content = string.format("Recorded %d actions in %.1f seconds", #recordedActions, totalRecordingTime),
                    Duration = 3,
                    Image = 4483362458,
                })
                print(string.format("[Recording] Stopped recording. Total time: %.2f seconds", totalRecordingTime))
                if #recordedActions > 0 and macroName and #macroName > 0 then
                    local macroData = {
                        name = macroName,
                        actions = recordedActions,
                        timestamp = os.time(),
                        recordingTime = totalRecordingTime,
                        player = playerName
                    }
                    local filePath = saveMacroAsTxt(macroName, recordedActions, macroData)
                    Rayfield:Notify({
                        Title = "Macro Saved",
                        Content = "Macro saved successfully",
                        Duration = 3,
                        Image = 4483362458,
                    })
                    print("[Macro] Saved to " .. filePath)
                    updateMacroDropdown(macroName)
                else
                    Rayfield:Notify({
                        Title = "Save Failed",
                        Content = "No macro name or no actions recorded.",
                        Duration = 3,
                        Image = 4483362458,
                    })
                end
                -- Clear macro name input after recording stops
                MacroNameInput:Set("")
                macroName = ""
            end
        end
    end,
})

-- === Macro playback logic (WAVE-BASED, COMPLETION-GUARANTEED, ACCURATE TIMING) ===
local macroIsPlaying = false
local autoPlaybackMacro = nil

local function getPlaybackMacroName()
    if autoPlaybackMacro ~= nil then
        return autoPlaybackMacro
    end
    return selectedMacro or userSettings.selectedMacro
end

local function waitUntilVoteStart()
    while not (getVoteStartButton() and getVoteStartButton().Visible) do
        if not PlaybackToggle.CurrentValue then
            return false
        end
        task.wait(0.2)
    end

local PlaybackToggle = RecordingSection:CreateToggle({
    Name = "Playback Macro",
    CurrentValue = userSettings.playbackToggle or false,
    Flag = "PlaybackToggle",
    Callback = function(Value)
        userSettings.playbackToggle = Value
        saveConfig()
        if Value then
            if not macroIsPlaying then
                playMacro()
            end
        else
            macroIsPlaying = false
            macroStatusLabel:Set("Status: Ready")
            Rayfield:Notify({
                Title = "Macro Playback",
                Content = "Playback manually stopped.",
                Duration = 3,
                Image = 4483362458,
            })
        end
    end,
})

-- Example extension: Add additional tabs/sections for merchant/mystery market/autobuy UI as you wish.
-- Use Rayfield:CreateTab, groupboxes, and toggles/buttons as demonstrated above.

-- You may want to port over your merchant/mystery market autobuyer system, etc.
-- If you want those sections fully ported, just say so!

Rayfield:Notify({
    Title = "SBTD Macro Loaded",
    Content = "Macro GUI loaded! Record/playback should work.",
    Duration = 6,
    Image = 4483362458,
})