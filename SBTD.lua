-- ====================================================================
-- SPONGEBOB TOWER DEFENSE SCRIPT V1.5
-- Complete organized and cleaned up version
-- ====================================================================

-- ====================================================================
-- CONSTANTS AND CONFIGURATION
-- ====================================================================

local CONSTANTS = {
    LOBBY_PLACE_ID = 123662243100680,
    CONFIG_FOLDER = "SBTD_Config",
    MACROS_FOLDER = "SBTD_Macros",
    SCRIPT_VERSION = "1.5",
    
    -- UI Constants
    LOADING_TIME = 5,
    MAX_TOWER_RETRIES = 40,
    WAVE_CHECK_INTERVAL = 0.05,
    AUTO_JOIN_CHECK_INTERVAL = 3,
    
    -- Timing
    MERCHANT_REFRESH_MINUTES = 10,
    MYSTERY_MARKET_REFRESH_MINUTES = 15,
    
    -- Game Speed Options
    GAME_SPEEDS = {
        ["1x"] = 1,
        ["2x"] = 2,
        ["3x"] = 3,
        ["5x"] = 4
    },
    
    -- Difficulty Mappings
    DIFFICULTIES = {
        ["Hard"] = 2,
        ["Nightmare"] = 3,
        ["Davy Jones' Locker"] = 4
    },
    
    -- Camera effects to disable for performance
    CAMERA_EFFECTS = {
        "AudioListener", "FocusHighlight", "NoBuildHighlight", 
        "PlacingHighlight", "ScreenBlur", "ScreenDepthOfField", "SelectionHighlight"
    },
    
    -- Items to exclude from merchant purchases
    EXCLUDED_MERCHANT_ITEMS = {
        "ChallengeToken", "Inventory", "Currency"
    }
}

-- ====================================================================
-- SERVICES AND GLOBALS
-- ====================================================================

local Services = {
    Players = game:GetService("Players"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    TeleportService = game:GetService("TeleportService"),
    RunService = game:GetService("RunService"),
    HttpService = game:GetService("HttpService"),
    Workspace = game:GetService("Workspace"),
    Lighting = game:GetService("Lighting")
}

local Player = Services.Players.LocalPlayer
local PlayerName = Player.Name:gsub("[^%w_]", "_")

-- Global state
local State = {
    isRecording = false,
    isPlayingMacro = false,
    autoJoinEnabled = false,
    currentWave = "1",
    waveStartTimes = {},
    recordingStartTime = 0,
    macroActions = {},
    unitCounter = 0,
    towerMappings = {},
    usedTowerIds = {},
    stageMacroMap = {},
    autobuyToggles = {},
    mysteryMarketToggles = {},
    selectedMacroName = "",
    
    -- Performance mode state
    performanceModeEnabled = false,
    hiddenObjects = {},
    originalLightingSettings = {},
    
    -- Auto-join state
    autoJoinConnection = nil,
    lastAutoJoinAttempt = 0,
    autoJoinCooldown = 2,
    waitingForPlayers = false,
    autoJoinStartTime = nil,
    
    -- Pre-match inventory snapshot
    preMatchInventory = {},
    hasPreMatchSnapshot = false
}

-- ====================================================================
-- CONFIGURATION SYSTEM
-- ====================================================================

local DefaultConfig = {
    -- Macro settings
    selectedMacro = nil,
    playbackToggle = false,
    autoReplayToggle = false,
    gameSpeed = "1x",
    
    -- Auto-buy toggles
    autobuyToggles = {},
    mysteryMarketToggles = {},
    
    -- Teleport settings
    AutoTeleportOnMerchant = false,
    AutoTeleportOnMysteryMarket = false,
    
    -- Game mode settings
    currentMode = "Lobby",
    selectedStage = "ConchStreet",
    selectedChapter = "Chapter_2",
    selectedDifficulty = "Hard",
    
    -- Auto-queue settings
    aqType = "Raid",
    aqDifficulty = 2,
    aqDifficultyName = "Hard",
    aqPriority = "Raid",
    aqRaidMaps = {},
    aqChallengeMaps = {},
    
    -- Story mode settings
    storyAutoJoin = false,
    minPlayersRequired = 1,
    aqAutoJoin = false,
    storyPartyOnly = false,
    autoJoinDelay = 5,
    
    -- Quality of life
    antiAfkEnabled = false,
    fpsCap = 60,
    resourceSaverEnabled = false,
    
    -- Auto features
    autoActivateBoosts = {},
    autoBoostsEnabled = false,
    autoOpenChests = {},
    autoOpenChestsEnabled = false,
    autoClaimPrizesEnabled = false,
    autoClaimSeasonPassEnabled = false,
    autoSkipCutscene = false,
    autoStartWave = false,
    autoClaimQuestsEnabled = false,
    autoPrestigeEnabled = false,
    
    -- Webhook settings
    completionWebhookUrl = "",
    completionWebhookEnabled = false,
    
    -- Crafting settings
    autoCraftEnabled = false,
    autoClaimEnabled = false,
    selectedCraftingRecipes = {},
    
    -- Misc
    bruteForceReplay = false
}

local Config = {}
for key, value in pairs(DefaultConfig) do
    Config[key] = value
end

-- ====================================================================
-- UTILITY FUNCTIONS
-- ====================================================================

local Utils = {}

function Utils.formatTime(seconds)
    local minutes = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    local milliseconds = math.floor(seconds % 1 * 1000)
    return string.format("%02d:%02d.%03d", minutes, secs, milliseconds)
end

function Utils.showNotification(message)
    task.defer(function()
        if Library then
            Library:Notify(message)
        else
            print("[SBTD] " .. message)
        end
    end)
end

function Utils.showError(message)
    task.defer(function()
        if Library then
            Library:Notify(message)
        else
            warn("[SBTD ERROR] " .. message)
        end
    end)
end

function Utils.isInLobby()
    return game.PlaceId == CONSTANTS.LOBBY_PLACE_ID
end

function Utils.getCurrentWave()
    local playerGui = Player:FindFirstChild("PlayerGui")
    if not playerGui then return nil end
    
    local gameUI = playerGui:FindFirstChild("GameUI")
    if not gameUI then return nil end
    
    local top = gameUI:FindFirstChild("Top")
    if not top then return nil end
    
    local main = top:FindFirstChild("Main")
    if not main then return nil end
    
    local stageInfo = main:FindFirstChild("StageInfo")
    if not stageInfo then return nil end
    
    local inner1 = stageInfo:FindFirstChild("Inner")
    if not inner1 then return nil end
    
    local inner2 = inner1:FindFirstChild("Inner")
    if not inner2 then return nil end
    
    local currentWave = inner2:FindFirstChild("CurrentWave")
    if not currentWave then return nil end
    
    return tostring(currentWave.Text or "")
end

function Utils.waitForWave()
    for i = 1, 10 do
        local wave = Utils.getCurrentWave()
        if wave and wave ~= "" and wave ~= "--" then
            return wave
        end
        task.wait(0.05)
    end
    return "1"
end

function Utils.getPlayerCount()
    return #Services.Players:GetPlayers()
end

function Utils.hasMinimumPlayers()
    return Utils.getPlayerCount() >= Config.minPlayersRequired
end

function Utils.comparePositions(pos1, pos2, tolerance)
    tolerance = tolerance or 0.01
    if typeof(pos1) ~= "CFrame" or typeof(pos2) ~= "CFrame" then
        warn("comparePositions called with non-CFrame arguments")
        return false, math.huge
    end
    
    local distance = (pos1.Position - pos2.Position).Magnitude
    return distance < tolerance, distance
end

function Utils.serializeCFrame(cframe)
    return {cframe:GetComponents()}
end

function Utils.deserializeCFrame(components)
    return CFrame.new(unpack(components))
end

function Utils.formatItemName(itemName)
    if type(itemName) == "string" and itemName:match("CHALLENGETOKEN") then
        return "Challenge Token Boost"
    end
    
    local nameMap = {
        AgedPatty = "Aged Patty",
        TraitRolls = "Trait Rolls",
        MagicConch = "Magic Conch",
        LegendaryTreasureChest = "Legendary Treasure Chest",
        MythicTreasureChest = "Mythic Treasure Chest",
        EpicTreasureChest = "Epic Treasure Chest",
        SecretTreasureChest = "Secret Treasure Chest",
        BoostedSecretChest = "Boosted Secret Chest",
        GoldenTraitRolls = "Golden Trait Rolls",
        PrettyPatties = "Pretty Patties",
        RandomUnit = "Random Unit",
        Inventory = "Inventory",
        Currency = "Currency"
    }
    
    if nameMap[itemName] then
        return nameMap[itemName]
    end
    
    return itemName:gsub("([a-z])([A-Z])", "%1 %2"):gsub("_", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

-- ====================================================================
-- CONFIGURATION MANAGEMENT
-- ====================================================================

local ConfigManager = {}

function ConfigManager.getConfigPath()
    return CONSTANTS.CONFIG_FOLDER .. "/unified_config_" .. PlayerName .. ".txt"
end

function ConfigManager.save()
    if not isfolder(CONSTANTS.CONFIG_FOLDER) then
        makefolder(CONSTANTS.CONFIG_FOLDER)
    end
    
    -- Update config with current state
    Config.autobuyToggles = State.autobuyToggles
    Config.mysteryMarketToggles = State.mysteryMarketToggles
    
    local configData = {
        userSettings = Config,
        stageMacroMap = State.stageMacroMap,
        version = CONSTANTS.SCRIPT_VERSION,
        lastSaved = os.time()
    }
    
    local success, result = pcall(function()
        local jsonData = Services.HttpService:JSONEncode(configData)
        writefile(ConfigManager.getConfigPath(), jsonData)
    end)
    
    if not success then
        warn("[Config] Failed to save: " .. tostring(result))
    end
end

function ConfigManager.load()
    local configPath = ConfigManager.getConfigPath()
    
    if not isfile(configPath) then
        print("[Config] No existing config file found, using defaults")
        return
    end
    
    local success, fileContent = pcall(readfile, configPath)
    if not success then
        warn("[Config] Failed to read config file: " .. tostring(fileContent))
        return
    end
    
    local success, configData = pcall(Services.HttpService.JSONDecode, Services.HttpService, fileContent)
    if not success then
        warn("[Config] Failed to parse config file: " .. tostring(configData))
        return
    end
    
    if configData.userSettings and type(configData.userSettings) == "table" then
        for key, value in pairs(configData.userSettings) do
            Config[key] = value
        end
        
        -- Load autobuy toggles
        if type(Config.autobuyToggles) == "table" then
            State.autobuyToggles = Config.autobuyToggles
        end
        if type(Config.mysteryMarketToggles) == "table" then
            State.mysteryMarketToggles = Config.mysteryMarketToggles
        end
        
        -- Initialize missing arrays
        Config.aqRaidMaps = Config.aqRaidMaps or {}
        Config.aqChallengeMaps = Config.aqChallengeMaps or {}
        Config.autoActivateBoosts = Config.autoActivateBoosts or {}
        Config.autoOpenChests = Config.autoOpenChests or {}
        Config.selectedCraftingRecipes = Config.selectedCraftingRecipes or {}
        
        print("[Config] Loaded config successfully")
    end
    
    if configData.stageMacroMap and type(configData.stageMacroMap) == "table" then
        State.stageMacroMap = configData.stageMacroMap
    end
end

-- ====================================================================
-- GAME DETECTION AND STATE
-- ====================================================================

local GameState = {}

function GameState.getCurrentMode()
    local success, result = pcall(function()
        return require(Services.ReplicatedStorage:WaitForChild("PlaceIds", 5)):GetDestination()
    end)
    
    if success and result then
        return result
    end
    
    if Utils.isInLobby() then
        return "Lobby"
    end
    
    local playerGui = Player:FindFirstChild("PlayerGui")
    if playerGui and playerGui:FindFirstChild("GameUI") then
        return "Story"
    end
    
    return "Lobby"
end

function GameState.isVoteStartVisible()
    local playerGui = Player:FindFirstChild("PlayerGui")
    if not playerGui then return false end
    
    local gameUI = playerGui:FindFirstChild("GameUI")
    if not gameUI then return false end
    
    local voteStart = gameUI:FindFirstChild("VoteStart")
    if not voteStart then return false end
    
    local main = voteStart:FindFirstChild("Main")
    if not main then return false end
    
    local button = main:FindFirstChild("Button")
    return button and button.Visible
end

function GameState.isRoundSummaryVisible()
    local playerGui = Player:FindFirstChild("PlayerGui")
    if not playerGui then return false end
    
    local roundSummary = playerGui:FindFirstChild("RoundSummary")
    return roundSummary and roundSummary.Enabled
end

function GameState.getCurrentMapName()
    local playerGui = Player:FindFirstChild("PlayerGui")
    if not playerGui then return nil end
    
    local gameUI = playerGui:FindFirstChild("GameUI")
    if not gameUI then return nil end
    
    local top = gameUI:FindFirstChild("Top")
    if not top then return nil end
    
    local main = top:FindFirstChild("Main")
    if not main then return nil end
    
    local stageInfo = main:FindFirstChild("StageInfo")
    if not stageInfo then return nil end
    
    local inner1 = stageInfo:FindFirstChild("Inner")
    if not inner1 then return nil end
    
    local inner2 = inner1:FindFirstChild("Inner")
    if not inner2 then return nil end
    
    local worldTitle = inner2:FindFirstChild("WorldTitle")
    if not worldTitle then return nil end
    
    return worldTitle.Text
end

function GameState.getHotbarUnits()
    local hotbar = Player.PlayerGui.HUD.Bottom.Hotbar
    local units = {}
    
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
                                units[slot] = children[1].Name
                            end
                        end
                    end
                end
            end
        end
    end
    
    return units
end

-- ====================================================================
-- CURRENCY AND INVENTORY
-- ====================================================================

local Economy = {}

function Economy.getCurrency()
    local success, result = pcall(function()
        local knit = require(Services.ReplicatedStorage.Packages.Knit)
        local dataController = knit.GetController("DataController")
        
        local coins = dataController:Get(Player, "Currency.Coins"):expect()
        local gems = dataController:Get(Player, "Currency.Gems"):expect()
        
        return coins or 0, gems or 0
    end)
    
    if success then
        return result
    else
        return 0, 0
    end
end

function Economy.getGems()
    local _, gems = Economy.getCurrency()
    return gems
end

function Economy.getFullInventory()
    local success, result = pcall(function()
        local knit = require(Services.ReplicatedStorage.Packages.Knit)
        local dataController = knit.GetController("DataController")
        
        local inventory = {}
        
        -- Get currency
        local currency = dataController:Get(Player, "Currency"):expect()
        for key, value in pairs(currency) do
            inventory[key] = value
        end
        
        -- Get inventory items
        local items = dataController:Get(Player, "Inventory"):expect()
        for key, value in pairs(items) do
            inventory[key] = value
        end
        
        return inventory
    end)
    
    return success and result or {}
end

-- ====================================================================
-- MACRO SYSTEM
-- ====================================================================

local MacroSystem = {}

-- Tower tracking for macro recording
local TowerTracker = {}
local noBuildZones = {}
local hookInstalled = false
local originalNamecall = nil

function TowerTracker.initialize()
    task.spawn(function()
        while true do
            local map = Services.Workspace:FindFirstChild("Map")
            if map then
                local zones = map:FindFirstChild("Zones")
                if zones then
                    local noBuildZones_folder = zones:FindFirstChild("NoBuildZones")
                    if noBuildZones_folder then
                        for _, zone in ipairs(noBuildZones_folder:GetChildren()) do
                            if zone:IsA("BasePart") then
                                local zoneId = zone.Name
                                local position = zone.CFrame
                                noBuildZones[zoneId] = position
                            end
                        end
                    end
                end
            end
            task.wait(0.05)
        end
    end)
end

function TowerTracker.findNearestUnusedZone(targetPosition, usedZones)
    local nearestZone, nearestDistance = nil, math.huge
    
    for zoneId, position in pairs(noBuildZones) do
        if not usedZones[zoneId] then
            local isNear, distance = Utils.comparePositions(position, targetPosition, 0.01)
            if isNear and distance < nearestDistance then
                nearestZone = zoneId
                nearestDistance = distance
            end
        end
    end
    
    return nearestZone
end

function TowerTracker.installHook()
    if hookInstalled then return end
    
    local metatable = getrawmetatable(game)
    local originalNamecall = metatable.__namecall
    
    setreadonly(metatable, false)
    metatable.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        local result = originalNamecall(self, ...)
        
        if State.isRecording and method == "InvokeServer" then
            local remoteName = tostring(self)
            
            -- Update wave tracking
            local currentWave = GameState.isVoteStartVisible() and "before votestart" or Utils.waitForWave()
            local waveStartTime = State.waveStartTimes[currentWave] or State.recordingStartTime
            local currentTime = tick()
            local waveOffset = currentTime - waveStartTime
            local totalTime = currentTime - State.recordingStartTime
            
            if remoteName == "PlaceTower" then
                local position = args[1]
                local slot = args[2] or 1
                
                local unitLabel = "unit" .. tostring(State.unitCounter + 1)
                State.unitCounter = State.unitCounter + 1
                
                local serializedPosition = Utils.serializeCFrame(position)
                
                -- Find unique tower ID
                local uniqueId = nil
                for attempt = 1, 40 do
                    uniqueId = TowerTracker.findNearestUnusedZone(position, State.usedTowerIds)
                    if uniqueId then break end
                    task.wait(0.05)
                end
                
                if uniqueId then
                    State.towerMappings[unitLabel] = uniqueId
                    State.usedTowerIds[uniqueId] = unitLabel
                end
                
                local hotbarUnits = GameState.getHotbarUnits()
                local unitName = hotbarUnits[slot] or "UnknownUnit"
                
                table.insert(State.macroActions, {
                    type = "place",
                    cframe = serializedPosition,
                    slotId = slot,
                    label = unitLabel,
                    unitId = uniqueId,
                    unitName = unitName,
                    timestamp = totalTime,
                    timeString = Utils.formatTime(totalTime),
                    wave = currentWave,
                    waveOffset = waveOffset
                })
                
            elseif remoteName == "UpgradeTower" then
                local towerId = args[1]
                local unitLabel = State.usedTowerIds[towerId] or towerId or "unknown"
                
                table.insert(State.macroActions, {
                    type = "upgrade",
                    label = unitLabel,
                    unitId = towerId,
                    timestamp = totalTime,
                    timeString = Utils.formatTime(totalTime),
                    wave = currentWave,
                    waveOffset = waveOffset
                })
                
            elseif remoteName == "SellTower" then
                local towerId = args[1]
                local unitLabel = State.usedTowerIds[towerId] or towerId or "unknown"
                
                table.insert(State.macroActions, {
                    type = "sell",
                    label = unitLabel,
                    unitId = towerId,
                    timestamp = totalTime,
                    timeString = Utils.formatTime(totalTime),
                    wave = currentWave,
                    waveOffset = waveOffset
                })
            end
        end
        
        return result
    end)
    setreadonly(metatable, true)
    hookInstalled = true
end

function TowerTracker.uninstallHook()
    if not hookInstalled then return end
    
    local metatable = getrawmetatable(game)
    setreadonly(metatable, false)
    metatable.__namecall = originalNamecall
    setreadonly(metatable, true)
    hookInstalled = false
end

function MacroSystem.getAvailableMacros()
    if not isfolder(CONSTANTS.MACROS_FOLDER) then
        makefolder(CONSTANTS.MACROS_FOLDER)
    end
    
    local files = listfiles(CONSTANTS.MACROS_FOLDER)
    local macros = {}
    
    for _, filePath in ipairs(files) do
        if filePath:sub(-4) == ".txt" then
            table.insert(macros, filePath:match("([^/\\]+)%.txt$"))
        end
    end
    
    table.sort(macros)
    return macros
end

function MacroSystem.startRecording(macroName)
    if State.isRecording then
        Utils.showError("Already recording!")
        return false
    end
    
    State.isRecording = true
    State.macroActions = {}
    State.unitCounter = 0
    State.towerMappings = {}
    State.usedTowerIds = {}
    State.selectedMacroName = macroName
    State.currentWave = Utils.waitForWave() or "1"
    State.waveStartTimes = {[State.currentWave] = tick()}
    State.recordingStartTime = tick()
    
    TowerTracker.installHook()
    
    Utils.showNotification("Recording started for: " .. macroName)
    return true
end

function MacroSystem.stopRecording()
    if not State.isRecording then
        return false
    end
    
    State.isRecording = false
    TowerTracker.uninstallHook()
    
    local recordingTime = tick() - State.recordingStartTime
    
    if #State.macroActions > 0 and State.selectedMacroName and #State.selectedMacroName > 0 then
        local metadata = {
            name = State.selectedMacroName,
            actions = State.macroActions,
            timestamp = os.time(),
            recordingTime = recordingTime,
            player = PlayerName
        }
        
        MacroSystem.saveMacro(State.selectedMacroName, State.macroActions, metadata)
        Utils.showNotification(string.format("Macro '%s' saved successfully.", State.selectedMacroName))
        return State.selectedMacroName
    else
        Utils.showError("Could not save macro: No name given or no actions recorded.")
        return false
    end
end

function MacroSystem.saveMacro(name, actions, metadata)
    if not isfolder(CONSTANTS.MACROS_FOLDER) then
        makefolder(CONSTANTS.MACROS_FOLDER)
    end
    
    local filePath = CONSTANTS.MACROS_FOLDER .. "/" .. name .. ".txt"
    local lines = {}
    
    -- Header
    table.insert(lines, "-- Spongebob Tower Defense Macro V1.3")
    table.insert(lines, "-- Macro Name: " .. name)
    table.insert(lines, "-- Player: " .. (metadata and metadata.player or "?"))
    table.insert(lines, "-- Recorded: " .. os.date("%Y-%m-%d %H:%M:%S", metadata and metadata.timestamp or os.time()))
    table.insert(lines, "-- Total time: " .. string.format("%.1fs", metadata and metadata.recordingTime or 0))
    table.insert(lines, "--")
    
    -- Actions
    for _, action in ipairs(actions) do
        if action.type == "place" then
            local waveOffset = action.wave == "before votestart" and "" or string.format("\tWaveOffset:%.3f", action.waveOffset or 0)
            table.insert(lines, string.format("PLACE\t%s\tSlot:%d\tUnitName:%s\tWave:%s\tTime:%s\tCF:[%s]\tUID:%s%s",
                action.label, action.slotId, tostring(action.unitName or ""), action.wave or "1",
                action.timeString, table.concat(action.cframe, ", "), tostring(action.unitId or ""), waveOffset))
                
        elseif action.type == "upgrade" then
            local waveOffset = action.wave == "before votestart" and "" or string.format("\tWaveOffset:%.3f", action.waveOffset or 0)
            table.insert(lines, string.format("UPGRADE\t%s\tWave:%s\tTime:%s\tUID:%s%s",
                action.label, action.wave or "1", action.timeString, tostring(action.unitId or ""), waveOffset))
                
        elseif action.type == "sell" then
            local waveOffset = action.wave == "before votestart" and "" or string.format("\tWaveOffset:%.3f", action.waveOffset or 0)
            table.insert(lines, string.format("SELL\t%s\tWave:%s\tTime:%s\tUID:%s%s",
                action.label, action.wave or "1", action.timeString, tostring(action.unitId or ""), waveOffset))
        end
    end
    
    local content = table.concat(lines, "\n")
    writefile(filePath, content)
    return filePath
end

function MacroSystem.loadMacro(name)
    if not isfolder(CONSTANTS.MACROS_FOLDER) then
        makefolder(CONSTANTS.MACROS_FOLDER)
    end
    
    local filePath = CONSTANTS.MACROS_FOLDER .. "/" .. name .. ".txt"
    if not isfile(filePath) then
        return {}, nil
    end
    
    local content = readfile(filePath)
    local actions = {}
    
    for line in content:gmatch("[^\r\n]+") do
        if not line:find("^%-%-") and #line > 0 then
            local actionType = line:match("^(%u+)")
            
            if actionType == "PLACE" then
                local label, slot, unitName, wave, timeString, cframeStr, unitId, extraData = 
                    line:match("PLACE\t([^\t]+)\tSlot:(%d+)\tUnitName:([^\t]*)\tWave:([^\t]+)\tTime:([%d%:%d%.]+)\tCF:%[(.-)%]\tUID:([^\t]*)%s*(.*)")
                
                local waveOffset = extraData and tonumber(extraData:match("WaveOffset:([%d%.%-]+)")) or 0
                
                if label and slot and wave and timeString and cframeStr then
                    local cframe = {}
                    for num in cframeStr:gmatch("[-%d%.]+") do
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
                        unitId = unitId ~= "" and unitId or nil,
                        waveOffset = waveOffset
                    })
                end
                
            elseif actionType == "UPGRADE" then
                local label, wave, timeString, unitId, extraData = 
                    line:match("UPGRADE\t([^\t]+)\tWave:([^\t]+)\tTime:([%d%:%d%.]+)\tUID:([^\t]*)%s*(.*)")
                
                local waveOffset = extraData and tonumber(extraData:match("WaveOffset:([%d%.%-]+)")) or 0
                
                if label and wave and timeString then
                    table.insert(actions, {
                        type = "upgrade",
                        label = label,
                        wave = wave,
                        timeString = timeString,
                        unitId = unitId ~= "" and unitId or nil,
                        waveOffset = waveOffset
                    })
                end
                
            elseif actionType == "SELL" then
                local label, wave, timeString, unitId, extraData = 
                    line:match("SELL\t([^\t]+)\tWave:([^\t]+)\tTime:([%d%:%d%.]+)\tUID:([^\t]*)%s*(.*)")
                
                local waveOffset = extraData and tonumber(extraData:match("WaveOffset:([%d%.%-]+)")) or 0
                
                if label and wave and timeString then
                    table.insert(actions, {
                        type = "sell",
                        label = label,
                        wave = wave,
                        timeString = timeString,
                        unitId = unitId ~= "" and unitId or nil,
                        waveOffset = waveOffset
                    })
                end
            end
        end
    end
    
    -- Convert time strings to timestamps
    for _, action in ipairs(actions) do
        if action.timeString then
            local minutes, seconds, milliseconds = action.timeString:match("(%d+):(%d+)%.(%d+)")
            action.timestamp = tonumber(minutes) * 60 + tonumber(seconds) + tonumber(milliseconds) / 1000
        end
    end
    
    return actions, {}
end

function MacroSystem.playMacro(macroName)
    if State.isPlayingMacro then
        Utils.showError("A macro is already playing.")
        return
    end
    
    State.isPlayingMacro = true
    Utils.showNotification("Playing macro: " .. macroName)
    
    local actions, metadata = MacroSystem.loadMacro(macroName)
    if not actions or #actions == 0 then
        Utils.showError("Macro '" .. macroName .. "' is empty or could not be loaded.")
        State.isPlayingMacro = false
        return
    end
    
    task.spawn(function()
        -- Get remote functions
        local placeTowerRemote = Services.ReplicatedStorage.Packages._Index["acecateer_knit@1.7.1"].knit.Services.TowerService.RF.PlaceTower
        local upgradeTowerRemote = Services.ReplicatedStorage.Packages._Index["acecateer_knit@1.7.1"].knit.Services.GameService.RF.UpgradeTower
        local sellTowerRemote = Services.ReplicatedStorage.Packages._Index["acecateer_knit@1.7.1"].knit.Services.TowerService.RF.SellTower
        local voteStartRemote = Services.ReplicatedStorage.Packages._Index["acecateer_knit@1.7.1"].knit.Services.GameService.RF.VoteStartRound
        
        -- Group actions by wave
        local waveActions = {}
        local waves = {}
        local waveSet = {}
        
        for _, action in ipairs(actions) do
            local wave = action.wave or "1"
            if not waveActions[wave] then
                waveActions[wave] = {}
                if not waveSet[wave] then
                    table.insert(waves, wave)
                    waveSet[wave] = true
                end
            end
            table.insert(waveActions[wave], action)
        end
        
        -- Sort waves
        table.sort(waves, function(a, b)
            if a == "before votestart" then return true end
            if b == "before votestart" then return false end
            local numA = tonumber(string.match(a, "%d+")) or 0
            local numB = tonumber(string.match(b, "%d+")) or 0
            return numA < numB
        end)
        
        local towerIdMap = {}
        local map = Services.Workspace:FindFirstChild("Map")
        local noBuildZones_folder = map and map:FindFirstChild("Zones") and map.Zones:FindFirstChild("NoBuildZones")
        
        if not noBuildZones_folder then
            Utils.showError("Error during playback: Could not find the map's NoBuildZones folder.")
            State.isPlayingMacro = false
            return
        end
        
        local usedZones = {}
        for _, zone in ipairs(noBuildZones_folder:GetChildren()) do
            if zone:IsA("BasePart") then
                usedZones[zone.Name] = true
            end
        end
        
        -- Handle pre-wave actions
        local preWaveActions = waveActions["before votestart"]
        if preWaveActions and #preWaveActions > 0 then
            Utils.showNotification("Placing pre-wave units...")
            
            for _, action in ipairs(preWaveActions) do
                if not State.isPlayingMacro then break end
                
                if action.type == "place" then
                    local hotbarUnits = GameState.getHotbarUnits()
                    local slot = nil
                    
                    for slotNum, unitName in pairs(hotbarUnits) do
                        if unitName == action.unitName then
                            slot = slotNum
                            break
                        end
                    end
                    
                    if slot then
                        local position = Utils.deserializeCFrame(action.cframe)
                        pcall(function()
                            placeTowerRemote:InvokeServer(position, slot)
                        end)
                        
                        -- Find the placed tower
                        local towerId = nil
                        for attempt = 1, 30 do
                            for _, zone in ipairs(noBuildZones_folder:GetChildren()) do
                                if zone:IsA("BasePart") and not usedZones[zone.Name] then
                                    local isNear, distance = Utils.comparePositions(zone.CFrame, position, 0.01)
                                    if isNear then
                                        towerId = zone
                                        break
                                    end
                                end
                            end
                            if towerId then break end
                            task.wait(0.1)
                        end
                        
                        if towerId then
                            towerIdMap[action.label] = towerId.Name
                            usedZones[towerId.Name] = true
                        end
                    else
                        Utils.showError("Unit '" .. tostring(action.unitName) .. "' not found in hotbar!")
                    end
                    
                elseif action.type == "upgrade" then
                    local towerId = towerIdMap[action.label]
                    if towerId then
                        pcall(function()
                            upgradeTowerRemote:InvokeServer(towerId)
                        end)
                    end
                    
                elseif action.type == "sell" then
                    local towerId = towerIdMap[action.label]
                    if towerId then
                        pcall(function()
                            sellTowerRemote:InvokeServer(towerId)
                        end)
                        towerIdMap[action.label] = nil
                    end
                end
            end
            
            -- Remove "before votestart" from waves list
            for i, wave in ipairs(waves) do
                if wave == "before votestart" then
                    table.remove(waves, i)
                    break
                end
            end
        end
        
        if not State.isPlayingMacro then
            State.isPlayingMacro = false
            return
        end
        
        Utils.showNotification("Starting game...")
        pcall(function()
            voteStartRemote:InvokeServer()
        end)
        task.wait(0.5)
        
        -- Execute wave actions
        for _, waveNum in ipairs(waves) do
            if not State.isPlayingMacro then break end
            
            local targetWave = tonumber(string.match(waveNum, "%d+"))
            if targetWave then
                Utils.showNotification("Waiting for Wave: " .. targetWave)
                
                while State.isPlayingMacro do
                    local currentWaveStr = Utils.getCurrentWave()
                    if currentWaveStr then
                        local currentWave = tonumber(string.match(currentWaveStr, "%d+"))
                        if currentWave and currentWave >= targetWave then
                            break
                        end
                    end
                    task.wait(0.2)
                end
                
                if not State.isPlayingMacro then break end
                
                local actions = waveActions[waveNum]
                local waveStartTime = tick()
                
                -- Sort actions by wave offset
                table.sort(actions, function(a, b)
                    return (a.waveOffset or 0) < (b.waveOffset or 0)
                end)
                
                for _, action in ipairs(actions) do
                    if not State.isPlayingMacro then break end
                    
                    local targetTime = action.waveOffset or 0
                    while tick() - waveStartTime < targetTime do
                        task.wait(0.02)
                        if not State.isPlayingMacro then break end
                    end
                    
                    if not State.isPlayingMacro then break end
                    
                    if action.type == "place" then
                        local hotbarUnits = GameState.getHotbarUnits()
                        local slot = nil
                        
                        for slotNum, unitName in pairs(hotbarUnits) do
                            if unitName == action.unitName then
                                slot = slotNum
                                break
                            end
                        end
                        
                        if slot then
                            local position = Utils.deserializeCFrame(action.cframe)
                            pcall(function()
                                placeTowerRemote:InvokeServer(position, slot)
                            end)
                            
                            -- Find the placed tower
                            local towerId = nil
                            for attempt = 1, 30 do
                                for _, zone in ipairs(noBuildZones_folder:GetChildren()) do
                                    if zone:IsA("BasePart") and not usedZones[zone.Name] then
                                        local isNear, distance = Utils.comparePositions(zone.CFrame, position, 0.01)
                                        if isNear then
                                            towerId = zone
                                            break
                                        end
                                    end
                                end
                                if towerId then break end
                                task.wait(0.1)
                            end
                            
                            if towerId then
                                towerIdMap[action.label] = towerId.Name
                                usedZones[towerId.Name] = true
                            end
                        end
                        
                    elseif action.type == "upgrade" then
                        local towerId = towerIdMap[action.label]
                        if towerId then
                            pcall(function()
                                upgradeTowerRemote:InvokeServer(towerId)
                            end)
                        end
                        
                    elseif action.type == "sell" then
                        local towerId = towerIdMap[action.label]
                        if towerId then
                            pcall(function()
                                sellTowerRemote:InvokeServer(towerId)
                            end)
                            towerIdMap[action.label] = nil
                        end
                    end
                end
            end
        end
        
        if State.isPlayingMacro then
            State.isPlayingMacro = false
            Utils.showNotification("Macro playback completed.")
        end
    end)
end

function MacroSystem.stopPlayback()
    State.isPlayingMacro = false
    Utils.showNotification("Macro playback stopped.")
end

-- ====================================================================
-- AUTO-JOIN SYSTEM
-- ====================================================================

local AutoJoinSystem = {}

function AutoJoinSystem.getLevelData()
    local levelData = {
        raids = {display = {}, map = {}, reverseMap = {}},
        challenges = {display = {}, map = {}, reverseMap = {}},
        story = {display = {}, map = {}, reverseMap = {}}
    }
    
    local levelsFolder = Services.ReplicatedStorage:FindFirstChild("Levels")
    if not levelsFolder then return levelData end
    
    local function processCategory(categoryName)
        local result = {display = {}, map = {}, reverseMap = {}}
        local categoryFolder = levelsFolder:FindFirstChild(categoryName)
        
        if categoryFolder then
            for _, levelModule in ipairs(categoryFolder:GetChildren()) do
                if levelModule:IsA("ModuleScript") then
                    local internalName = levelModule.Name
                    local displayName = Utils.formatItemName(internalName)
                    
                    local success, levelData = pcall(require, levelModule)
                    if success and type(levelData) == "table" and levelData.DisplayName and levelData.DisplayName ~= "" then
                        displayName = levelData.DisplayName
                    end
                    
                    table.insert(result.display, displayName)
                    result.map[displayName] = internalName
                    result.reverseMap[internalName] = displayName
                end
            end
        end
        
        table.sort(result.display)
        return result
    end
    
    levelData.raids = processCategory("Raid")
    levelData.challenges = processCategory("Challenge")
    levelData.story = processCategory("Story")
    
    return levelData
end

function AutoJoinSystem.findAvailableQueues()
    local queues = {}
    local matchmakersFolder = Services.Workspace:FindFirstChild("Matchmakers")
    
    if matchmakersFolder then
        for _, queueArea in ipairs(matchmakersFolder:GetChildren()) do
            if queueArea.Name == "QueueArea" and queueArea:IsA("Model") then
                local attributes = queueArea:GetAttributes()
                local mode = attributes.Mode or "Unknown"
                local stage = attributes.Stage or "Unknown"
                local difficulty = attributes.Difficulty or 0
                
                if mode == "Raid" or mode == "Challenge" then
                    table.insert(queues, {
                        queueType = mode,
                        stage = stage,
                        difficulty = difficulty,
                        cframe = queueArea.WorldPivot or CFrame.new(0, 0, 0)
                    })
                end
            end
        end
    end
    
    return queues
end

function AutoJoinSystem.tryJoinQueue(targetDifficulty, forceJoin, priorityType)
    if not Utils.isInLobby() then
        Utils.showError("This feature only works in the main lobby.")
        return false
    end
    
    if not forceJoin and not Utils.hasMinimumPlayers() then
        Utils.showNotification(string.format("Waiting for more players... (%d/%d)", 
            Utils.getPlayerCount(), Config.minPlayersRequired))
        return false
    end
    
    local primaryType = priorityType
    local secondaryType = priorityType == "Raid" and "Challenge" or "Raid"
    local primaryMaps = primaryType == "Raid" and Config.aqRaidMaps or Config.aqChallengeMaps
    local secondaryMaps = secondaryType == "Raid" and Config.aqRaidMaps or Config.aqChallengeMaps
    
    local availableQueues = AutoJoinSystem.findAvailableQueues()
    
    local function tryJoinMaps(queueType, maps, isPriority)
        if not maps or #maps == 0 then return false end
        
        local mapSet = {}
        for _, mapName in ipairs(maps) do
            mapSet[string.lower(mapName)] = true
        end
        
        local matchingQueues = {}
        for _, queue in pairs(availableQueues) do
            if queue.queueType == queueType and queue.difficulty == targetDifficulty and 
               mapSet[string.lower(queue.stage)] then
                table.insert(matchingQueues, queue)
            end
        end
        
        if #matchingQueues > 0 then
            local selectedQueue = matchingQueues[1]
            if Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") then
                Player.Character.HumanoidRootPart.CFrame = selectedQueue.cframe + Vector3.new(0, 3, 0)
                local queueTypeText = isPriority and queueType .. " (Priority)" or queueType
                Utils.showNotification(string.format("Joining %s: %s", queueTypeText, selectedQueue.stage))
                return true
            end
        end
        
        return false
    end
    
    -- Try priority type first
    if tryJoinMaps(primaryType, primaryMaps, true) then
        return true
    end
    
    -- Try secondary type
    if tryJoinMaps(secondaryType, secondaryMaps, false) then
        return true
    end
    
    if not forceJoin then
        if not Utils.hasMinimumPlayers() then
            Utils.showNotification(string.format("Waiting for more players... (%d/%d)", 
                Utils.getPlayerCount(), Config.minPlayersRequired))
        else
            Utils.showNotification("No selected maps are available right now. Still looking...")
        end
    end
    
    return false
end

function AutoJoinSystem.start()
    if not Utils.isInLobby() then
        return
    end
    
    if State.autoJoinConnection then
        State.autoJoinConnection:Disconnect()
    end
    
    State.autoJoinEnabled = true
    State.lastAutoJoinAttempt = 0
    State.waitingForPlayers = false
    State.autoJoinStartTime = nil
    
    State.autoJoinConnection = Services.RunService.Heartbeat:Connect(function()
        if not State.autoJoinEnabled or not Utils.isInLobby() then
            return
        end
        
        local currentTime = tick()
        if currentTime - State.lastAutoJoinAttempt < State.autoJoinCooldown then
            return
        end
        
        State.lastAutoJoinAttempt = currentTime
        
        if not (Config.aqRaidMaps and #Config.aqRaidMaps > 0 or Config.aqChallengeMaps and #Config.aqChallengeMaps > 0) then
            return
        end
        
        if Utils.hasMinimumPlayers() then
            if not State.autoJoinStartTime then
                State.autoJoinStartTime = tick()
                State.waitingForPlayers = false
            end
            
            local waitTime = tick() - State.autoJoinStartTime
            if waitTime >= Config.autoJoinDelay then
                local success = AutoJoinSystem.tryJoinQueue(Config.aqDifficulty, true, Config.aqPriority)
                if not success then
                    Utils.showNotification("Auto-join: No available queues match your selection. Still searching...")
                end
                State.autoJoinStartTime = nil
                State.waitingForPlayers = false
            else
                if not State.waitingForPlayers then
                    Utils.showNotification(string.format("Player requirement met. Joining in %d seconds...", Config.autoJoinDelay))
                    State.waitingForPlayers = true
                end
            end
        else
            if State.autoJoinStartTime then
                Utils.showNotification("Player count dropped. Pausing auto-join...")
            end
            State.autoJoinStartTime = nil
            State.waitingForPlayers = false
        end
    end)
    
    Utils.showNotification(string.format("Auto-join enabled! Priority: %s", Config.aqPriority))
end

function AutoJoinSystem.stop()
    State.autoJoinEnabled = false
    if State.autoJoinConnection then
        State.autoJoinConnection:Disconnect()
        State.autoJoinConnection = nil
    end
    Utils.showNotification("Auto-join disabled.")
end

-- ====================================================================
-- STORY MODE SYSTEM
-- ====================================================================

local StoryModeSystem = {}

function StoryModeSystem.clickPlayButton()
    local success, result = pcall(function()
        local hudGui = Player.PlayerGui:FindFirstChild("HUD")
        if not hudGui then return false end
        
        local function findPlayButton(parent, depth)
            depth = depth or 0
            for _, child in ipairs(parent:GetChildren()) do
                if child.Name == "Play" and (child:IsA("TextButton") or child:IsA("ImageButton") or child:IsA("GuiButton")) then
                    return child
                end
                if depth < 4 and (child:IsA("Frame") or child:IsA("ScrollingFrame") or child:IsA("Folder")) then
                    local button = findPlayButton(child, depth + 1)
                    if button then return button end
                end
            end
            return nil
        end
        
        local playButton = findPlayButton(hudGui)
        if playButton and playButton.Visible then
            local connections = getconnections(playButton.Activated)
            for _, connection in pairs(connections) do
                if connection and connection.Function then
                    connection.Function()
                    return true
                end
            end
            
            local clickConnections = getconnections(playButton.MouseButton1Click)
            for _, connection in pairs(clickConnections) do
                if connection and connection.Function then
                    connection.Function()
                    return true
                end
            end
        end
        
        return false
    end)
    
    return success and result
end

function StoryModeSystem.selectStage(stageName)
    local success, result = pcall(function()
        task.wait(0.2)
        local queueScreen = Player.PlayerGui:FindFirstChild("QueueScreen")
        if not queueScreen then return false end
        
        local stagesContainer = queueScreen.Main.SelectionScreen.Main.StageSelect.WorldSelect.Content.Stages
        if not stagesContainer then return false end
        
        local stageButton = stagesContainer:FindFirstChild(stageName)
        if not stageButton then
            -- Try to find by partial name match
            for _, child in ipairs(stagesContainer:GetChildren()) do
                if child:IsA("TextButton") or child:IsA("ImageButton") or child:IsA("GuiButton") then
                    if string.find(string.lower(child.Name), string.lower(stageName)) then
                        stageButton = child
                        break
                    end
                end
            end
        end
        
        if stageButton and stageButton.Visible then
            local connections = getconnections(stageButton.MouseButton1Click)
            if #connections > 0 then
                for _, connection in pairs(connections) do
                    if connection.Function then
                        connection.Function()
                        return true
                    elseif connection.Fire then
                        connection:Fire()
                        return true
                    end
                end
            end
            
            local activatedConnections = getconnections(stageButton.Activated)
            if #activatedConnections > 0 then
                for _, connection in pairs(activatedConnections) do
                    if connection.Function then
                        connection.Function()
                        return true
                    elseif connection.Fire then
                        connection:Fire()
                        return true
                    end
                end
            end
        end
        
        return false
    end)
    
    return success and result
end

function StoryModeSystem.selectChapter(chapterName)
    local success, result = pcall(function()
        local chapterSelect = Player.PlayerGui.QueueScreen.Main.SelectionScreen.Main.StageSelect.ChapterSelect
        local chapterFolders = {"Act1_Chapters", "Act2_Chapters"}
        
        for _, folderName in ipairs(chapterFolders) do
            local folder = chapterSelect:FindFirstChild(folderName)
            if folder and folder:FindFirstChild("Content") then
                local chapterButton = folder.Content:FindFirstChild(chapterName)
                if chapterButton and chapterButton.Visible then
                    local connections = getconnections(chapterButton.Activated)
                    for _, connection in pairs(connections) do
                        if connection and connection.Function then
                            connection.Function()
                            return true
                        end
                    end
                end
            end
        end
        
        return false
    end)
    
    return success and result
end

function StoryModeSystem.selectDifficulty(difficultyName)
    local success, result = pcall(function()
        local difficultiesContainer = Player.PlayerGui.QueueScreen.Main.SelectionScreen.Main.StageSelect.Info.Content.Difficulties
        local difficultyButton = difficultiesContainer:FindFirstChild(difficultyName)
        
        if difficultyButton and difficultyButton.Visible then
            local connections = getconnections(difficultyButton.Activated)
            for _, connection in pairs(connections) do
                if connection and connection.Function then
                    connection.Function()
                    return true
                end
            end
        end
        
        return false
    end)
    
    return success and result
end

function StoryModeSystem.confirmSelection()
    local success, result = pcall(function()
        local confirmButton = Player.PlayerGui.QueueScreen.Main.SelectionScreen.Main.Options.Options.Confirm
        
        if confirmButton and confirmButton.Visible then
            local connections = getconnections(confirmButton.Activated)
            for _, connection in pairs(connections) do
                if connection and connection.Function then
                    connection.Function()
                    return true
                end
            end
        end
        
        return false
    end)
    
    return success and result
end

function StoryModeSystem.startQueue()
    local success, result = pcall(function()
        task.wait(0.3)
        local startButton = Player.PlayerGui.QueueScreen.Main.StartScreen.Main.Options.Start
        
        if startButton and startButton.Visible then
            local connections = getconnections(startButton.Activated)
            for _, connection in pairs(connections) do
                if connection and connection.Function then
                    connection.Function()
                    return true
                end
            end
            
            local clickConnections = getconnections(startButton.MouseButton1Click)
            for _, connection in pairs(clickConnections) do
                if connection and connection.Function then
                    connection.Function()
                    return true
                end
            end
        end
        
        return false
    end)
    
    return success and result
end

function StoryModeSystem.startStoryQueue()
    if not Utils.hasMinimumPlayers() then
        Utils.showNotification(string.format("Waiting for more players... (%d/%d)", 
            Utils.getPlayerCount(), Config.minPlayersRequired))
        return
    end
    
    if not StoryModeSystem.clickPlayButton() then
        Utils.showError("Could not start queue. Is the 'Play' button visible?")
        return
    end
    
    task.wait(0.2)
    if not StoryModeSystem.selectStage(Config.selectedStage) then
        Utils.showError("Could not select the chosen stage.")
        return
    end
    
    task.wait(0.2)
    if not StoryModeSystem.selectChapter(Config.selectedChapter) then
        Utils.showError("Could not select the chosen chapter.")
        return
    end
    
    task.wait(0.2)
    if not StoryModeSystem.selectDifficulty(Config.selectedDifficulty) then
        Utils.showError("Could not select the chosen difficulty.")
        return
    end
    
    task.wait(0.2)
    if Config.storyPartyOnly then
        local success, result = pcall(function()
            local friendsToggle = Player.PlayerGui.QueueScreen.Main.SelectionScreen.Main.Options.FriendsOption.Toggle
            if friendsToggle and friendsToggle.Visible then
                local connections = getconnections(friendsToggle.Activated)
                for _, connection in pairs(connections) do
                    connection:Fire()
                end
                Utils.showNotification("Switched to 'Party Only' mode.")
                return true
            end
            return false
        end)
        
        if not success or not result then
            Utils.showError("Could not enable 'Party Only' mode.")
        end
        task.wait(0.2)
    end
    
    if not StoryModeSystem.confirmSelection() then
        Utils.showError("Could not confirm the selection.")
        return
    end
    
    task.wait(0.3)
    if not StoryModeSystem.startQueue() then
        Utils.showError("Could not start the game.")
        return
    end
    
    Utils.showNotification("Successfully started the story queue!")
end

-- ====================================================================
-- MERCHANT AUTOMATION SYSTEM
-- ====================================================================

local MerchantSystem = {}

function MerchantSystem.isExcludedItem(itemName)
    for _, excluded in ipairs(CONSTANTS.EXCLUDED_MERCHANT_ITEMS) do
        if itemName == excluded then
            return true
        end
        if tostring(itemName):find(excluded) then
            return true
        end
    end
    return false
end

function MerchantSystem.getMerchantItems()
    if not MerchantRotation then return {} end
    
    local items = {}
    local processedItems = {}
    
    local function addItem(item, isSpecial)
        local itemName = tostring(item.name or item.type)
        if MerchantSystem.isExcludedItem(itemName) then return end
        
        local rarity = item.rarity and tostring(item.rarity) or ""
        local key = itemName .. "|" .. rarity
        
        if not processedItems[key] then
            processedItems[key] = true
            table.insert(items, {
                name = itemName,
                rarity = rarity,
                isSpecial = isSpecial,
                key = key
            })
        end
    end
    
    -- Regular offers
    for _, batch in ipairs(MerchantRotation) do
        for _, offer in ipairs(batch) do
            addItem(offer.item, false)
        end
    end
    
    -- Special offers
    if MerchantRotation.SpecialOffers then
        for _, offer in pairs(MerchantRotation.SpecialOffers) do
            addItem(offer.item, true)
        end
    end
    
    table.sort(items, function(a, b)
        if a.isSpecial and not b.isSpecial then
            return true
        elseif not a.isSpecial and b.isSpecial then
            return false
        else
            return a.name:lower() < b.name:lower()
        end
    end)
    
    return items
end

function MerchantSystem.getTimeUntilMerchantRefresh()
    local currentTime = os.date("*t")
    local minutes, seconds = currentTime.min, currentTime.sec
    local nextRefresh = CONSTANTS.MERCHANT_REFRESH_MINUTES - (minutes % CONSTANTS.MERCHANT_REFRESH_MINUTES)
    if nextRefresh == CONSTANTS.MERCHANT_REFRESH_MINUTES then nextRefresh = 0 end
    local timeUntilRefresh = nextRefresh * 60 - seconds
    if timeUntilRefresh < 0 then timeUntilRefresh = timeUntilRefresh + CONSTANTS.MERCHANT_REFRESH_MINUTES * 60 end
    return timeUntilRefresh
end

function MerchantSystem.getTimeUntilMysteryMarketRefresh()
    local currentTime = os.date("*t")
    local minutes, seconds = currentTime.min, currentTime.sec
    local nextRefresh = CONSTANTS.MYSTERY_MARKET_REFRESH_MINUTES - (minutes % CONSTANTS.MYSTERY_MARKET_REFRESH_MINUTES)
    if nextRefresh == CONSTANTS.MYSTERY_MARKET_REFRESH_MINUTES then nextRefresh = 0 end
    local timeUntilRefresh = nextRefresh * 60 - seconds
    if timeUntilRefresh < 0 then timeUntilRefresh = timeUntilRefresh + CONSTANTS.MYSTERY_MARKET_REFRESH_MINUTES * 60 end
    return timeUntilRefresh
end

-- ====================================================================
-- PERFORMANCE OPTIMIZATION SYSTEM
-- ====================================================================

local PerformanceSystem = {}

function PerformanceSystem.enablePerformanceMode()
    if State.performanceModeEnabled then return end
    
    local lighting = Services.Lighting
    local camera = Services.Workspace.CurrentCamera
    
    -- Store original lighting settings
    if not State.originalLightingSettings.FogEnd then
        State.originalLightingSettings.FogEnd = lighting.FogEnd
    end
    if not State.originalLightingSettings.FogStart then
        State.originalLightingSettings.FogStart = lighting.FogStart
    end
    if not State.originalLightingSettings.GlobalShadows then
        State.originalLightingSettings.GlobalShadows = lighting.GlobalShadows
    end
    if not State.originalLightingSettings.Technology then
        State.originalLightingSettings.Technology = lighting.Technology
    end
    
    -- Apply performance settings
    lighting.FogEnd = 100
    lighting.FogStart = 0
    lighting.GlobalShadows = false
    lighting.Technology = Enum.Technology.Compatibility
    
    -- Disable camera effects
    for _, effectName in ipairs(CONSTANTS.CAMERA_EFFECTS) do
        local effect = camera:FindFirstChild(effectName)
        if effect then
            if pcall(function() return effect.Enabled end) and effect.Enabled and not State.hiddenObjects[effect] then
                State.hiddenObjects[effect] = {original_enabled = true}
                effect.Enabled = false
            elseif pcall(function() return effect.Active end) and effect.Active and not State.hiddenObjects[effect] then
                State.hiddenObjects[effect] = {original_active = true}
                effect.Active = false
            end
        end
    end
    
    State.performanceModeEnabled = true
    
    -- Start performance optimization loop
    if not State.performanceConnection then
        State.performanceConnection = task.spawn(function()
            while State.performanceModeEnabled do
                -- Hide other players
                for _, player in ipairs(Services.Players:GetPlayers()) do
                    if player.Character and player.Character.Parent == Services.Workspace then
                        local character = player.Character
                        
                        -- Hide accessories
                        for _, accessory in ipairs(character:GetChildren()) do
                            if accessory:IsA("Accessory") and not State.hiddenObjects[accessory] then
                                State.hiddenObjects[accessory] = character
                                accessory.Parent = nil
                            end
                        end
                        
                        -- Hide other players' characters
                        if player ~= Player and not State.hiddenObjects[character] then
                            State.hiddenObjects[character] = Services.Workspace
                            character.Parent = nil
                        end
                    end
                end
                
                -- Hide effects and particles
                for _, object in ipairs(Services.Workspace:GetDescendants()) do
                    if not State.hiddenObjects[object] then
                        local isPlayerObject = false
                        if Player.Character then
                            isPlayerObject = object:IsDescendantOf(Player.Character)
                        end
                        
                        if not isPlayerObject then
                            if object:IsA("BasePart") and object.Transparency < 1 then
                                State.hiddenObjects[object] = {original_transparency = object.Transparency}
                                object.Transparency = 1
                            elseif object:IsA("ParticleEmitter") or object:IsA("Beam") or object:IsA("Trail") or 
                                   object:IsA("Smoke") or object:IsA("Sparkles") then
                                if object.Enabled then
                                    State.hiddenObjects[object] = {original_enabled = true}
                                    object.Enabled = false
                                end
                            elseif object:IsA("Decal") or object:IsA("Texture") then
                                if object.Transparency < 1 then
                                    State.hiddenObjects[object] = {original_transparency = object.Transparency}
                                    object.Transparency = 1
                                end
                            elseif object:IsA("Explosion") then
                                State.hiddenObjects[object] = {original_parent = object.Parent}
                                object.Parent = nil
                            end
                        end
                    end
                end
                
                -- Clear effect folders
                local effectFolders = {"Debris", "Effect", "Effects", "Particles", "Projectiles"}
                for _, folderName in ipairs(effectFolders) do
                    local folder = Services.Workspace:FindFirstChild(folderName)
                    if folder then
                        folder:ClearAllChildren()
                    end
                end
                
                task.wait(0.5)
            end
        end)
    end
end

function PerformanceSystem.disablePerformanceMode()
    if not State.performanceModeEnabled then return end
    
    State.performanceModeEnabled = false
    
    -- Stop performance loop
    if State.performanceConnection then
        task.cancel(State.performanceConnection)
        State.performanceConnection = nil
    end
    
    -- Restore hidden objects
    for object, originalData in pairs(State.hiddenObjects) do
        pcall(function()
            if type(originalData) == "Instance" then
                object.Parent = originalData
            elseif type(originalData) == "table" then
                if originalData.original_enabled ~= nil then
                    object.Enabled = originalData.original_enabled
                end
                if originalData.original_active ~= nil then
                    object.Active = originalData.original_active
                end
                if originalData.original_transparency ~= nil then
                    object.Transparency = originalData.original_transparency
                end
                if originalData.original_parent ~= nil then
                    object.Parent = originalData.original_parent
                end
            end
        end)
    end
    
    State.hiddenObjects = {}
    
    -- Restore lighting settings
    local lighting = Services.Lighting
    if State.originalLightingSettings.FogEnd ~= nil then
        lighting.FogEnd = State.originalLightingSettings.FogEnd
        State.originalLightingSettings.FogEnd = nil
    end
    if State.originalLightingSettings.FogStart ~= nil then
        lighting.FogStart = State.originalLightingSettings.FogStart
        State.originalLightingSettings.FogStart = nil
    end
    if State.originalLightingSettings.GlobalShadows ~= nil then
        lighting.GlobalShadows = State.originalLightingSettings.GlobalShadows
        State.originalLightingSettings.GlobalShadows = nil
    end
    if State.originalLightingSettings.Technology ~= nil then
        lighting.Technology = State.originalLightingSettings.Technology
        State.originalLightingSettings.Technology = nil
    end
end

-- ====================================================================
-- AFK SCREEN SYSTEM
-- ====================================================================

local AFKSystem = {}
local afkScreenGui = nil
local afkUpdateConnection = nil

function AFKSystem.createAFKScreen()
    afkScreenGui = Instance.new("ScreenGui")
    afkScreenGui.Name = "StopRenderingGui"
    afkScreenGui.IgnoreGuiInset = true
    afkScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    afkScreenGui.DisplayOrder = 999999
    afkScreenGui.Enabled = false
    afkScreenGui.ResetOnSpawn = false
    
    local blackFrame = Instance.new("Frame", afkScreenGui)
    blackFrame.Name = "BlackFrame"
    blackFrame.BackgroundColor3 = Color3.new(0, 0, 0)
    blackFrame.BorderSizePixel = 0
    blackFrame.Size = UDim2.new(1, 0, 1, 0)
    
    local playerLabel = Instance.new("TextLabel", blackFrame)
    playerLabel.Font = Enum.Font.GothamBlack
    playerLabel.TextColor3 = Color3.new(1, 1, 1)
    playerLabel.TextSize = 60
    playerLabel.BackgroundTransparency = 1
    playerLabel.AnchorPoint = Vector2.new(0.5, 0)
    playerLabel.Position = UDim2.new(0.5, 0, 0.05, 0)
    playerLabel.Size = UDim2.new(0.9, 0, 0, 60)
    playerLabel.Text = "Player: " .. PlayerName
    
    local levelLabel = Instance.new("TextLabel", blackFrame)
    levelLabel.Font = Enum.Font.Gotham
    levelLabel.TextColor3 = Color3.new(1, 1, 1)
    levelLabel.TextSize = 45
    levelLabel.BackgroundTransparency = 1
    levelLabel.AnchorPoint = Vector2.new(0.5, 0)
    levelLabel.Position = UDim2.new(0.5, 0, 0.2, 0)
    levelLabel.Size = UDim2.new(0.9, 0, 0, 50)
    levelLabel.Text = "Level: ..."
    
    local seasonPassLabel = Instance.new("TextLabel", blackFrame)
    seasonPassLabel.Font = Enum.Font.Gotham
    seasonPassLabel.TextColor3 = Color3.new(1, 1, 1)
    seasonPassLabel.TextSize = 45
    seasonPassLabel.BackgroundTransparency = 1
    seasonPassLabel.AnchorPoint = Vector2.new(0.5, 0)
    seasonPassLabel.Position = UDim2.new(0.5, 0, 0.3, 0)
    seasonPassLabel.Size = UDim2.new(0.9, 0, 0, 50)
    seasonPassLabel.Text = "Season Pass Tier: ..."
    
    local currencyLabel = Instance.new("TextLabel", blackFrame)
    currencyLabel.Font = Enum.Font.Gotham
    currencyLabel.TextColor3 = Color3.new(1, 1, 1)
    currencyLabel.TextSize = 45
    currencyLabel.BackgroundTransparency = 1
    currencyLabel.AnchorPoint = Vector2.new(0.5, 0)
    currencyLabel.Position = UDim2.new(0.5, 0, 0.4, 0)
    currencyLabel.Size = UDim2.new(0.9, 0, 0, 50)
    currencyLabel.Text = "Coins: ... | Gems: ..."
    
    local tokensLabel = Instance.new("TextLabel", blackFrame)
    tokensLabel.Font = Enum.Font.Gotham
    tokensLabel.TextColor3 = Color3.new(1, 1, 1)
    tokensLabel.TextSize = 45
    tokensLabel.BackgroundTransparency = 1
    tokensLabel.AnchorPoint = Vector2.new(0.5, 0)
    tokensLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
    tokensLabel.Size = UDim2.new(0.9, 0, 0, 50)
    tokensLabel.Text = "Challenge Tokens: ... | Golden Spatulas: ..."
    
    local traitRollsLabel = Instance.new("TextLabel", blackFrame)
    traitRollsLabel.Font = Enum.Font.Gotham
    traitRollsLabel.TextColor3 = Color3.new(1, 1, 1)
    traitRollsLabel.TextSize = 45
    traitRollsLabel.BackgroundTransparency = 1
    traitRollsLabel.AnchorPoint = Vector2.new(0.5, 0)
    traitRollsLabel.Position = UDim2.new(0.5, 0, 0.6, 0)
    traitRollsLabel.Size = UDim2.new(0.9, 0, 0, 50)
    traitRollsLabel.Text = "Trait Rolls: ... | Golden Trait Rolls: ..."
    
    local statusLabel = Instance.new("TextLabel", blackFrame)
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.TextColor3 = Color3.new(1, 1, 1)
    statusLabel.TextSize = 50
    statusLabel.BackgroundTransparency = 1
    statusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    statusLabel.Position = UDim2.new(0.5, 0, 0.75, 0)
    statusLabel.Size = UDim2.new(0.9, 0, 0, 60)
    statusLabel.Text = "Status: Ready"
    
    local gameInfoLabel = Instance.new("TextLabel", blackFrame)
    gameInfoLabel.Font = Enum.Font.Gotham
    gameInfoLabel.TextColor3 = Color3.new(1, 1, 1)
    gameInfoLabel.TextSize = 45
    gameInfoLabel.BackgroundTransparency = 1
    gameInfoLabel.AnchorPoint = Vector2.new(0.5, 1)
    gameInfoLabel.Position = UDim2.new(0.5, 0, 0.9, 0)
    gameInfoLabel.Size = UDim2.new(0.9, 0, 0, 50)
    gameInfoLabel.Text = "Current Wave: N/A | Game Speed: 1x"
    
    local creditLabel = Instance.new("TextLabel", blackFrame)
    creditLabel.Name = "CreditLabel"
    creditLabel.Font = Enum.Font.Gotham
    creditLabel.TextColor3 = Color3.new(1, 1, 1)
    creditLabel.TextSize = 24
    creditLabel.BackgroundTransparency = 1
    creditLabel.Text = "MADE BY: LM6Z ♥"
    creditLabel.TextXAlignment = Enum.TextXAlignment.Right
    creditLabel.AnchorPoint = Vector2.new(1, 0)
    creditLabel.Position = UDim2.new(1, -10, 0, 10)
    creditLabel.Size = UDim2.new(0, 300, 0, 30)
    
    afkScreenGui.Parent = Player:WaitForChild("PlayerGui")
    
    -- Store references for updates
    AFKSystem.levelLabel = levelLabel
    AFKSystem.seasonPassLabel = seasonPassLabel
    AFKSystem.currencyLabel = currencyLabel
    AFKSystem.tokensLabel = tokensLabel
    AFKSystem.traitRollsLabel = traitRollsLabel
    AFKSystem.statusLabel = statusLabel
    AFKSystem.gameInfoLabel = gameInfoLabel
end

function AFKSystem.enableAFKMode()
    if not afkScreenGui then
        AFKSystem.createAFKScreen()
    end
    
    afkScreenGui.Enabled = true
    Utils.showNotification("Rendering stopped. Game is now in AFK mode.")
    
    if afkUpdateConnection then
        task.cancel(afkUpdateConnection)
    end
    
    afkUpdateConnection = task.spawn(function()
        local knit = require(Services.ReplicatedStorage.Packages.Knit)
        local dataController = knit.GetController("DataController")
        
        while afkScreenGui.Enabled do
            -- Update currency
            pcall(function()
                local coins, gems = Economy.getCurrency()
                AFKSystem.currencyLabel.Text = string.format("Coins: %s | Gems: %s", 
                    tostring(math.floor(coins)), tostring(math.floor(gems)))
            end)
            
            -- Update level
            pcall(function()
                local playerStats = dataController:Get(Player, "PlayerStats"):expect()
                if playerStats and playerStats.Level then
                    AFKSystem.levelLabel.Text = string.format("Level: %s", tostring(playerStats.Level))
                end
            end)
            
            -- Update season pass
            pcall(function()
                local seasonPass = dataController:Get(Player, "SeasonPass"):expect()
                if seasonPass and seasonPass.Level then
                    AFKSystem.seasonPassLabel.Text = string.format("Season Pass Tier: %s", tostring(seasonPass.Level))
                end
            end)
            
            -- Update currency details
            pcall(function()
                local currency = dataController:Get(Player, "Currency"):expect()
                if currency then
                    local challengeTokens = currency.ChallengeToken or 0
                    local goldenSpatulas = currency.GoldenSpatula or 0
                    AFKSystem.tokensLabel.Text = string.format("Challenge Tokens: %s | Golden Spatulas: %s", 
                        tostring(challengeTokens), tostring(goldenSpatulas))
                    
                    local traitRolls = currency.TraitRolls or 0
                    local goldenTraitRolls = currency.GoldenTraitRolls or 0
                    AFKSystem.traitRollsLabel.Text = string.format("Trait Rolls: %s | Golden Trait Rolls: %s", 
                        tostring(traitRolls), tostring(goldenTraitRolls))
                end
            end)
            
            -- Update status and location
            if Utils.isInLobby() then
                AFKSystem.gameInfoLabel.Text = "Location: Lobby"
                if Config.storyAutoJoin then
                    AFKSystem.statusLabel.Text = "Status: Searching for Story..."
                elseif Config.aqAutoJoin then
                    AFKSystem.statusLabel.Text = "Status: Searching for Raid/Challenge..."
                else
                    AFKSystem.statusLabel.Text = "Status: Idle in Lobby"
                end
            else
                local mapName = GameState.getCurrentMapName() or "Unknown Map"
                local currentWave = Utils.getCurrentWave() or "N/A"
                AFKSystem.gameInfoLabel.Text = string.format("Map: %s | Wave: %s", mapName, currentWave)
                
                if State.isPlayingMacro then
                    AFKSystem.statusLabel.Text = "Status: Playing Macro..."
                else
                    AFKSystem.statusLabel.Text = "Status: In Game"
                end
            end
            
            task.wait(1)
        end
    end)
end

function AFKSystem.disableAFKMode()
    if afkScreenGui then
        afkScreenGui.Enabled = false
    end
    
    if afkUpdateConnection then
        task.cancel(afkUpdateConnection)
        afkUpdateConnection = nil
    end
    
    Utils.showNotification("Rendering resumed.")
end

-- ====================================================================
-- AUTO FEATURES SYSTEM
-- ====================================================================

local AutoFeatures = {}

function AutoFeatures.claimPlaytimePrizes()
    local success = pcall(function()
        local hasClaimed = false
        
        pcall(function()
            local knit = require(Services.ReplicatedStorage.Packages.Knit)
            if not knit.IsStarted then
                task.wait(3)
            end
            
            local dataController = knit.GetController("DataController")
            local playtimePrizeService = knit.GetService("PlaytimePrizeService")
            local playtimePrizesShared = require(Services.ReplicatedStorage.Shared.Data.PlaytimePrizesShared)
            
            local claimedRewards = dataController:Get(Player, "ClaimedPlaytimeRewards"):expect() or {}
            local currentSessionPlaytime = dataController:Get(Player, "CurrentSessionPlaytime"):expect() or 0
            
            local claimedCount = 0
            for i, reward in ipairs(playtimePrizesShared.REWARDS) do
                if not table.find(claimedRewards, i) and currentSessionPlaytime >= reward.time then
                    playtimePrizeService:ClaimPrize(i)
                    claimedCount = claimedCount + 1
                    task.wait(0.5)
                end
            end
            
            if claimedCount > 0 then
                hasClaimed = true
            end
        end)
    end)
    
    return success
end

function AutoFeatures.claimSeasonPass()
    pcall(function()
        Services.ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("acecateer_knit@1.7.1"):WaitForChild("knit"):WaitForChild("Services"):WaitForChild("SeasonPassService"):WaitForChild("RF"):WaitForChild("ClaimAll"):InvokeServer()
    end)
end

function AutoFeatures.claimQuests()
    if Utils.isInLobby() then
        pcall(function()
            local questService = Services.ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("acecateer_knit@1.7.1"):WaitForChild("knit"):WaitForChild("Services"):WaitForChild("ProgressionService"):WaitForChild("RF"):WaitForChild("ClaimAllQuests")
            questService:InvokeServer("All")
        end)
    end
end

function AutoFeatures.prestige()
    pcall(function()
        Services.ReplicatedStorage:WaitForChild("Packages"):WaitForChild("_Index"):WaitForChild("acecateer_knit@1.7.1"):WaitForChild("knit"):WaitForChild("Services"):WaitForChild("StatsService"):WaitForChild("RF"):WaitForChild("Prestige"):InvokeServer()
    end)
end

-- ====================================================================
-- WEBHOOK SYSTEM
-- ====================================================================

local WebhookSystem = {}

function WebhookSystem.sendCompletionWebhook(gameResult, mapName, waves, playerLevel, seasonPassLevel, currencyGains)
    if not Config.completionWebhookEnabled or not Config.completionWebhookUrl or #Config.completionWebhookUrl == 0 then
        return
    end
    
    if typeof(request) ~= "function" then
        return
    end
    
    local success, result = pcall(function()
        local isVictory = gameResult and string.find(gameResult, "VICTORY", 1, true)
        local title = isVictory and "Game Complete!" or "Game Over!"
        local color = isVictory and 3066993 or 15158332
        
        local fields = {}
        
        -- Game info
        table.insert(fields, {
            name = "📊 Game Info",
            value = string.format("🗺️ **Map:** %s\n🏅 **Result:** %s\n🌊 **Waves:** %s", 
                mapName or "N/A", isVictory and "Victory" or "Defeat", waves or "N/A"),
            inline = false
        })
        
        -- Account info
        table.insert(fields, {
            name = "👤 Account Info",
            value = string.format("🧑‍💻 **Player:** ||`%s`||\n✨ **Level:** %s\n🏆 **Season Pass:** %s", 
                PlayerName, playerLevel or "N/A", seasonPassLevel or "N/A"),
            inline = false
        })
        
        -- Currency gains (if provided)
        if currencyGains and #currencyGains > 0 then
            local currencyText = ""
            local foodText = ""
            local materialsText = ""
            
            local currencyEmojis = {
                Coins = "🪙", Gems = "💎", GoldenSpatula = "✨", ChallengeToken = "💠",
                TraitRolls = "🎲", GoldenTraitRolls = "🌟", MagicConch = "🐚",
                ["Aged Patty"] = "🍔", ["Kelp Shake"] = "🥤", ["Fruit Cake"] = "🍰",
                ["MysteryPatty"] = "❓", ["Chocolate Bar"] = "🍫", ["Pretty Patties"] = "🌈"
            }
            
            local currencyItems = {"Coins", "Gems", "GoldenSpatula", "ChallengeToken", "TraitRolls", "GoldenTraitRolls", "MagicConch"}
            local foodItems = {"Aged Patty", "Kelp Shake", "Fruit Cake", "MysteryPatty", "Chocolate Bar", "Pretty Patties"}
            
            for _, gain in ipairs(currencyGains) do
                local emoji = currencyEmojis[gain.name] or "📦"
                local line = string.format("%s **+%s** %s (**%s**)\n", 
                    emoji, tostring(gain.amount), Utils.formatItemName(gain.name), tostring(gain.total))
                
                if table.find(currencyItems, gain.name) then
                    currencyText = currencyText .. line
                elseif table.find(foodItems, gain.name) then
                    foodText = foodText .. line
                else
                    materialsText = materialsText .. line
                end
            end
            
            if currencyText ~= "" then
                table.insert(fields, {name = "💰 Currency Gained", value = currencyText, inline = true})
            end
            if foodText ~= "" then
                table.insert(fields, {name = "🍔 Food Gained", value = foodText, inline = true})
            end
            if materialsText ~= "" then
                table.insert(fields, {name = "🛠️ Materials Gained", value = materialsText, inline = true})
            end
        end
        
        local embed = {
            embeds = {{
                title = title,
                color = color,
                fields = fields,
                timestamp = os.date("!%Y-%m-%dT%H:%M:%S.000Z")
            }}
        }
        
        local jsonData = Services.HttpService:JSONEncode(embed)
        local requestData = {
            Url = Config.completionWebhookUrl,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = jsonData
        }
        
        return request(requestData)
    end)
    
    if success then
        print("[Webhook] Game completion webhook sent successfully.")
    else
        print("[Webhook] Failed to send completion webhook:", tostring(result))
    end
end

function WebhookSystem.testWebhook()
    if typeof(request) ~= "function" then
        Utils.showError("❌ This executor does not support http requests.")
        return
    end
    
    if not Config.completionWebhookUrl or type(Config.completionWebhookUrl) ~= "string" or #Config.completionWebhookUrl == 0 then
        Utils.showError("Please enter a webhook URL first.")
        return
    end
    
    Utils.showNotification("Sending test webhook...")
    
    local success, result = pcall(function()
        local testData = {
            content = "This is a test message from the Spongebob Tower Defense script! If you see this, your webhook is working correctly. ✨"
        }
        
        local jsonData = Services.HttpService:JSONEncode(testData)
        local requestData = {
            Url = Config.completionWebhookUrl,
            Method = "POST",
            Headers = {["Content-Type"] = "application/json"},
            Body = jsonData
        }
        
        return request(requestData)
    end)
    
    if success then
        Utils.showNotification("✅ Test webhook sent successfully!")
    else
        Utils.showError("❌ Failed to send test webhook. Check console for details.")
        print("[Webhook Test] Error:", tostring(result))
    end
end

-- ====================================================================
-- INITIALIZATION AND MAIN SCRIPT
-- ====================================================================

local function showLoadingScreen()
    local startTime = tick()
    
    -- Create loading GUI
    local screenGui = Instance.new("ScreenGui", Player:WaitForChild("PlayerGui"))
    screenGui.ResetOnSpawn = false
    
    local frame = Instance.new("Frame", screenGui)
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.Size = UDim2.new(0, 450, 0, 120)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BorderSizePixel = 0
    
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(80, 80, 80)
    stroke.Thickness = 1
    
    local header = Instance.new("Frame", frame)
    header.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    header.BorderSizePixel = 0
    header.Size = UDim2.new(1, 0, 0, 30)
    
    local title = Instance.new("TextLabel", header)
    title.Font = Enum.Font.SourceSansBold
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 16
    title.Text = "Spongebob Tower Defense 🍍"
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Position = UDim2.new(0, 10, 0, 0)
    title.Size = UDim2.new(1, -20, 1, 0)
    title.BackgroundTransparency = 1
    
    local statusLabel = Instance.new("TextLabel", frame)
    statusLabel.Font = Enum.Font.SourceSans
    statusLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
    statusLabel.TextSize = 18
    statusLabel.Text = "Initializing..."
    statusLabel.BackgroundTransparency = 1
    statusLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
    statusLabel.Size = UDim2.new(1, -20, 0, 30)
    statusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Center
    
    local progressBar = Instance.new("Frame", frame)
    progressBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    progressBar.BorderSizePixel = 0
    progressBar.Position = UDim2.new(0.5, 0, 0.8, 0)
    progressBar.Size = UDim2.new(0.9, 0, 0, 10)
    progressBar.AnchorPoint = Vector2.new(0.5, 0.5)
    
    local progressFill = Instance.new("Frame", progressBar)
    progressFill.BackgroundColor3 = Color3.fromRGB(80, 120, 255)
    progressFill.BorderSizePixel = 0
    progressFill.Size = UDim2.new(0, 0, 1, 0)
    
    statusLabel.Text = "Loading..."
    progressFill:TweenSize(UDim2.new(1, 0, 1, 0), Enum.EasingDirection.Out, Enum.EasingStyle.Linear, 5, true)
    
    -- Wait for minimum loading time
    local elapsed = tick() - startTime
    local remainingTime = CONSTANTS.LOADING_TIME - elapsed
    if remainingTime > 0 then
        task.wait(remainingTime)
    end
    
    screenGui:Destroy()
end

local function initializeBackgroundTasks()
    -- Initialize tower tracker
    TowerTracker.initialize()
    
    -- Apply FPS cap if set
    if Config.fpsCap and type(Config.fpsCap) == "number" then
        setfpscap(Config.fpsCap)
    end
    
    -- Apply performance mode if enabled
    PerformanceSystem.enablePerformanceMode(Config.resourceSaverEnabled)
    
    -- Initialize AFK screen
    AFKSystem.createAFKScreen()
    
    -- Set current mode
    Config.currentMode = GameState.getCurrentMode()
    
    -- Start background loops
    task.spawn(function()
        -- Anti-AFK loop
        local camera = Services.Workspace.CurrentCamera
        while true do
            if Config.antiAfkEnabled then
                pcall(function()
                    if camera then
                        local microRotation = CFrame.Angles(0, 0.00001, 0)
                        camera.CFrame = camera.CFrame * microRotation
                    end
                end)
            end
            task.wait(60)
        end
    end)
    
    -- Game speed enforcement
    task.spawn(function()
        local gameSpeedRemote = Services.ReplicatedStorage.Packages._Index["acecateer_knit@1.7.1"].knit.Services.GameService.RF.ChangeGameSpeed
        while true do
            local speedValue = CONSTANTS.GAME_SPEEDS[Config.gameSpeed] or 1
            pcall(function()
                gameSpeedRemote:InvokeServer(speedValue)
            end)
            task.wait(3)
        end
    end)
    
    -- Auto-claim features
    task.spawn(function()
        while true do
            if Config.autoClaimPrizesEnabled then
                AutoFeatures.claimPlaytimePrizes()
            end
            task.wait(3)
        end
    end)
    
    task.spawn(function()
        while true do
            if Config.autoClaimSeasonPassEnabled then
                AutoFeatures.claimSeasonPass()
            end
            task.wait(3)
        end
    end)
    
    task.spawn(function()
        while true do
            if Config.autoClaimQuestsEnabled then
                AutoFeatures.claimQuests()
            end
            task.wait(5)
        end
    end)
    
    task.spawn(function()
        while true do
            if Config.autoPrestigeEnabled then
                AutoFeatures.prestige()
            end
            task.wait(3)
        end
    end)
    
    -- Inventory snapshot system
    task.spawn(function()
        while true do
            if not Utils.isInLobby() and not State.hasPreMatchSnapshot then
                State.preMatchInventory = Economy.getFullInventory()
                State.hasPreMatchSnapshot = true
                print("--- SNAPSHOT: BEFORE MATCH ---")
                for item, amount in pairs(State.preMatchInventory) do
                    print(item .. ": " .. tostring(amount))
                end
                print("----------------------------")
            end
            
            if Utils.isInLobby() and State.hasPreMatchSnapshot then
                State.hasPreMatchSnapshot = false
                State.preMatchInventory = {}
            end
            
            task.wait(1)
        end
    end)
    
    -- Merchant automation (if in lobby)
    if Utils.isInLobby() and MerchantRotation then
        task.spawn(function()
            local knit = require(Services.ReplicatedStorage.Packages.Knit)
            local merchantService = knit.GetService("MerchantService")
            
            while true do
                pcall(function()
                    local coins, gems = Economy.getCurrency()
                    local shopBatch = merchantService.ShopBatch
                    
                    if not shopBatch then return end
                    
                    local batchData = shopBatch:Get()
                    if not batchData then return end
                    
                    local currentBatch = batchData.Batch or 1
                    local specialOfferIndex = batchData.SpecialOfferIndex
                    
                    -- Process regular offers
                    if MerchantRotation and MerchantRotation[currentBatch] then
                        for index, offer in ipairs(MerchantRotation[currentBatch]) do
                            local item = offer.item
                            local itemName = tostring(item.name or item.type)
                            
                            if not MerchantSystem.isExcludedItem(itemName) then
                                local rarity = item.rarity and tostring(item.rarity) or ""
                                local key = itemName .. "|" .. rarity
                                
                                if State.autobuyToggles[key] then
                                    local cost = offer.cost or 0
                                    local currency = offer.currency or "Coins"
                                    local stock = offer.stock or 0
                                    
                                    local canAfford = currency == "Coins" and coins >= cost or currency == "Gems" and gems >= cost
                                    
                                    if canAfford and stock > 0 then
                                        local success, error = pcall(function()
                                            local purchaseRemote = Services.ReplicatedStorage.Packages._Index["acecateer_knit@1.7.1"].knit.Services.MerchantService.RF.Purchase
                                            purchaseRemote:InvokeServer(index, 1)
                                        end)
                                        
                                        if not success then
                                            print("Purchase failed:", error)
                                        end
                                        
                                        task.wait(0.05)
                                    end
                                end
                            end
                        end
                    end
                    
                    -- Process special offers
                    if MerchantRotation and MerchantRotation.SpecialOffers and specialOfferIndex and MerchantRotation.SpecialOffers[specialOfferIndex] then
                        local specialOffer = MerchantRotation.SpecialOffers[specialOfferIndex]
                        local item = specialOffer.item
                        local itemName = tostring(item.name or item.type)
                        
                        if not MerchantSystem.isExcludedItem(itemName) then
                            local rarity = item.rarity and tostring(item.rarity) or ""
                            local key = itemName .. "|" .. rarity
                            
                            if State.autobuyToggles[key] then
                                local cost = specialOffer.cost or 0
                                local currency = specialOffer.currency or "Coins"
                                local stock = specialOffer.stock or 0
                                
                                local canAfford = currency == "Coins" and coins >= cost or currency == "Gems" and gems >= cost
                                
                                if canAfford and stock > 0 then
                                    local success, error = pcall(function()
                                        local purchaseRemote = Services.ReplicatedStorage.Packages._Index["acecateer_knit@1.7.1"].knit.Services.MerchantService.RF.Purchase
                                        purchaseRemote:InvokeServer(specialOfferIndex, 1)
                                    end)
                                    
                                    if not success then
                                        print("Special purchase failed:", error)
                                    end
                                    
                                    task.wait(0.05)
                                end
                            end
                        end
                    end
                end)
                
                task.wait(0.05)
            end
        end)
        
        -- Mystery Market automation
        task.spawn(function()
            local purchasedItems = {}
            
            while true do
                pcall(function()
                    local knit = require(Services.ReplicatedStorage.Packages.Knit)
                    local mysteryMarketService = knit.GetService("MysteryMarketService")
                    
                    if mysteryMarketService and mysteryMarketService.MarketData then
                        local marketData = mysteryMarketService.MarketData:Get()
                        if marketData and marketData.CurrentItems then
                            for index, item in pairs(marketData.CurrentItems) do
                                local material = item.Material
                                local stock = item.Stock or 0
                                
                                if material and stock > 0 and State.mysteryMarketToggles[material] then
                                    if not purchasedItems[material] then
                                        purchasedItems[material] = true
                                        
                                        local success, error = pcall(function()
                                            if mysteryMarketService.TryBuyMaterial then
                                                mysteryMarketService.TryBuyMaterial:Fire(index)
                                            else
                                                error("MysteryMarketService.TryBuyMaterial not found")
                                            end
                                        end)
                                        
                                        if not success then
                                            print("Mystery Market purchase failed for", material, "Error:", error)
                                        end
                                        
                                        task.wait(0.05)
                                        purchasedItems[material] = false
                                    end
                                end
                            end
                        end
                    end
                end)
                
                task.wait(0.05)
            end
        end)
        
        -- Teleport on merchant refresh
        task.spawn(function()
            local lastMerchantTeleport = 0
            while true do
                if Config.AutoTeleportOnMerchant then
                    local timeUntilRefresh = MerchantSystem.getTimeUntilMerchantRefresh()
                    if timeUntilRefresh <= 3 and tick() - lastMerchantTeleport > 30 then
                        if game.PlaceId ~= CONSTANTS.LOBBY_PLACE_ID then
                            Services.TeleportService:Teleport(CONSTANTS.LOBBY_PLACE_ID)
                            lastMerchantTeleport = tick()
                        else
                            lastMerchantTeleport = tick()
                        end
                        task.wait(1)
                    end
                end
                task.wait(0.5)
            end
        end)
        
        -- Teleport on mystery market refresh
        task.spawn(function()
            local lastMysteryTeleport = 0
            while true do
                if Config.AutoTeleportOnMysteryMarket then
                    local timeUntilRefresh = MerchantSystem.getTimeUntilMysteryMarketRefresh()
                    if timeUntilRefresh <= 2 and tick() - lastMysteryTeleport > 15 then
                        if game.PlaceId ~= CONSTANTS.LOBBY_PLACE_ID then
                            Services.TeleportService:Teleport(CONSTANTS.LOBBY_PLACE_ID)
                            lastMysteryTeleport = tick()
                        end
                    end
                end
                task.wait(0.5)
            end
        end)
    end
    
    -- Game completion detection and webhook
    task.spawn(function()
        while true do
            local roundSummary = GameState.isRoundSummaryVisible()
            if roundSummary then
                pcall(function()
                    local currentInventory = Economy.getFullInventory()
                    print("--- SNAPSHOT: AFTER MATCH ---")
                    for item, amount in pairs(currentInventory) do
                        print(item .. ": " .. tostring(amount))
                    end
                    print("---------------------------")
                    
                    -- Calculate gains and send webhook
                    local gains = {}
                    for item, currentAmount in pairs(currentInventory) do
                        local previousAmount = State.preMatchInventory[item] or 0
                        local gain = currentAmount - previousAmount
                        if gain > 0 then
                            table.insert(gains, {
                                name = item,
                                amount = gain,
                                total = currentAmount
                            })
                        end
                    end
                    
                    -- Get game result info
                    local success, gameResult = pcall(function()
                        return Player.PlayerGui.RoundSummary.Main.Title.TitleContainer.Title.Text
                    end)
                    
                    local success2, waveText = pcall(function()
                        return Player.PlayerGui.RoundSummary.Main.Stats.Wave.Text
                    end)
                    
                    local mapName = GameState.getCurrentMapName()
                    
                    local knit = require(Services.ReplicatedStorage.Packages.Knit)
                    local dataController = knit.GetController("DataController")
                    
                    local success3, playerLevel = pcall(function()
                        return dataController:Get(Player, "PlayerStats"):expect().Level
                    end)
                    
                    local success4, seasonPassLevel = pcall(function()
                        return dataController:Get(Player, "SeasonPass"):expect().Level
                    end)
                    
                    WebhookSystem.sendCompletionWebhook(
                        success and gameResult or nil,
                        mapName,
                        success2 and waveText or nil,
                        success3 and tostring(playerLevel) or nil,
                        success4 and tostring(seasonPassLevel) or nil,
                        gains
                    )
                end)
                
                -- Wait for round summary to disappear
                while GameState.isRoundSummaryVisible() do
                    if Config.autoReplayToggle then
                        -- Try to click replay button
                        local success = pcall(function()
                            local roundSummaryGui = Player.PlayerGui.RoundSummary
                            if roundSummaryGui and roundSummaryGui.Main then
                                local actionsFolder = roundSummaryGui.Main:FindFirstChild("Content", true)
                                if actionsFolder then
                                    actionsFolder = actionsFolder:FindFirstChild("Actions", true)
                                    if actionsFolder then
                                        local replayButton = actionsFolder:FindFirstChild("Replay")
                                        local nextButton = actionsFolder:FindFirstChild("Next")
                                        
                                        local function pressButton(button)
                                            local activatedConnections = getconnections(button.Activated)
                                            for _, connection in pairs(activatedConnections) do
                                                pcall(function() connection:Fire() end)
                                            end
                                            local clickConnections = getconnections(button.MouseButton1Click)
                                            for _, connection in pairs(clickConnections) do
                                                pcall(function() connection:Fire() end)
                                            end
                                        end
                                        
                                        if replayButton and replayButton.Visible then
                                            pressButton(replayButton)
                                            Utils.showNotification("Match ended. Clicking 'Replay'...")
                                            break
                                        elseif nextButton and nextButton.Visible then
                                            pressButton(nextButton)
                                            Utils.showNotification("Replay button not found. Clicking 'Next'...")
                                            break
                                        end
                                    end
                                end
                            end
                        end)
                    else
                        task.wait(0.5)
                    end
                    task.wait(0.1)
                end
                
                State.hasPreMatchSnapshot = false
            end
            task.wait(0.1)
        end
    end)
end

-- Load required data
local MerchantRotation = nil
local CraftingData = nil
local merchantDataLoaded = false
local craftingDataLoaded = false

pcall(function()
    MerchantRotation = require(Services.ReplicatedStorage:WaitForChild("MerchantRotation"))
    if MerchantRotation then
        merchantDataLoaded = true
    end
end)

pcall(function()
    CraftingData = require(Services.ReplicatedStorage.Shared.Data.CraftingData)
    if CraftingData then
        craftingDataLoaded = true
    end
end)

-- Retry loading if failed
if not merchantDataLoaded then
    task.wait(1)
    pcall(function()
        MerchantRotation = require(Services.ReplicatedStorage:WaitForChild("MerchantRotation"))
        if MerchantRotation then
            merchantDataLoaded = true
        end
    end)
end

if not craftingDataLoaded then
    task.wait(1)
    pcall(function()
        CraftingData = require(Services.ReplicatedStorage.Shared.Data.CraftingData)
        if CraftingData then
            craftingDataLoaded = true
        end
    end)
end

local function initialize()
    -- Show loading screen
    showLoadingScreen()
    
    -- Load Linoria library
    Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/LionTheGreatRealFrFr/MobileLinoriaLib/main/Library.lua"))()
    getgenv().Options = getgenv().Options or {}
    
    -- Load configuration
    ConfigManager.load()
    
    -- Initialize background tasks
    initializeBackgroundTasks()
    
    -- Create GUI
    local Window = Library:CreateWindow({
        Title = "Spongebob Tower Defense 🍍",
        Center = true,
        AutoShow = true,
        Size = UDim2.new(0, 600, 0, 450)
    })
    
    -- Create tabs
    local AutomationTab = Window:AddTab("Automation 🤖")
    local MerchantsTab = Window:AddTab("Merchants 💰")
    local CraftingTab = Window:AddTab("Crafting 🛠️")
    local MiscTab = Window:AddTab("Misc. ⚙️")
    
    -- ====================================================================
    -- AUTOMATION TAB
    -- ====================================================================
    
    local AutoJoinGroup = AutomationTab:AddLeftGroupbox("Auto-Join section")
    local MacroGroup = AutomationTab:AddRightGroupbox("Macro Section")
    local StoryGroup = AutomationTab:AddLeftGroupbox("Story Mode 📖")
    
    -- Story Mode section
    local levelData = AutoJoinSystem.getLevelData()
    local storyData = levelData.story
    
    if not storyData.reverseMap[Config.selectedStage] and #storyData.display > 0 then
        Config.selectedStage = storyData.map[storyData.display[1]]
        ConfigManager.save()
    end
    
    local stageDisplayName = storyData.reverseMap[Config.selectedStage]
    StoryGroup:AddDropdown("StageSelect", {
        Values = storyData.display,
        Default = stageDisplayName,
        Multi = false,
        Text = "Select Stage",
        Tooltip = "Choose the story stage to play."
    }):OnChanged(function(value)
        Config.selectedStage = storyData.map[value]
        ConfigManager.save()
    end)
    
    local chapterMap = {
        ["Chapter_1"] = "Chapter 1", ["Chapter_2"] = "Chapter 2", ["Chapter_3"] = "Chapter 3",
        ["Chapter_4"] = "Chapter 4", ["Chapter_5"] = "Chapter 5", ["Chapter_6"] = "Chapter 6",
        ["Chapter_7"] = "Chapter 7", ["Chapter_8"] = "Chapter 8", ["Chapter_9"] = "Chapter 9",
        ["Chapter_10"] = "Chapter 10", ["Endless_A"] = "Endless (A)", ["Endless_B"] = "Endless (B)"
    }
    
    local reverseChapterMap = {}
    for internal, display in pairs(chapterMap) do
        reverseChapterMap[display] = internal
    end
    
    local chapterOrder = {"Chapter_1", "Chapter_2", "Chapter_3", "Chapter_4", "Chapter_5", 
                         "Chapter_6", "Chapter_7", "Chapter_8", "Chapter_9", "Chapter_10", 
                         "Endless_A", "Endless_B"}
    local chapterDisplayOrder = {}
    for _, internal in ipairs(chapterOrder) do
        table.insert(chapterDisplayOrder, chapterMap[internal])
    end
    
    local currentChapterDisplay = chapterMap[Config.selectedChapter]
    if not currentChapterDisplay then
        Config.selectedChapter = "Chapter_2"
        currentChapterDisplay = chapterMap[Config.selectedChapter]
        ConfigManager.save()
    end
    
    StoryGroup:AddDropdown("ChapterSelect", {
        Values = chapterDisplayOrder,
        Default = currentChapterDisplay,
        Multi = false,
        Text = "Select Chapter",
        Tooltip = "Choose the chapter to play."
    }):OnChanged(function(value)
        Config.selectedChapter = reverseChapterMap[value]
        ConfigManager.save()
    end)
    
    local difficulties = {"Normal", "Hard", "Nightmare", "Davy Jones' Locker"}
    if not table.find(difficulties, Config.selectedDifficulty) then
        Config.selectedDifficulty = "Hard"
        ConfigManager.save()
    end
    
    StoryGroup:AddDropdown("DifficultySelect", {
        Values = difficulties,
        Default = Config.selectedDifficulty,
        Multi = false,
        Text = "Select Difficulty",
        Tooltip = "Choose the difficulty level."
    }):OnChanged(function(value)
        Config.selectedDifficulty = value
        ConfigManager.save()
    end)
    
    StoryGroup:AddToggle("StoryPartyOnlyToggle", {
        Text = "Party Only",
        Default = Config.storyPartyOnly or false,
        Tooltip = "If enabled, the story queue will be private to your party."
    }):OnChanged(function(value)
        Config.storyPartyOnly = value
        ConfigManager.save()
    end)
    
    local storyAutoJoinConnection = nil
    StoryGroup:AddToggle("StoryAutoJoin", {
        Text = "Auto-Start Story",
        Default = Config.storyAutoJoin or false,
        Tooltip = "Automatically starts the selected story mode when ready."
    }):OnChanged(function(value)
        Config.storyAutoJoin = value
        ConfigManager.save()
        
        if value then
            if Utils.isInLobby() then
                if storyAutoJoinConnection then
                    task.cancel(storyAutoJoinConnection)
                end
                storyAutoJoinConnection = task.spawn(function()
                    while Config.storyAutoJoin do
                        if Utils.hasMinimumPlayers() then
                            Utils.showNotification(string.format("Story: Player requirement met. Joining in %d seconds...", Config.autoJoinDelay))
                            task.wait(Config.autoJoinDelay)
                            if Config.storyAutoJoin and Utils.hasMinimumPlayers() then
                                StoryModeSystem.startStoryQueue()
                                task.wait(5)
                            else
                                Utils.showNotification("Story: Join conditions changed. Resetting...")
                            end
                        else
                            Utils.showNotification(string.format("Story: Waiting for more players... (%d/%d)", 
                                Utils.getPlayerCount(), Config.minPlayersRequired))
                            task.wait(3)
                        end
                    end
                end)
                Utils.showNotification("Auto-start for story mode enabled.")
            else
                Utils.showNotification("Auto-start will begin when you enter the lobby.")
            end
        else
            if storyAutoJoinConnection then
                task.cancel(storyAutoJoinConnection)
                storyAutoJoinConnection = nil
            end
            Utils.showNotification("Auto-start for story mode disabled.")
        end
    end)
    
    StoryGroup:AddButton("Join Queue", function()
        if Utils.hasMinimumPlayers() then
            StoryModeSystem.startStoryQueue()
        else
            Utils.showNotification(string.format("Waiting for more players... (%d/%d)", 
                Utils.getPlayerCount(), Config.minPlayersRequired))
        end
    end):AddTooltip("Manually start the story queue process.")
    
    Utils.showNotification("GUI Loaded! Welcome, " .. PlayerName .. " 👋")
end

-- Cleanup on player leaving
Services.Players.PlayerRemoving:Connect(function(player)
    if player == Player then
        AutoJoinSystem.stop()
        TowerTracker.uninstallHook()
    end
end)

-- Start the script
initialize()