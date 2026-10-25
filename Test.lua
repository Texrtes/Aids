local Globals = getgenv()

if shared.TDSTable then
    return shared.TDSTable
end

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()

local Window

local function earlyExtractPrivateServerCode(linkOrCode)
    if not linkOrCode or type(linkOrCode) ~= "string" then return "", "none" end
    local trimmed = linkOrCode:gsub('^["\'%s]*(.-)["\'%s]*$', "%1")
    if trimmed == "" then return "", "none" end

    local lower = trimmed:lower()
    if lower == "nil" or lower == "null" or lower == "none" or lower == "false" or lower == "0" or lower == "undefined" or lower == "n/a" or lower == "placeholder" then
        return "", "none"
    end

    -- 1. Standard Legacy Private Server Link (?privateServerLinkCode=...)
    local psCode = trimmed:match("privateServerLinkCode=([%w%-%_]+)")
    if psCode and #psCode > 0 then return psCode, "linkCode" end

    local linkCode = trimmed:match("[?&]linkCode=([%w%-%_]+)")
    if linkCode and #linkCode > 0 then return linkCode, "linkCode" end

    -- 2. New Roblox Share Link (?code=...&type=Server)
    local shareCode = trimmed:match("[?&]code=([%w%-%_]+)")
    if shareCode and #shareCode > 0 then return shareCode, "shareCode" end

    if trimmed:find("roblox%.com") or trimmed:find("https?://") then
        local sharePath = trimmed:match("/share%?code=([%w%-%_]+)")
        if sharePath and #sharePath > 0 then return sharePath, "shareCode" end
        local endCode = trimmed:match("/([%w%-%_]+)%s*$")
        if endCode and #endCode >= 15 and not endCode:find("^%d+$") then
            return endCode, "shareCode"
        end
        return "", "none"
    end

    -- 3. Raw 32-digit numeric code (like 16570715161949672940011188486713)
    if trimmed:match("^%d+$") and #trimmed >= 20 then
        return trimmed, "linkCode"
    end

    -- 4. Raw alphanumeric code (32-char hex share code or custom code)
    if #trimmed >= 8 and #trimmed <= 128 and trimmed:match("^[%w%-%_]+$") then
        if not (lower:find("tower") or lower:find("defense") or lower:find("simulator")) then
            if #trimmed == 32 and trimmed:match("^%x+$") and not trimmed:match("^%d+$") then
                return trimmed, "shareCode"
            end
            return trimmed, "linkCode"
        end
    end

    return "", "none"
end

local function launchOrTeleportPrivateServer(placeId, code, player)
    local targetCode, codeType = earlyExtractPrivateServerCode(code)
    if not targetCode or targetCode == "" then
        targetCode = tostring(code or ""):gsub('^["\'%s]*(.-)["\'%s]*$', "%1")
        codeType = targetCode:match("^%d+$") and "linkCode" or "shareCode"
    end
    if not targetCode or targetCode == "" then return false end

    placeId = tonumber(placeId) or 3260590327

    -- Check if we are already in a VIP Server in the Lobby to avoid Error 771 loop
    if game.PlaceId == placeId and game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0 then
        warn("[PrivateServer] Already inside a Private Server lobby!")
        return true
    end

    local setid = setthreadidentity or set_thread_identity or (syn and syn.set_thread_identity) or setidentity

    -- Method 1: ExperienceService with elevated thread identity (8)
    local launched = false
    pcall(function()
        if setid then pcall(setid, 8) end
        local ExperienceService = game:GetService("ExperienceService")
        if codeType == "shareCode" then
            ExperienceService:LaunchExperience({
                placeId = placeId,
                joinData = { launchData = "" },
                linkCode = tostring(targetCode)
            })
        else
            ExperienceService:LaunchExperience({
                placeId = placeId,
                linkCode = tostring(targetCode)
            })
        end
        launched = true
    end)

    -- Method 2: Deep-link protocol fallback (works reliably on Windows/Mobile executors when ExperienceService throws 771)
    if not launched then
        pcall(function()
            if setid then pcall(setid, 8) end
            local url
            if codeType == "shareCode" then
                url = string.format("roblox://navigation/share_links?code=%s&type=Server", tostring(targetCode))
            else
                url = string.format("roblox://placeId=%d&linkCode=%s", placeId, tostring(targetCode))
            end
            game:GetService("GuiService"):OpenBrowserWindow(url)
            launched = true
        end)
    end

    return launched
end

Globals.earlyExtractPrivateServerCode = earlyExtractPrivateServerCode
Globals.launchOrTeleportPrivateServer = launchOrTeleportPrivateServer

local function SmartTeleportToLobby()
    local lobbyId = 3260590327

    local success, err = pcall(function()
        local rawCode = (Globals and Globals.PrivateCode)
            or (typeof(getgenv) == "function" and getgenv().PrivateCode)
            or _G.PrivateCode
            or (Globals and Globals.PrivateServerCode)
            or (typeof(getgenv) == "function" and getgenv().PrivateServerCode)
            or _G.PrivateServerCode

        local targetCode = earlyExtractPrivateServerCode(rawCode)
        if targetCode == "" and rawCode and rawCode ~= "" then
            targetCode = tostring(rawCode):gsub('^["\'%s]*(.-)["\'%s]*$', "%1")
        end

        local launched = false
        if targetCode and targetCode ~= "" then
            launched = launchOrTeleportPrivateServer(lobbyId, targetCode, LocalPlayer)
        end

        if not launched then
            TeleportService:Teleport(lobbyId)
        end
    end)

    if not success then
        warn("[SmartTeleport] Failed to initiate teleport:", err)
        pcall(function()
            TeleportService:Teleport(lobbyId)
        end)
    end

    task.spawn(function()
        task.wait(10)
        warn("[SmartTeleport] Teleport timed out or failed to complete after 10 seconds.")
        
        if Window then
            Window:Notify({
                Title = "Teleport Failed",
                Desc = "It looks like you're stuck! If you are using Delta, please ensure that 'Verify Teleports' is disabled in your settings.",
                Time = 9999,
                Type = "error"
            })
            task.wait(5)
            Window:Notify({
                Title = "Fixing Delta Teleport Issues",
                Desc = "1. Disconnect from the game\n" ..
                       "2. Completely empty your 'autoexecute' folder\n" ..
                       "3. Reopen Roblox and join the game\n" ..
                       "4. Go to Delta settings and disable 'Verify Teleports'\n" ..
                       "5. Disconnect and rejoin to confirm 'Verify Teleports' remains OFF\n" ..
                       "6. Once verified, restore your files to 'autoexecute' and rejoin",
                Time = 9999,
                Type = "normal"
            })
        end
    end)
end

local function Reconnect(errorMessage)
    local initialCode = nil
    pcall(function()
        initialCode = GuiService:GetErrorCode()
    end)
    
    local hasError = false
    if initialCode and initialCode ~= Enum.ConnectionError.OK then
        hasError = true
    elseif type(errorMessage) == "string" and #errorMessage > 0 then
        hasError = true
    end

    if hasError then
        task.wait(5)
        
        local currentCode = nil
        pcall(function()
            currentCode = GuiService:GetErrorCode()
        end)

        if (currentCode and currentCode == initialCode) or (type(errorMessage) == "string" and #errorMessage > 0) then
            pcall(function()
                TeleportService:TeleportReconnect()
            end)
            pcall(function()
                if SmartTeleportToLobby then
                    SmartTeleportToLobby()
                else
                    TeleportService:Teleport(3260590327)
                end
            end)
        end
    end
end

local function AntiStuck()
    task.spawn(function()
        local secondsStuck = 0

        while true do 
            task.wait(1)
            
            local attrLoading = LocalPlayer:GetAttribute("Loading") == true
            local attrTeleporting = LocalPlayer:GetAttribute("Teleporting") == true
            
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            local loadScreen = pg and pg:FindFirstChild("LoadingScreen")
            local loadContent = loadScreen and loadScreen:FindFirstChild("content")
            local isLoadVisible = loadContent and loadContent.Visible == true
            
            local countScreen = pg and pg:FindFirstChild("PlayerCountdown")
            local countFrame = countScreen and countScreen:FindFirstChild("Frame")
            local isCountVisible = countFrame and countFrame.Visible == true

            if attrLoading or attrTeleporting or isLoadVisible or isCountVisible then
                secondsStuck = secondsStuck + 1
                if secondsStuck >= 60 then
                    pcall(SmartTeleportToLobby)
                    secondsStuck = 0 
                end
            else
                secondsStuck = 0 
            end
        end
    end)
end

AntiStuck()
pcall(function() task.spawn(Reconnect) end)
pcall(function() GuiService.ErrorMessageChanged:Connect(Reconnect) end)

if not game:IsLoaded() then game.Loaded:Wait() end

local VirtualUser = game:GetService("VirtualUser")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local mouse = LocalPlayer:GetMouse()
local RemoteFunc = ReplicatedStorage:WaitForChild("RemoteFunction")
local RemoteEvent = ReplicatedStorage:WaitForChild("RemoteEvent")
local FileName = "ADS_Config.json"
local Logger
local StartBackToLobby
local IsMobile = false
pcall(function()
    local platform = UserInputService:GetPlatform()
    IsMobile = (platform == Enum.Platform.IOS or platform == Enum.Platform.Android)
end)
if not IsMobile then
    IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled
end

task.spawn(function()
    LocalPlayer.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end)

task.spawn(function()
    pcall(function()
        RemoteFunc:InvokeServer("Settings", "Update", "Show Nametags", false)
    end)
end)

local function IdentifyGameState()
    local players = game:GetService("Players")
    local TempPlayer = players.LocalPlayer or players.PlayerAdded:Wait()
    local TempGui = TempPlayer:WaitForChild("PlayerGui")

    while true do
        if TempGui:FindFirstChild("ReactLobbyHud") then
            return "LOBBY"
        elseif TempGui:FindFirstChild("ReactUniversalHotbar") then
            return "GAME"
        end
        task.wait(1)
    end
end

local GameState = IdentifyGameState()

local function StartAntiAfk()
    task.spawn(function()
        local LobbyTimer = 0
        while GameState == "LOBBY" do 
            task.wait(1)
            LobbyTimer = LobbyTimer + 1
            if LobbyTimer >= 600 then
                SmartTeleportToLobby()
                break 
            end
        end
    end)
end

StartAntiAfk()

local SendRequest = request or http_request or httprequest
    or GetDevice and GetDevice().request

if not SendRequest then 
    warn("failure: no http function") 
    return 
end

local BackToLobbyRunning = false
local AutoPickupsRunning, StartAutoPickups = false, nil
local AutoSkipRunning = false
local AutoClaimRewards = false
local AntiLagRunning = false
local AutoChainRunning = false
local AutoDjRunning = false
local AutoNecroRunning = false
local TimeScaleRunning = false
local TimeScaleNoTicketsWarned = false
local AutoMercenaryBaseRunning = false
local AutoMilitaryBaseRunning = false
local SellFarmsRunning = false
local AutoGatlingRunning = false
local GatlingExecuted = false
local GatlifyRunning = false
local GatlifyExecuted = false
local IsCurrentlyLoading = false
local LastLoadTime = 0
local IsEquippingLoadout = false
local AutoPremiumRunning = false
local PremiumLoaded = false

local MaxPathDistance = 300 -- default
local MilMarker = nil
local MercMarker = nil

local CurrentEquippedTowers = {"None"}

local StackEnabled = false
local SelectedTower = nil
local StackSphere = nil

local AutoMedicRunning = false
local _AutoTrialsRunning = false

local AllModifiers = {
    "HiddenEnemies", "Glass", "ExplodingEnemies", "Limitation", 
    "Committed", "HealthyEnemies", "Fog", "FlyingEnemies", 
    "Broke", "SpeedyEnemies", "Quarantine", "JailedTowers", "Inflation"
}

local DefaultSettings = {
    PathVisuals = false,
    MilitaryPath = false,
    MercenaryPath = false,
    AutoSkip = false,
    AutoOpenCrates = false,
    SelectedCrate = "All",
    AutoReady = false,
    AutoChain = false,
    AutoGatling = false,
    Gatlify = false,
    AutoPremium = false,
    SupportCaravan = false,
    AutoDJ = false,
    DJCustomSongID = "",
    AutoNecro = false,
    AutoRejoin = true,
    AutoRestart = true,
    PrivateCode = "",
    TimeScaleEnabled = false,
    TimeScaleValue = 2,
    SellFarms = false,
    AutoMercenary = false,
    AutoMilitary = false,
    Frost = false,
    Fallen = false,
    Easy = false,
    AntiLag = false,
    Disable3DRendering = false,
    AutoPickups = false,
    AutoExecuteStrat = false,
    selectedStrat = "Strat.txt",
    ClaimRewards = false,
    SendWebhook = false,
    NoRecoil = false,
    SellFarmsWave = 1,
    Snapper = false,
    WebhookURL = "",
    PickupMethod = "Pathfinding",
    StreamerMode = false,
    HideUsername = false,
    BuffOverlay = false,
    StreamerName = "",
    tagName = "None",
    Modifiers = {},
    LicenseKey = "",
    AutoMedic = false,
    AutoTrials = false
}

local TowerSnapper = {
    Enabled = Globals.Snapper ~= nil and Globals.Snapper or true,
    MaxRadius = 16,
    CoarseStep = 0.35,
    FineStep = 0.08,
    SpacingOffset = 0.04,
    LastInput = nil,
    LastSnapped = nil,
    LastHit = nil,
    LastValid = false,
    TowerCount = 0
}

local BuffOverlay = {
    Enabled = true,
    AuraVisuals = {},
    PulseClock = 0,
    BasePreviewRange = nil,
    CurrentExpandedRange = nil,
    SupportDefinitions = {
        ["DJ Booth"] = {
            Tag = "DJ",
            Color = Color3.fromRGB(255, 43, 79),
            GlowColor = Color3.fromRGB(255, 90, 120),
            FallbackRanges = { [0] = 12, [1] = 15, [2] = 15, [3] = 15, [4] = 16.5, [5] = 18 }
        },
        ["Commander"] = {
            Tag = "CMD",
            Color = Color3.fromRGB(0, 210, 255),
            GlowColor = Color3.fromRGB(120, 235, 255),
            FallbackRanges = { [0] = 10, [1] = 10, [2] = 13, [3] = 15, [4] = 17 }
        },
        ["Medic"] = {
            Tag = "MED",
            Color = Color3.fromRGB(0, 255, 163),
            GlowColor = Color3.fromRGB(120, 255, 210),
            FallbackRanges = { [0] = 12, [1] = 12, [2] = 14, [3] = 15, [4] = 18, [5] = 20 }
        }
    }
}

local TimeScaleValues = {0.5, 1, 1.5, 2}

local function NormalizeTimeScaleValue(val)
    val = tonumber(val)
    if not val then
        return nil
    end
    for _, v in ipairs(TimeScaleValues) do
        if v == val then
            return v
        end
    end
    return nil
end

local function CoerceTimeScaleValue(val, fallback)
    return NormalizeTimeScaleValue(val) or fallback
end

local function GetTimescaleFrame()
    local hotbar = PlayerGui:FindFirstChild("ReactUniversalHotbar")
    local frame = hotbar and hotbar:FindFirstChild("Frame")
    return frame and frame:FindFirstChild("timescale")
end

local StartTimeScale
local ApplyTimeScaleOnce

-- // icon item ids ill add more soon arghh
local ItemNames = {
    ["17447507910"] = "Timescale Ticket(s)",
    ["17438486690"] = "Range Flag(s)",
    ["17438486138"] = "Damage Flag(s)",
    ["17438487774"] = "Cooldown Flag(s)",
    ["17429537022"] = "Blizzard(s)",
    ["17448596749"] = "Napalm Strike(s)",
    ["18493073533"] = "Spin Ticket(s)",
    ["17429548305"] = "Supply Drop(s)",
    ["18443277308"] = "Low Grade Consumable Crate(s)",
    ["136180382135048"] = "Santa Radio(s)",
    ["18443277106"] = "Mid Grade Consumable Crate(s)",
    ["18443277591"] = "High Grade Consumable Crate(s)",
    ["132155797622156"] = "Christmas Tree(s)",
    ["124065875200929"] = "Fruit Cake(s)",
    ["17429541513"] = "Barricade(s)",
    ["110415073436604"] = "Holy Hand Grenade(s)",
    ["17429533728"] = "Frag Grenade(s)",
    ["17437703262"] = "Molotov(s)",
    ["139414922355803"] = "Present Clusters(s)"
}

local executed_actions = {}

-- // tower management core
TDS = {
    PlacedTowers = {},
    ActiveStrat = true,
    IsEquippingLoadout = false,
    LoadoutPending = false,
    MatchmakingMap = {
        ["PizzaParty"] = "halloween",
        ["Badlands"] = "badlands",
        ["PollutedWasteland"] = "polluted",
        ["DuckyEasy"] = "ducky2025",
        ["DuckyHard"] = "ducky2025"
    }
}
TDS["placed_towers"] = TDS.PlacedTowers
TDS["active_strat"] = TDS.ActiveStrat
TDS["matchmaking_map"] = TDS.MatchmakingMap

local UpgradeHistory = {}

-- // shared for addons
shared.TDSTable = TDS
shared["TDS_Table"] = TDS

function TDS:ResetAllStates()
    table.clear(self.PlacedTowers)
    table.clear(UpgradeHistory)
    table.clear(executed_actions)
    if Logger and Logger.Clear then
        pcall(function()
            Logger:Clear()
            Logger:Log("Restarting strategy...")
        end)
    end
end

function TDS:RunStrategy()
    if Globals.activeStrategyThread then
        pcall(task.cancel, Globals.activeStrategyThread)
        Globals.activeStrategyThread = nil
    end

    Globals.activeStrategyThread = task.spawn(function()
        Globals.tdsReplaying = true
        pcall(function()
            loadstring(readfile("ADS_LastStrat.lua"))()
        end)
        Globals.tdsReplaying = false
        Globals.activeStrategyThread = nil
    end)
end

-- // load & save
local function SaveSettings()
    local DataToSave = {}
    for key, _ in pairs(DefaultSettings) do
        DataToSave[key] = Globals[key]
    end
    writefile(FileName, HttpService:JSONEncode(DataToSave))
end

local function LoadSettings()
    local data = {}
    if isfile(FileName) then
        pcall(function()
            data = HttpService:JSONDecode(readfile(FileName))
        end)
    end

    for key, DefaultVal in pairs(DefaultSettings) do
        if Globals[key] == nil then
            if data[key] ~= nil then
                Globals[key] = data[key]
            else
                Globals[key] = DefaultVal
            end
        end
    end
    
    SaveSettings()
end

local function SetSetting(name, value)
    if DefaultSettings[name] ~= nil then
        if name == "TimeScaleValue" then
            value = CoerceTimeScaleValue(value, Globals.TimeScaleValue or 2)
        end
        Globals[name] = value
        SaveSettings()
    end
end

local function Apply3dRendering()
    pcall(function()
        local set3d = set3drendering or set_3d_rendering
        if type(set3d) == "function" then
            set3d(not Globals.Disable3DRendering)
        end
    end)
    pcall(function()
        local setid = setthreadidentity or set_thread_identity or (syn and syn.set_thread_identity) or setidentity
        if setid then pcall(setid, 8) end
        RunService:Set3dRenderingEnabled(not Globals.Disable3DRendering)
    end)
    local PlayerGui = LocalPlayer:FindFirstChild("PlayerGui")
    local gui = PlayerGui and PlayerGui:FindFirstChild("ADS_BlackScreen")
    if Globals.Disable3DRendering then
        if PlayerGui and not gui then
            gui = Instance.new("ScreenGui")
            gui.Name = "ADS_BlackScreen"
            gui.IgnoreGuiInset = true
            gui.ResetOnSpawn = false
            gui.DisplayOrder = -1000
            gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            gui.Parent = PlayerGui
            local frame = Instance.new("Frame")
            frame.Name = "Cover"
            frame.BackgroundColor3 = Color3.new(0, 0, 0)
            frame.BorderSizePixel = 0
            frame.Size = UDim2.fromScale(1, 1)
            frame.ZIndex = 0
            frame.Parent = gui
        end
        gui.Enabled = true
    else
        if gui then
            gui.Enabled = false
        end
    end
end

LoadSettings()
Globals.TimeScaleValue = CoerceTimeScaleValue(Globals.TimeScaleValue, 2)
Apply3dRendering()

local collectTagOptions, stopTagChanger, startTagChanger, UpdatePrivacyState
do
local isTagChangerRunning = false
local tagChangerConn = nil
local tagChangerTag = nil
local tagChangerOrig = nil

collectTagOptions = function()
    local list = {}
    local seen = {}
    local function addFolder(folder)
        if not folder then
            return
        end
        for _, child in ipairs(folder:GetChildren()) do
            local childName = child.Name
            if childName and not seen[childName] then
                seen[childName] = true
                list[#list + 1] = childName
            end
        end
    end
    local content = ReplicatedStorage:FindFirstChild("Content")
    if content then
        local nametag = content:FindFirstChild("Nametag")
        if nametag then
            addFolder(nametag:FindFirstChild("Basic"))
            addFolder(nametag:FindFirstChild("Exclusive"))
        end
    end
    table.sort(list)
    table.insert(list, 1, "None")
    return list
end

stopTagChanger = function()
    if tagChangerConn then
        tagChangerConn:Disconnect()
        tagChangerConn = nil
    end
    if tagChangerTag and tagChangerTag.Parent and tagChangerOrig ~= nil then
        pcall(function()
            tagChangerTag.Value = tagChangerOrig
        end)
    end
    tagChangerTag = nil
    tagChangerOrig = nil
end

startTagChanger = function()
    if isTagChangerRunning then
        return
    end
    isTagChangerRunning = true
    task.spawn(function()
        while Globals.tagName and Globals.tagName ~= "" and Globals.tagName ~= "None" do
            local tag = LocalPlayer:FindFirstChild("Tag")
            if tag then
                if tagChangerTag ~= tag then
                    if tagChangerConn then
                        tagChangerConn:Disconnect()
                        tagChangerConn = nil
                    end
                    tagChangerTag = tag
                    if tagChangerOrig == nil then
                        tagChangerOrig = tag.Value
                    end
                end
                if tag.Value ~= Globals.tagName then
                    tag.Value = Globals.tagName
                end
                if not tagChangerConn then
                    tagChangerConn = tag:GetPropertyChangedSignal("Value"):Connect(function()
                        if Globals.tagName and Globals.tagName ~= "" and Globals.tagName ~= "None" then
                            if tag.Value ~= Globals.tagName then
                                tag.Value = Globals.tagName
                            end
                        end
                    end)
                end
            end
            task.wait(0.5)
        end
        isTagChangerRunning = false
    end)
end

if Globals.tagName and Globals.tagName ~= "" and Globals.tagName ~= "None" then
    startTagChanger()
end

local OriginalDisplayName = LocalPlayer.DisplayName
local OriginalUserName = LocalPlayer.Name

local SpoofTextCache = setmetatable({}, {__mode = "k"})
local PrivacyRunning = false
local LastSpoofName = nil
local PrivacyConns = {}
local PrivacyTextNodes = setmetatable({}, {__mode = "k"})
local StreamerTag = nil
local StreamerTagOrig = nil
local StreamerTagConn = nil

local function AddPrivacyConn(conn)
    if conn then
        PrivacyConns[#PrivacyConns + 1] = conn
    end
end

local function ClearPrivacyConns()
    for _, c in ipairs(PrivacyConns) do
        pcall(function()
            c:Disconnect()
        end)
    end
    PrivacyConns = {}
    for inst in pairs(PrivacyTextNodes) do
        PrivacyTextNodes[inst] = nil
    end
end

local function MakeSpoofName()
    return "BelowNatural"
end

local function EnsureSpoofName()
    local nm = Globals.StreamerName
    if not nm or nm == "" then
        nm = MakeSpoofName()
        SetSetting("StreamerName", nm)
    end
    return nm
end

local function IsTagChangerActive()
    return Globals.tagName and Globals.tagName ~= "" and Globals.tagName ~= "None"
end

local function SetLocalDisplayName(nm)
    if not nm or nm == "" then
        return
    end
    pcall(function()
        LocalPlayer.DisplayName = nm
    end)
end

local function ReplacePlain(str, old, new)
    if not str or str == "" or not old or old == "" or old == new then
        return str, false
    end
    local start = 1
    local out = {}
    local changed = false
    while true do
        local i, j = string.find(str, old, start, true)
        if not i then
            out[#out + 1] = string.sub(str, start)
            break
        end
        changed = true
        out[#out + 1] = string.sub(str, start, i - 1)
        out[#out + 1] = new
        start = j + 1
    end
    if changed then
        return table.concat(out), true
    end
    return str, false
end

local function ApplySpoofToInstance(inst, OldA, OldB, NewName)
    if not inst then
        return
    end
    if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
        local txt = inst.Text
        if type(txt) == "string" and txt ~= "" then
            local HasA = OldA and OldA ~= "" and string.find(txt, OldA, 1, true)
            local HasB = OldB and OldB ~= "" and string.find(txt, OldB, 1, true)
            if not HasA and not HasB then
                return
            end
            local t = txt
            local changed = false
            local ch
            if OldA and OldA ~= "" then
                t, ch = ReplacePlain(t, OldA, NewName)
                if ch then changed = true end
            end
            if OldB and OldB ~= "" then
                t, ch = ReplacePlain(t, OldB, NewName)
                if ch then changed = true end
            end
            if changed then
                if SpoofTextCache[inst] == nil then
                    SpoofTextCache[inst] = txt
                end
                inst.Text = t
            end
        end
    end
end

local function RestoreSpoofText()
    for inst, txt in pairs(SpoofTextCache) do
        if inst and inst.Parent then
            pcall(function()
                inst.Text = txt
            end)
        end
        SpoofTextCache[inst] = nil
    end
end

local function GetPrivacyName()
    if Globals.StreamerMode then
        return EnsureSpoofName()
    end
    if Globals.HideUsername then
        return "████████"
    end
    return nil
end

local function AddPrivacyNode(inst)
    if not (inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")) then
        return
    end
    PrivacyTextNodes[inst] = true
    local nm = GetPrivacyName()
    if nm then
        ApplySpoofToInstance(inst, OriginalDisplayName, OriginalUserName, nm)
    end
end

local function HookPrivacyRoot(root)
    if not root then
        return
    end
    for _, inst in ipairs(root:GetDescendants()) do
        AddPrivacyNode(inst)
    end
    AddPrivacyConn(root.DescendantAdded:Connect(function(inst)
        if GetPrivacyName() then
            AddPrivacyNode(inst)
        end
    end))
end

local function SweepPrivacyText(nm)
    for inst in pairs(PrivacyTextNodes) do
        if inst and inst.Parent then
            ApplySpoofToInstance(inst, OriginalDisplayName, OriginalUserName, nm)
        else
            PrivacyTextNodes[inst] = nil
        end
    end
end

local function ApplyStreamerTag()
    if IsTagChangerActive() then
        if StreamerTagConn then
            StreamerTagConn:Disconnect()
            StreamerTagConn = nil
        end
        StreamerTag = nil
        StreamerTagOrig = nil
        return
    end
    local nm = EnsureSpoofName()
    local tag = LocalPlayer:FindFirstChild("Tag")
    if not tag then
        return
    end
    if StreamerTag and StreamerTag ~= tag then
        if StreamerTagConn then
            StreamerTagConn:Disconnect()
            StreamerTagConn = nil
        end
    end
    if StreamerTag ~= tag then
        StreamerTag = tag
        StreamerTagOrig = tag.Value
    end
    if tag.Value ~= nm then
        tag.Value = nm
    end
    if StreamerTagConn then
        StreamerTagConn:Disconnect()
        StreamerTagConn = nil
    end
    StreamerTagConn = tag:GetPropertyChangedSignal("Value"):Connect(function()
        if not Globals.StreamerMode then
            return
        end
        if IsTagChangerActive() then
            return
        end
        local nm2 = EnsureSpoofName()
        if tag.Value ~= nm2 then
            tag.Value = nm2
        end
    end)
end

local function RestoreStreamerTag()
    if StreamerTagConn then
        StreamerTagConn:Disconnect()
        StreamerTagConn = nil
    end
    if IsTagChangerActive() then
        StreamerTag = nil
        StreamerTagOrig = nil
        return
    end
    if StreamerTag and StreamerTag.Parent and StreamerTagOrig ~= nil then
        pcall(function()
            StreamerTag.Value = StreamerTagOrig
        end)
    end
    StreamerTag = nil
    StreamerTagOrig = nil
end

local function ApplyPrivacyOnce()
    local nm = GetPrivacyName()
    if not nm then
        return
    end
    if LastSpoofName and LastSpoofName ~= nm then
        RestoreSpoofText()
    end
    if Globals.StreamerMode then
        ApplyStreamerTag()
    else
        RestoreStreamerTag()
    end
    SetLocalDisplayName(nm)
    SweepPrivacyText(nm)
    LastSpoofName = nm
end

local function StopPrivacyMode()
    ClearPrivacyConns()
    RestoreSpoofText()
    LastSpoofName = nil
    RestoreStreamerTag()
    SetLocalDisplayName(OriginalDisplayName)
    PrivacyRunning = false
end

local function StartPrivacyMode()
    if PrivacyRunning then
        return
    end
    PrivacyRunning = true
    ClearPrivacyConns()
    ApplyPrivacyOnce()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg then
        HookPrivacyRoot(pg)
    end
    local CoreGui = game:GetService("CoreGui")
    if CoreGui then
        HookPrivacyRoot(CoreGui)
    end
    local TagsRoot = workspace:FindFirstChild("Nametags")
    if TagsRoot then
        HookPrivacyRoot(TagsRoot)
    end
    local ch = LocalPlayer.Character
    if ch then
        HookPrivacyRoot(ch)
    end
    AddPrivacyConn(LocalPlayer.CharacterAdded:Connect(function(NewChar)
        if GetPrivacyName() then
            HookPrivacyRoot(NewChar)
            ApplyPrivacyOnce()
        end
    end))
    AddPrivacyConn(workspace.ChildAdded:Connect(function(inst)
        if GetPrivacyName() and inst.Name == "Nametags" then
            HookPrivacyRoot(inst)
            ApplyPrivacyOnce()
        end
    end))
    local function step()
        if not GetPrivacyName() then
            StopPrivacyMode()
            return
        end
        ApplyPrivacyOnce()
        task.delay(0.5, step)
    end
    task.defer(step)
end

UpdatePrivacyState = function()
    if GetPrivacyName() then
        if not PrivacyRunning then
            StartPrivacyMode()
        else
            ApplyPrivacyOnce()
        end
    else
        if PrivacyRunning then
            StopPrivacyMode()
        end
    end
end

UpdatePrivacyState()
end

-- // for calculating path
local function FindPath()
    local MapFolder = workspace:FindFirstChild("Map")
    if not MapFolder then return nil end
    local PathsFolder = MapFolder:FindFirstChild("Paths")
    if not PathsFolder then return nil end
    local PathFolder = PathsFolder:GetChildren()[1]
    if not PathFolder then return nil end

    local PathNodes = {}
    for _, node in ipairs(PathFolder:GetChildren()) do
        if node:IsA("BasePart") then
            table.insert(PathNodes, node)
        end
    end

    table.sort(PathNodes, function(a, b)
        local NumA = tonumber(a.Name:match("%d+"))
        local NumB = tonumber(b.Name:match("%d+"))
        if NumA and NumB then return NumA < NumB end
        return a.Name < b.Name
    end)

    return PathNodes
end

local function TotalLength(PathNodes)
    local TotalLength = 0
    for i = 1, #PathNodes - 1 do
        TotalLength = TotalLength + (PathNodes[i + 1].Position - PathNodes[i].Position).Magnitude
    end
    return TotalLength
end

local MercenarySlider
local MilitarySlider
local MaxLenght

local function CalcLength()
    local map = workspace:FindFirstChild("Map")

    if GameState == "GAME" and map then
        local PathNodes = FindPath()

        if PathNodes and #PathNodes > 0 then
            MaxPathDistance = TotalLength(PathNodes)

            if MercenarySlider then
                MercenarySlider:SetMax(MaxPathDistance) 
            end

            if MilitarySlider then
                MilitarySlider:SetMax(MaxPathDistance)
            end

            if MaxLenght then
                MaxLenght = MaxPathDistance
            end
            return true
        end
    end
    return false
end

local function GetPointAtDistance(PathNodes, distance)
    if not PathNodes or #PathNodes < 2 then return nil end

    local CurrentDist = 0
    for i = 1, #PathNodes - 1 do
        local StartPos = PathNodes[i].Position
        local EndPos = PathNodes[i+1].Position
        local SegmentLen = (EndPos - StartPos).Magnitude

        if CurrentDist + SegmentLen >= distance then
            local remaining = distance - CurrentDist
            local direction = (EndPos - StartPos).Unit
            return StartPos + (direction * remaining)
        end
        CurrentDist = CurrentDist + SegmentLen
    end
    return PathNodes[#PathNodes].Position
end

local function UpdatePathVisuals()
    if not Globals.PathVisuals then
        if MilMarker then 
            MilMarker:Destroy() 
            MilMarker = nil 
        end
        if MercMarker then 
            MercMarker:Destroy() 
            MercMarker = nil 
        end
        return
    end

    local PathNodes = FindPath()
    if not PathNodes then return end

    if not MilMarker then
        MilMarker = Instance.new("Part")
        MilMarker.Name = "MilVisual"
        MilMarker.Shape = Enum.PartType.Cylinder
        MilMarker.Size = Vector3.new(0.3, 3, 3)
        MilMarker.Color = Color3.fromRGB(0, 255, 0)
        MilMarker.Material = Enum.Material.Plastic
        MilMarker.Anchored = true
        MilMarker.CanCollide = false
        MilMarker.Orientation = Vector3.new(0, 0, 90)
        MilMarker.Parent = workspace
    end

    if not MercMarker then
        MercMarker = MilMarker:Clone()
        MercMarker.Name = "MercVisual"
        MercMarker.Color = Color3.fromRGB(255, 0, 0)
        MercMarker.Parent = workspace
    end

    local MilPos = GetPointAtDistance(PathNodes, Globals.MilitaryPath or 0)
    local MercPos = GetPointAtDistance(PathNodes, Globals.MercenaryPath or 0)

    if MilPos then
        MilMarker.Position = MilPos + Vector3.new(0, 0.2, 0)
        MilMarker.Transparency = 0.7
    end
    if MercPos then
        MercMarker.Position = MercPos + Vector3.new(0, 0.2, 0)
        MercMarker.Transparency = 0.7
    end
end

local function MissionsUIFix()
    task.spawn(function()
        while task.wait(1) do
            pcall(function()
                local MissionsScrollingFrame = game:GetService("Players").LocalPlayer.PlayerGui.ReactLobbyQuests.quests.missions.scrollingFrame
                local MissionsListLayout = MissionsScrollingFrame.listLayout
                local MissionFrame = MissionsScrollingFrame["1"]
                if MissionFrame.AbsoluteSize.Y > 0 then
                    local UIScaleRatio = MissionFrame.AbsoluteSize.Y / MissionFrame.Size.Y.Offset
                    local CurrentCanvasSize = MissionsScrollingFrame.CanvasSize
                    local CanvasHeight = (MissionsListLayout.AbsoluteContentSize.Y / UIScaleRatio) + 25
                    MissionsScrollingFrame.CanvasSize = UDim2.new(CurrentCanvasSize.X.Scale, CurrentCanvasSize.X.Offset, CurrentCanvasSize.Y.Scale, CanvasHeight)
                end
            end)
        end
    end)
end

function TDS:Addons(SkipGameState)
    if GameState == "LOBBY" and not SkipGameState then
        return false
    end

    if PremiumLoaded then
        return true
    end
    
    while IsCurrentlyLoading or IsEquippingLoadout or (TDS and TDS.LoadoutPending) or (os.clock() - LastLoadTime < 5) do 
        task.wait(0.2) 
    end

    local originalPlace = self.Place
    IsCurrentlyLoading = true

    local url = "https://api.jnkie.com/api/v1/luascripts/public/57fe397f76043ce06afad24f07528c9f93e97730930242f57134d0b60a2d250b/download"
    local success, code

    repeat
        success, code = pcall(game.HttpGet, game, url)
        if not success or not code then
            task.wait(1)
        end
    until success and code

    local func = loadstring(code)
    if not func then
        IsCurrentlyLoading = false
        LastLoadTime = os.clock()
        return false
    end

    pcall(func)

    while self.Place == originalPlace do
        task.wait(0.1)
    end

    PremiumLoaded = true
    IsCurrentlyLoading = false
    LastLoadTime = os.clock()
    return true
end

local function GetEquippedTowers()
    local towers = {}
    local StateReplicators = ReplicatedStorage:FindFirstChild("StateReplicators")

    if StateReplicators then
        for _, folder in ipairs(StateReplicators:GetChildren()) do
            if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == LocalPlayer.UserId then
                local equipped = folder:GetAttribute("EquippedTowers")
                if type(equipped) == "string" then
                    local CleanedJson = equipped:match("%[.*%]") 
                    local success, TowerTable = pcall(function()
                        return HttpService:JSONDecode(CleanedJson)
                    end)

                    if success and type(TowerTable) == "table" then
                        for i = 1, 5 do
                            if TowerTable[i] then
                                table.insert(towers, TowerTable[i])
                            end
                        end
                    end
                end
            end
        end
    end
    return #towers > 0 and towers or {"None"}
end

CurrentEquippedTowers = GetEquippedTowers()

local CrateList = {
    "All", "Basic", "Premium", "Deluxe", "Golden", "Bunny", "Halloween 2019", 
    "Party", "Toy", "Valentines", "Xmas 2019", "Spooky", "Pumpkin", "Frost", 
    "Lovely", "Cold Front", "Ducky", "Vigilante", "Pirate", "Phantom", 
    "Halloween", "Jolly", "Lunar", "Lovestruck", "UglyCrate", "Coin Crate", 
    "Banned", "Christmas 2025", "Showtime", "Valentines 2026", "Shamrock",
    "Low Grade", "Mid Grade", "High Grade"
}

local AutoOpenRunning = false

local function StartAutoOpenCrates()
    if AutoOpenRunning or not Globals.AutoOpenCrates then return end
    AutoOpenRunning = true

    for _, crateName in ipairs(CrateList) do
        if crateName == "All" then continue end

        task.spawn(function()
            while Globals.AutoOpenCrates do
                if Globals.SelectedCrate == "All" or Globals.SelectedCrate == crateName then
                    local success, res = pcall(function()
                        return RemoteFunc:InvokeServer("Inventory", "Open", "Crate", crateName)
                    end)

                    if success and type(res) == "table" then
                        task.wait(0.1) 
                    else
                        task.wait(5)
                    end
                else
                    task.wait(1)
                end
            end
        end)
    end

    task.spawn(function()
        repeat task.wait(1) until not Globals.AutoOpenCrates
        AutoOpenRunning = false
    end)
end

-- // voting & map selection
local function RunVoteSkip()
    while true do
        local success = pcall(function()
            RemoteFunc:InvokeServer("Voting", "Skip")
        end)
        if success then break end
        task.wait(0.1)
    end
end

AutoReadyRunning = false

local function StartAutoReady()
    if AutoReadyRunning or not Globals.AutoReady or GameState ~= "GAME" then return end
    AutoReadyRunning = true

    task.spawn(function()
        local voteReplicator = ReplicatedStorage:WaitForChild("StateReplicators"):WaitForChild("VoteReplicator")
        
        repeat task.wait(0.1) until voteReplicator:GetAttribute("Enabled") == true and voteReplicator:GetAttribute("Title") == "Ready?"
        
        RunVoteSkip()
        
        repeat task.wait(0.1) until voteReplicator:GetAttribute("Enabled") == false
        
        AutoReadyRunning = false
    end)
end

local EasyModeRunning = false

local function StartEasyMode()
    if EasyModeRunning or not Globals.Easy then return end

    EasyModeRunning = true

    task.spawn(function()
        local content = nil

        while Globals.Easy and content == nil do
            local success, res = pcall(function() 
                return game:HttpGet("https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Strategies/Easy.lua") 
            end)

            if success and type(res) == "string" then
                content = res
            else
                task.wait(1)
            end
        end

        if content then
            while not (TDS and TDS.Loadout) do 
                task.wait(0.5) 
            end

            local func = loadstring(content)

            if func then
                pcall(func)

                Window:Notify({Title = "ADS", Desc = "Running...", Time = 3})
            end
        end

        repeat task.wait(2) until not Globals.Easy or (GameState == "GAME" and not game:IsLoaded())

        EasyModeRunning = false
    end)
end

local function AutoSetDJSong(tower)
    task.spawn(function()
        local replicator = tower:WaitForChild("TowerReplicator", 10)
        if not replicator then return end
        if replicator:GetAttribute("Name") ~= "DJ Booth" then return end
        if replicator:GetAttribute("OwnerId") ~= LocalPlayer.UserId then return end
        
        local songIdNum = tonumber(Globals.DJCustomSongID)
        if not songIdNum then return end
        
        pcall(function()
            RemoteFunc:InvokeServer(
                "Troops",
                "Execute",
                {
                    Data = { songIdNum },
                    Name = "Music",
                    Tower = tower
                }
            )
        end)
    end)
end

task.spawn(function()
    local Towers = workspace:WaitForChild("Towers", 10)
    if not Towers then return end
    Towers.ChildAdded:Connect(AutoSetDJSong)
    for _, tower in ipairs(Towers:GetChildren()) do
        AutoSetDJSong(tower)
    end
end)

local function InvalidateSnapCache()
    TowerSnapper.LastInput = nil
    TowerSnapper.LastSnapped = nil
    TowerSnapper.LastHit = nil
    TowerSnapper.LastValid = false
end
task.spawn(function()
    local TowersFolder = workspace:WaitForChild("Towers", 30)
    if TowersFolder then
        TowersFolder.ChildAdded:Connect(InvalidateSnapCache)
        TowersFolder.ChildRemoved:Connect(InvalidateSnapCache)
    end
end)

local function GetTwoCircleTangents(PosA, RadiusA, PosB, RadiusB, RadiusNew)
    local CenterDist = (Vector3.new(PosB.X, 0, PosB.Z) - Vector3.new(PosA.X, 0, PosA.Z)).Magnitude
    local DistA = RadiusA + RadiusNew + TowerSnapper.SpacingOffset
    local DistB = RadiusB + RadiusNew + TowerSnapper.SpacingOffset
    if CenterDist > (DistA + DistB) or CenterDist < math.abs(DistA - DistB) or CenterDist == 0 then
        return nil
    end
    local SideA = (DistA^2 - DistB^2 + CenterDist^2) / (2 * CenterDist)
    local HeightSq = DistA^2 - SideA^2
    if HeightSq < 0 then return nil end
    local Height = math.sqrt(HeightSq)
    local DirX = (PosB.X - PosA.X) / CenterDist
    local DirZ = (PosB.Z - PosA.Z) / CenterDist
    local MidX = PosA.X + (DirX * SideA)
    local MidZ = PosA.Z + (DirZ * SideA)
    local NormX = -DirZ
    local NormZ = DirX
    local Pocket1 = Vector3.new(MidX + (NormX * Height), PosA.Y, MidZ + (NormZ * Height))
    local Pocket2 = Vector3.new(MidX - (NormX * Height), PosA.Y, MidZ - (NormZ * Height))
    return Pocket1, Pocket2
end

local function FindHoneycombCandidates(TowerName, TargetPos)
    local TowersFolder = workspace:FindFirstChild("Towers")
    if not TowersFolder then return {} end
    local Asset = require(ReplicatedStorage.Shared.Modules.Asset)
    local SharedConstants = require(ReplicatedStorage.Shared.Modules.SharedGameConstants)
    local TowerAsset = Asset("Troops", TowerName)
    local DefaultBoundary = SharedConstants.DEFAULT_BOUNDARY_SIZE or 1.5
    local NewRadius = (TowerAsset and TowerAsset.Properties and TowerAsset.Properties.BoundarySize) or DefaultBoundary
    local NearbyTowers = {}

    for _, TowerInstance in ipairs(TowersFolder:GetChildren()) do
        local Replicator = TowerInstance:FindFirstChild("TowerReplicator")
        if Replicator then
            local OtherName = Replicator:GetAttribute("Name") or TowerInstance.Name
            local OtherAsset = Asset("Troops", OtherName)
            local OtherRadius = (OtherAsset and OtherAsset.Properties and OtherAsset.Properties.BoundarySize) or DefaultBoundary
            local TowerPos = TowerInstance:GetPivot().Position
            local Dist = (Vector3.new(TowerPos.X, 0, TowerPos.Z) - Vector3.new(TargetPos.X, 0, TargetPos.Z)).Magnitude
            if Dist <= (OtherRadius + NewRadius + 12) then
                table.insert(NearbyTowers, {
                    Position = TowerPos,
                    Radius = OtherRadius,
                    Distance = Dist
                })
            end
        end
    end

    if #NearbyTowers == 0 then return {} end
    table.sort(NearbyTowers, function(A, B) return A.Distance < B.Distance end)

    local Candidates = {}

    if #NearbyTowers >= 2 then
        for FirstIdx = 1, math.min(#NearbyTowers - 1, 3) do
            for SecondIdx = FirstIdx + 1, math.min(#NearbyTowers, 4) do
                local TowerA = NearbyTowers[FirstIdx]
                local TowerB = NearbyTowers[SecondIdx]
                local P1, P2 = GetTwoCircleTangents(TowerA.Position, TowerA.Radius, TowerB.Position, TowerB.Radius, NewRadius)
                if P1 then table.insert(Candidates, P1) end
                if P2 then table.insert(Candidates, P2) end
            end
        end
    end

    for Index = 1, math.min(#NearbyTowers, 3) do
        local Tower = NearbyTowers[Index]
        local Dir = (Vector3.new(TargetPos.X, 0, TargetPos.Z) - Vector3.new(Tower.Position.X, 0, Tower.Position.Z))
        local TangentDist = Tower.Radius + NewRadius + TowerSnapper.SpacingOffset

        if Dir.Magnitude > 0.01 then
            table.insert(Candidates, Tower.Position + (Dir.Unit * TangentDist))
        end

        for AngleIdx = 0, 15 do
            local Angle = (math.pi * 2 / 16) * AngleIdx
            table.insert(Candidates, Tower.Position + Vector3.new(math.cos(Angle) * TangentDist, 0, math.sin(Angle) * TangentDist))
        end
    end

    return Candidates
end

local function FindNearestValidPlacement(CheckCollisionsOriginal, TowerName, TargetPos, Team, MaxRadius)
    local CurrentTowerCount = #workspace.Towers:GetChildren()
    if CurrentTowerCount ~= TowerSnapper.TowerCount then
        TowerSnapper.TowerCount = CurrentTowerCount
        InvalidateSnapCache()
    end

    local IsValidDirect, DirectHit = CheckCollisionsOriginal(TowerName, TargetPos, Team)
    if IsValidDirect then
        TowerSnapper.LastInput = TargetPos
        TowerSnapper.LastSnapped = TargetPos
        TowerSnapper.LastHit = DirectHit
        TowerSnapper.LastValid = true
        return TargetPos, DirectHit, false
    end

    if TowerSnapper.LastInput and (TargetPos - TowerSnapper.LastInput).Magnitude < 0.02 then
        if TowerSnapper.LastValid and TowerSnapper.LastSnapped then
            return TowerSnapper.LastSnapped, TowerSnapper.LastHit, true
        end
    end

    local BestPos = nil
    local BestDist = math.huge
    local BestHit = nil

    local HoneycombCandidates = FindHoneycombCandidates(TowerName, TargetPos)
    for _, CandPos in ipairs(HoneycombCandidates) do
        local IsCandValid, CandHit = CheckCollisionsOriginal(TowerName, CandPos, Team)
        if IsCandValid and CandHit then
            local ActualPos = (typeof(CandHit) == "RaycastResult") and CandHit.Position or CandPos
            local CandDist = (Vector3.new(ActualPos.X, 0, ActualPos.Z) - Vector3.new(TargetPos.X, 0, TargetPos.Z)).Magnitude
            if CandDist < BestDist then
                BestDist = CandDist
                BestPos = ActualPos
                BestHit = CandHit
            end
        end
    end

    MaxRadius = MaxRadius or TowerSnapper.MaxRadius
    local CoarseStep = TowerSnapper.CoarseStep
    local BestCoarseDist = math.huge
    local BestAngle = 0
    local BestRadius = 0

    for Radius = CoarseStep, MaxRadius, CoarseStep do
        if Radius >= BestDist then
            break
        end

        local Count = math.max(12, math.floor(2 * math.pi * Radius / CoarseStep))
        local AngleStep = (2 * math.pi) / Count
        local FoundInRing = false

        for Index = 0, Count - 1 do
            local Theta = Index * AngleStep
            local TestPos = TargetPos + Vector3.new(math.cos(Theta) * Radius, 0, math.sin(Theta) * Radius)
            local Valid, Res = CheckCollisionsOriginal(TowerName, TestPos, Team)
            if Valid and Res then
                local ActualPos = (typeof(Res) == "RaycastResult") and Res.Position or TestPos
                local Dist = (Vector3.new(ActualPos.X, 0, ActualPos.Z) - Vector3.new(TargetPos.X, 0, TargetPos.Z)).Magnitude
                if Dist < BestCoarseDist then
                    BestCoarseDist = Dist
                    BestAngle = Theta
                    BestRadius = Radius
                    FoundInRing = true
                end
            end
        end

        if FoundInRing and BestCoarseDist <= Radius + (CoarseStep * 0.5) then
            break
        end
    end

    if BestCoarseDist < BestDist then
        local FineBestPos = nil
        local FineBestDist = math.huge
        local FineBestRes = nil
        local RadiusMin = math.max(0.04, BestRadius - CoarseStep)
        local RadiusMax = BestRadius + (CoarseStep * 0.5)
        local RadiusStep = TowerSnapper.FineStep
        local AngleSpan = math.atan2(CoarseStep, BestRadius) * 1.6

        for Radius = RadiusMin, RadiusMax, RadiusStep do
            local AngleSteps = math.max(6, math.floor(Radius * AngleSpan / RadiusStep))
            for Index = -AngleSteps, AngleSteps do
                local Theta = BestAngle + (Index * (AngleSpan / AngleSteps))
                local TestPos = TargetPos + Vector3.new(math.cos(Theta) * Radius, 0, math.sin(Theta) * Radius)
                local Valid, Res = CheckCollisionsOriginal(TowerName, TestPos, Team)
                if Valid and Res then
                    local ActualPos = (typeof(Res) == "RaycastResult") and Res.Position or TestPos
                    local Dist = (Vector3.new(ActualPos.X, 0, ActualPos.Z) - Vector3.new(TargetPos.X, 0, TargetPos.Z)).Magnitude
                    if Dist < FineBestDist then
                        FineBestDist = Dist
                        FineBestPos = ActualPos
                        FineBestRes = Res
                    end
                end
            end
            if FineBestPos and FineBestDist <= Radius + 0.04 then
                break
            end
        end

        if FineBestPos and FineBestDist < BestDist then
            BestDist = FineBestDist
            BestPos = FineBestPos
            BestHit = FineBestRes
        end
    end

    local FinalPos = BestPos or TargetPos
    local FinalRes = BestHit or DirectHit
    local IsSnapped = (BestPos ~= nil)

    TowerSnapper.LastInput = TargetPos
    TowerSnapper.LastSnapped = FinalPos
    TowerSnapper.LastHit = FinalRes
    TowerSnapper.LastValid = IsSnapped

    return FinalPos, FinalRes, IsSnapped
end

local function HookPlacementSystem()
    local Success, Err = pcall(function()
        local NewPlacementController = require(ReplicatedStorage.Client.Controllers.Game.NewPlacementController)
        local SharedGameFunctions = require(ReplicatedStorage.Shared.Modules.SharedGameFunctions)
        local Scheduler = require(ReplicatedStorage.Shared.Modules.Scheduler)
        local OrigCheckTowerCollisions = SharedGameFunctions.CheckTowerCollisions
        local ProxyShared = setmetatable({}, {
            __index = function(_, Key)
                if Key == "CheckTowerCollisions" then
                    return function(TowerName, Pos, Team, ...)
                        if not TowerSnapper.Enabled then
                            return OrigCheckTowerCollisions(TowerName, Pos, Team, ...)
                        end
                        local SnappedPos, HitRes, IsSnapped = FindNearestValidPlacement(
                            OrigCheckTowerCollisions,
                            TowerName,
                            Pos,
                            Team
                        )
                        if IsSnapped and HitRes then
                            return true, HitRes
                        end
                        return OrigCheckTowerCollisions(TowerName, Pos, Team, ...)
                    end
                end
                return SharedGameFunctions[Key]
            end,
            __newindex = function(_, Key, Val)
                SharedGameFunctions[Key] = Val
            end
        })
        if getupvalues and setupvalue then
            local Upvals = getupvalues(NewPlacementController.Start)
            for Idx, Val in pairs(Upvals) do
                if Val == SharedGameFunctions then
                    setupvalue(NewPlacementController.Start, Idx, ProxyShared)
                    break
                end
            end
        end
        if NewPlacementController.Place and NewPlacementController.Place.Connect then
            NewPlacementController.Place:Connect(function()
                InvalidateSnapCache()
            end)
        end
        local OrigAdd = Scheduler.add
        Scheduler.add = function(Name, Signal, Callback)
            if Name == "TowerPlacement" and type(Callback) == "function" then
                local WrappedCallback = function(Dt)
                    if not TowerSnapper.Enabled then
                        return Callback(Dt)
                    end
                    local Upvals = getupvalues(Callback)
                    local Mouse = Upvals[1]
                    local RaycastParams = Upvals[2]
                    local SharedGame = Upvals[3]
                    local TowerData = Upvals[4]
                    local Team = Upvals[5]
                    local UpgradesStore = Upvals[7]
                    local Model = Upvals[8]
                    local SpringPos = Upvals[11]
                    local RotLerp = Upvals[12]
                    local TargetRot = Upvals[13]
                    local AnimController = Upvals[14]
                    local TowerClass = Upvals[15]
                    local EnumModule = Upvals[16]
                    local SpringNormal = Upvals[17]
                    local QuaternionModule = Upvals[18]
                    local Ray = workspace:Raycast(Mouse.UnitRay.Origin, Mouse.UnitRay.Direction * 1000, RaycastParams)
                    if Ray then
                        local IsValid, HitRes = SharedGame.CheckTowerCollisions(TowerData.Name, Ray.Position, Team)
                        if Upvals[6] ~= IsValid then
                            setupvalue(Callback, 6, IsValid)
                            UpgradesStore.updateValid(Model, IsValid)
                        end
                        local FinalTargetPos = Ray.Position
                        local FinalTargetNormal = Ray.Normal
                        if IsValid and HitRes then
                            local HitPos = (typeof(HitRes) == "RaycastResult") and HitRes.Position or HitRes
                            setupvalue(Callback, 9, HitPos)
                            FinalTargetPos = HitPos
                            if typeof(HitRes) == "RaycastResult" and HitRes.Normal then
                                FinalTargetNormal = HitRes.Normal
                            end
                        end
                        if Upvals[10] then
                            setupvalue(Callback, 10, false)
                            SpringPos.init(FinalTargetPos, Vector3.new(0, 0, 0))
                        else
                            SpringPos.t = FinalTargetPos
                        end
                        local DtAlpha = math.min(Dt * 10, 1)
                        RotLerp = math.lerp(RotLerp, TargetRot, DtAlpha)
                        setupvalue(Callback, 12, RotLerp)
                        local ModelCF = CFrame.new(SpringPos.p) * CFrame.Angles(0, math.rad(RotLerp), 0)
                        if AnimController and TowerClass ~= EnumModule.TowerType.Flying and SpringNormal and QuaternionModule then
                            SpringNormal.t = ModelCF.Position
                            local Tilt = QuaternionModule(FinalTargetNormal, FinalTargetNormal + (-0.01 * SpringNormal.v)) + SpringNormal.p
                            ModelCF = ModelCF * (Tilt - Tilt.Position)
                        end
                        Model:PivotTo(CFrame.new(ModelCF.X, FinalTargetPos.Y, ModelCF.Z) * CFrame.Angles(ModelCF:toEulerAnglesXYZ()))
                    end
                end
                return OrigAdd(Name, Signal, WrappedCallback)
            end
            return OrigAdd(Name, Signal, Callback)
        end
    end)
end

local function GetDJRangeBuffPercent(UpgradeLevel, TrackName)
    TrackName = TrackName or "Purple"
    if TrackName == "Purple" then
        local PurpleTable = { [0] = 12.5, [1] = 12.5, [2] = 15, [3] = 17.5, [4] = 22.5, [5] = 25 }
        return PurpleTable[UpgradeLevel] or 12.5
    elseif TrackName == "Green" or TrackName == "Red" then
        if UpgradeLevel >= 5 then
            return 10
        end
    end
    return 0
end

local function ClearBuffVisuals()
    for _, VisualRecord in pairs(BuffOverlay.AuraVisuals) do
        if VisualRecord.OutlinePart and VisualRecord.OutlinePart.Parent then
            VisualRecord.OutlinePart:Destroy()
        end
    end
    table.clear(BuffOverlay.AuraVisuals)

    if BuffOverlay.BasePreviewRange then
        pcall(function()
            local UpgradesStore = require(ReplicatedStorage.Client.Interfaces.Stores.Game.UpgradesStore)
            UpgradesStore.updateZone({ range = BuffOverlay.BasePreviewRange })
        end)
        BuffOverlay.BasePreviewRange = nil
        BuffOverlay.CurrentExpandedRange = nil
    end
end

local function UpdateBuffOverlay(CursorPosition, DeltaTime)
    if not BuffOverlay.Enabled or not CursorPosition then
        ClearBuffVisuals()
        return
    end

    local TowersFolder = workspace:FindFirstChild("Towers")
    if not TowersFolder then
        ClearBuffVisuals()
        return
    end

    BuffOverlay.PulseClock = BuffOverlay.PulseClock + (DeltaTime or 0.016)
    local PulseAlpha = (math.sin(BuffOverlay.PulseClock * 4) + 1) * 0.5

    local FoundSupports = {}
    local ActiveDJBuffPercent = 0

    for _, TowerInstance in ipairs(TowersFolder:GetChildren()) do
        local Replicator = TowerInstance:FindFirstChild("TowerReplicator")
        if Replicator then
            local TowerName = Replicator:GetAttribute("Name")
            local Definition = BuffOverlay.SupportDefinitions[TowerName]
            if Definition then
                local UpgradeLevel = Replicator:GetAttribute("Upgrade") or 0
                
                local BaseRange = Replicator:GetAttribute("Range")
                if not BaseRange or BaseRange <= 0 then
                    BaseRange = Definition.FallbackRanges[UpgradeLevel] or Definition.FallbackRanges[0] or 12
                end

                local RangeBuff = Replicator:GetAttribute("RangeBuff") or 0
                local ActualRadius = BaseRange * (1 + (RangeBuff / 100))
                local TowerPosition = TowerInstance:GetPivot().Position

                table.insert(FoundSupports, {
                    Name = TowerName,
                    Tag = Definition.Tag,
                    Definition = Definition,
                    Instance = TowerInstance,
                    Position = TowerPosition,
                    Radius = ActualRadius,
                    Replicator = Replicator,
                    Upgrade = UpgradeLevel
                })
            end
        end
    end

    if #FoundSupports == 0 then
        ClearBuffVisuals()
        return
    end

    for _, SupportData in ipairs(FoundSupports) do
        local FlatDistance = (Vector3.new(SupportData.Position.X, 0, SupportData.Position.Z) - Vector3.new(CursorPosition.X, 0, CursorPosition.Z)).Magnitude
        local InRange = (FlatDistance <= SupportData.Radius)

        if InRange and SupportData.Tag == "DJ" then
            local TrackName = SupportData.Replicator:GetAttribute("Track") or "Purple"
            local BuffPercent = GetDJRangeBuffPercent(SupportData.Upgrade, TrackName)
            if BuffPercent > ActiveDJBuffPercent then
                ActiveDJBuffPercent = BuffPercent
            end
        end

        local VisualRecord = BuffOverlay.AuraVisuals[SupportData.Instance]
        if not VisualRecord then
            local OutlinePart = Instance.new("Part")
            OutlinePart.Name = "AuraOutline_" .. SupportData.Tag
            OutlinePart.Anchored = true
            OutlinePart.CanCollide = false
            OutlinePart.CanTouch = false
            OutlinePart.CanQuery = false
            OutlinePart.Transparency = 1
            OutlinePart.Material = Enum.Material.Plastic
            OutlinePart.Parent = workspace

            local Adornment = Instance.new("CylinderHandleAdornment")
            Adornment.Name = "RingAdornment"
            Adornment.Adornee = OutlinePart
            Adornment.AlwaysOnTop = false
            Adornment.ZIndex = 1
            Adornment.CFrame = CFrame.Angles(math.rad(90), 0, 0)
            Adornment.Parent = OutlinePart

            VisualRecord = {
                OutlinePart = OutlinePart,
                Adornment = Adornment
            }
            BuffOverlay.AuraVisuals[SupportData.Instance] = VisualRecord
        end

        local FloorY = SupportData.Position.Y + 0.08
        VisualRecord.OutlinePart.Position = Vector3.new(SupportData.Position.X, FloorY, SupportData.Position.Z)
        VisualRecord.OutlinePart.Size = Vector3.new(0.2, 0.2, 0.2)

        local Radius = SupportData.Radius
        local Thickness = 0.18
        VisualRecord.Adornment.Radius = Radius
        VisualRecord.Adornment.InnerRadius = Radius - Thickness
        VisualRecord.Adornment.Height = 0.05
        VisualRecord.Adornment.Color3 = InRange and SupportData.Definition.GlowColor or SupportData.Definition.Color
        VisualRecord.Adornment.Transparency = InRange and (0.15 - (PulseAlpha * 0.1)) or 0.55
    end

    for SupportInstance, VisualRecord in pairs(BuffOverlay.AuraVisuals) do
        if not SupportInstance or not SupportInstance.Parent then
            if VisualRecord.OutlinePart then VisualRecord.OutlinePart:Destroy() end
            BuffOverlay.AuraVisuals[SupportInstance] = nil
        end
    end

    pcall(function()
        local UpgradesStore = require(ReplicatedStorage.Client.Interfaces.Stores.Game.UpgradesStore)
        local State = UpgradesStore.getState()
        local CurrentStoreRange = State.range or 0

        if CurrentStoreRange > 0 then
            if not BuffOverlay.BasePreviewRange or (CurrentStoreRange ~= BuffOverlay.CurrentExpandedRange and CurrentStoreRange ~= BuffOverlay.BasePreviewRange) then
                BuffOverlay.BasePreviewRange = CurrentStoreRange
            end

            local TargetRange = BuffOverlay.BasePreviewRange
            if ActiveDJBuffPercent > 0 and TargetRange then
                TargetRange = math.round(BuffOverlay.BasePreviewRange * (1 + (ActiveDJBuffPercent / 100)))
            end

            if TargetRange and TargetRange ~= CurrentStoreRange then
                BuffOverlay.CurrentExpandedRange = TargetRange
                UpgradesStore.updateZone({ range = TargetRange })
            end
        end
    end)
end

RunService.RenderStepped:Connect(function(DeltaTime)
    if GameState ~= "GAME" then
        ClearBuffVisuals()
        return
    end

    local NewPlacementController = require(ReplicatedStorage.Client.Controllers.Game.NewPlacementController)
    if not NewPlacementController.Active or not BuffOverlay.Enabled then
        ClearBuffVisuals()
        return
    end

    local TargetPosition = TowerSnapper and TowerSnapper.LastSnapped
    if not TargetPosition then
        local Mouse = LocalPlayer:GetMouse()
        TargetPosition = Mouse.Hit and Mouse.Hit.Position
    end
    
    if TargetPosition then
        UpdateBuffOverlay(TargetPosition, DeltaTime)
    else
        ClearBuffVisuals()
    end
end)

if GameState == "GAME" then
    HookPlacementSystem()
end

-- // ui
local function loadNEWUI()
    local searchPaths = {
        "[DUXXY[/NEWUI.lua",
        "[DUXXY[\\NEWUI.lua",
        "[DUXXY]/NEWUI.lua",
        "[DUXXY]\\NEWUI.lua",
        "NEWUI.lua",
        "C:\\Users\\ADMINI~1\\AppData\\Local\\Real\\workspace\\[DUXXY[\\NEWUI.lua",
        "C:/Users/ADMINI~1/AppData/Local/Real/workspace/[DUXXY[/NEWUI.lua",
        "C:\\Users\\Administrator\\AppData\\Local\\Real\\workspace\\[DUXXY[\\NEWUI.lua",
        "C:/Users/Administrator/AppData/Local/Real/workspace/[DUXXY[/NEWUI.lua",
        "[SomethingNew]/NEWUI.lua",
        "[SomethingNew]\\NEWUI.lua",
        "CoreRevampNewAPI.lua",
    }
    for _, path in ipairs(searchPaths) do
        local ok, content = pcall(function()
            if typeof(isfile) == "function" and not isfile(path) then
                return nil
            end
            if typeof(readfile) == "function" then
                return readfile(path)
            end
            return nil
        end)
        if ok and type(content) == "string" and #content > 0 then
            local loader, parseErr = loadstring(content, "NEWUI")
            if loader then
                local execOk, lib = pcall(loader)
                if execOk and lib then
                    return lib
                end
            end
        end
    end

    local ok, fallback = pcall(readfile, "[DUXXY[/NEWUI.lua")
    if not ok or type(fallback) ~= "string" or #fallback == 0 then
        ok, fallback = pcall(readfile, "NEWUI.lua")
    end
    if ok and type(fallback) == "string" and #fallback > 0 then
        local loader = loadstring(fallback, "NEWUI")
        if loader then
            local execOk, lib = pcall(loader)
            if execOk and lib then
                return lib
            end
        end
    end

    -- Fallback to remote UI if local NEWUI is not reachable
    local remoteOk, remoteChunk = pcall(game.HttpGet, game, "https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Sources/UI.lua")
    if remoteOk and type(remoteChunk) == "string" and #remoteChunk > 0 then
        local loader = loadstring(remoteChunk, "UI")
        if loader then
            local execOk, lib = pcall(loader)
            if execOk and lib then
                return lib
            end
        end
    end

    error("[DUXXY] Failed to load NEWUI.lua from workspace or remote")
end

local Library = loadNEWUI()

Window = Library:Window({
    Title = "CORE",
    Desc = "your #1 hub",
    Theme = "Default",
    DiscordLink = "https://discord.gg/aetherhub",
    Icon = 116265951007418,
    Config = {
        Keybind = Enum.KeyCode.LeftControl,
        Size = UDim2.new(0, 680, 0, 420)
    }
})

Window:Notify({
    Title = "Core",
    Desc = "This is fully keyless, but please join our Discord to stay updated on new features and scripts! https://discord.gg/getcore",
    Time = 5,
    Type = "normal"
})

task.spawn(function()
    local retries = 0
    while retries < 10 do
        local success, inGroup = pcall(LocalPlayer.IsInGroup, LocalPlayer, 4914494)
        if success then
            if not inGroup then
                Window:Notify({
                    Title = "Warning",
                    Desc = "Please consider joining the Paradoxum Group. Otherwise, strategies may not work for you.",
                    Time = 25,
                    Type = "error"
                })
            end
            break
        end
        retries += 1
        task.wait(1)
    end
end)

-- =============================================================================
-- PREMIUM AUTHENTICATION & KEY SYSTEM (Dynamic Boot & Junkie SDK)
-- =============================================================================
local checkIsPremium, getJunkieSDK, saveVerifiedKey, loadVerifiedKey, clearSavedKey
do
    local INBUILT_PREMIUM_WHITELIST = {}
    local lastVerifiedKeySuccess = nil
    local lastVerifiedKeyTime = 0
    local cachedJunkieSDK = nil

    getJunkieSDK = function()
        if cachedJunkieSDK then return cachedJunkieSDK end
        local sdkChunk = nil
        pcall(function()
            if typeof(isfile) == "function" and isfile("JunkieSDK.lua") and typeof(readfile) == "function" then
                sdkChunk = readfile("JunkieSDK.lua")
            end
        end)
        if not sdkChunk or #sdkChunk == 0 then
            pcall(function()
                sdkChunk = game:HttpGet("https://jnkie.com/sdk/library.lua")
            end)
        end
        if not sdkChunk then return nil end
        local success, junkie = pcall(function()
            return loadstring(sdkChunk)()
        end)
        if success and type(junkie) == "table" then
            junkie.service = "[SomethingHub]"
            junkie.identifier = "1083049"
            junkie.provider = "Access"
            cachedJunkieSDK = junkie
            return junkie
        end
        return nil
    end

    loadVerifiedKey = function()
        local candidates = {
            "[DUXXY[/verified_key.txt",
            "[DUXXY[\\verified_key.txt",
            "[DUXXY[/verified_key",
            "[SomethingNew]/verified_key.txt",
            "verified_key.txt",
            "verified_key"
        }
        for _, path in ipairs(candidates) do
            local ok, content = pcall(function()
                if typeof(isfile) == "function" and isfile(path) and typeof(readfile) == "function" then
                    return readfile(path)
                end
                return nil
            end)
            if ok and content and content ~= "" then
                local trimmed = (tostring(content):gsub("^%s*(.-)%s*$", "%1"))
                if #trimmed > 0 then
                    return trimmed
                end
            end
        end
        return nil
    end

    saveVerifiedKey = function(key)
        if getgenv then
            getgenv().SCRIPT_KEY = key
        end
        local candidateFiles = {
            "[DUXXY[/verified_key.txt",
            "verified_key.txt"
        }
        for _, path in ipairs(candidateFiles) do
            pcall(function()
                if typeof(writefile) == "function" then
                    writefile(path, tostring(key))
                end
            end)
        end
        return true
    end

    clearSavedKey = function()
        if getgenv then
            getgenv().SCRIPT_KEY = nil
        end
        local candidateFiles = {
            "[DUXXY[/verified_key.txt",
            "[DUXXY[/verified_key",
            "verified_key.txt",
            "verified_key"
        }
        for _, path in ipairs(candidateFiles) do
            pcall(function()
                if typeof(delfile) == "function" and typeof(isfile) == "function" and isfile(path) then
                    delfile(path)
                elseif typeof(writefile) == "function" then
                    writefile(path, "")
                end
            end)
        end
        return true
    end

    local function checkSavedLicense()
        if typeof(JD_IS_PREMIUM) == "boolean" then
            PremiumLoaded = (JD_IS_PREMIUM == true)
            return PremiumLoaded
        end
        local verified_key = loadVerifiedKey()
        if not verified_key and getgenv and type(getgenv().SCRIPT_KEY) == "string" and #getgenv().SCRIPT_KEY >= 4 then
            verified_key = getgenv().SCRIPT_KEY
        end
        if verified_key and verified_key ~= "" and #verified_key >= 4 then
            local Junkie = getJunkieSDK()
            if Junkie and typeof(Junkie.check_key) == "function" then
                local ok, result = pcall(function()
                    return Junkie.check_key(verified_key)
                end)
                if ok and result and result.valid == true then
                    lastVerifiedKeySuccess = verified_key
                    lastVerifiedKeyTime = os.clock()
                    PremiumLoaded = true
                    if getgenv then getgenv().SCRIPT_KEY = verified_key end
                    if Logger and Logger.Success then
                        Logger:Success("Saved license key verified via Junkie! Premium VIP active.")
                    end
                    return true
                else
                    local reason = (result and (result.error or result.message)) or "KEY_INVALID"
                    if Logger and Logger.Warn then
                        Logger:Warn(string.format("Saved license key '%s' is invalid (%s). Purging saved key.", tostring(verified_key), tostring(reason)))
                    end
                    clearSavedKey()
                    if getgenv and getgenv().SCRIPT_KEY == verified_key then
                        getgenv().SCRIPT_KEY = nil
                    end
                    lastVerifiedKeySuccess = nil
                    PremiumLoaded = false
                    return false
                end
            else
                PremiumLoaded = false
                return false
            end
        end
        PremiumLoaded = false
        return false
    end

    checkIsPremium = function()
        if PremiumLoaded == true then return true end
        if typeof(JD_IS_PREMIUM) == "boolean" and JD_IS_PREMIUM == true then return true end
        if Globals and (Globals.IsPremium == true or Globals.JD_IS_PREMIUM == true) then return true end
        if getgenv and (getgenv().IsPremium == true or getgenv().JD_IS_PREMIUM == true) then return true end
        if LocalPlayer and (INBUILT_PREMIUM_WHITELIST[LocalPlayer.UserId] or INBUILT_PREMIUM_WHITELIST[LocalPlayer.Name]) then
            return true
        end
        return false
    end

    -- Export checkIsPremium globally
    if getgenv then getgenv().checkIsPremium = checkIsPremium end
    if _G then _G.checkIsPremium = checkIsPremium end
    if Globals then Globals.checkIsPremium = checkIsPremium end

    -- Dynamic First Boot Check: Auto load premium features if verified
    pcall(function()
        local isPrem = checkSavedLicense() or checkIsPremium()
        if isPrem then
            PremiumLoaded = true
            Globals.IsPremium = true
            task.spawn(function()
                task.wait(0.5)
                if type(TDS) == "table" and type(TDS.Addons) == "function" then
                    pcall(function() TDS:Addons(true) end)
                end
                pcall(function()
                    if Window and Window.UserProfile then
                        Window:UserProfile({
                            Badge = "PREMIUM VIP",
                            TimeLeft = "Permanent",
                        })
                    end
                end)
                if Logger and Logger.Success then
                    Logger:Success("Dynamic Boot: Premium VIP verified! Features loaded automatically.")
                end
            end)
        else
            PremiumLoaded = false
            Globals.IsPremium = false
        end
    end)
end

Window:Line()

do
    -- =============================================================================
    -- OVERVIEW TAB (Live Player Profile, Stats & Dynamic Overview)
    -- =============================================================================
    local OverviewTab = Window:Tab({
        Title = "Overview",
        Icon = "overview",
        Subtitle = "System Status & Overview",
    })

    local StatsGrid = nil
    local userOverviewBox = nil
    local refreshLiveOverview = nil
    local isRefreshingLiveOverview = false

    OverviewTab:Banner({
        Title = "Welcome to DUXXY ADS",
        Desc = "Next-generation tactical automation initialized. Configure your modules in the tabs below.",
        Type = "Info",
    })

    StatsGrid = OverviewTab:MetricGrid({
        Cols = 2,
        Items = {
            { Title = "STATUS", Value = "ONLINE", Sub = "Nominal", Color = Color3.fromRGB(34, 197, 94) },
            { Title = "SESSION TIME", Value = "00:00:00", Sub = "Runtime" },
        }
    })

    -- Live session runtime counter
    task.spawn(function()
        local startTime = os.clock()
        while true do
            task.wait(1)
            local elapsed = math.floor(os.clock() - startTime)
            local hrs = math.floor(elapsed / 3600)
            local mins = math.floor((elapsed % 3600) / 60)
            local secs = elapsed % 60
            local timeFormatted = string.format("%02d:%02d:%02d", hrs, mins, secs)
            pcall(function()
                if StatsGrid and StatsGrid.UpdateItem then
                    StatsGrid:UpdateItem(2, timeFormatted, "Runtime")
                end
            end)
        end
    end)

    -- DataHandler Loader
    local cachedDataHandler = nil
    local function getDataHandler()
        if cachedDataHandler then return cachedDataHandler end
        local candidates = {
            "[DUXXY[/DataHandler.lua",
            "[DUXXY[\\DataHandler.lua",
            "[SomethingNew]/DataHandler.lua",
            "[SomethingNew]\\DataHandler.lua",
            "DataHandler.lua",
            "C:/Users/ADMINI~1/AppData/Local/Real/workspace/[DUXXY[/DataHandler.lua",
            "C:\\Users\\ADMINI~1\\AppData\\Local\\Real\\workspace\\[DUXXY[\\DataHandler.lua",
            "C:/Users/Administrator/AppData/Local/Real/workspace/[DUXXY[/DataHandler.lua",
            "C:\\Users\\Administrator\\AppData\\Local\\Real\\workspace\\[DUXXY[\\DataHandler.lua",
        }
        for _, path in ipairs(candidates) do
            local ok, content = pcall(function()
                if typeof(isfile) == "function" and not isfile(path) then return nil end
                if typeof(readfile) == "function" then return readfile(path) end
                return nil
            end)
            if ok and type(content) == "string" and #content > 0 then
                local fn = loadstring(content, "DataHandler")
                if fn then
                    local s, res = pcall(fn)
                    if s and res then
                        cachedDataHandler = res
                        return res
                    end
                end
            end
        end
        local ok, res = pcall(function()
            return loadstring(game:HttpGet("https://raw.githubusercontent.com/Texrtes/-AutoProg--Updated/main/DataHandler.lua"))()
        end)
        if ok and res then
            cachedDataHandler = res
            return res
        end
        return nil
    end

    local function formatCommas(amount)
        local formatted = tostring(math.floor(tonumber(amount) or 0))
        local k
        while true do
            formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
            if k == 0 then break end
        end
        return formatted
    end

    local SKILLTREE_FILE = "[DUXXY[/userskilltree.json"
    local function getLiveSkillTree()
        local DH = getDataHandler()
        local tree = nil
        if DH and typeof(DH.GetSkillTree) == "function" then
            local ok, res = pcall(function() return DH:GetSkillTree() end)
            if ok and res and type(res) == "table" and #res > 0 then
                tree = res
            end
        end
        if tree and #tree > 0 then
            pcall(function()
                if typeof(writefile) == "function" and HttpService then
                    writefile(SKILLTREE_FILE, HttpService:JSONEncode(tree))
                    writefile("userskilltree.json", HttpService:JSONEncode(tree))
                end
            end)
            return tree
        end
        for _, path in ipairs({ SKILLTREE_FILE, "userskilltree.json" }) do
            if typeof(isfile) == "function" and isfile(path) and typeof(readfile) == "function" then
                local ok, raw = pcall(readfile, path)
                if ok and raw and raw ~= "" then
                    local decOk, decoded = pcall(function() return HttpService:JSONDecode(raw) end)
                    if decOk and type(decoded) == "table" and #decoded > 0 then
                        return decoded
                    end
                end
            end
        end
        return {}
    end

    local function getSkillTreeSummaryText()
        local tree = getLiveSkillTree()
        if not tree or #tree == 0 then
            return "Skill Tree: Not Available"
        end
        local maxedCount = 0
        local totalCount = #tree
        for _, skill in ipairs(tree) do
            if skill.IsMaxed then
                maxedCount = maxedCount + 1
            end
        end
        if maxedCount == totalCount then
            return string.format("Skill Tree: %d/%d Maxed (Complete ✓)", maxedCount, totalCount)
        else
            return string.format("Skill Tree: %d/%d Maxed (%d Skills)", maxedCount, totalCount, totalCount)
        end
    end

    local function getUserDataChecklist()
        local lvl = 0
        local coins = 0
        local gems = 0
        local timescaleTickets = 0
        local expDisplay = "0 / 0"
        local goldenCount = 0

        local DH = getDataHandler()
        if DH and typeof(DH.GetPlayerStats) == "function" then
            local ok, stats = pcall(function() return DH:GetPlayerStats() end)
            if ok and stats then
                lvl = stats.Level or 0
                coins = stats.Coins or 0
                gems = stats.Gems or 0
                timescaleTickets = stats.TimescaleTickets or 0
                expDisplay = stats.ExpDisplay or "0 / 0"
            end
            if (not timescaleTickets or timescaleTickets == 0) and typeof(DH.GetTimescaleTickets) == "function" then
                pcall(function() timescaleTickets = DH:GetTimescaleTickets() or 0 end)
            end
            local gOk, gList = pcall(function() return DH:GetGoldenOwned() end)
            if gOk and gList then goldenCount = #gList end
        else
            if LocalPlayer then
                local c = LocalPlayer:FindFirstChild("Coins") or LocalPlayer:FindFirstChild("Gold")
                if c then coins = c.Value or 0 end
                local g = LocalPlayer:FindFirstChild("Gems") or LocalPlayer:FindFirstChild("Diamonds")
                if g then gems = g.Value or 0 end
                local l = LocalPlayer:FindFirstChild("Level")
                if l then lvl = l.Value or 0 end
                local e = LocalPlayer:FindFirstChild("Experience")
                if e then expDisplay = tostring(e.Value or 0) end
            end
        end

        local items = {
            string.format("Level: %d", lvl),
            string.format("Coins: %s", formatCommas(coins)),
            string.format("Gems: %s", formatCommas(gems)),
            string.format("Timescales: %s", formatCommas(timescaleTickets)),
            string.format("EXP: %s", expDisplay),
            string.format("Golden Towers: %d Owned", goldenCount),
            getSkillTreeSummaryText(),
        }

        local tree = getLiveSkillTree()
        if tree and #tree > 0 then
            for _, s in ipairs(tree) do
                local statText = string.format("Skill: %s (Lvl %s)", s.Name, s.LevelFormatted or tostring(s.Level))
                table.insert(items, statText)
            end
        end

        return items
    end

    local function getAllTowersList()
        local towers = {}
        pcall(function()
            local Content = require(game:GetService("ReplicatedStorage").Shared.Modules.Content)
            local ok, towerFolder = pcall(Content, "Tower")
            if ok and towerFolder then
                for _, t in ipairs(towerFolder:GetChildren()) do
                    table.insert(towers, t.Name)
                end
            end
        end)
        if #towers > 0 then
            table.sort(towers)
            return towers
        end
        return {
            "Accelerator", "Ace Pilot", "Archer", "Assassin", "Biologist", "Boomerang",
            "Brawler", "Commander", "Commando", "Cowboy", "Crook Boss", "Cryomancer",
            "DJ Booth", "Demoman", "Electroshocker", "Elementalist", "Elf Camp", "Engineer",
            "Executioner", "Farm", "Firework Technician", "Freezer", "Frost Blaster",
            "Gatling Gun", "Gladiator", "Hacker", "Hallow Punk", "Harvester", "Hunter",
            "Jester", "Mecha Base", "Medic", "Mercenary Base", "Militant", "Military Base",
            "Minigunner", "Mortar", "Necromancer", "Paintballer", "Pulse Trooper", "Pursuit",
            "Pyromancer", "Ranger", "Rocketeer", "Saboteur", "Scout", "Shotgunner",
            "Slasher", "Sledger", "Slime Trooper", "Sniper", "Snowballer", "Soldier",
            "Spotlight Tech", "Swarmer", "Tesla", "Toxic Gunner", "Trapper", "Turret",
            "Warden", "War Machine", "Warlock"
        }
    end

    local cachedOwnedTowersList = nil
    local function getOwnedTowersChecklist(forceRefresh)
        if cachedOwnedTowersList and not forceRefresh then
            return cachedOwnedTowersList
        end
        local DH = getDataHandler()
        local allTowers = getAllTowersList()
        local list = {}
        for _, name in ipairs(allTowers) do
            local owned = false
            if DH and typeof(DH.IsTowerOwned) == "function" then
                local ok, res = pcall(function() return DH:IsTowerOwned(name) end)
                owned = ok and (res == true)
            end
            if owned then
                table.insert(list, name .. ": Owned (✓)")
            else
                table.insert(list, name .. ": Not Owned [X]")
            end
        end
        cachedOwnedTowersList = list
        return list
    end

    local cachedOwnedTrialsList = nil
    local cachedWonTrialsList = nil
    local cachedNotWonTrialsList = nil

    local function getOwnedTrialsData(forceRefresh)
        if cachedOwnedTrialsList and not forceRefresh then
            return cachedOwnedTrialsList, cachedWonTrialsList, cachedNotWonTrialsList
        end
        local allList = {}
        local wonList = {}
        local notWonList = {}

        local DH = getDataHandler()
        local trials = nil
        if DH and typeof(DH.GetAllTrialsList) == "function" then
            pcall(function() trials = DH:GetAllTrialsList() end)
        end

        if not trials or #trials == 0 then
            if DH and DH.StaticTrialDefinitions then
                trials = {}
                for _, t in ipairs(DH.StaticTrialDefinitions) do
                    local won = false
                    pcall(function() won = DH:IsTrialWon(t.Name) end)
                    table.insert(trials, {
                        Name = t.Name,
                        Title = t.Title or t.Name,
                        Map = t.Map or "Unknown",
                        IsWon = won,
                        Status = won and "YES" or "NO",
                    })
                end
            end
        end

        pcall(function()
            local ownedMods = nil
            local cModule = game:GetService("ReplicatedStorage"):FindFirstChild("Client")
            cModule = cModule and cModule:FindFirstChild("Modules")
            cModule = cModule and cModule:FindFirstChild("Cache")
            if cModule then
                local Cache = require(cModule)
                local atom = Cache("Inventory.Modifiers")
                if atom and type(atom.GetValue) == "function" then
                    ownedMods = atom:GetValue()
                end
            end
            if type(ownedMods) == "table" and trials then
                local modLookup = {}
                for _, m in ipairs(ownedMods) do
                    modLookup[tostring(m)] = true
                    local clean = string.lower(tostring(m)):gsub("%s+", "")
                    modLookup[clean] = true
                end
                for _, t in ipairs(trials) do
                    local tName = tostring(t.Name or "")
                    local tTitle = tostring(t.Title or "")
                    local cleanName = string.lower(tName):gsub("%s+", "")
                    local cleanTitle = string.lower(tTitle):gsub("%s+", "")
                    if modLookup[tName] or modLookup[cleanName] or modLookup[tTitle] or modLookup[cleanTitle] then
                        t.IsWon = true
                        t.Status = "YES"
                    end
                end
            end
        end)

        local wonCount = 0
        local totalCount = trials and #trials or 0
        if trials then
            for _, t in ipairs(trials) do
                if t.IsWon then wonCount = wonCount + 1 end
            end
        end

        local summaryText = string.format("Completed Trials: %d / %d (%d%%)", wonCount, totalCount, totalCount > 0 and math.floor((wonCount / totalCount) * 100) or 0)
        table.insert(allList, summaryText)
        table.insert(wonList, string.format("Won Modifiers: %d / %d Completed", wonCount, totalCount))
        table.insert(notWonList, string.format("Remaining Trials: %d Pending", totalCount - wonCount))

        if trials and #trials > 0 then
            for _, t in ipairs(trials) do
                local displayName = t.Title or t.Name
                if t.IsWon then
                    local line = string.format("%s: Won (✓) [Map: %s]", displayName, t.Map or "N/A")
                    table.insert(allList, line)
                    table.insert(wonList, line)
                else
                    local line = string.format("%s: Not Won [X] [Map: %s]", displayName, t.Map or "N/A")
                    table.insert(allList, line)
                    table.insert(notWonList, line)
                end
            end
        else
            table.insert(allList, "No trials data available.")
            table.insert(wonList, "None completed.")
            table.insert(notWonList, "None pending.")
        end

        cachedOwnedTrialsList = allList
        cachedWonTrialsList = wonList
        cachedNotWonTrialsList = notWonList

        return allList, wonList, notWonList
    end

    local function getOwnedTrialsChecklist(forceRefresh)
        local all = getOwnedTrialsData(forceRefresh)
        return all
    end

    local UserOverviewSection = OverviewTab:Section({ Title = "Live Player Profile, Towers & Trials" })

    userOverviewBox = UserOverviewSection:SelectionBox({
        Selections = { "User Data", "User Owned Towers", "User Owned Trials" },
        Value = "User Data",
        Descriptions = {
            ["User Data"] = "Live Player Progression, Timescales & Wallet Stats",
            ["User Owned Towers"] = "TDS Tower Inventory Ownership & Verification",
            ["User Owned Trials"] = "TDS Completed Trials & Won Modifiers Progress",
        },
        Checklist = {
            ["User Data"] = getUserDataChecklist(),
            ["User Owned Towers"] = getOwnedTowersChecklist(),
            ["User Owned Trials"] = getOwnedTrialsChecklist(),
        },
        ButtonTexts = {
            ["User Data"] = "Refresh Live Player Stats",
            ["User Owned Towers"] = "Scan Owned Towers Inventory",
            ["User Owned Trials"] = "Scan Completed Trials",
        },
        Callbacks = {
            ["User Data"] = function()
                if refreshLiveOverview then refreshLiveOverview() end
                Window:Notify({
                    Title = "Player Stats Refreshed",
                    Desc = "Fetched latest coins, gems, timescales, level & EXP from DataHandler.",
                    Duration = 2,
                })
            end,
            ["User Owned Towers"] = function()
                cachedOwnedTowersList = nil
                if refreshLiveOverview then refreshLiveOverview() end
                Window:Notify({
                    Title = "Towers Inventory Scanned",
                    Desc = "Verified current owned vs missing towers from DataHandler.",
                    Duration = 2,
                })
            end,
            ["User Owned Trials"] = function()
                cachedOwnedTrialsList = nil
                cachedWonTrialsList = nil
                cachedNotWonTrialsList = nil
                if refreshLiveOverview then refreshLiveOverview() end
                Window:Notify({
                    Title = "Trials Progress Scanned",
                    Desc = "Fetched latest won modifiers and completed trials progress.",
                    Duration = 2,
                })
            end,
        },
    })

    refreshLiveOverview = function()
        if isRefreshingLiveOverview then return end
        isRefreshingLiveOverview = true
        task.defer(function()
            task.wait(0.05)
            isRefreshingLiveOverview = false
            if userOverviewBox and userOverviewBox.SetChecklist then
                pcall(function()
                    userOverviewBox:SetChecklist({
                        ["User Data"] = getUserDataChecklist(),
                        ["User Owned Towers"] = getOwnedTowersChecklist(),
                        ["User Owned Trials"] = getOwnedTrialsChecklist(),
                    })
                end)
            end
        end)
    end

    -- Real-time reactive listeners for dynamic stats
    local function setupLiveStatListeners()
        pcall(function()
            local cModule = game:GetService("ReplicatedStorage"):FindFirstChild("Client")
            cModule = cModule and cModule:FindFirstChild("Modules")
            cModule = cModule and cModule:FindFirstChild("Cache")
            if cModule then
                local Cache = require(cModule)
                local atomsToTrack = {
                    "Values.Coins", "Values.Gems", "Values.Experience", "Values.Level",
                    "Values.TimescaleTickets", "Values.SpinTickets", "Inventory.Troops",
                    "Inventory.Skins", "Inventory.Modifiers", "Equipped.Troops"
                }
                for _, atomName in ipairs(atomsToTrack) do
                    local atom = Cache(atomName)
                    if atom and atom.Updated and type(atom.Updated.Connect) == "function" then
                        atom.Updated:Connect(function()
                            if atomName == "Inventory.Troops" or atomName == "Inventory.Skins" then
                                cachedOwnedTowersList = nil
                            elseif atomName == "Inventory.Modifiers" or atomName == "Values.TimescaleTickets" then
                                cachedOwnedTrialsList = nil
                            end
                            refreshLiveOverview()
                        end)
                    end
                end
            end
        end)

        pcall(function()
            local Charm = require(game:GetService("ReplicatedStorage").Packages.Charm)
            local client = game:GetService("ReplicatedStorage"):FindFirstChild("Client")
            local ifaces = client and client:FindFirstChild("Interfaces")
            local stores = ifaces and ifaces:FindFirstChild("Stores")
            local shared = stores and stores:FindFirstChild("Shared")
            local pss = shared and shared:FindFirstChild("PlayerStatsStore")
            if pss then
                local pStore = require(pss)
                if Charm and type(Charm.subscribe) == "function" and pStore and type(pStore.getState) == "function" then
                    Charm.subscribe(pStore.getState, function()
                        refreshLiveOverview()
                    end)
                end
            end
        end)

        if LocalPlayer then
            for _, valName in ipairs({ "Experience", "Level", "Coins", "Gems", "Gold", "Diamonds" }) do
                local vObj = LocalPlayer:FindFirstChild(valName)
                if vObj and vObj:IsA("ValueBase") then
                    vObj.Changed:Connect(function()
                        refreshLiveOverview()
                    end)
                end
            end
        end

        pcall(function()
            local ws = game:GetService("Workspace")
            for i = 1, 17 do
                local tile = ws:FindFirstChild(tostring(i))
                if tile then
                    local sGui = tile:FindFirstChild("TileSurfaceGui")
                    local frame = sGui and sGui:FindFirstChild("Frame")
                    local lvlLabel = frame and frame:FindFirstChild("SkillLevel")
                    if lvlLabel and lvlLabel:IsA("TextLabel") then
                        lvlLabel:GetPropertyChangedSignal("Text"):Connect(function()
                            refreshLiveOverview()
                        end)
                    end
                end
            end
        end)
    end

    setupLiveStatListeners()
end

Window:Line()

local Automation = Window:Tab({Title = "Automation", Icon = "bot"}) do
    
    Automation:Section({Title = "Match Progression"})
    
    Automation:Toggle({
        Title = "Auto Rejoin",
        Desc = "Turn this ON if you are running a WIN strat",
        Value = Globals.AutoRejoin,
        Callback = function(v)
            SetSetting("AutoRejoin", v)
            if isfile("ADS_LastStrat.lua") then
                pcall(delfile, "ADS_LastStrat.lua")
            end
            if v and GameState == "GAME" then
                if #executed_actions > 0 then
                    local content = "local TDS = shared.TDSTable or loadstring(game:HttpGet(\"https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua\"))()\n\n"
                    content = content .. table.concat(executed_actions, "\n")
                    writefile("ADS_LastStrat.lua", content)
                end
                if not BackToLobbyRunning then
                    StartBackToLobby()
                end
            end
        end
    })
	
	Automation:Toggle({
        Title = "Auto Rematch",
        Desc = "Fires RE:Rematch after the match ends instead of returning to lobby",
        Value = Globals.AutoRematch,
        Callback = function(v)
            SetSetting("AutoRematch", v)
            if v and GameState == "GAME" then
                if #executed_actions > 0 then
                    local content = "local TDS = shared.TDSTable or loadstring(game:HttpGet(\"https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua\"))()\n\n"
                    content = content .. table.concat(executed_actions, "\n")
                    writefile("ADS_LastStrat.lua", content)
                end
                if not BackToLobbyRunning then
                    StartBackToLobby()
                end
                InitAutoAutomation()
            end
        end
    })

    Automation:Toggle({
        Title = "Auto Restart",
        Desc = "Turn this ON if you are running a LOSE strat",
        Value = Globals.AutoRestart,
        Callback = function(v)
            SetSetting("AutoRestart", v)
            if isfile("ADS_LastStrat.lua") then
                pcall(delfile, "ADS_LastStrat.lua")
            end
            if v and GameState == "GAME" then
                if #executed_actions > 0 then
                    local content = "local TDS = shared.TDSTable or loadstring(game:HttpGet(\"https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua\"))()\n\n"
                    content = content .. table.concat(executed_actions, "\n")
                    writefile("ADS_LastStrat.lua", content)
                end
                if not BackToLobbyRunning then
                    StartBackToLobby()
                end
            end
        end
    })

    local PrivateCodeBox = Automation:Textbox({
        Title = "Private Server Code",
        Desc = "Paste your Private Server Link or Code here to always join your private server",
        Placeholder = "Link or Code (e.g. share link or privateServerLinkCode)",
        Value = Globals.PrivateCode or "",
        ClearTextOnFocus = false,
        UpdateOnType = true,
        Callback = function(text)
            local clean = earlyExtractPrivateServerCode(text)
            if clean == "" and text and text:match("%S") then
                clean = text:gsub('^["\'%s]*(.-)["\'%s]*$', "%1")
            end
            Globals.PrivateCode = clean
            if typeof(getgenv) == "function" then
                getgenv().PrivateCode = clean
            end
            _G.PrivateCode = clean
            SetSetting("PrivateCode", text)
        end
    })
	
	local RejoinBTN = Automation:Button({
        Title = "Rejoin Game",
        Desc = "Stuck? Rejoin the current lobby / private server",
        Callback = function()
            task.spawn(function()
                if PrivateCodeBox and typeof(PrivateCodeBox.GetValue) == "function" then
                    local liveVal = PrivateCodeBox:GetValue()
                    if liveVal and liveVal ~= "" then
                        local clean = earlyExtractPrivateServerCode(liveVal)
                        if clean == "" and liveVal:match("%S") then
                            clean = liveVal:gsub('^["\'%s]*(.-)["\'%s]*$', "%1")
                        end
                        if clean ~= "" then
                            Globals.PrivateCode = clean
                            if typeof(getgenv) == "function" then getgenv().PrivateCode = clean end
                            _G.PrivateCode = clean
                        end
                    end
                end

                Window:Notify({Title = "Teleporting", Desc = "Rejoining match or private lobby...", Time = 3})
                SmartTeleportToLobby()
            end)
        end
    })

    Automation:Toggle({
    Title = "Auto Ready Up",
    Desc = "Automatically readies up when starting a match",
    Value = Globals.AutoReady,
    Callback = function(v)
        Globals.AutoReady = v
        SetSetting("AutoReady", v)
        if v then StartAutoReady() end
    end
    }) 

    Automation:Toggle({
        Title = "Auto Skip Waves",
        Desc = "Skips all Waves",
        Value = Globals.AutoSkip,
        Callback = function(v)
            SetSetting("AutoSkip", v)
        end
    })

    Automation:Dropdown({
        Title = "Modifiers:",
        Desc = "Selected modifiers must already be unlocked via trials!",
        List = AllModifiers,
        Value = Globals.Modifiers,
        Multi = true,
        Callback = function(choice)
            SetSetting("Modifiers", choice)
        end
    })

    Automation:Section({Title = "Auto-Abilities"})
    
    Automation:Toggle({
        Title = "Auto Chain",
        Desc = "Chains Commander Ability",
        Value = Globals.AutoChain,
        Callback = function(v)
            SetSetting("AutoChain", v)
        end
    })

     Automation:Toggle({
        Title = "Auto Medic",
        Desc = "Chains Medic Ability",
        Value = Globals.AutoMedic,
        Callback = function(v)
            SetSetting("AutoMedic", v)
        end
    })

    Automation:Toggle({
        Title = "Support Caravan",
        Desc = "Uses Commander Support Caravan",
        Value = Globals.SupportCaravan,
        Callback = function(v)
            SetSetting("SupportCaravan", v)
        end
    })

    Automation:Toggle({
        Title = "Auto DJ Booth",
        Desc = "Uses DJ Booth Ability",
        Value = Globals.AutoDJ,
        Callback = function(v)
            SetSetting("AutoDJ", v)
        end
    })

    Automation:Textbox({
        Title = "DJ Custom Music",
        Desc = "Custom audio ID for your DJ Booth (Requires Gamepass)",
        Placeholder = "Audio ID",
        Value = Globals.DJCustomSongID or "",
        ClearTextOnFocus = false,
        Callback = function(value)
            SetSetting("DJCustomSongID", value or "")
            if not tonumber(value) then return end
            task.spawn(function()
                local TowersFolder = workspace:FindFirstChild("Towers")
                if not TowersFolder then return end
                for _, tower in ipairs(TowersFolder:GetChildren()) do
                    AutoSetDJSong(tower)
                end
            end)
        end
    })

    Automation:Toggle({
        Title = "Auto Necro",
        Desc = "Uses Necromancer Ability",
        Value = Globals.AutoNecro,
        Callback = function(v)
            SetSetting("AutoNecro", v)
        end
    })

    Automation:Section({Title = "Unit Spawners"})
    
    Automation:Toggle({
        Title = "Enable Path Distance Marker",
        Desc = "Red = Mercenary Base, Green = Military Baset",
        Value = Globals.PathVisuals,
        Callback = function(v)
            SetSetting("PathVisuals", v)
        end
    })

    Automation:Toggle({
        Title = "Auto Mercenary Base",
        Desc = "Uses Air-Drop Ability",
        Value = Globals.AutoMercenary,
        Callback = function(v)
            SetSetting("AutoMercenary", v)
        end
    })

    MercenarySlider = Automation:Slider({
        Title = "Path Distance",
        Min = 0,
        Max = 300,
        Rounding = 0,
        Value = Globals.MercenaryPath,
        Callback = function(val)
            SetSetting("MercenaryPath", val)
        end
    })

    Automation:Toggle({
        Title = "Auto Military Base",
        Desc = "Uses Airstrike Ability",
        Value = Globals.AutoMilitary,
        Callback = function(v)
            SetSetting("AutoMilitary", v)
        end
    })

    MilitarySlider = Automation:Slider({
        Title = "Path Distance",
        Min = 0,
        Max = 300,
        Rounding = 0,
        Value = Globals.MilitaryPath,
        Callback = function(val)
            SetSetting("MilitaryPath", val)
        end
    })

    task.spawn(function()
        while true do
            local success = CalcLength()
            if success then break end 
            task.wait(3)
        end
    end)

    Automation:Section({Title = "Inventory Management"})

    Automation:Toggle({
    Title = "Auto Open Crates",
    Desc = "Periodically attempts to open selected crates.",
    Value = Globals.AutoOpenCrates or false,
    Callback = function(v)
        Globals.AutoOpenCrates = v
        SetSetting("AutoOpenCrates", v)
        if v then StartAutoOpenCrates() end
    end
    })

    Automation:Dropdown({
    Title = "Target Crate:",
    List = CrateList,
    Value = Globals.SelectedCrate or "All",
    Callback = function(choice)
        Globals.SelectedCrate = choice
        SetSetting("SelectedCrate", choice)
    end
    })

    Automation:Section({Title = "Economy & Farming"})
    
    Automation:Toggle({
        Title = "Sell Farms",
        Desc = "Sells all your farms on the specified wave",
        Value = Globals.SellFarms,
        Callback = function(v)
            SetSetting("SellFarms", v)
        end
    })

    Automation:Textbox({
        Title = "Wave:",
        Desc = "Wave to sell farms",
        Placeholder = "40",
        Value = tostring(Globals.SellFarmsWave),
        ClearTextOnFocus = false,
        Callback = function(text)
            local number = tonumber(text)
            if number then
                SetSetting("SellFarmsWave", number)
            else
                Window:Notify({
                    Title = "ADS",
                    Desc = "Invalid number entered!",
                    Time = 3,
                    Type = "error"
                })
            end
        end
    })

    Automation:Section({Title = "Utilities"})
    
    Automation:Toggle({
        Title = "Auto Gatling",
        Desc = "Loads external Auto Gatling (credits to DeadSignalFound on GitHub)",
        Value = Globals.AutoGatling,
        Callback = function(v)
            SetSetting("AutoGatling", v)
        end
    })

    Automation:Toggle({
        Title = "Gatlify",
        Desc = "External Gatling script with better stability and features than Railgun that uses its own key system, so Core hub premium keys will not work and must be bought separately!",
        Value = Globals.Gatlify,
        Callback = function(v)
            SetSetting("Gatlify", v)
        end
    })

    Automation:Toggle({
        Title = "Auto Collect Pickups",
        Desc = "Collects Event Currencies, Lorebooks, Charms & Map Drops",
        Value = Globals.AutoPickups,
        Callback = function(v)
            Globals.AutoPickups = v
            if getgenv then getgenv().AutoPickups = v end
            SetSetting("AutoPickups", v)
            if v and type(StartAutoPickups) == "function" then
                StartAutoPickups()
            end
        end
    })

    Automation:Dropdown({
        Title = "Pickup Method",
        Desc = "Movement technique for collecting item drops (Pathfinding or Instant)",
        List = {"Pathfinding", "Instant"},
        Value = Globals.PickupMethod or "Pathfinding",
        Callback = function(choice)
            local selected = type(choice) == "table" and choice[1] or choice
            if not selected or selected == "" then
                selected = "Pathfinding"
            end
            Globals.PickupMethod = selected
            if getgenv then getgenv().PickupMethod = selected end
            SetSetting("PickupMethod", selected)
            if Logger and Logger.Info then
                Logger:Info("Pickup Method: " .. tostring(selected))
            end
        end
    })

    Automation:Toggle({
        Title = "Claim Rewards",
        Desc = "Claims your playtime and uses spin tickets in Lobby",
        Value = Globals.ClaimRewards,
        Callback = function(v)
            SetSetting("ClaimRewards", v)
        end
    })
end

Window:Line()

do
    -- =============================================================================
    -- AUTO CURRENCY TAB (Farming & Resource Automation Layout)
    -- =============================================================================
    local CurrencyTab = Window:Tab({
        Title = "Auto Currency",
        Icon = "coins",
        Subtitle = "Farming & Resource Automation",
    })

    local AutoCurrencyState = {
        SelectedTab = "Auto Coins",
        Coins = { Enabled = false, Condition = "Lose", Target = "0" },
        Gems = { Enabled = false, Condition = "Lose", Target = "0" },
        Levels = { Enabled = false, Condition = "Lose", Currency = "Coins", Target = "0" },
        Timescales = { Enabled = false, Fallback = "Molten", Target = "0", IgnoredTrials = { "Glass", "Committed", "Limitation" } },
        Evo = { Enabled = false, Target = "All", Strategy = "Lose" }
    }
    Globals.AutoCurrency = AutoCurrencyState

    -- Section references for mode switching
    local CoinsSection = nil
    local GemsSection = nil
    local LevelsSection = nil
    local TimescalesSection = nil
    local EvoSection = nil
    local EvoTrackerSection = nil

    local function showCurrencySection(mode)
        AutoCurrencyState.SelectedTab = mode
        if SetSetting then SetSetting("SelectedCurrencyTab", mode) end
        if CoinsSection then CoinsSection:SetVisible(mode == "Auto Coins") end
        if GemsSection then GemsSection:SetVisible(mode == "Auto Gems") end
        if LevelsSection then LevelsSection:SetVisible(mode == "Auto Levels") end
        if TimescalesSection then TimescalesSection:SetVisible(mode == "Auto Timescales") end
        if EvoSection then EvoSection:SetVisible(mode == "Auto Evo") end
        if EvoTrackerSection then EvoTrackerSection:SetVisible(mode == "Auto Evo") end
    end

    -- Segmented mode selector
    local CurrencyModesSegmented = CurrencyTab:Segmented({
        Options = { "Auto Coins", "Auto Gems", "Auto Levels", "Auto Timescales", "Auto Evo" },
        Value = AutoCurrencyState.SelectedTab or "Auto Coins",
        Callback = function(choice)
            showCurrencySection(choice)
        end,
    })

    -- 1. Auto Coins Section
    CoinsSection = CurrencyTab:Section({ Title = "Auto Coins Configuration" })

    CoinsSection:Banner({
        Title = "Auto Coins Farming",
        Desc = "Automated match queuing, wave progression, and target-based coin accumulation.",
        Type = "Info",
    })

    CoinsSection:Toggle({
        Title = "Turn on Auto Coins",
        Desc = "Toggle automated coin farming routines",
        Value = AutoCurrencyState.Coins.Enabled,
        Callback = function(val)
            AutoCurrencyState.Coins.Enabled = val
            if Logger and Logger.Info then Logger:Info("Auto Coins: " .. (val and "ACTIVE" or "OFF")) end
        end,
    })

    CoinsSection:Dropdown({
        Title = "Conditions",
        Desc = "Trigger match leave/retry on victory or defeat",
        List = { "Lose", "Win" },
        Value = AutoCurrencyState.Coins.Condition or "Lose",
        Callback = function(choice)
            AutoCurrencyState.Coins.Condition = choice
        end,
    })

    CoinsSection:Textbox({
        Title = "Target Coins",
        Desc = "Amount of coins to farm (0 = infinite)",
        Placeholder = "0 = infinite",
        Value = AutoCurrencyState.Coins.Target,
        ClearTextOnFocus = false,
        Callback = function(txt)
            AutoCurrencyState.Coins.Target = txt
        end,
    })

    CoinsSection:Label({
        Title = "Coins Status",
        Desc = "Coins Status: Standing by",
    })

    CoinsSection:Label({
        Title = "Coins: Towers Needed",
        Desc = "Checking requirements...",
    })

    -- 2. Auto Gems Section
    GemsSection = CurrencyTab:Section({ Title = "Auto Gems Configuration" })

    GemsSection:Banner({
        Title = "Auto Gems Farming (Hardcore)",
        Desc = "Automated Hardcore lobby matchmaking, strategic wave advancement, and gem threshold monitoring.",
        Type = "Info",
    })

    GemsSection:Toggle({
        Title = "Turn on Auto Gems",
        Desc = "Toggle automated gem farming routines",
        Value = AutoCurrencyState.Gems.Enabled,
        Callback = function(val)
            AutoCurrencyState.Gems.Enabled = val
            if Logger and Logger.Info then Logger:Info("Auto Gems: " .. (val and "ACTIVE" or "OFF")) end
        end,
    })

    GemsSection:Dropdown({
        Title = "Conditions",
        Desc = "Trigger match leave/retry on victory or defeat",
        List = { "Lose", "Win" },
        Value = AutoCurrencyState.Gems.Condition or "Lose",
        Callback = function(choice)
            AutoCurrencyState.Gems.Condition = choice
        end,
    })

    GemsSection:Textbox({
        Title = "Target Gems",
        Desc = "Amount of gems to farm (0 = infinite)",
        Placeholder = "0 = infinite",
        Value = AutoCurrencyState.Gems.Target,
        ClearTextOnFocus = false,
        Callback = function(txt)
            AutoCurrencyState.Gems.Target = txt
        end,
    })

    GemsSection:Label({
        Title = "Gems Status",
        Desc = "Gems Status: Standing by",
    })

    GemsSection:Label({
        Title = "Gems: Towers Needed",
        Desc = "Checking requirements...",
    })

    -- 3. Auto Levels Section
    LevelsSection = CurrencyTab:Section({ Title = "Auto Levels Configuration" })

    LevelsSection:Banner({
        Title = "Auto Levels Progression",
        Desc = "Rapid EXP match cycling to hit specific account level milestones automatically.",
        Type = "Info",
    })

    LevelsSection:Toggle({
        Title = "Turn on Auto Levels",
        Desc = "Toggle automated EXP leveling routines",
        Value = AutoCurrencyState.Levels.Enabled,
        Callback = function(val)
            AutoCurrencyState.Levels.Enabled = val
            if Logger and Logger.Info then Logger:Info("Auto Levels: " .. (val and "ACTIVE" or "OFF")) end
        end,
    })

    LevelsSection:Dropdown({
        Title = "Conditions",
        Desc = "Trigger match leave/retry on victory or defeat",
        List = { "Lose", "Win" },
        Value = AutoCurrencyState.Levels.Condition or "Lose",
        Callback = function(choice)
            AutoCurrencyState.Levels.Condition = choice
        end,
    })

    LevelsSection:Dropdown({
        Title = "Selected Currency",
        Desc = "Choose currency farming route for Auto Levels",
        List = { "Coins", "Gems" },
        Value = AutoCurrencyState.Levels.Currency or "Coins",
        Callback = function(choice)
            AutoCurrencyState.Levels.Currency = choice
        end,
    })

    LevelsSection:Textbox({
        Title = "Target Level",
        Desc = "Target player level to reach (0 = infinite)",
        Placeholder = "0 = infinite",
        Value = AutoCurrencyState.Levels.Target,
        ClearTextOnFocus = false,
        Callback = function(txt)
            AutoCurrencyState.Levels.Target = txt
        end,
    })

    LevelsSection:Label({
        Title = "Level status",
        Desc = "Levels Status: Standing by",
    })

    LevelsSection:Label({
        Title = "Levels: Towers Needed",
        Desc = "Checking requirements...",
    })

    -- 4. Auto Timescales Section
    TimescalesSection = CurrencyTab:Section({ Title = "Auto Timescales Configuration" })

    TimescalesSection:Banner({
        Title = "Auto Timescales Farming",
        Desc = "Special mode farming for timescale tickets and accelerated reward boosts.",
        Type = "Info",
    })

    TimescalesSection:Toggle({
        Title = "Turn on Auto Timescales",
        Desc = "Toggle automated Trials timescale ticket farming routines",
        Value = AutoCurrencyState.Timescales.Enabled,
        Callback = function(val)
            AutoCurrencyState.Timescales.Enabled = val
            if Logger and Logger.Info then Logger:Info("Auto Timescales: " .. (val and "ACTIVE" or "OFF")) end
        end,
    })

    TimescalesSection:Label({
        Title = "Current Trial",
        Desc = "Current Trial: None",
    })

    TimescalesSection:Label({
        Title = "Next Trial",
        Desc = "Next Trial: Checking rotation...",
    })

    TimescalesSection:Label({
        Title = "Trial Eligibility",
        Desc = "Trial Eligibility: Pending verification",
    })

    local allTrialList = {
        "Glass", "Committed", "Limitation", "Speedy Enemies", "Quarantine",
        "Fog", "Flying Enemies", "Jailed", "Exploding Enemies", "Inflation",
        "Hidden Enemies", "Broke", "Healthy Enemies"
    }

    TimescalesSection:Dropdown({
        Title = "Trials to Ignore",
        Desc = "Ignore active trials matching these types and wait for next rotation (Premium)",
        List = allTrialList,
        Multi = true,
        Value = AutoCurrencyState.Timescales.IgnoredTrials,
        Callback = function(selectedList)
            if not checkIsPremium() then
                Window:Notify({
                    Title = "Premium Plan Required",
                    Desc = "Please activate Premium plan",
                    Duration = 3,
                })
                return
            end
            AutoCurrencyState.Timescales.IgnoredTrials = selectedList
        end,
    })

    TimescalesSection:Dropdown({
        Title = "Fallbacks",
        Desc = "Backup mode to run if ineligible for the active trial (Premium)",
        List = { "Molten", "Fallen" },
        Value = AutoCurrencyState.Timescales.Fallback or "Molten",
        Callback = function(choice)
            if not checkIsPremium() then
                Window:Notify({
                    Title = "Premium Plan Required",
                    Desc = "Please activate Premium plan",
                    Duration = 3,
                })
                return
            end
            AutoCurrencyState.Timescales.Fallback = choice
        end,
    })

    TimescalesSection:Textbox({
        Title = "Target Timescales",
        Desc = "Target timescale tickets to reach (0 = infinite)",
        Placeholder = "0 = infinite",
        Value = AutoCurrencyState.Timescales.Target or "0",
        ClearTextOnFocus = false,
        Callback = function(txt)
            if not checkIsPremium() then
                Window:Notify({
                    Title = "Premium Plan Required",
                    Desc = "Please activate Premium plan",
                    Duration = 3,
                })
                return
            end
            AutoCurrencyState.Timescales.Target = txt
        end,
    })

    TimescalesSection:Label({
        Title = "Timescales Status",
        Desc = "Timescales Status: Standing by",
    })

    -- 5. Auto Evo Section
    EvoSection = CurrencyTab:Section({ Title = "Auto Evolution Configuration" })

    EvoSection:Banner({
        Title = "Auto Evolution Farming",
        Desc = "Automated evolution progression: farms Coins, Gems, and EXP, then evolves towers.",
        Type = "Info",
    })

    EvoSection:Toggle({
        Title = "Auto Evo",
        Desc = "Toggle automated evolution progression routines (Premium)",
        Value = AutoCurrencyState.Evo.Enabled,
        Callback = function(val)
            AutoCurrencyState.Evo.Enabled = val
            if Logger and Logger.Info then Logger:Info("Auto Evo: " .. (val and "ACTIVE" or "OFF")) end
        end,
    })

    EvoSection:Dropdown({
        Title = "Target Evo",
        Desc = "Select the target evolution tower (Default: All)",
        List = { "All", "Scout", "Shotgunner", "Crook Boss", "Minigunner" },
        Value = AutoCurrencyState.Evo.Target or "All",
        Callback = function(choice)
            if not checkIsPremium() then
                Window:Notify({
                    Title = "Premium Plan Required",
                    Desc = "Please activate key at product key",
                    Duration = 3,
                })
                return
            end
            AutoCurrencyState.Evo.Target = choice
        end,
    })

    EvoSection:Dropdown({
        Title = "Win / Lose Strategy",
        Desc = "Select outcome preference for Auto Evo (Default: Lose)",
        List = { "Lose", "Win" },
        Value = AutoCurrencyState.Evo.Strategy or "Lose",
        Callback = function(choice)
            if not checkIsPremium() then
                Window:Notify({
                    Title = "Premium Plan Required",
                    Desc = "Please activate key at product key",
                    Duration = 3,
                })
                return
            end
            AutoCurrencyState.Evo.Strategy = choice
        end,
    })

    EvoSection:Label({
        Title = "Status",
        Desc = "Status: Checking...",
    })

    EvoSection:Label({
        Title = "Missing:",
        Desc = "Missing: Checking...",
    })

    -- 6. Evolution Trackers Section
    EvoTrackerSection = CurrencyTab:Section({ Title = "Evolution Trackers" })

    EvoTrackerSection:Label({
        Title = "Coins & Gems Tracker",
        Desc = "Waiting for data...",
    })

    EvoTrackerSection:Label({
        Title = "Towers Level",
        Desc = "Waiting for data...",
    })

    -- Activate default section
    showCurrencySection(AutoCurrencyState.SelectedTab or "Auto Coins")
end

Window:Line()

local Interactive = Window:Tab({Title = "Interactive", Icon = "mouse-pointer-click"}) do
    
    Interactive:Section({Title = "Tower Controls"})
        
    Interactive:Toggle({
        Title = "Tower Snapper",
        Desc = "Automatically snaps and honeycomb-packs towers into the nearest valid position when hovering invalid spots",
        Value = Globals.Snapper ~= nil and Globals.Snapper or true,
        Callback = function(Value)
            TowerSnapper.Enabled = Value
            SetSetting("Snapper", Value)
            InvalidateSnapCache()
        end
    })

    Interactive:Toggle({
        Title = "Buff Indicator Overlay",
        Desc = "Shows active DJ/Commander/Medic range auras and in-range badges while placing",
        Value = Globals.BuffOverlay ~= nil and Globals.BuffOverlay or true,
        Callback = function(Value)
            BuffOverlay.Enabled = Value
            SetSetting("BuffOverlay", Value)
            if not Value then
                ClearBuffVisuals()
            end
        end
    })

    local TowerDropdown = Interactive:Dropdown({
        Title = "Tower:",
        List = CurrentEquippedTowers,
        Value = CurrentEquippedTowers[1],
        Callback = function(choice)
            SelectedTower = choice
        end
    })

    local function RefreshDropdown()
        local NewTowers = GetEquippedTowers()
        if table.concat(NewTowers, ",") ~= table.concat(CurrentEquippedTowers, ",") then
            TowerDropdown:Clear() 

            for _, TowerName in ipairs(NewTowers) do
                TowerDropdown:Add(TowerName)
            end

            CurrentEquippedTowers = NewTowers
        end
    end

    task.spawn(function()
        while task.wait(2) do
            RefreshDropdown()
        end
    end)

    Interactive:Toggle({
        Title = "Stack Tower",
        Desc = "Enables Stacking placement",
        Value = false,
        Callback = function(v)
            StackEnabled = v
            Globals.StackEnabled = v

            if StackEnabled then
                Window:Notify({
                    Title = "ADS",
                    Desc = "Make sure not to equip the tower, only select it and then place where you want to!",
                    Time = 5,
                    Type = "normal"
                })
            end
        end
    })

    Interactive:Button({
        Title = "Open Inventory",
        Desc = "Place initial towers, then click this to swap loadout before readying up (bypasses 5-tower limit).\nNote: Does not work on low sUNC executors like Solara/Xeno",
        Callback = function()
            pcall(function()
                require(game:GetService("ReplicatedStorage").Client.Interfaces.LegacyInterface.Controllers.ViewController):setView("Inventory")
            end)
        end
    })

    Interactive:Button({
        Title = "Upgrade Selected",
        Desc = "",
        Callback = function()
            if SelectedTower then
                for _, v in pairs(workspace.Towers:GetChildren()) do
                    if v:FindFirstChild("TowerReplicator") and v.TowerReplicator:GetAttribute("Name") == SelectedTower and v.TowerReplicator:GetAttribute("OwnerId") == LocalPlayer.UserId then
                        RemoteFunc:InvokeServer("Troops", "Upgrade", "Set", {Troop = v})
                    end
                end
                Window:Notify({
                    Title = "ADS",
                    Desc = "Attempted to upgrade all the selected towers!",
                    Time = 3,
                    Type = "normal"
                })
            end
        end
    })

    Interactive:Button({
        Title = "Sell Selected",
        Desc = "",
        Callback = function()
            if SelectedTower then
                for _, v in pairs(workspace.Towers:GetChildren()) do
                    if v:FindFirstChild("TowerReplicator") and v.TowerReplicator:GetAttribute("Name") == SelectedTower and v.TowerReplicator:GetAttribute("OwnerId") == LocalPlayer.UserId then
                        RemoteFunc:InvokeServer("Troops", "Sell", {Troop = v})
                    end
                end
                Window:Notify({
                    Title = "ADS",
                    Desc = "Attempted to sell all the selected towers!",
                    Time = 3,
                    Type = "normal"
                })
            end
        end
    })

    Interactive:Button({
        Title = "Upgrade All",
        Desc = "",
        Callback = function()
            for _, v in pairs(workspace.Towers:GetChildren()) do
                if v:FindFirstChild("Owner") and v.Owner.Value == LocalPlayer.UserId then
                    RemoteFunc:InvokeServer("Troops", "Upgrade", "Set", {Troop = v})
                end
            end
            Window:Notify({
                Title = "ADS",
                Desc = "Attempted to upgrade all the towers!",
                Time = 3,
                Type = "normal"
            })
        end
    })

    Interactive:Button({
        Title = "Sell All",
        Desc = "",
        Callback = function()
            Window:Dialog({
                Title = "Do you want to sell all the towers?",
                Button1 = {
                    Title = "Confirm",
                    Color = Color3.fromRGB(226, 39, 6),
                    Callback = function()
                        for _, v in pairs(workspace.Towers:GetChildren()) do
                            if v:FindFirstChild("Owner") and v.Owner.Value == LocalPlayer.UserId then
                                RemoteFunc:InvokeServer("Troops", "Sell", {Troop = v})
                            end
                        end

                        Window:Notify({
                            Title = "ADS",
                            Desc = "Attempted to sell all the towers!",
                            Time = 3,
                            Type = "normal"
                        })
                    end
                },
                Button2 = {
                    Title = "Cancel",
                    Color = Color3.fromRGB(0, 188, 0)
                }
            })
        end
    })

    Interactive:Section({Title = "TimeScale Management"})
    
    Interactive:Toggle({
        Title = "Enable TimeScale",
        Desc = "Unlocks and sets game speed using tickets",
        Value = Globals.TimeScaleEnabled,
        Callback = function(v)
            SetSetting("TimeScaleEnabled", v)
            if v then
                StartTimeScale()
            end
        end
    })

    Interactive:Dropdown({
        Title = "TimeScale Speed",
        Desc = "Choose: 0.5, 1, 1.5, 2",
        List = {"0.5", "1", "1.5", "2"},
        Value = tostring(Globals.TimeScaleValue or 2),
        Callback = function(choice)
            local selected = type(choice) == "table" and choice[1] or choice
            local value = CoerceTimeScaleValue(selected, Globals.TimeScaleValue or 2)
            SetSetting("TimeScaleValue", value)
            if Globals.TimeScaleEnabled then
                ApplyTimeScaleOnce()
            end
        end
    })



    Interactive:Section({Title = "Player Statistics"})
    
    local CoinsLabel = Interactive:Label({Title = "Coins: 0", Desc = ""})
    local GemsLabel = Interactive:Label({Title = "Gems: 0", Desc = ""})
    local TicketsLabel = Interactive:Label({Title = "Timescale Tickets: 0", Desc = ""})
    local LevelLabel = Interactive:Label({Title = "Level: 0", Desc = ""})
    local WinsLabel = Interactive:Label({Title = "Wins: 0", Desc = ""})
    local LosesLabel = Interactive:Label({Title = "Loses: 0", Desc = ""})
    local ExpLabel = Interactive:Label({Title = "Experience: 0 / 0", Desc = ""})
    local ExpSlider = Interactive:Slider({
        Title = "EXP",
        Desc = "",
        Min = 0,
        Max = 100,
        Rounding = 0,
        Value = 0,
        Callback = function()
        end
    })

    local function ParseNumber(val)
        if type(val) == "number" then
            return val
        end
        if type(val) == "string" then
            local cleaned = string.gsub(val, ",", "")
            local n = tonumber(cleaned)
            if n then
                return n
            end
        end
        if type(val) == "table" and val.get then
            local ok, v = pcall(function()
                return val:get()
            end)
            if ok then
                return ParseNumber(v)
            end
        end
        return nil
    end

    local function ReadValue(obj)
        if not obj then
            return nil
        end
        local ok, v = pcall(function()
            return obj.Value
        end)
        if ok then
            return ParseNumber(v)
        end
        return nil
    end

    local function GetStatNumber(name)
        local obj = LocalPlayer:FindFirstChild(name)
        local v = ReadValue(obj)
        if v ~= nil then
            return v
        end
        local attr = LocalPlayer:GetAttribute(name)
        v = ParseNumber(attr)
        if v ~= nil then
            return v
        end
        return nil
    end

    local function PickExpMax()
        local ExpObj = LocalPlayer:FindFirstChild("Experience")
        local AttrMax = ExpObj and ParseNumber(ExpObj:GetAttribute("Max"))
        local AttrNeed = ExpObj and ParseNumber(ExpObj:GetAttribute("Required"))
        local AttrNext = ExpObj and ParseNumber(ExpObj:GetAttribute("Next"))
        return AttrMax
            or AttrNeed
            or AttrNext
            or GetStatNumber("ExperienceMax")
            or GetStatNumber("ExperienceNeeded")
            or GetStatNumber("ExperienceRequired")
            or GetStatNumber("ExperienceToNextLevel")
            or GetStatNumber("ExperienceToLevel")
            or GetStatNumber("NextLevelExp")
            or GetStatNumber("ExpToNextLevel")
            or GetStatNumber("ExpNeeded")
            or GetStatNumber("ExpRequired")
            or GetStatNumber("MaxExp")
            or GetStatNumber("MaxExperience")
            or 100
    end

    local GcExpCache = { t = nil, last = 0 }
    local function GetGcExp()
        if not getgc then
            return nil
        end
        local t = GcExpCache.t
        if t then
            local exp = ParseNumber(rawget(t, "exp") or rawget(t, "Exp") or rawget(t, "experience") or rawget(t, "Experience"))
            local MaxExp = ParseNumber(rawget(t, "maxExp") or rawget(t, "MaxExp") or rawget(t, "maxEXP") or rawget(t, "MaxEXP") or rawget(t, "maxExperience") or rawget(t, "MaxExperience"))
            local lvl = ParseNumber(rawget(t, "level") or rawget(t, "Level") or rawget(t, "lvl") or rawget(t, "Lvl"))
            if exp and MaxExp then
                return exp, MaxExp, lvl
            end
        end
        local now = os.clock()
        if now - GcExpCache.last < 3 then
            return nil
        end
        GcExpCache.last = now
        local plvl = GetStatNumber("Level")
        for _, obj in ipairs(getgc(true)) do
            if type(obj) == "table" then
                local exp = ParseNumber(rawget(obj, "exp") or rawget(obj, "Exp") or rawget(obj, "experience") or rawget(obj, "Experience"))
                local MaxExp = ParseNumber(rawget(obj, "maxExp") or rawget(obj, "MaxExp") or rawget(obj, "maxEXP") or rawget(obj, "MaxEXP") or rawget(obj, "maxExperience") or rawget(obj, "MaxExperience"))
                if exp and MaxExp then
                    local lvl = ParseNumber(rawget(obj, "level") or rawget(obj, "Level") or rawget(obj, "lvl") or rawget(obj, "Lvl"))
                    if not plvl or not lvl or lvl == plvl then
                        GcExpCache.t = obj
                        return exp, MaxExp, lvl
                    end
                end
            end
        end
        return nil
    end

    local function UpdateStats()
        local coins = GetStatNumber("Coins") or 0
        local gems = GetStatNumber("Gems") or 0
        local tickets = GetStatNumber("TimescaleTickets") or 0
        local lvl = GetStatNumber("Level") or 0
        local wins = GetStatNumber("Triumphs") or 0
        local loses = GetStatNumber("Loses") or 0
        local exp = GetStatNumber("Experience") or 0
        local MaxExp = PickExpMax()
        local GcExp, GcMax, GcLvl = GetGcExp()
        if GcExp and GcMax then
            exp = GcExp
            MaxExp = GcMax
            if GcLvl then
                lvl = GcLvl
            end
        end
        if MaxExp < 1 then
            MaxExp = 1
        end
        if exp > MaxExp then
            MaxExp = exp
        end
        if CoinsLabel then CoinsLabel:SetTitle("Coins: " .. tostring(coins)) end
        if GemsLabel then GemsLabel:SetTitle("Gems: " .. tostring(gems)) end
        if TicketsLabel then TicketsLabel:SetTitle("Timescale Tickets: " .. tostring(tickets)) end
        if LevelLabel then LevelLabel:SetTitle("Level: " .. tostring(lvl)) end
        if WinsLabel then WinsLabel:SetTitle("Wins: " .. tostring(wins)) end
        if LosesLabel then LosesLabel:SetTitle("Loses: " .. tostring(loses)) end
        if ExpLabel then ExpLabel:SetTitle("Experience: " .. tostring(exp) .. " / " .. tostring(MaxExp)) end
        if ExpSlider then
            ExpSlider:SetMin(0)
            ExpSlider:SetMax(MaxExp)
            ExpSlider:SetValue(exp)
        end
    end

    local StatsQueued = false
    local function QueueStatsUpdate()
        if StatsQueued then
            return
        end
        StatsQueued = true
        task.delay(0.2, function()
            StatsQueued = false
            UpdateStats()
        end)
    end

    local function HookStatObj(obj)
        if not obj then
            return
        end
        if obj.Changed then
            obj.Changed:Connect(QueueStatsUpdate)
        end
        obj:GetAttributeChangedSignal("Max"):Connect(QueueStatsUpdate)
        obj:GetAttributeChangedSignal("Required"):Connect(QueueStatsUpdate)
        obj:GetAttributeChangedSignal("Next"):Connect(QueueStatsUpdate)
    end

    local StatNames = {"Coins", "Gems", "TimescaleTickets", "Level", "Triumphs", "Loses", "Experience"}
    local ExpAttrNames = {
        "ExperienceMax",
        "ExperienceNeeded",
        "ExperienceRequired",
        "ExperienceToNextLevel",
        "ExperienceToLevel",
        "NextLevelExp",
        "ExpToNextLevel",
        "ExpNeeded",
        "ExpRequired",
        "MaxExp",
        "MaxExperience"
    }

    for _, name in ipairs(StatNames) do
        HookStatObj(LocalPlayer:FindFirstChild(name))
        LocalPlayer:GetAttributeChangedSignal(name):Connect(QueueStatsUpdate)
    end

    for _, name in ipairs(ExpAttrNames) do
        LocalPlayer:GetAttributeChangedSignal(name):Connect(QueueStatsUpdate)
    end

    LocalPlayer.ChildAdded:Connect(function(child)
        if table.find(StatNames, child.Name) then
            HookStatObj(child)
            QueueStatsUpdate()
        end
    end)

    LocalPlayer.ChildRemoved:Connect(function(child)
        if table.find(StatNames, child.Name) then
            QueueStatsUpdate()
        end
    end)

    QueueStatsUpdate()
end

Window:Line()

local Configuration = Window:Tab({Title = "Configuration", Icon = "sliders-horizontal"}) do
    Configuration:Section({Title = "Performance Optimization"})
    
    Configuration:Toggle({
        Title = "Enable Anti-Lag",
        Desc = "Boosts your FPS",
        Value = Globals.AntiLag,
        Callback = function(v)
            SetSetting("AntiLag", v)
        end
    })

    Configuration:Toggle({
        Title = "Disable 3d rendering",
        Desc = "Turns off 3d rendering",
        Value = Globals.Disable3DRendering,
        Callback = function(v)
            SetSetting("Disable3DRendering", v)
            Apply3dRendering()
        end
    })

    Configuration:Section({Title = "Custom Nametags"})
    
    local tagOptions = collectTagOptions()
    local tagValue = Globals.tagName or "None"
    if not table.find(tagOptions, tagValue) then
        tagValue = "None"
    end
    Configuration:Dropdown({
        Title = "Tag Changer",
        Desc = "",
        List = tagOptions,
        Value = tagValue,
        Callback = function(choice)
            local selected = choice
            if type(choice) == "table" then
                selected = choice[1]
            end
            if not selected or selected == "" then
                selected = "None"
            end
            SetSetting("tagName", selected)
            if selected == "None" then
                stopTagChanger()
            else
                startTagChanger()
            end
        end
    })

    Configuration:Section({Title = "Config Management"})
    
    Configuration:Button({
        Title = "Save Settings",
        Callback = function()
            Window:Notify({
                    Title = "ADS",
                    Desc = "Settings Saved!",
                    Time = 3,
                    Type = "normal"
                })
            SaveSettings()
        end
    })

    Configuration:Button({
        Title = "Load Settings",
        Callback = function()
            Window:Notify({
                    Title = "ADS",
                    Desc = "Settings Loaded!",
                    Time = 3,
                    Type = "normal"
                })
            LoadSettings()
        end
    })

    Configuration:Section({Title = "Experimental Features"})
    
    local StickerSpam = false

    Configuration:Toggle({
        Title = "Sticker Spam",
        Desc = "This will drop everyones FPS to like 5 (you will not be able to see this unless you have an alt)",
        Value = false,
        Callback = function(v)
            StickerSpam = v

            if StickerSpam then
                task.spawn(function()
                    while StickerSpam do
                        for i = 1, 9999 do
                            if not StickerSpam then break end

                            local args = {"Flex"}
                            game:GetService("ReplicatedStorage"):WaitForChild("Network"):WaitForChild("Sticker"):WaitForChild("URE:Show"):FireServer(unpack(args))
                        end
                        task.wait()
                    end
                end)
            end
        end
    })

    Configuration:Button({
        Title = "Unlock Admin+ (Sandbox)",
        Desc = "Keep in mind that some features such as selecting maps, spawning in enemies and changing tower stats will not work!",
        Callback = function()
            if GameState == "GAME" then
                local args = {
                    game.Players.LocalPlayer.UserId,
                    true
                }

                game:GetService("ReplicatedStorage"):WaitForChild("Network"):WaitForChild("Sandbox"):WaitForChild("RE:SetAdmin"):FireServer(unpack(args))

                Window:Notify({
                    Title = "ADS",
                    Desc = "Successfully unlocked Admin+ Mode!",
                    Time = 3,
                    Type = "normal"
                })
            else
                Window:Notify({
                    Title = "ADS",
                    Desc = "You must be in Sandbox mode for this to work!",
                    Time = 3,
                    Type = "normal"
                })
            end
        end
    })
end

Window:Line()




Window:Line()

Logger = Window:Tab({Title = "Logger", Icon = "terminal"}); do
    Logger = Logger:CreateLogger({
        Title = "STRATEGY LOGGER:",
        Size = UDim2.new(0, 330, 0, 300)
    })
end

Window:Line()

do
-- =============================================================================
-- RECORDER & STRATEGY LIBRARY VAULT
-- =============================================================================
local recordingFileName = "Strat"
local autoPlayRecordingActive = false
local recordingConsoleRef = nil
local recordingStatusLabel = nil
local spawnedRecorderTowers = {}
local recordedTowerCount = 0
local recorderLastWave = -1
local selectedLibraryFile = ""
local selectedStrat = "Strat.txt"
local stratManagerRef = nil
local hasStratExecutedForThisMatch = false
local currentRunningStratThread = nil
local currentRunningStratName = nil
local hasAutoExecutedThisMatch = false
local isTdsMethodCalling = false
local lastRecordedSkipWave = -1
local hasRecordedReadyThisMatch = false
local hookedTDSMethods = {}

local function checkIsPremium()
    return JD_IS_PREMIUM == true or (Globals and Globals.IsPremium == true) or (getgenv and getgenv().IsPremium == true)
end

local function isStackerActive()
    return (Globals and (Globals.Stacker == true or Globals.StackEnabled == true or Globals.Snapper == true))
        or (getgenv and (getgenv().Stacker == true or getgenv().StackEnabled == true or getgenv().Snapper == true))
end

local function resolve_tower_index(tower)
    if typeof(tower) ~= "Instance" then
        return nil
    end

    if spawnedRecorderTowers[tower] then
        return spawnedRecorderTowers[tower]
    end

    local current = tower.Parent
    while current do
        if spawnedRecorderTowers[current] then
            return spawnedRecorderTowers[current]
        end
        current = current.Parent
    end

    local activeTDS = TDS or shared.TDSTable or (getgenv and getgenv().TDS) or _G.TDS
    if activeTDS and type(activeTDS.PlacedTowers) == "table" then
        for idx, t in ipairs(activeTDS.PlacedTowers) do
            if t == tower or (typeof(tower) == "Instance" and (t == tower.Parent or tower:IsDescendantOf(t))) then
                spawnedRecorderTowers[tower] = idx
                return idx
            end
        end
    end

    return nil
end

local function serializeRecordArgument(argumentValue)
    local argumentType = type(argumentValue)
    if typeof(argumentValue) == "Vector3" then
        return string.format("Vector3.new(%s, %s, %s)", tostring(argumentValue.X), tostring(argumentValue.Y), tostring(argumentValue.Z))
    elseif argumentType == "string" then
        return string.format("%q", argumentValue)
    elseif argumentType == "number" or argumentType == "boolean" then
        return tostring(argumentValue)
    elseif argumentType == "table" then
        local parts = {}
        for key, val in pairs(argumentValue) do
            local keyType = type(key)
            local formattedKey
            if keyType == "string" then
                if key:match("^[%a_][%w_]*$") then
                    formattedKey = key
                else
                    formattedKey = string.format("[%q]", key)
                end
            elseif keyType == "number" then
                formattedKey = string.format("[%d]", key)
            else
                formattedKey = string.format("[%s]", tostring(key))
            end
            local formattedValue = serializeRecordArgument(val)
            table.insert(parts, formattedKey .. " = " .. formattedValue)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    elseif typeof(argumentValue) == "Instance" then
        local idx = resolve_tower_index(argumentValue)
        if idx then return tostring(idx) end
        return "nil"
    else
        return "nil"
    end
end

local function ensureSavedRecordedFolder()
    if typeof(isfolder) == "function" then
        if not isfolder("[SavedRecorded]") then
            if typeof(makefolder) == "function" then
                pcall(makefolder, "[SavedRecorded]")
            end
        end
    elseif typeof(makefolder) == "function" then
        pcall(makefolder, "[SavedRecorded]")
    end
end

local function getSavedRecordedFilesList()
    ensureSavedRecordedFolder()
    local files = {}
    pcall(function()
        if typeof(listfiles) == "function" then
            local rawFiles = listfiles("[SavedRecorded]")
            if type(rawFiles) == "table" then
                for _, path in ipairs(rawFiles) do
                    local cleanName = tostring(path):match("([^/\\]+)$") or tostring(path)
                    if cleanName ~= "" then
                        table.insert(files, cleanName)
                    end
                end
            end
        end
    end)
    if #files == 0 then
        pcall(function()
            if typeof(isfile) == "function" and isfile("[SavedRecorded]/Strat.txt") then
                table.insert(files, "Strat.txt")
            end
        end)
    end
    if #files == 0 then
        table.insert(files, "Strat.txt")
    end
    table.sort(files)
    return files
end

local function getCleanRecordTargetFilePath()
    ensureSavedRecordedFolder()
    local name = tostring(recordingFileName or "Strat"):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then
        name = "Strat"
    end
    name = name:gsub('[/\\:*?"<>|]', "_")
    if not name:match("%.txt$") and not name:match("%.lua$") then
        name = name .. ".txt"
    end
    return "[SavedRecorded]/" .. name, name
end

local function appendRecordActionLine(commandStr, logDesc)
    if not autoPlayRecordingActive then return end
    table.insert(executed_actions, commandStr)
    pcall(function()
        local savePath = getCleanRecordTargetFilePath()
        local wavePrefix = ""
        local stateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
        local gsr = stateReps and stateReps:FindFirstChild("GameStateReplicator")
        local curWave = gsr and gsr:GetAttribute("Wave") or 0
        if curWave > recorderLastWave then
            recorderLastWave = curWave
            wavePrefix = string.format("\n-- [ Wave %d ] --\n", curWave)
        end
        if typeof(appendfile) == "function" then
            appendfile(savePath, wavePrefix .. commandStr .. "\n")
            appendfile("Strat.txt", wavePrefix .. commandStr .. "\n")
            appendfile("ADS_LastStrat.lua", wavePrefix .. commandStr .. "\n")
        end
    end)
    if logDesc and recordingConsoleRef then
        pcall(function()
            recordingConsoleRef:Log(logDesc)
        end)
    end
end

-- =============================================================================
-- RECORDER TAB
-- =============================================================================
local RecorderTab = Window:Tab({
    Title = "Recorder",
    Icon = "camera",
    Subtitle = "Auto Play System",
})

RecorderTab:Banner({
    Title = "Strategy Action Recorder",
    Desc = "Record real-time tower placements, upgrades, sells, and abilities into an executable strategy script.",
    Type = "Info",
})

local RecorderConfigSection = RecorderTab:Section({ Title = "Recorder Controls" })

RecorderConfigSection:Textbox({
    Title = "Record File Name",
    Desc = "Target file name to save inside [SavedRecorded] (e.g. Strat, FallenLayBy)",
    Placeholder = "Strat",
    Value = recordingFileName,
    ClearTextOnFocus = false,
    Callback = function(txt)
        local val = txt:gsub("^%s+", ""):gsub("%s+$", "")
        if val ~= "" then
            recordingFileName = val
        else
            recordingFileName = "Strat"
        end
        if Logger and Logger.Info then Logger:Info("Recorder file name set to: " .. recordingFileName) end
    end,
})

recordingStatusLabel = RecorderConfigSection:Label({
    Title = "Recorder Status",
    Desc = "IDLE - Standing by",
})

local strategyRecordingSetup

RecorderConfigSection:Button({
    Title = "START RECORDING",
    Desc = "Begins capturing in-game actions into [SavedRecorded]",
    Image = "Check",
    Callback = function()
        if autoPlayRecordingActive then
            Window:Notify({
                Title = "Already Recording",
                Desc = "Strategy recorder is already running!",
                Duration = 2,
            })
            return
        end

        local filePath, fileName = getCleanRecordTargetFilePath()
        autoPlayRecordingActive = true
        if getgenv then
            getgenv().record_strat = true
            getgenv().__active_record_path = filePath
        end
        if Globals then
            Globals.record_strat = true
            Globals.__active_record_path = filePath
            Globals.__last_recorded_wave = -1
        end
        table.clear(spawnedRecorderTowers)
        table.clear(executed_actions)
        recordedTowerCount = 0
        recorderLastWave = -1
        lastRecordedSkipWave = -1
        hasRecordedReadyThisMatch = false

        if recordingConsoleRef then
            recordingConsoleRef:Clear()
            recordingConsoleRef:Info("=== RECORDER INITIALIZED ===")
            recordingConsoleRef:Info("Target File: " .. filePath)
        end

        -- Determine map, mode, and equipped towers header
        local currentMap = "Unknown"
        local currentMode = "Unknown"
        local stateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
        local gsr = stateReps and stateReps:FindFirstChild("GameStateReplicator")
        if gsr then
            currentMap = gsr:GetAttribute("Map") or "Unknown"
            currentMode = gsr:GetAttribute("Difficulty") or gsr:GetAttribute("Mode") or "Unknown"
        end

        local stateFolder = ReplicatedStorage:FindFirstChild("State")
        if stateFolder then
            pcall(function()
                if stateFolder:FindFirstChild("Map") and stateFolder.Map.Value ~= "" then
                    currentMap = stateFolder.Map.Value
                end
                if stateFolder:FindFirstChild("Difficulty") and stateFolder.Difficulty.Value ~= "" then
                    currentMode = stateFolder.Difficulty.Value
                end
            end)
        end

        local towerList = { "None", "None", "None", "None", "None" }
        if stateReps and LocalPlayer then
            for _, folder in ipairs(stateReps:GetChildren()) do
                if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == LocalPlayer.UserId then
                    local equipped = folder:GetAttribute("EquippedTowers")
                    if type(equipped) == "string" then
                        local cleanedJson = equipped:match("%[.*%]")
                        if cleanedJson and HttpService then
                            pcall(function()
                                local decoded = HttpService:JSONDecode(cleanedJson)
                                if type(decoded) == "table" then
                                    for i = 1, 5 do
                                        towerList[i] = decoded[i] or "None"
                                    end
                                end
                            end)
                        end
                    end
                end
            end
        end

        local headerComment = string.format([[-- Generated by Bogus Hub Auto Play Recorder
local TDS = shared.TDSTable or loadstring(game:HttpGet("https://raw.githubusercontent.com/DuxiiT/auto-strat/refs/heads/main/Library.lua"))()

TDS:Loadout("%s", "%s", "%s", "%s", "%s")
TDS:Mode("%s")
TDS:GameInfo("%s", {})

]], towerList[1], towerList[2], towerList[3], towerList[4], towerList[5], currentMode, currentMap)

        pcall(function()
            if typeof(writefile) == "function" then
                writefile(filePath, headerComment)
                writefile("Strat.txt", headerComment)
                writefile("ADS_LastStrat.lua", headerComment)
            end
        end)

        -- Sync existing towers
        local towersFolder = workspace:FindFirstChild("Towers")
        if towersFolder and LocalPlayer then
            for _, tower in ipairs(towersFolder:GetChildren()) do
                local replicator = tower:FindFirstChild("TowerReplicator")
                if replicator and replicator:GetAttribute("OwnerId") == LocalPlayer.UserId then
                    recordedTowerCount = recordedTowerCount + 1
                    spawnedRecorderTowers[tower] = recordedTowerCount
                end
            end
        end

        if typeof(strategyRecordingSetup) == "function" then
            strategyRecordingSetup()
        end

        if recordingStatusLabel then
            recordingStatusLabel:SetTitle("Recorder Status")
            recordingStatusLabel:SetDesc("RECORDING ACTIVE -> " .. fileName)
        end

        Window:Notify({
            Title = "Recording Started",
            Desc = "Capturing to [SavedRecorded]/" .. fileName,
            Duration = 3,
        })
        if Logger and Logger.Success then Logger:Success("Auto Play Recorder started -> [SavedRecorded]/" .. fileName) end
    end,
})

RecorderConfigSection:Button({
    Title = "STOP RECORDING",
    Desc = "Stops active recording session and finalizes file",
    Image = "Button",
    Callback = function()
        if not autoPlayRecordingActive then
            Window:Notify({
                Title = "Recorder Idle",
                Desc = "No recording session is currently active.",
                Duration = 2,
            })
            return
        end

        autoPlayRecordingActive = false
        if getgenv then
            getgenv().record_strat = false
            getgenv().__active_record_path = nil
        end
        if Globals then
            Globals.record_strat = false
            Globals.__active_record_path = nil
        end

        local filePath, fileName = getCleanRecordTargetFilePath()
        if recordingConsoleRef then
            recordingConsoleRef:Success("Recording stopped successfully.")
            recordingConsoleRef:Info("Strategy file saved: " .. filePath)
        end

        if recordingStatusLabel then
            recordingStatusLabel:SetTitle("Recorder Status")
            recordingStatusLabel:SetDesc("IDLE - Strategy saved: " .. fileName)
        end

        if stratManagerRef and typeof(stratManagerRef.SetStrats) == "function" and typeof(getSavedRecordedStrategyItems) == "function" then
            pcall(function()
                stratManagerRef:SetStrats(getSavedRecordedStrategyItems())
            end)
        end

        Window:Notify({
            Title = "Recording Saved",
            Desc = "File successfully written to [SavedRecorded]/" .. fileName,
            Duration = 3.5,
        })
        if Logger and Logger.Success then Logger:Success("Auto Play Recorder stopped. Strategy written: " .. fileName) end
    end,
})

local RecorderLogSection = RecorderTab:Section({ Title = "Live Recording Feed" })
recordingConsoleRef = RecorderLogSection:LogConsole({
    Title = "RECORDER ACTIVITY LOG",
    Height = 150,
    MaxLines = 100,
})

-- Workspace tower listeners for recorder
task.spawn(function()
    local towersFolder = workspace:WaitForChild("Towers", 10) or workspace:FindFirstChild("Towers")
    if towersFolder then
        towersFolder.ChildAdded:Connect(function(tower)
            if not autoPlayRecordingActive then return end
            task.wait(0.1)
            local replicator = tower:WaitForChild("TowerReplicator", 4)
            if not replicator then return end
            if LocalPlayer and replicator:GetAttribute("OwnerId") ~= LocalPlayer.UserId then return end
            if replicator:GetAttribute("Hologram") == true then return end

            recordedTowerCount = recordedTowerCount + 1
            local myIndex = recordedTowerCount
            spawnedRecorderTowers[tower] = myIndex

            local towerName = replicator:GetAttribute("Name") or tower.Name
            local rawPos = replicator:GetAttribute("Position")
            local posX, posY, posZ
            if typeof(rawPos) == "Vector3" then
                posX, posY, posZ = rawPos.X, rawPos.Y, rawPos.Z
            else
                local p = tower:GetPivot().Position
                posX, posY, posZ = p.X, p.Y, p.Z
            end

            local isStackerOn = isStackerActive()
            local cmd
            if isStackerOn then
                cmd = string.format('TDS:Place("%s", %s, %s, %s, true)', towerName, tostring(posX), tostring(posY), tostring(posZ))
            else
                cmd = string.format('TDS:Place("%s", %s, %s, %s)', towerName, tostring(posX), tostring(posY), tostring(posZ))
            end
            appendRecordActionLine(cmd, string.format("Placed %s (Index: %d)", towerName, myIndex))
        end)

        towersFolder.ChildRemoved:Connect(function(tower)
            if not autoPlayRecordingActive then return end
            local myIndex = spawnedRecorderTowers[tower]
            if myIndex then
                local cmd = string.format("TDS:Sell(%d)", myIndex)
                appendRecordActionLine(cmd, string.format("Sold Tower (Index: %d)", myIndex))
                spawnedRecorderTowers[tower] = nil
            end
        end)
    end
end)

local function handleRecordedRemoteCall(remote, method, args, results)
    if not autoPlayRecordingActive or isTdsMethodCalling then
        return
    end

    if method ~= "InvokeServer" and method ~= "FireServer" then
        return
    end

    local a1 = args[1]
    local a2 = args[2]
    local a3 = args[3]
    local a4 = args[4]

    -- 1. Upgrades: InvokeServer("Troops", "Upgrade", "Set", { Troop = ..., Path = ... })
    if a1 == "Troops" and a2 == "Upgrade" and a3 == "Set" then
        if type(a4) == "table" then
            local tower = a4.Troop
            local my_index = resolve_tower_index(tower)
            local path = a4.Path or 1

            if my_index and (not results or results[1] == true or results[1] == nil) then
                local replicator = (typeof(tower) == "Instance" and tower:FindFirstChild("TowerReplicator"))
                local tower_name = (replicator and replicator:GetAttribute("Name")) or (typeof(tower) == "Instance" and tower.Name) or ("Tower " .. tostring(my_index))

                local cmd = (path > 1) and string.format("TDS:Upgrade(%d, %d)", my_index, path) or string.format("TDS:Upgrade(%d)", my_index)
                appendRecordActionLine(cmd, string.format("Upgraded %s (Index: %d)", tower_name, my_index))
                return
            end
        end
    end

    -- 2. Target: InvokeServer("Troops", "Target", "Set", { Troop = ..., Target = ... })
    if a1 == "Troops" and a2 == "Target" and a3 == "Set" then
        if type(a4) == "table" then
            local my_index = resolve_tower_index(a4.Troop)
            local target_type = a4.Target
            if my_index and type(target_type) == "string" then
                local cmd = string.format("TDS:SetTarget(%d, %q)", my_index, target_type)
                appendRecordActionLine(cmd, string.format("Target: Tower %d -> %s", my_index, target_type))
                return
            end
        end
    end

    -- 3. Options (DJ track, Trapper mode, etc.): InvokeServer("Troops", "Option", "Set", { Troop = ..., Name = ..., Value = ... })
    if a1 == "Troops" and a2 == "Option" and a3 == "Set" then
        if type(a4) == "table" then
            local idx = resolve_tower_index(a4.Troop)
            local opt_name = a4.Name or a4.Option or a4.Key or a4.Track
            local opt_val = a4.Value or a4.Val
            if idx and type(opt_name) == "string" then
                local valStr = serializeRecordArgument(opt_val)
                local cmd = string.format("TDS:SetOption(%d, %q, %s)", idx, opt_name, valStr)
                appendRecordActionLine(cmd, string.format("Option: Tower %d %s = %s", idx, opt_name, tostring(opt_val)))
                return
            end
        end
    end

    -- 4. Abilities: InvokeServer("Troops", "Abilities", "Activate", { Troop = ..., Name = ..., Data = ... })
    if a1 == "Troops" and a2 == "Abilities" and a3 == "Activate" then
        if type(a4) == "table" then
            local idx = resolve_tower_index(a4.Troop)
            local name = a4.Name
            if idx and type(name) == "string" then
                local data = a4.Data
                local cmd
                local isStackerOn = isStackerActive()

                if data == nil or (type(data) == "table" and next(data) == nil) then
                    cmd = string.format("TDS:Ability(%d, %q)", idx, name)
                else
                    local serializedData = serializeRecordArgument(data)
                    if name == "Hologram Tower" or name == "Hologram" or (type(data) == "table" and (data.towerToClone or data.towerPosition)) then
                        if isStackerOn then
                            cmd = string.format("TDS:Ability(%d, %q, %s, true, true)", idx, name, serializedData)
                        else
                            cmd = string.format("TDS:Ability(%d, %q, %s, true)", idx, name, serializedData)
                        end
                    else
                        cmd = string.format("TDS:Ability(%d, %q, %s)", idx, name, serializedData)
                    end
                end
                appendRecordActionLine(cmd, string.format("Ability: %s (Index: %d)", name, idx))
                return
            end
        end
    end

    -- 5. Medic: InvokeServer("Troops", "TowerServerEvent", "ToggleSelectedTower", tower1, tower2)
    if a1 == "Troops" and a2 == "TowerServerEvent" and a3 == "ToggleSelectedTower" then
        local idx = resolve_tower_index(args[4])
        local target_idx = resolve_tower_index(args[5])
        if idx and target_idx then
            local cmd = string.format("TDS:MedicSelect(%d, %d)", idx, target_idx)
            appendRecordActionLine(cmd, string.format("Medic: %d -> %d", idx, target_idx))
            return
        end
    end

    -- 6. Skip & Ready: InvokeServer("Voting", "Skip")
    if a1 == "Voting" and a2 == "Skip" then
        local stateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
        local gsr = stateReps and stateReps:FindFirstChild("GameStateReplicator")
        local curWave = gsr and gsr:GetAttribute("Wave") or 0
        if curWave == 0 then
            if not hasRecordedReadyThisMatch then
                hasRecordedReadyThisMatch = true
                appendRecordActionLine("TDS:Ready()", "Readied up for match")
            end
        else
            if lastRecordedSkipWave ~= curWave then
                lastRecordedSkipWave = curWave
                appendRecordActionLine(string.format("TDS:VoteSkip(%d)", curWave), "Voted to skip wave " .. curWave)
            end
        end
        return
    end
end

-- Namecall metamethod hook
if type(hookmetamethod) == "function" and not (getgenv and getgenv().__tds_recorder_namecall_hooked) then
    if getgenv then getgenv().__tds_recorder_namecall_hooked = true end
    local originalNamecall
    originalNamecall = hookmetamethod(game, "__namecall", function(self, ...)
        local method = getnamecallmethod and getnamecallmethod() or nil
        local args = {...}
        local results = table.pack(originalNamecall(self, ...))
        if autoPlayRecordingActive and (method == "InvokeServer" or method == "FireServer") then
            task.spawn(function()
                local set_id = setthreadidentity or setidentity or setthreadcontext
                if set_id then pcall(set_id, 8) end
                pcall(handleRecordedRemoteCall, self, method, args, results)
            end)
        end
        return table.unpack(results, 1, results.n)
    end)
end

-- Fallback instance-level InvokeServer hook on RemoteFunction
task.spawn(function()
    pcall(function()
        if type(hookfunction) == "function" and not (getgenv and getgenv().__tds_recorder_rf_hooked) then
            local testRf = Instance.new("RemoteFunction")
            local rawInvoke = testRf.InvokeServer
            testRf:Destroy()
            if type(rawInvoke) == "function" then
                if getgenv then getgenv().__tds_recorder_rf_hooked = true end
                local origRfInvoke
                origRfInvoke = hookfunction(rawInvoke, function(self, ...)
                    local args = {...}
                    local results = table.pack(origRfInvoke(self, ...))
                    if autoPlayRecordingActive then
                        task.spawn(function()
                            pcall(handleRecordedRemoteCall, self, "InvokeServer", args, results)
                        end)
                    end
                    return table.unpack(results, 1, results.n)
                end)
            end
        end
    end)
end)

-- Strategy recording method hook
strategyRecordingSetup = function(targetTDS)
    local activeTDS = targetTDS or TDS or shared.TDSTable or (getgenv and getgenv().TDS) or _G.TDS
    if not activeTDS or type(activeTDS) ~= "table" then return end

    local recordableMethods = {
        "Mode", "Place", "Upgrade", "SetTarget", "Sell", "SellAll", "Ability", "SetOption", "MedicSelect", "MedicChain", "Ready", "VoteSkip", "WaitForWave", "UnlockTimeScale", "TimeScale"
    }

    for _, methodName in ipairs(recordableMethods) do
        if typeof(activeTDS[methodName]) == "function" and not hookedTDSMethods[methodName] then
            local origMethod = activeTDS[methodName]
            hookedTDSMethods[methodName] = origMethod

            activeTDS[methodName] = function(self, ...)
                if autoPlayRecordingActive and not (Globals and Globals.tdsReplaying) then
                    local args = {...}
                    local stringified = {}
                    for _, arg in ipairs(args) do
                        table.insert(stringified, serializeRecordArgument(arg))
                    end

                    if methodName == "Mode" then
                        table.clear(executed_actions)
                    elseif methodName == "VoteSkip" then
                        local targetWave = tonumber(args[1])
                        if not targetWave then
                            local stateReps = ReplicatedStorage:FindFirstChild("StateReplicators")
                            local gsr = stateReps and stateReps:FindFirstChild("GameStateReplicator")
                            targetWave = gsr and gsr:GetAttribute("Wave") or 0
                        end
                        if lastRecordedSkipWave ~= targetWave then
                            lastRecordedSkipWave = targetWave
                            local actionString = string.format("TDS:VoteSkip(%d)", targetWave)
                            appendRecordActionLine(actionString, string.format("TDS:VoteSkip(%d)", targetWave))
                        end
                    elseif methodName == "Ready" then
                        if not hasRecordedReadyThisMatch then
                            hasRecordedReadyThisMatch = true
                            appendRecordActionLine("TDS:Ready()", "TDS:Ready()")
                        end
                    else
                        local actionString = string.format("TDS:%s(%s)", methodName, table.concat(stringified, ", "))
                        appendRecordActionLine(actionString, string.format("TDS:%s(%s)", methodName, table.concat(stringified, ", ")))
                    end
                end

                if methodName == "VoteSkip" then
                    local isSkipEnabled = (Globals and Globals.AutoSkip == true)
                        or (getgenv and getgenv().AutoSkip == true)
                    if not isSkipEnabled then
                        return false
                    end
                end

                isTdsMethodCalling = true
                local res = table.pack(pcall(origMethod, self, ...))
                isTdsMethodCalling = false

                if res[1] == true then
                    return table.unpack(res, 2, res.n)
                else
                    error(res[2])
                end
            end
        end
    end
end

strategyRecordingSetup()

Window:Line()

-- =============================================================================
-- LIBRARY TAB (STRATEGY LIBRARY VAULT)
-- =============================================================================
local function getSavedRecordedStrategyItems()
    ensureSavedRecordedFolder()
    local items = {}
    local files = {}
    pcall(function()
        if typeof(listfiles) == "function" then
            local rawFiles = listfiles("[SavedRecorded]")
            if type(rawFiles) == "table" then
                for _, path in ipairs(rawFiles) do
                    local cleanName = tostring(path):match("([^/\\]+)$") or tostring(path)
                    if cleanName ~= "" and (cleanName:sub(-4) == ".txt" or cleanName:sub(-4) == ".lua") then
                        table.insert(files, { Name = cleanName, Path = path })
                    end
                end
            end
        end
    end)

    if #files == 0 then
        pcall(function()
            if typeof(isfile) == "function" and isfile("[SavedRecorded]/Strat.txt") then
                table.insert(files, { Name = "Strat.txt", Path = "[SavedRecorded]/Strat.txt" })
            elseif typeof(isfile) == "function" and isfile("Strat.txt") then
                table.insert(files, { Name = "Strat.txt", Path = "Strat.txt" })
            end
        end)
    end

    for _, f in ipairs(files) do
        local mode = "?"
        local map = "?"
        local isPremium = false
        pcall(function()
            if typeof(readfile) == "function" and typeof(isfile) == "function" and isfile(f.Path) then
                local content = readfile(f.Path)
                if content and #content > 0 then
                    local m = content:match('["\']?Mode["\']?%s*[:=]%s*["\']([^"\']+)["\']')
                        or content:match('TDS:Mode%(%s*["\']([^"\']+)["\']')
                        or content:match('["\']?Difficulty["\']?%s*[:=]%s*["\']([^"\']+)["\']')
                        or content:match('%-%-%s*[Mm]ode%s*:%s*([%w%s]+)')
                    if m and m ~= "" then
                        mode = m:gsub("^%s+", ""):gsub("%s+$", "")
                    end

                    local mp = content:match('TDS:GameInfo%(%s*["\']([^"\']+)["\']')
                        or content:match('TDS:Map%(%s*["\']([^"\']+)["\']')
                        or content:match('["\']?Map["\']?%s*[:=]%s*["\']([^"\']+)["\']')
                        or content:match('%-%-%s*[Mm]ap%s*:%s*([%w%s]+)')
                    if mp and mp ~= "" then
                        map = mp:gsub("^%s+", ""):gsub("%s+$", "")
                    end

                    if content:match('TDS:Place%s*%([^%)]*,%s*true%s*%)')
                        or content:match('TDS:Ability%s*%([^%)]*,%s*true%s*,%s*true%s*%)')
                        or content:match('TDS:Mode%s*%(%s*["\'][^"\']+["\']%s*,%s*true')
                        or content:match('TDS:GameInfo%s*%(%s*["\'][^"\']+["\']%s*,%s*true')
                        or content:match('TDS:GameInfo%s*%(%s*["\'][^"\']+["\']%s*,%s*[^,%)]*,%s*true')
                        or content:match('TDS:Map%s*%(%s*["\'][^"\']+["\']%s*,%s*true')
                        or content:match('TDS:Loadout%s*%([^%)]*,%s*true')
                        or content:match('["\']?Mode["\']?%s*[:=]%s*["\'][^"\']+["\']%s*,%s*true')
                        or content:match('["\']?Premium["\']?%s*[:=]%s*true')
                        or content:match('[Pp]remium%s*=%s*true')
                        or content:match('%-%-%s*[Pp]remium') then
                        isPremium = true
                    end
                end
            end
        end)
        table.insert(items, {
            Name = f.Name,
            Mode = mode,
            Map = map,
            IsPremium = isPremium,
            Path = f.Path,
        })
    end

    if #items == 0 then
        table.insert(items, {
            Name = "Strat.txt",
            Mode = "?",
            Path = "[SavedRecorded]/Strat.txt",
        })
    end

    return items
end

local function executeStrategyFile(stratName, optPath, isAuto)
    if not stratName or stratName == "" then return false end

    local currentMatchId = (game.JobId ~= "" and game.JobId) or tostring(game.PlaceInstanceId or "MatchInstance")
    local winExecuted = hasStratExecutedForThisMatch or (Globals and Globals.WinStratExecuted) or (getgenv and (getgenv().WinStratExecuted or getgenv().__WIN_STRAT_EXECUTED_JOB_ID == currentMatchId))
    if winExecuted then
        if Logger and Logger.Warn then Logger:Warn("[executeStrategyFile] Execution blocked: Strategy already executed for this match.") end
        return false
    end

    local possiblePaths = {}
    if optPath and type(optPath) == "string" and optPath ~= "" then
        table.insert(possiblePaths, optPath)
    end

    pcall(function()
        local recordedItems = getSavedRecordedStrategyItems()
        for _, it in ipairs(recordedItems) do
            if it.Name == stratName and it.Path then
                table.insert(possiblePaths, it.Path)
                break
            end
        end
    end)

    table.insert(possiblePaths, "[SavedRecorded]/" .. stratName)
    table.insert(possiblePaths, "[SavedRecorded]\\" .. stratName)
    table.insert(possiblePaths, stratName)
    table.insert(possiblePaths, "workspace/[SavedRecorded]/" .. stratName)
    table.insert(possiblePaths, "workspace/[SavedRecorded]\\" .. stratName)

    local content = nil
    for _, p in ipairs(possiblePaths) do
        if p and typeof(isfile) == "function" and isfile(p) and typeof(readfile) == "function" then
            local c = nil
            pcall(function() c = readfile(p) end)
            if c and #c > 0 then
                content = c
                break
            end
        end
    end

    if not content or content == "" then
        Window:Notify({
            Title = isAuto and "Auto-Execute Error" or "Execute Error",
            Desc = "Strategy file is empty or missing: " .. tostring(stratName),
            Duration = 3,
            Type = "error",
        })
        if Logger and Logger.Error then Logger:Error("Strategy file missing or empty: " .. tostring(stratName)) end
        return false
    end

    -- Premium Strategy Lockout Check
    local isStratPremium = false
    local recordedItems = getSavedRecordedStrategyItems()
    for _, it in ipairs(recordedItems) do
        if it.Name == stratName and it.IsPremium then
            isStratPremium = true
            break
        end
    end
    if not isStratPremium and content then
        if content:match('TDS:Place%s*%([^%)]*,%s*true%s*%)')
            or content:match('TDS:Ability%s*%([^%)]*,%s*true%s*,%s*true%s*%)')
            or content:match('TDS:Mode%s*%(%s*["\'][^"\']+["\']%s*,%s*true')
            or content:match('TDS:GameInfo%s*%(%s*["\'][^"\']+["\']%s*,%s*true')
            or content:match('TDS:GameInfo%s*%(%s*["\'][^"\']+["\']%s*,%s*[^,%)]*,%s*true')
            or content:match('TDS:Map%s*%(%s*["\'][^"\']+["\']%s*,%s*true')
            or content:match('TDS:Loadout%s*%([^%)]*,%s*true')
            or content:match('["\']?Mode["\']?%s*[:=]%s*["\'][^"\']+["\']%s*,%s*true')
            or content:match('["\']?Premium["\']?%s*[:=]%s*true')
            or content:match('[Pp]remium%s*=%s*true')
            or content:match('%-%-%s*[Pp]remium') then
            isStratPremium = true
        end
    end

    if isStratPremium and not checkIsPremium() then
        Window:Notify({
            Title = "Premium Plan Required",
            Desc = "This strategy requires Premium features!",
            Duration = 5,
            Type = "error",
        })
        if Logger and Logger.Warn then Logger:Warn("Execution blocked: Strategy requires Premium plan! Disabling Auto Execute.") end
        Globals.AutoExecuteStrat = false
        SetSetting("AutoExecuteStrat", false)
        if stratManagerRef and typeof(stratManagerRef.SetAutoExecute) == "function" then
            stratManagerRef:SetAutoExecute(false)
        end
        return false
    end

    -- Guard against duplicate launches of the SAME active running strategy
    if currentRunningStratThread and currentRunningStratName == stratName and coroutine.status(currentRunningStratThread) ~= "dead" then
        if Logger and Logger.Info then Logger:Info("[Auto-Exec] Strategy '" .. tostring(stratName) .. "' is already running. Skipping duplicate launch.") end
        return true
    end

    if currentRunningStratThread then
        pcall(task.cancel, currentRunningStratThread)
        currentRunningStratThread = nil
        if Logger and Logger.Info then Logger:Info("Terminated previously running strategy (" .. tostring(currentRunningStratName) .. ") to switch execution.") end
    end

    local activeTDS = TDS or shared.TDSTable or (getgenv and getgenv().TDS) or _G.TDS
    if activeTDS then
        if getgenv then getgenv().TDS = activeTDS end
        _G.TDS = activeTDS
        shared.TDSTable = activeTDS
    end

    currentRunningStratName = stratName
    hasAutoExecutedThisMatch = true
    hasStratExecutedForThisMatch = true
    if Globals then Globals.WinStratExecuted = true end
    if getgenv then
        getgenv().WinStratExecuted = true
        getgenv().__WIN_STRAT_EXECUTED_JOB_ID = currentMatchId
    end

    Window:Notify({
        Title = isAuto and "Auto-Executing Strategy" or "Executing Strategy",
        Desc = (isAuto and "[Auto] " or "") .. "Running " .. tostring(stratName) .. "...",
        Duration = 3,
        Type = "normal",
    })
    if Logger and Logger.Info then Logger:Info((isAuto and "[Auto-Exec]" or "[Manual-Exec]") .. " Launching strategy: " .. tostring(stratName)) end

    currentRunningStratThread = task.spawn(function()
        local func, pErr = loadstring(content, stratName)
        if func then
            local env = getfenv(func)
            if activeTDS then
                env.TDS = activeTDS
            end
            setfenv(func, env)

            local ok, rErr = pcall(func)
            currentRunningStratThread = nil

            if not ok then
                if Logger and Logger.Error then Logger:Error("Strategy execution error: " .. tostring(rErr)) end
                Window:Notify({
                    Title = "Strategy Error",
                    Desc = tostring(rErr),
                    Duration = 4,
                    Type = "error",
                })
            else
                if Logger and Logger.Success then Logger:Success("Strategy completed successfully: " .. tostring(stratName)) end
                Window:Notify({
                    Title = "Strategy Completed",
                    Desc = tostring(stratName) .. " executed successfully.",
                    Duration = 3,
                    Type = "normal",
                })
            end
        else
            currentRunningStratThread = nil
            if Logger and Logger.Error then Logger:Error("Strategy parse error: " .. tostring(pErr)) end
            Window:Notify({
                Title = "Strategy Parse Error",
                Desc = tostring(pErr),
                Duration = 4,
                Type = "error",
            })
        end
    end)

    return true
end

local LibraryTab = Window:Tab({
    Title = "Library",
    Icon = "package",
    Subtitle = "Strategy Library",
})

LibraryTab:Banner({
    Title = "Strategy Library Vault",
    Desc = "Manage, view, and export strategies recorded into your [SavedRecorded] directory.",
    Type = "Info",
})

local LibrarySection = LibraryTab:Section({ Title = "Recorded Strategies" })

local stratItemsInit = getSavedRecordedStrategyItems()
local savedAutoStrat = Globals.selectedStrat or (stratItemsInit[1] and stratItemsInit[1].Name) or "Strat.txt"
selectedStrat = savedAutoStrat
selectedLibraryFile = savedAutoStrat
Globals.selectedStrat = savedAutoStrat
if getgenv then getgenv().selectedStrat = savedAutoStrat end
_G.selectedStrat = savedAutoStrat

stratManagerRef = LibrarySection:StrategyManager({
    Title = "Strategy Manager",
    Height = 180,
    Strats = stratItemsInit,
    Selected = selectedLibraryFile,
    AutoExecute = Globals.AutoExecuteStrat or false,
    AutoExecuteTitle = "Auto Execute on Run",
    ExecuteTitle = "▶ EXECUTE",
    OnSelect = function(item, index)
        selectedStrat = item.Name
        selectedLibraryFile = item.Name
        if getgenv then getgenv().selectedStrat = item.Name end
        _G.selectedStrat = item.Name
        Globals.selectedStrat = item.Name
        SetSetting("selectedStrat", item.Name)
        if Logger and Logger.Info then Logger:Info("Selected strategy: " .. item.Name .. " [Mode: " .. tostring(item.Mode or "?") .. "]") end

        if Globals.AutoExecuteStrat then
            if Logger and Logger.Info then Logger:Info("Auto Execute is ON: Running newly selected strategy -> " .. item.Name) end
            executeStrategyFile(item.Name, item.Path, true)
        end
    end,
    OnDelete = function(item, index)
        local path = item.Path or ("[SavedRecorded]/" .. item.Name)
        pcall(function()
            if typeof(delfile) == "function" and typeof(isfile) == "function" and isfile(path) then
                delfile(path)
            end
        end)
        if stratManagerRef then
            stratManagerRef:RemoveStrat(item.Name)
        end
        Window:Notify({
            Title = "Strategy Deleted",
            Desc = "Successfully removed " .. item.Name,
            Duration = 2.5,
            Type = "warning",
        })
        if Logger and Logger.Warn then Logger:Warn("Deleted strategy file: " .. item.Name) end
    end,
    OnExtract = function(item, index)
        local path = item.Path or ("[SavedRecorded]/" .. item.Name)
        local stratContent = nil
        pcall(function()
            if typeof(readfile) == "function" and typeof(isfile) == "function" and isfile(path) then
                stratContent = readfile(path)
            end
        end)
        if not stratContent or stratContent == "" then
            Window:Notify({
                Title = "Extract Failed",
                Desc = "File is empty or cannot be read: " .. item.Name,
                Duration = 2.5,
                Type = "error",
            })
            return
        end
        local copied = false
        pcall(function()
            if typeof(setclipboard) == "function" then
                setclipboard(stratContent)
                copied = true
            elseif typeof(toclipboard) == "function" then
                toclipboard(stratContent)
                copied = true
            end
        end)
        if copied then
            Window:Notify({
                Title = "Strategy Extracted!",
                Desc = "Copied " .. item.Name .. " (" .. #stratContent .. " chars) to clipboard.",
                Duration = 3,
                Type = "normal",
            })
            if Logger and Logger.Success then Logger:Success("Extracted strategy to clipboard: " .. item.Name) end
        else
            Window:Notify({
                Title = "Clipboard Error",
                Desc = "Executor does not support setclipboard.",
                Duration = 2.5,
            })
        end
    end,
    OnExecute = function(item, index)
        executeStrategyFile(item.Name, item.Path, false)
    end,
    OnAutoExecute = function(val)
        Globals.AutoExecuteStrat = val
        SetSetting("AutoExecuteStrat", val)
        local target = selectedStrat or Globals.selectedStrat
        if Logger and Logger.Info then Logger:Info("Auto Execute Strat on Run: " .. (val and "ENABLED" or "DISABLED")) end
        Window:Notify({
            Title = "Auto Execute Strat",
            Desc = val and ("Strategy will run automatically on match start (" .. (target or "selected") .. ")")
                or "Auto strategy execution disabled.",
            Duration = 2.5,
            Type = val and "normal" or "warning",
        })
        if val and target and target ~= "" and GameState == "GAME" then
            executeStrategyFile(target, nil, true)
        end
    end,
})

-- Auto-execute immediately upon running if in GAME and AutoExecuteStrat is ON
task.spawn(function()
    task.wait(1.5)
    if GameState == "GAME" and Globals.AutoExecuteStrat then
        local target = selectedStrat or Globals.selectedStrat
        if target and target ~= "" then
            if Logger and Logger.Info then Logger:Info("[Auto Execute] Launching selected strategy: " .. tostring(target)) end
            executeStrategyFile(target, nil, true)
        end
    end
end)

LibrarySection:Button({
    Title = "Refresh Strategy Library",
    Desc = "Rescans [SavedRecorded] directory and refreshes all strategy files & modes",
    Image = "Button",
    Callback = function()
        local updated = getSavedRecordedStrategyItems()
        if stratManagerRef then
            stratManagerRef:SetStrats(updated)
        end
        Window:Notify({
            Title = "Library Refreshed",
            Desc = string.format("Found %d recorded strategy file(s).", #updated),
            Duration = 2,
        })
        if Logger and Logger.Info then Logger:Info("Library scanned: " .. #updated .. " strategy files available.") end
    end,
})
end

Window:Line()



-- =============================================================================
-- PRODUCT TAB (Tier Plans & Key Activation)
-- =============================================================================
do
    local ProductTab = Window:Tab({
        Title = "Product",
        Icon = "key",
        Subtitle = "Tier Plans & Features",
    })

    ProductTab:Banner({
        Title = "Hub Licensing & Subscription Tiers",
        Desc = "Explore available tiers or activate a key below to unlock accelerated bypasses.",
        Type = "Info",
    })

    local isPremProduct = checkIsPremium()

    ProductTab:SelectionBox({
        Selections = { "Free", "Premium" },
        Descriptions = {
            Free = "Community Edition",
            Premium = "VIP Access (Full)",
        },
        Checklist = {
            Free = {
                "Standard Molten & Fallen farming (Lose Mode)",
                "Hardcore Gem cycling (Lose Mode)",
                "Standard EXP Leveling routines",
                "Basic Auto Trials (Wait for rotation)",
                "Community Discord support access",
            },
            Premium = {
                "Full Auto Evolution farming (Auto Evo)",
                "Molten & Fallen Win Condition farming (Win Mode)",
                "Auto Timescales ticket farming with Fallbacks",
                "Trials to Ignore custom filter (Skip unwanted modifiers)",
                "Dedicated Dual-Tower Loadout auto-equipping",
                "Rich Discord Webhook alerts & match session logs",
                "Target milestone watchdog & in-place retry",
            },
        },
        ButtonTexts = {
            Free = isPremProduct and "Included" or "Current Tier Active",
            Premium = isPremProduct and "Current Tier Active" or "Activate Key Below",
        },
        Callbacks = {
            Free = function()
                Window:Notify({
                    Title = "Free Tier",
                    Desc = checkIsPremium() and "You currently have Premium active." or "You are currently running the Free Community Tier.",
                    Duration = 2.5,
                })
            end,
            Premium = function()
                Window:Notify({
                    Title = checkIsPremium() and "Premium Active" or "Premium Key Required",
                    Desc = checkIsPremium() and "Premium VIP is active on this account." or "Please enter your license key in the activation box below to activate.",
                    Duration = 3,
                })
            end,
        },
    })

    local ProductLicense = ProductTab:Section({ Title = "Key Activation & Verification" })

    local currentTierBanner = ProductLicense:Banner({
        Title = isPremProduct and "Current License Status: Premium VIP (Active)" or "Current License Status: Standard Tier",
        Desc = isPremProduct and "All high-speed routines, bypasses, and uncap limits unlocked!" or "Basic features active. Enter a license key below to unlock VIP / Lifetime.",
        Type = isPremProduct and "Info" or "Warning",
    })

    local enteredLicenseKey = (checkIsPremium() and (loadVerifiedKey() or "PREMIUM-ACTIVE")) or (Globals and Globals.LicenseKey) or ""

    ProductLicense:Textbox({
        Title = "License Key",
        Desc = "Paste your license or promotional key here",
        Placeholder = "SN-XXXX-XXXX-XXXX",
        Value = enteredLicenseKey,
        ClearTextOnFocus = false,
        Callback = function(keyStr)
            enteredLicenseKey = keyStr
            if Globals then Globals.LicenseKey = keyStr end
        end,
    })

    ProductLicense:Button({
        Title = "Redeem & Validate Key",
        Desc = "Validates the entered key and applies unlocked features",
        Image = "Check",
        Callback = function()
            local rawKey = enteredLicenseKey or ""
            local key = string.gsub(rawKey, "%s+", "")
            if #key < 4 then
                Window:Notify({
                    Title = "Activation Failed",
                    Desc = "Please enter a valid license key.",
                    Duration = 2.5,
                })
                return
            end

            Window:Notify({
                Title = "Verifying Key",
                Desc = "Validating key with Junkie Key System...",
                Duration = 2,
            })

            local Junkie = getJunkieSDK()
            if not Junkie then
                Window:Notify({
                    Title = "Connection Error",
                    Desc = "Unable to connect to Junkie authentication service.",
                    Duration = 3,
                })
                return
            end

            local ok, result = pcall(function()
                return Junkie.check_key(key)
            end)

            if ok and result and result.valid then
                saveVerifiedKey(key)
                if getgenv then getgenv().SCRIPT_KEY = key end
                PremiumLoaded = true
                if Globals then
                    Globals.IsPremium = true
                    Globals.LicenseKey = key
                end
                pcall(function()
                    Window:UserProfile({
                        Badge = "PREMIUM VIP",
                        TimeLeft = "Permanent",
                    })
                end)
                pcall(function()
                    currentTierBanner.Title = "Current License Status: Premium VIP (Active)"
                    currentTierBanner.Desc = "All high-speed routines, bypasses, and auto timescales unlocked!"
                end)
                if Logger and Logger.Success then
                    Logger:Success("Junkie Key verified! Unlocked Premium VIP tier.")
                end
                Window:Notify({
                    Title = "License Activated!",
                    Desc = "Welcome to Premium VIP! Key verified successfully.",
                    Duration = 3,
                })
            else
                local failMsg = (result and (result.message or result.error)) or "Invalid key or verification failed."
                Window:Notify({
                    Title = "Activation Failed",
                    Desc = failMsg,
                    Duration = 3,
                })
            end
        end,
    })

    ProductLicense:Button({
        Title = "Get Key",
        Desc = "Copies Junkie key link to clipboard",
        Image = "Link",
        Callback = function()
            local Junkie = getJunkieSDK()
            local link = (Junkie and typeof(Junkie.get_key_link) == "function" and Junkie.get_key_link())
                or "https://jnkie.com"
            if setclipboard then
                setclipboard(link)
                Window:Notify({
                    Title = "Key Link Copied",
                    Desc = "Junkie key link copied to clipboard!",
                    Duration = 3,
                })
            elseif toclipboard then
                toclipboard(link)
                Window:Notify({
                    Title = "Key Link Copied",
                    Desc = "Junkie key link copied to clipboard!",
                    Duration = 3,
                })
            else
                Window:Notify({
                    Title = "Key Link",
                    Desc = link,
                    Duration = 5,
                })
            end
        end,
    })
end

Window:Line()

local Settings = Window:Tab({Title = "Settings", Icon = "settings"}) do
    Settings:Section({Title = "Settings"})
    Settings:Button({
        Title = "Save Settings",
        Callback = function()
            Window:Notify({
                    Title = "ADS",
                    Desc = "Settings Saved!",
                    Time = 3,
                    Type = "normal"
                })
            SaveSettings()
        end
    })

    Settings:Button({
        Title = "Load Settings",
        Callback = function()
            Window:Notify({
                    Title = "ADS",
                    Desc = "Settings Loaded!",
                    Time = 3,
                    Type = "normal"
                })
            LoadSettings()
        end
    })

    Settings:Section({Title = "Privacy"})
    Settings:Toggle({
        Title = "Hide Username",
        Desc = "",
        Value = Globals.HideUsername,
        Callback = function(v)
            SetSetting("HideUsername", v)

            if v then
                UpdatePrivacyState()
            end
        end
    })

    Settings:Textbox({
        Title = "Streamer Name",
        Desc = "",
        Placeholder = "Spoof Name",
        Value = Globals.StreamerName or "",
        ClearTextOnFocus = false,
        Callback = function(value)
            SetSetting("StreamerName", value or "")
            UpdatePrivacyState()
        end
    })

    Settings:Toggle({
        Title = "Streamer Mode",
        Desc = "",
        Value = Globals.StreamerMode,
        Callback = function(v)
            SetSetting("StreamerMode", v)
            UpdatePrivacyState()
        end
    })

    Settings:Section({Title = "Tags"})
    local tagOptions = collectTagOptions()
    local tagValue = Globals.tagName or "None"
    if not table.find(tagOptions, tagValue) then
        tagValue = "None"
    end
    Settings:Dropdown({
        Title = "Tag Changer",
        Desc = "",
        List = tagOptions,
        Value = tagValue,
        Callback = function(choice)
            local selected = choice
            if type(choice) == "table" then
                selected = choice[1]
            end
            if not selected or selected == "" then
                selected = "None"
            end
            SetSetting("tagName", selected)
            if selected == "None" then
                stopTagChanger()
            else
                startTagChanger()
            end
        end
    })

    Settings:Section({Title = "Webhook"})
    Settings:Toggle({
        Title = "Send Webhook",
        Desc = "",
        Value = Globals.SendWebhook,
        Callback = function(v)
            SetSetting("SendWebhook", v)
        end
    })

    Settings:Button({
        Title = "Test Webhook",
        Callback = function()
            if not Globals.WebhookURL or Globals.WebhookURL == "" then
                Window:Notify({Title = "Error", Desc = "Webhook URL is empty!", Time = 3, Type = "error"})
                return
            end

            local success, response = pcall(function()
                return SendRequest({
                    Url = Globals.WebhookURL,
                    Method = "POST",
                    Headers = { ["Content-Type"] = "application/json" },
                    Body = game:GetService("HttpService"):JSONEncode({["content"] = "Webhook Test"})
                })
            end)

            if success and response.StatusCode >= 200 and response.StatusCode < 300 then
                Window:Notify({
                    Title = "ADS",
                    Desc = "Webhook sent successfully and is working!",
                    Time = 3,
                    Type = "normal"
                })
            else
                Window:Notify({
                    Title = "Error",
                    Desc = "Invalid Webhook, Discord returned an error.",
                    Time = 5,
                    Type = "error"
                })
            end
        end
    })

    Settings:Textbox({
        Title = "Webhook URL:",
        Desc = "",
        Placeholder = "https://discord.com/api/webhooks/...",
        Value = Globals.WebhookURL,
        ClearTextOnFocus = true,
        Callback = function(value)
            SetSetting("WebhookURL", value) 

            if value ~= "" and value:find("https://discord.com/api/webhooks/") then
                Window:Notify({
                    Title = "ADS",
                    Desc = "Webhook is successfully set!",
                    Time = 3,
                    Type = "normal"
                })
            end
        end
    })
end

RunService.RenderStepped:Connect(function()
    if StackEnabled then
        if not StackSphere then
            StackSphere = Instance.new("Part")
            StackSphere.Shape = Enum.PartType.Ball
            StackSphere.Size = Vector3.new(1.5, 1.5, 1.5)
            StackSphere.Color = Color3.fromRGB(0, 255, 0)
            StackSphere.Transparency = 0.5
            StackSphere.Anchored = true
            StackSphere.CanCollide = false
            StackSphere.CanTouch = false
            StackSphere.CanQuery = false
            StackSphere.Material = Enum.Material.Neon
            StackSphere.Parent = workspace
            mouse.TargetFilter = workspace:FindFirstChild("Towers") or StackSphere
        end
        local hit = mouse.Hit
        if hit then StackSphere.Position = hit.Position end
    elseif StackSphere then
        StackSphere:Destroy()
        StackSphere = nil
    end

    UpdatePathVisuals()
end)

mouse.Button1Down:Connect(function()
    if StackEnabled and StackSphere and SelectedTower then
        local pos = StackSphere.Position
        local newpos = Vector3.new(pos.X, pos.Y + 25, pos.Z)
        RemoteFunc:InvokeServer("Troops", "Place", {Rotation = CFrame.new(), Position = newpos}, SelectedTower)
    end
end)

-- // currency tracking
local StartCoins, CurrentTotalCoins, StartGems, CurrentTotalGems = 0, 0, 0, 0
if GameState == "GAME" then
    pcall(function()
        repeat task.wait(1) until LocalPlayer:FindFirstChild("Coins")
        StartCoins = LocalPlayer.Coins.Value
        CurrentTotalCoins = StartCoins
        StartGems = LocalPlayer.Gems.Value
        CurrentTotalGems = StartGems
    end)
end

-- // check if remote returned valid
local function CheckResOk(data)
    if data == true then return true end
    if type(data) == "table" and data.Success == true then return true end

    local success, IsModel = pcall(function()
        return data and data:IsA("Model")
    end)

    if success and IsModel then return true end
    if type(data) == "userdata" then return true end

    return false
end

-- // scrap ui for match data
local function GetAllRewards()
    local results = {
        Coins = 0, 
        Gems = 0, 
        XP = 0, 
        Wave = 0,
        Level = 0,
        Time = "00:00",
        Status = "UNKNOWN",
        Others = {} 
    }

    local UiRoot = PlayerGui:FindFirstChild("ReactGameNewRewards")
    local MainFrame = UiRoot and UiRoot:FindFirstChild("Frame")
    local GameOver = MainFrame and MainFrame:FindFirstChild("gameOver")
    local RewardsScreen = GameOver and GameOver:FindFirstChild("RewardsScreen")

    local GameStats = RewardsScreen and RewardsScreen:FindFirstChild("gameStats")
    local StatsList = GameStats and GameStats:FindFirstChild("stats")

    if StatsList then
        for _, frame in ipairs(StatsList:GetChildren()) do
            local l1 = frame:FindFirstChild("textLabel")
            local l2 = frame:FindFirstChild("textLabel2")
            local refLabel = l2 and l2:FindFirstChild("refLabel")
            if l1 and refLabel and l1.Text:find("Time Completed:") then
                results.Time = refLabel.Text
                break
            end
        end
    end

    local TopBanner = RewardsScreen and RewardsScreen:FindFirstChild("RewardBanner")
    if TopBanner and TopBanner:FindFirstChild("textLabel") then
        local txt = TopBanner.textLabel.Text:upper()
        results.Status = txt:find("TRIUMPH") and "WIN" or (txt:find("LOST") and "LOSS" or "UNKNOWN")
    end

    local LevelValue = LocalPlayer.Level
    if LevelValue then
        results.Level = LevelValue.Value or 0
    end

    local label = PlayerGui:WaitForChild("ReactGameTopGameDisplay").Frame.wave.container.value
    local WaveNum = label.Text:match("^(%d+)")

    if WaveNum then
        results.Wave = tonumber(WaveNum) or 0
    end

    local SectionRewards = RewardsScreen and RewardsScreen:FindFirstChild("RewardsSection")
    if SectionRewards then
        for _, item in ipairs(SectionRewards:GetChildren()) do
            if tonumber(item.Name) then 
                local IconId = "0"
                local img = item:FindFirstChildWhichIsA("ImageLabel", true)
                if img then IconId = img.Image:match("%d+") or "0" end

                for _, child in ipairs(item:GetDescendants()) do
                    if child:IsA("TextLabel") then
                        local text = child.Text
                        local amt = tonumber(text:match("(%d+)")) or 0

                        if text:find("Coins") then
                            results.Coins = amt
                        elseif text:find("Gems") then
                            results.Gems = amt
                        elseif text:find("XP") then
                            results.XP = amt
                        elseif text:lower():find("x%d+") then 
                            local displayName = ItemNames[IconId] or "Unknown Item (" .. IconId .. ")"
                            table.insert(results.Others, {Amount = text:match("x%d+"), Name = displayName})
                        end
                    end
                end
            end
        end
    end

    return results
end

-- // rejoining
local function RejoinMatch()

	if Globals.AutoRematch then
        local rematchRemote = ReplicatedStorage:WaitForChild("Network", 5)
            and ReplicatedStorage.Network:WaitForChild("GameManager", 5)
            and ReplicatedStorage.Network.GameManager:WaitForChild("RE:Rematch", 5)

        if rematchRemote then
            rematchRemote:FireServer()
            if Logger then
                Logger:Log("Auto-Rematch fired via RE:Rematch!")
            end
        end
        return true
    end
	
    local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunction")
    local success = false
    local res

    local pvCode = (Globals.PrivateCode and Globals.PrivateCode ~= "" and Globals.PrivateCode) 
        or (typeof(getgenv) == "function" and getgenv().PrivateCode)
        or _G.PrivateCode
    if pvCode and pvCode ~= "" then
        Logger:Log("Private server code detected. Returning to private lobby...")
        SmartTeleportToLobby()
        task.wait(9e9)
        return
    end

    repeat
        local StateFolder = ReplicatedStorage:FindFirstChild("State")
        local CurrentMode = StateFolder and StateFolder.Difficulty.Value
        if not CurrentMode or CurrentMode == "" then
            CurrentMode = TDS.SavedDifficulty
        end

        if CurrentMode and CurrentMode ~= "" then
            local ok, result = pcall(function()
                local payload
                local EventMode = StateFolder:FindFirstChild("Mode") and StateFolder.Mode.Value

                if CurrentMode == "PizzaParty" then
                    payload = {
                        mode = "halloween",
                        count = 1
                    }
                elseif tostring(EventMode or ""):lower() == "hardcore" then
                    payload = {
                        difficulty = CurrentMode,
                        mode = "hardcore",
                        count = 1
                    }
                elseif CurrentMode == "PollutedWasteland" then
                    payload = {
                        mode = "polluted",
                        count = 1
                    }
                elseif CurrentMode == "Badlands" then
                    payload = {
                        mode = "badlands",
                        count = 1
                    }
                elseif EventMode == "DuckEvent" then
                    payload = {
                        difficulty = CurrentMode,
                        mode = "ducky2025",
                        count = 1
                    }
                elseif CurrentMode == "Trial" then
                    payload = {
                        mode = "Trials",
                        count = 1
                    }
                else
                    payload = {
                        difficulty = CurrentMode,
                        mode = "survival",
                        count = 1
                    }
                end

                return remote:InvokeServer("Multiplayer", "v2:start", payload)
            end)

            if ok and CheckResOk(result) then
                success = true
                res = result
            else
                task.wait(0.5) 
            end
        else
            task.wait(1)
        end
    until success

    return res
end

local function HandlePostMatch(skipRejoin)
    local UiRoot
    repeat
        task.wait(1)

        local root = PlayerGui:FindFirstChild("ReactGameNewRewards")
        local frame = root and root:FindFirstChild("Frame")
        local gameOver = frame and frame:FindFirstChild("gameOver")
        local RewardsScreen = gameOver and gameOver:FindFirstChild("RewardsScreen")
        UiRoot = RewardsScreen and RewardsScreen:FindFirstChild("RewardsSection")
    until UiRoot

    if not UiRoot then 
        if not skipRejoin then
            RejoinMatch() 
        end
        return
    end
    if not Globals.AutoRejoin and not Globals.AutoRestart and not Globals.AutoRematch then return end

    if not Globals.SendWebhook then
        if not skipRejoin then
            RejoinMatch()
        end
        return
    end

    task.wait(1)

    local match = GetAllRewards()

    CurrentTotalCoins += match.Coins
    CurrentTotalGems += match.Gems

    local BonusString = ""
    if #match.Others > 0 then
        for _, res in ipairs(match.Others) do
            BonusString = BonusString .. "🎁 **" .. res.Amount .. " " .. res.Name .. "**\n"
        end
    else
        BonusString = "_No bonus rewards found._"
    end

    local PostData = {
        username = "TDS AutoStrat",
        embeds = {{
            title = (match.Status == "WIN" and "🏆 TRIUMPH" or "💀 DEFEAT"),
            color = (match.Status == "WIN" and 0x2ecc71 or 0xe74c3c),
            description =
                "### 📋 Match Overview\n" ..
                "> **Status:** `" .. match.Status .. "`\n" ..
                "> **Time:** `" .. match.Time .. "`\n" ..
                "> **Current Level:** `" .. match.Level .. "`\n" ..
                "> **Wave:** `" .. match.Wave .. "`\n",

            fields = {
                {
                    name = "✨ Rewards",
                    value = "```ansi\n" ..
                            "[2;33mCoins:[0m +" .. match.Coins .. "\n" ..
                            "[2;34mGems: [0m +" .. match.Gems .. "\n" ..
                            "[2;32mXP:   [0m +" .. match.XP .. "```",
                    inline = false
                },
                {
                    name = "🎁 Bonus Items",
                    value = BonusString,
                    inline = true
                },
                {
                    name = "📊 Session Totals",
                    value = "```py\n# Total Amount\nCoins: " .. CurrentTotalCoins .. "\nGems:  " .. CurrentTotalGems .. "```",
                    inline = true
                }
            },
            footer = { text = "Logged for " .. LocalPlayer.Name .. " • TDS AutoStrat" },
            timestamp = DateTime.now():ToIsoDate()
        }}
    }

    pcall(function()
        SendRequest({
            Url = Globals.WebhookURL,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = game:GetService("HttpService"):JSONEncode(PostData)
        })
    end)

    task.wait(1.5)

    if not skipRejoin then
        RejoinMatch()
    end

    task.wait(9e9)
end

local function MatchReadyUp()
    local stateReplicators = ReplicatedStorage:WaitForChild("StateReplicators")
    local voteReplicator = stateReplicators:WaitForChild("VoteReplicator")
    local gameStateReplicator = stateReplicators:WaitForChild("GameStateReplicator")

    if gameStateReplicator:GetAttribute("GameStarted") == true then
        return
    end
    
    local voteTitle = voteReplicator:GetAttribute("Title")
    if voteTitle == "Ready?" and voteReplicator:GetAttribute("Enabled") == true then
        RunVoteSkip()
        return
    end

    local yieldSignal = Instance.new("BindableEvent")
    local voteConnection
    local gameStartedConnection

    voteConnection = voteReplicator.AttributeChanged:Connect(function(attributeName)
        if attributeName == "Enabled" and voteReplicator:GetAttribute("Enabled") == true then
            if voteReplicator:GetAttribute("Title") == "Ready?" then
                RunVoteSkip()
                yieldSignal:Fire()
            end
        elseif attributeName == "Title" and voteReplicator:GetAttribute("Title") ~= "Ready?" then
            yieldSignal:Fire()
        elseif attributeName == "VoteCount" or attributeName == "MaxVotes" then
            local currentVotes = voteReplicator:GetAttribute("VoteCount")
            local maxVotesRequired = voteReplicator:GetAttribute("MaxVotes")
            if currentVotes and maxVotesRequired and maxVotesRequired > 0 and currentVotes >= maxVotesRequired then
                yieldSignal:Fire()
            end
        end
    end)

    gameStartedConnection = gameStateReplicator:GetAttributeChangedSignal("GameStarted"):Connect(function()
        if gameStateReplicator:GetAttribute("GameStarted") == true then
            yieldSignal:Fire()
        end
    end)

    yieldSignal.Event:Wait()

    if voteConnection then
        voteConnection:Disconnect()
    end
    if gameStartedConnection then
        gameStartedConnection:Disconnect()
    end
    yieldSignal:Destroy()
end

local function CastMapVote(MapId, PosVec)
    local TargetMap = MapId or "Simplicity"
    local TargetPos = PosVec or Vector3.new(0,0,0)
    RemoteEvent:FireServer("LobbyVoting", "Vote", TargetMap, TargetPos)
    Logger:Log("Cast map vote: " .. TargetMap)
end

local function LobbyReadyUp()
    pcall(function()
        RemoteEvent:FireServer("LobbyVoting", "Ready")
        Logger:Log("Lobby ready up sent")
    end)
end

local function SelectMapOverride(MapId, ...)
    local args = {...}

    if args[#args] == "vip" then
        RemoteFunc:InvokeServer("LobbyVoting", "Override", MapId)
    end

    task.wait(3)
    CastMapVote(MapId, Vector3.new(12.59, 10.64, 52.01))
    task.wait(1)
    LobbyReadyUp()
end

local function CastModifierVote(ModsTable)
    local BulkModifiers = ReplicatedStorage:WaitForChild("Network"):WaitForChild("Modifiers"):WaitForChild("RF:BulkVoteModifiers")
    local ModRep = ReplicatedStorage:WaitForChild("StateReplicators"):FindFirstChild("ModifierReplicator")

    local Available = {}
    if ModRep then
        local raw = ModRep:GetAttribute("Available")
        if type(raw) == "string" then
            local clean = raw:match("{.+}")
            if clean then
                pcall(function()
                    Available = HttpService:JSONDecode(clean)
                end)
            end
        end
    end

    local SelectedMods = {}
    local missingMods = {}

    if ModsTable then
        for k, v in pairs(ModsTable) do
            local modName = type(k) == "string" and k or v
            
            if type(modName) == "string" then
                if Available[modName] == true then
                    SelectedMods[modName] = true
                else
                    table.insert(missingMods, modName)
                end
            end
        end
    end

    if #missingMods > 0 then
        Window:Notify({
            Title = "ADS",
            Desc = "Locked (Skipped) modifiers: " .. table.concat(missingMods, ", "),
            Time = 50,
            Type = "error"
        })
    end

    if next(SelectedMods) then
        pcall(function()
            BulkModifiers:InvokeServer(SelectedMods)
            Logger:Log("Successfully casted modifier votes.")
        end)
    end
end

local function IsMapAvailable(name)
    for _, g in ipairs(workspace:GetDescendants()) do
        if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
            local t = g:FindFirstChild("Title")
            if t and t.Text == name then return true end
        end
    end

    local hasVoted = false

    repeat
        local IntermissionFrame = PlayerGui:WaitForChild("ReactGameIntermission"):WaitForChild("Frame")
        local VetoValue = IntermissionFrame.buttons.veto.value
        local VetoText = VetoValue.Text
        
        if VetoText ~= "" then
            if not VetoText:find("Veto") then
                return false 
            end

            local currentStr, totalStr = VetoText:match("(%d+)/(%d+)")
            local current, total = tonumber(currentStr), tonumber(totalStr)

            if not hasVoted and total and total > 0 and current == 0 then
                RemoteEvent:FireServer("LobbyVoting", "Veto")
                hasVoted = true
            end
        end

        local found = false
        for _, g in ipairs(workspace:GetDescendants()) do
            if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
                local t = g:FindFirstChild("Title")
                if t and t.Text == name then
                    found = true
                    break
                end
            end
        end

        task.wait(1)

        local TotalPlayer = #Players:GetChildren()
        local isFull = VetoText == "Veto ("..TotalPlayer.."/"..TotalPlayer..")"

    until found or isFull

    for _, g in ipairs(workspace:GetDescendants()) do
        if g:IsA("SurfaceGui") and g.Name == "MapDisplay" then
            local t = g:FindFirstChild("Title")
            if t and t.Text == name then return true end
        end
    end

    return false
end

-- // timescale logic
local function SetGameTimescale(TargetVal)
    if GameState ~= "GAME" then 
        return 
    end

    local SpeedList = {0, 0.5, 1, 1.5, 2}

    local TargetIdx
    for i, v in ipairs(SpeedList) do
        if v == TargetVal then
            TargetIdx = i
            break
        end
    end

    if not TargetIdx then
        return
    end

    local SpeedLabel =
        LocalPlayer.PlayerGui.ReactUniversalHotbar.Frame.timescale.Speed

    local CurrentVal = tonumber(SpeedLabel.Text:match("x([%d%.]+)"))
    if not CurrentVal then
        return
    end

    local CurrentIdx
    for i, v in ipairs(SpeedList) do
        if v == CurrentVal then
            CurrentIdx = i
            break
        end
    end

    if not CurrentIdx then
        return
    end

    local diff = TargetIdx - CurrentIdx

    if diff < 0 then
        diff = #SpeedList + diff
    end

    for _ = 1, diff do
        ReplicatedStorage.RemoteFunction:InvokeServer(
            "TicketsManager",
            "CycleTimeScale"
        )

        task.wait(0.5)
    end
end

local function UnlockSpeedTickets()
    if GameState ~= "GAME" then
        return
    end

    if LocalPlayer.TimescaleTickets.Value >= 1 then
        local TimescaleButton =
            LocalPlayer.PlayerGui.ReactUniversalHotbar.Frame.timescale

        local LockIcon = TimescaleButton:FindFirstChild("Lock")

        if LockIcon and LockIcon.Visible then
            ReplicatedStorage.RemoteFunction:InvokeServer(
                "TicketsManager",
                "UnlockTimeScale"
            )

            Logger:Log("Unlocked timescale tickets")
        end
    else
        Logger:Log("No timescale tickets left")
    end
end

ApplyTimeScaleOnce = function()
    if not Globals.TimeScaleEnabled then
        return
    end

    local stateReplicators = ReplicatedStorage:FindFirstChild("StateReplicators")
    local gameStateReplicator = stateReplicators and stateReplicators:FindFirstChild("GameStateReplicator")

    if not gameStateReplicator then
        return
    end

    if gameStateReplicator:GetAttribute("GameStarted") ~= true then
        return
    end

    local frame = GetTimescaleFrame()

    if not frame or not frame.Visible then
        return
    end

    local desired = CoerceTimeScaleValue(
        Globals.TimeScaleValue,
        2
    )

    if not desired then
        return
    end

    local lock = frame:FindFirstChild("Lock")

    if lock and lock.Visible then
        if LocalPlayer.TimescaleTickets.Value < 1 then
            if not TimeScaleNoTicketsWarned then
                Logger:Log("No timescale tickets left")
                TimeScaleNoTicketsWarned = true
            end

            return
        end

        UnlockSpeedTickets()
        task.wait(0.4)
    else
        TimeScaleNoTicketsWarned = false
    end

    SetGameTimescale(desired)
end

StartTimeScale = function()
    if TimeScaleRunning or not Globals.TimeScaleEnabled then
        return
    end

    TimeScaleRunning = true

    task.spawn(function()
        while Globals.TimeScaleEnabled do
            ApplyTimeScaleOnce()
            task.wait(3)
        end

        TimeScaleNoTicketsWarned = false
        TimeScaleRunning = false
    end)
end

-- // ingame control
local function TriggerRestart()
    local UiRoot = PlayerGui:WaitForChild("ReactGameNewRewards")
    local FoundSection = false

    repeat
        task.wait(0.3)
        local f = UiRoot:FindFirstChild("Frame")
        local g = f and f:FindFirstChild("gameOver")
        local s = g and g:FindFirstChild("RewardsScreen")
        if s and s:FindFirstChild("RewardsSection") then
            FoundSection = true
        end
    until FoundSection

    task.wait(3)
    RunVoteSkip()
end

local function GetCurrentWave()
    local label

    repeat
        task.wait(0.5)
        label = PlayerGui:FindFirstChild("ReactGameTopGameDisplay", true) 
            and PlayerGui.ReactGameTopGameDisplay.Frame.wave.container:FindFirstChild("value")
    until label ~= nil

    local text = label.Text
    local WaveNum = text:match("(%d+)")

    return tonumber(WaveNum) or 0
end

local function DoPlaceTower(TName, TPos)
    local retries = 0
    while true do
        local ok, res = pcall(function()
            return RemoteFunc:InvokeServer("Troops", "Place", {
                Rotation = CFrame.new(),
                Position = TPos
            }, TName)
        end)
 
        if ok and CheckResOk(res) then return true end
        retries = retries + 1
        task.wait(0.25)
    end
end

local function DoUpgradeTower(TObj, PathId)
    while true do
        local ok, res = pcall(function()
            return RemoteFunc:InvokeServer("Troops", "Upgrade", "Set", {
                Troop = TObj,
                Path = PathId
            })
        end)
        if ok and CheckResOk(res) then return true end
        task.wait(0.25)
    end
end

local function DoSellTower(TObj)
    while true do
        local ok, res = pcall(function()
            return RemoteFunc:InvokeServer("Troops", "Sell", { Troop = TObj })
        end)
        if ok and CheckResOk(res) then return true end
        task.wait(0.25)
    end
end

local function DoSetOption(TObj, OptName, OptVal, ReqWave)
    if ReqWave then
        repeat task.wait(0.3) until GetCurrentWave() >= ReqWave
    end

    while true do
        local ok, res = pcall(function()
            return RemoteFunc:InvokeServer("Troops", "Option", "Set", {
                Troop = TObj,
                Name = OptName,
                Value = OptVal
            })
        end)
        if ok and CheckResOk(res) then return true end
        task.wait(0.25)
    end
end

local function DoActivateAbility(TObj, AbName, AbData, IsLooping)
    if type(AbData) == "boolean" then
        IsLooping = AbData
        AbData = nil
    end

    AbData = type(AbData) == "table" and AbData or nil

    local positions
    if AbData and type(AbData.towerPosition) == "table" then
        positions = AbData.towerPosition
    end

    local CloneIdx = AbData and AbData.towerToClone
    local TargetIdx = AbData and AbData.towerTarget

    local function attempt()
        while true do
            local ok, res = pcall(function()
                local data

                if AbData then
                    data = table.clone(AbData)

                    if positions and #positions > 0 then
                        data.towerPosition = positions[math.random(#positions)]
                    end

                    if type(CloneIdx) == "number" then
                        data.towerToClone = TDS.PlacedTowers[CloneIdx]
                    end

                    if type(TargetIdx) == "number" then
                        data.towerTarget = TDS.PlacedTowers[TargetIdx]
                    end
                end

                return RemoteFunc:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    {
                        Troop = TObj,
                        Name = AbName,
                        Data = data
                    }
                )
            end)

            if ok and CheckResOk(res) then
                return true
            end

            task.wait(0.25)
        end
    end

    if IsLooping then
        local active = true
        task.spawn(function()
            while active do
                attempt()
                task.wait(1)
            end
        end)
        return function() active = false end
    end

    return attempt()
end

-- // public api
-- lobby
function TDS:Mode(difficulty, code)
    self.SavedDifficulty = difficulty
    local targetCode = ""

    if code and code ~= "" then
        targetCode = code
    elseif Globals.PrivateCode and Globals.PrivateCode ~= "" then
        targetCode = Globals.PrivateCode
    elseif typeof(getgenv) == "function" and getgenv().PrivateCode and getgenv().PrivateCode ~= "" then
        targetCode = getgenv().PrivateCode
    elseif _G.PrivateCode and _G.PrivateCode ~= "" then
        targetCode = _G.PrivateCode
    end

    self.PrivateCode = tostring(targetCode)

    if GameState ~= "LOBBY" then 
        return false 
    end

    if targetCode ~= "" and not MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, 10518590) then
        local ServerType = "Standard"
        pcall(function()
            ServerType = game:GetService('RobloxReplicatedStorage').GetServerType:InvokeServer()
        end)
        
        if ServerType ~= "VIPServer" then
            local ok = launchOrTeleportPrivateServer(game.PlaceId, targetCode, LocalPlayer)
            if ok then
                return true
            end
        end
    end

    if difficulty == "Trial" then
        local success = pcall(function()
            RemoteFunc:InvokeServer(
                "Multiplayer",
                "v2:start",
                {
                    count = 1,
                    mode = "Trials"
                }
            )
        end)
        
        return success
    end

    local LobbyHud = PlayerGui:WaitForChild("ReactLobbyHud", 30)
    local frame = LobbyHud and LobbyHud:WaitForChild("Frame", 30)
    local MatchMaking = frame and frame:WaitForChild("matchmaking", 30)

    if MatchMaking then
        local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteFunction")
        local success = false
        repeat
            local ok, result = pcall(function()
                local mode = TDS.MatchmakingMap[difficulty]
                local payload

                if difficulty == "Hardcore" then
                    payload = {
                        mode = "hardcore",
                        difficulty = "Easy",
                        count = 1
                    }
                elseif difficulty == "Voidcore" then
                    payload = {
                        mode = "hardcore",
                        difficulty = "Hard",
                        count = 1
                    }
                elseif difficulty == "Act1" then
                    payload = {
                        difficulty = "Act1",
                        night = 1,
                        mode = "halloween2026",
                        count = 1
                    }
                elseif mode then
                    payload = {
                        mode = mode,
                        count = 1
                    }
                    if difficulty:match("Ducky") then
                        payload.difficulty = difficulty:gsub("Ducky", "")
                    end
                else
                    payload = {
                        difficulty = difficulty,
                        mode = "survival",
                        count = 1
                    }
                end

                return remote:InvokeServer("Multiplayer", "v2:start", payload)
            end)

            if ok and CheckResOk(result) then
                success = true
            else
                task.wait(0.5) 
            end
        until success
    end

    return true
end

function TDS:Loadout(...)
    if GameState ~= "GAME" then
        return
    end

    while IsCurrentlyLoading do
        task.wait(0.2)
    end

    IsCurrentlyLoading = true
    IsEquippingLoadout = true
    self.IsEquippingLoadout = true

    local towers = {...}
    local remote = game:GetService("ReplicatedStorage"):WaitForChild("RemoteEvent")
    local StateReplicators = ReplicatedStorage:FindFirstChild("StateReplicators")

    local success = pcall(function()
        local CurrentlyEquipped = {}

        if StateReplicators then
            for _, folder in ipairs(StateReplicators:GetChildren()) do
                if folder.Name == "PlayerReplicator" and folder:GetAttribute("UserId") == LocalPlayer.UserId then
                    local EquippedAttr = folder:GetAttribute("EquippedTowers")
                    if type(EquippedAttr) == "string" then
                        local CleanedJson = EquippedAttr:match("%[.*%]") 
                        local DecodeSuccess, decoded = pcall(function()
                            return HttpService:JSONDecode(CleanedJson)
                        end)

                        if DecodeSuccess and type(decoded) == "table" then
                            CurrentlyEquipped = decoded
                        end
                    end
                end
            end
        end

        for _, CurrentTower in ipairs(CurrentlyEquipped) do
            if CurrentTower ~= "None" then
                local UnequipDone = false
                repeat
                    local ok = pcall(function()
                        remote:FireServer("Inventory", "Unequip", "Tower", CurrentTower)
                        task.wait(0.3)
                    end)
                    if ok then UnequipDone = true else task.wait(0.2) end
                until UnequipDone
            end
        end

        task.wait(0.5)

        for _, TowerName in ipairs(towers) do
            if TowerName and TowerName ~= "" then
                local EquipSuccess = false
                repeat
                    local ok = pcall(function()
                        remote:FireServer("Inventory", "Equip", "Tower", TowerName)
                        Logger:Log("Equipped tower: " .. TowerName)
                        task.wait(0.3)
                    end)
                    if ok then EquipSuccess = true else task.wait(0.2) end
                until EquipSuccess
            end
        end

        task.wait(0.5)
    end)

    IsCurrentlyLoading = false
    IsEquippingLoadout = false
    self.IsEquippingLoadout = false
    self.LoadoutPending = false
    LastLoadTime = os.clock()

    return success
end

-- ingame
function TDS:VoteSkip(StartWave, EndWave)
    task.spawn(function()
        local CurrentWave = GetCurrentWave()
        
        self.LastVoteSkipTarget = self.LastVoteSkipTarget or 0
        
        if not StartWave then
            if self.LastVoteSkipTarget < CurrentWave then
                self.LastVoteSkipTarget = CurrentWave
            else
                self.LastVoteSkipTarget = self.LastVoteSkipTarget + 1
            end
            StartWave = self.LastVoteSkipTarget
            EndWave = StartWave
        else
            EndWave = EndWave or StartWave
            self.LastVoteSkipTarget = EndWave
        end

        for wave = StartWave, EndWave do
            while GetCurrentWave() < wave do
                task.wait(1)
            end

            local TargetNextWave = wave + 1
            
            while GetCurrentWave() < TargetNextWave do
                local VoteUi = PlayerGui:FindFirstChild("ReactOverridesVote")
                local VoteButton = VoteUi 
                    and VoteUi:FindFirstChild("Frame") 
                    and VoteUi.Frame:FindFirstChild("votes") 
                    and VoteUi.Frame.votes:FindFirstChild("vote", true)

                if VoteButton and VoteButton.Position == UDim2.new(0.5, 0, 0.5, 0) then
                    pcall(function()
                        RemoteFunc:InvokeServer("Voting", "Skip")
                    end)
                end
                
                task.wait(0.5)
            end
            
            Logger:Log("Successfully skipped wave " .. wave)
        end
    end)
end

function TDS:GameInfo(name, list)
    if GameState ~= "GAME" or name == "Sorrowful Remains" then return false end

    local VoteGui = PlayerGui:WaitForChild("ReactGameIntermission", 30)
    if not (VoteGui and VoteGui.Enabled and VoteGui:WaitForChild("Frame", 5)) then return end

    local modifiers = (list and next(list)) and list or Globals.Modifiers

    CastModifierVote(modifiers)

    local stateReplicators = game:GetService("ReplicatedStorage"):WaitForChild("StateReplicators", 5)
    local gameStateReplicator = stateReplicators and stateReplicators:FindFirstChild("GameStateReplicator")

    if MarketplaceService:UserOwnsGamePassAsync(LocalPlayer.UserId, 10518590) or (gameStateReplicator and gameStateReplicator:GetAttribute("IsPrivateServer") == true) then
        SelectMapOverride(name, "vip")
        Logger:Log("Selected map: " .. name)
        repeat task.wait(1) until PlayerGui:FindFirstChild("ReactUniversalHotbar")
        return true 
    elseif IsMapAvailable(name) then
        SelectMapOverride(name)
        repeat task.wait(1) until PlayerGui:FindFirstChild("ReactUniversalHotbar")
        return true
    else
        Logger:Log("Map '" .. name .. "' not available, rejoining...")
        RejoinMatch()
        repeat task.wait(9999) until false
    end
end

function TDS:UnlockTimeScale()
    UnlockSpeedTickets()
end

function TDS:TimeScale(val)
    SetGameTimescale(val)
end

function TDS:StartGame()
    LobbyReadyUp()
end

function TDS:Ready()
    if GameState ~= "GAME" then
        return false 
    end
    MatchReadyUp()
    return true
end

function TDS:GetWave()
    return GetCurrentWave()
end

function TDS:WaitForWave(targetWave)
    if GameState ~= "GAME" then return false end
    while self:GetWave() < targetWave do
        task.wait(0.5)
    end
    return true
end

function TDS:RestartGame()
    TriggerRestart()
end

function TDS:Place(TName, px, py, pz, ...)
    local args = {...}
    local stack = false
 
    if args[#args] == "stack" or args[#args] == true then
        py = py+25
    end
    if game.PlaceId == 3260590327 then
        return false 
    end
 
    local towersFolder = workspace:FindFirstChild("Towers") or workspace:WaitForChild("Towers", 5)
    local existing = {}
    if towersFolder then
        for _, child in ipairs(towersFolder:GetChildren()) do
            for _, SubChild in ipairs(child:GetChildren()) do
                if SubChild.Name == "Owner" and SubChild.Value == LocalPlayer.UserId then
                    existing[child] = true
                    break
                end
            end
        end
    end
 
    DoPlaceTower(TName, Vector3.new(px, py, pz))
 
    local NewT
    local waitStart = os.time()
    repeat
        local curTowers = workspace:FindFirstChild("Towers")
        if curTowers then
            for _, child in ipairs(curTowers:GetChildren()) do
                if not existing[child] then
                    for _, SubChild in ipairs(child:GetChildren()) do
                        if SubChild.Name == "Owner" and SubChild.Value == LocalPlayer.UserId then
                            NewT = child
                            break
                        end
                    end
                end
                if NewT then break end
            end
        end
        if not NewT then task.wait(0.05) end
    until NewT or (os.time() - waitStart > 10)
 
    if NewT then
        table.insert(self.PlacedTowers, NewT)
    end
    return #self.PlacedTowers
end

function TDS:Upgrade(idx, PId)
    local t = self.PlacedTowers[idx]
    if t then
        DoUpgradeTower(t, PId or 1)
        Logger:Log("Upgrading tower index: " .. idx)
        UpgradeHistory[idx] = (UpgradeHistory[idx] or 0) + 1
    end
end

function TDS:SetTarget(idx, TargetType, ReqWave)
    if ReqWave then
        repeat task.wait(0.5) until GetCurrentWave() >= ReqWave
    end

    local t = self.PlacedTowers[idx]
    if not t then return end

    pcall(function()
        RemoteFunc:InvokeServer("Troops", "Target", "Set", {
            Troop = t,
            Target = TargetType
        })
        Logger:Log("Set target for tower index " .. idx .. " to " .. TargetType)
    end)
end

function TDS:Sell(idx, ReqWave)
    if ReqWave then
        repeat task.wait(0.5) until GetCurrentWave() >= ReqWave
    end
    local t = self.PlacedTowers[idx]
    if t and DoSellTower(t) then
        return true
    end
    return false
end

function TDS:SellAll(ReqWave)
    task.spawn(function()
        if ReqWave then
            repeat task.wait(0.5) until GetCurrentWave() >= ReqWave
        end

        local TowersCopy = {unpack(self.PlacedTowers)}
        for idx, t in ipairs(TowersCopy) do
            if DoSellTower(t) then
                for i, OrigT in ipairs(self.PlacedTowers) do
                    if OrigT == t then
                        table.remove(self.PlacedTowers, i)
                        break
                    end
                end
            end
        end

        return true
    end)
end

function TDS:Ability(idx, name, data, loop)
    local t = self.PlacedTowers[idx]
    if not t then return false end
    Logger:Log("Activating ability '" .. name .. "' for tower index: " .. idx)
    return DoActivateAbility(t, name, data, loop)
end

function TDS:AutoChain(...)
    local TowerIndices = {...}
    if #TowerIndices == 0 then return end

    local running = true

    task.spawn(function()
        local i = 1
        while running do
            local idx = TowerIndices[i]
            local tower = TDS.PlacedTowers[idx]

            if tower then
                DoActivateAbility(tower, "Call Of Arms")
            end

            local hotbar = PlayerGui.ReactUniversalHotbar.Frame
            local timescale = hotbar:FindFirstChild("timescale")

            if timescale then
                if timescale:FindFirstChild("Lock") then
                    task.wait(10.5)
                else
                    task.wait(5.5)
                end
            else
                task.wait(10.5)
            end

            i += 1
            if i > #TowerIndices then
                i = 1
            end
        end
    end)

    return function()
        running = false
    end
end

function TDS:SetOption(idx, name, val, ReqWave)
    local t = self.PlacedTowers[idx]
    if t then
        Logger:Log("Setting option '" .. name .. "' for tower index: " .. idx)
        return DoSetOption(t, name, val, ReqWave)
    end
    return false
end

function TDS:MedicSelect(idx, val)
    local t = self.PlacedTowers[idx]
    local target = self.PlacedTowers[val]
    if t and target then
        Logger:Log("Medic: " .. idx .. " -> " .. val)
        RemoteFunc:InvokeServer("Troops", "TowerServerEvent", "ToggleSelectedTower", t, target)
        return true
    end
    return false
end

local MedicChainAPI

function TDS:MedicChain(...)
    if not MedicChainAPI then
        local loaded = loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/Ceepizz/rya/refs/heads/main/api"
        ))()

        if type(loaded) == "table"
            and type(loaded.MedicChain) == "function" then

            MedicChainAPI = loaded.MedicChain

        elseif type(loaded) == "function" then
            MedicChainAPI = loaded

        else
            warn("[MedicChain] Failed to load API")
            return false
        end
    end

    return MedicChainAPI(self, ...)
end

-- TDS methods hooked by strategyRecordingSetup in Recorder Tab

if GameState == "LOBBY" and Globals.AutoRejoin and isfile("ADS_LastStrat.lua") then
    pcall(delfile, "ADS_LastStrat.lua")
end

if GameState == "GAME" and Globals.AutoRejoin and isfile("ADS_LastStrat.lua") then
    local stratContent = pcall(readfile, "ADS_LastStrat.lua") and readfile("ADS_LastStrat.lua") or ""
    if stratContent:find(":Loadout%(") then
        TDS.LoadoutPending = true
    end
    task.spawn(function()
        task.wait(2)
        TDS:RunStrategy()
    end)
end

-- // misc utility
local function GetRoot()
    local char = LocalPlayer and LocalPlayer.Character
    return char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
end

-- // misc utility
local function IsVoidCharm(obj)
    if not obj then return true end
    local pos
    if obj:IsA("BasePart") then
        pos = obj.Position
    elseif obj:IsA("Model") then
        local ok, cf = pcall(obj.GetPivot, obj)
        pos = ok and cf and cf.Position
    end
    if not pos then return true end
    return math.abs(pos.Y) > 999999
end

local function GetRoot()
    local char = LocalPlayer.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

local function isCollectibleItem(item)
    if not item or not item.Parent then return false end
    if not (item:IsA("MeshPart") or item:IsA("BasePart") or item:IsA("Model")) then return false end
    if IsVoidCharm(item) then return false end

    local name = item.Name
    if name == "Fragment" or name:find("Fragment")
        or name == "Bunz" or name == "Lorebook" or name == "SnowCharm"
        or name == "CandyCorn" or name == "Candy" or name == "Pumpkin"
        or name == "Present" or name == "Gift"
        or name == "Egg" or name == "GoldenEgg" or name == "Golden Egg"
        or name:find("Charm") or name:find("Shard") or name:find("Solar")
        or name:find("Lunar") or name:find("Token") or name:find("Coin")
        or name:find("Drop") or name:find("Pickup") then
        return true
    end

    if item:IsA("MeshPart") or item:IsA("BasePart") or item:IsA("Model") then
        return true
    end

    return false
end

local function getItemCFrameAndPos(item)
    if item:IsA("BasePart") then
        return item.CFrame, item.Position
    elseif item:IsA("Model") then
        local cf = item:GetPivot()
        return cf, cf.Position
    end
    return nil, nil
end

StartAutoPickups = function()
    local isEnabled = Globals and Globals.AutoPickups
    if AutoPickupsRunning or not isEnabled then return end
    AutoPickupsRunning = true

    task.spawn(function()
        while Globals and Globals.AutoPickups do
            local folder = workspace:FindFirstChild("Pickups")
            local hrp = GetRoot()

            if folder and hrp and hrp.Parent then
                local char = hrp.Parent
                local humanoid = char and char:FindFirstChildOfClass("Humanoid")
                local function MoveToPos(TargetPos)
                    if not humanoid or not hrp or not hrp.Parent then
                        return false
                    end
                    local function MoveDirect(pos)
                        humanoid:MoveTo(pos)
                        local StartT = os.clock()
                        while os.clock() - StartT < 2 do
                            if not (Globals and Globals.AutoPickups) then
                                return false
                            end
                            if not hrp or not hrp.Parent then
                                return false
                            end
                            if (hrp.Position - pos).Magnitude < 4 then
                                return true
                            end
                            task.wait(0.1)
                        end
                        return (hrp.Position - pos).Magnitude < 4
                    end
                    local path = PathfindingService:CreatePath({
                        AgentRadius = 2,
                        AgentHeight = 6,
                        AgentCanJump = true,
                        AgentJumpHeight = 7,
                        AgentMaxSlope = 45
                    })
                    local ok = pcall(function()
                        path:ComputeAsync(hrp.Position, TargetPos)
                    end)
                    if ok and path.Status == Enum.PathStatus.Success then
                        local waypoints = path:GetWaypoints()
                        local BlockedConn = nil
                        BlockedConn = path.Blocked:Connect(function()
                            if BlockedConn then
                                BlockedConn:Disconnect()
                                BlockedConn = nil
                            end
                            if Globals and Globals.AutoPickups then
                                task.spawn(function()
                                    MoveToPos(TargetPos)
                                end)
                            end
                        end)
                        for _, wp in ipairs(waypoints) do
                            if not (Globals and Globals.AutoPickups) then
                                if BlockedConn then
                                    BlockedConn:Disconnect()
                                    BlockedConn = nil
                                end
                                return false
                            end
                            if wp.Action == Enum.PathWaypointAction.Jump then
                                humanoid.Jump = true
                            end
                            if not MoveDirect(wp.Position) then
                                if BlockedConn then
                                    BlockedConn:Disconnect()
                                    BlockedConn = nil
                                end
                                return false
                            end
                        end
                        if BlockedConn then
                            BlockedConn:Disconnect()
                            BlockedConn = nil
                        end
                        return true
                    end
                    return MoveDirect(TargetPos)
                end

                local method = (Globals and Globals.PickupMethod) or "Pathfinding"

                for _, item in ipairs(folder:GetChildren()) do
                    if not (Globals and Globals.AutoPickups) then break end

                    if isCollectibleItem(item) then
                        local itemCFrame, itemPos = getItemCFrameAndPos(item)
                        if itemCFrame and itemPos then
                            if method == "Instant" then
                                hrp.CFrame = itemCFrame * CFrame.new(0, 3, 0)
                                task.wait(0.2)
                                task.wait(0.3)
                            else
                                local TargetPos = itemPos + Vector3.new(0, 3, 0)
                                MoveToPos(TargetPos)
                                task.wait(0.2)
                                task.wait(0.3)
                            end
                        end
                    end
                end
            end

            task.wait(1)
        end

        AutoPickupsRunning = false
    end)
end

local function StartAutoGatling()
    if AutoGatlingRunning or not Globals.AutoGatling then return end
    AutoGatlingRunning = true
    task.spawn(function()
        while Globals.AutoGatling do
            if GameState == "GAME" then
                if not GatlingExecuted then
                    GatlingExecuted = true 
                    task.spawn(function()
                        pcall(function()
                            loadstring(game:HttpGet("https://raw.githubusercontent.com/avtryxz/autogutlin/refs/heads/main/autogutlin.lua"))()
                        end)
                    end)
                end
            else
                GatlingExecuted = false 
            end
            task.wait(1)
        end
        AutoGatlingRunning = false
    end)
end

local function StartGatlify()
    if GatlifyRunning or not Globals.Gatlify then return end
    GatlifyRunning = true
    task.spawn(function()
        while Globals.Gatlify do
            if GameState == "GAME" then
                if not GatlifyExecuted then
                    repeat task.wait(0.5) until not IsCurrentlyLoading and not IsEquippingLoadout and not (TDS and TDS.LoadoutPending) and (os.clock() - LastLoadTime >= 5)
                    if not Globals.Gatlify then break end
                    if not GatlifyExecuted then
                        IsCurrentlyLoading = true
                        GatlifyExecuted = true 
                        pcall(function()
                            loadstring(game:HttpGet("https://raw.githubusercontent.com/avtryxz/Gatlify/refs/heads/main/Gatlify.lua"))()
                        end)
                        IsCurrentlyLoading = false
                        LastLoadTime = os.clock()
                    end
                end
            else
                GatlifyExecuted = false 
            end
            task.wait(1)
        end
        GatlifyRunning = false
    end)
end

local function StartAutoPremium()
    if AutoPremiumRunning or not Globals.AutoPremium or PremiumLoaded then return end
    AutoPremiumRunning = true

    task.spawn(function()
        if GameState == "GAME" then
            repeat task.wait(0.5) until not IsCurrentlyLoading and not IsEquippingLoadout and not (TDS and TDS.LoadoutPending) and (os.clock() - LastLoadTime >= 5)
            if not Globals.AutoPremium or PremiumLoaded then
                AutoPremiumRunning = false
                return
            end

            Window:Notify({
                Title = "ADS",
                Desc = "Loading Key System...",
                Time = 3,
                Type = "normal"
            })

            local success = TDS:Addons()
            
            if success then
                Window:Notify({
                    Title = "ADS",
                    Desc = "Premium Unlocked!",
                    Time = 3,
                    Type = "normal"
                })
            else
                task.wait(5)
                AutoPremiumRunning = false 
            end
        else
            AutoPremiumRunning = false
        end
    end)
end

local function StartAutoSkip()
    if AutoSkipRunning or not Globals.AutoSkip then return end
    AutoSkipRunning = true

    task.spawn(function()
        while Globals.AutoSkip do
            local SkipVisible =
                PlayerGui:FindFirstChild("ReactOverridesVote")
                and PlayerGui.ReactOverridesVote:FindFirstChild("Frame")
                and PlayerGui.ReactOverridesVote.Frame:FindFirstChild("votes")
                and PlayerGui.ReactOverridesVote.Frame.votes:FindFirstChild("vote")

            if SkipVisible and SkipVisible.Position == UDim2.new(0.5, 0, 0.5, 0) then
                RunVoteSkip()
            end

            task.wait(0.1)
        end

        AutoSkipRunning = false
    end)
end

local function StartClaimRewards()
    if AutoClaimRewards or not Globals.ClaimRewards or GameState ~= "LOBBY" then 
        return 
    end

    AutoClaimRewards = true

    local player = game:GetService("Players").LocalPlayer
    local network = game:GetService("ReplicatedStorage"):WaitForChild("Network")

    local SpinTickets = player:WaitForChild("SpinTickets", 15)

    if SpinTickets and SpinTickets.Value > 0 then
        local TicketCount = SpinTickets.Value

        local DailySpin = network:WaitForChild("DailySpin", 5)
        local RedeemRemote = DailySpin and DailySpin:WaitForChild("RF:RedeemSpin", 5)

        if RedeemRemote then
            for i = 1, TicketCount do
                RedeemRemote:InvokeServer()
                task.wait(0.5)
            end
        end
    end

    for i = 1, 6 do
        local args = { i }
        network:WaitForChild("PlaytimeRewards"):WaitForChild("RF:ClaimReward"):InvokeServer(unpack(args))
        task.wait(0.5)
    end

    game:GetService("ReplicatedStorage").Network.DailySpin["RF:RedeemReward"]:InvokeServer()
    AutoClaimRewards = false
end

function StartBackToLobby()
    if GameState ~= "GAME" then return end
    if BackToLobbyRunning then return end
    BackToLobbyRunning = true

    task.spawn(function()
        local stateReplicators = ReplicatedStorage:WaitForChild("StateReplicators", 30)
        local gameStateReplicator = stateReplicators and stateReplicators:WaitForChild("GameStateReplicator", 30)
        local voteReplicator = stateReplicators and stateReplicators:WaitForChild("VoteReplicator", 30)
        
        if not gameStateReplicator or not voteReplicator then
            while true do
                pcall(HandlePostMatch)
                task.wait(1)
            end
            return
        end

       while Globals.AutoRejoin or Globals.AutoRestart or Globals.AutoRematch do
            local isGameOver = gameStateReplicator:GetAttribute("GameOver") == true
            if isGameOver then
                local health = gameStateReplicator:GetAttribute("Health") or 0
                if Globals.AutoRematch then
                    -- Sends webhook (if enabled) and fires RE:Rematch inside RejoinMatch()
                    pcall(HandlePostMatch, false)
                    
                    -- Wait for the match to reset if it restarts in the same server
                    repeat task.wait(1) until gameStateReplicator:GetAttribute("GameOver") == false or not Globals.AutoRematch
                    if Globals.AutoRematch and isfile("ADS_LastStrat.lua") then
                        TDS:ResetAllStates()
                        TDS:RunStrategy()
                    end
                elseif health > 0 then
                    if Globals.AutoRejoin then
                        if isfile("ADS_LastStrat.lua") then
                            pcall(delfile, "ADS_LastStrat.lua")
                        end
                        pcall(HandlePostMatch)
                        break
                    end
                else
                    if Globals.AutoRestart then
                        task.spawn(pcall, HandlePostMatch, true)
                        local lastVoteTime = 0
                        while Globals.AutoRestart do
                            local title = voteReplicator:GetAttribute("Title")
                            local enabled = voteReplicator:GetAttribute("Enabled")
                            
                            if enabled == true and title == "Restart?" then
                                if os.clock() - lastVoteTime > 3 then
                                    pcall(function()
                                        RemoteFunc:InvokeServer("Voting", "Skip")
                                    end)
                                    lastVoteTime = os.clock()
                                end
                            end
                            
                            if title == "Ready?" or gameStateReplicator:GetAttribute("GameOver") == false then
                                break
                            end
                            task.wait(0.5)
                        end
                        
                        if not Globals.AutoRestart then break end
                        
                        if isfile("ADS_LastStrat.lua") then
                            task.spawn(function()
                                repeat
                                    task.wait(0.1)
                                    local towersFolder = workspace:FindFirstChild("Towers")
                                until (towersFolder and #towersFolder:GetChildren() == 0) or not Globals.AutoRestart
                                
                                if not Globals.AutoRestart then return end
                                TDS:ResetAllStates()
                                TDS:RunStrategy()
                            end)
                        end
                        
                        repeat task.wait(1) until gameStateReplicator:GetAttribute("GameOver") == false or not Globals.AutoRestart
                    elseif Globals.AutoRejoin then
                        if isfile("ADS_LastStrat.lua") then
                            pcall(delfile, "ADS_LastStrat.lua")
                        end
                        pcall(HandlePostMatch)
                        break
                    end
                end
            end
            task.wait(1)
        end
        BackToLobbyRunning = false
    end)
end

local function StartAntiLag()
    if AntiLagRunning then return end
    AntiLagRunning = true

    pcall(function()
        local setid = setthreadidentity or set_thread_identity or (syn and syn.set_thread_identity) or setidentity
        if setid then pcall(setid, 8) end
        local rSettings = settings and settings()
        if rSettings and rSettings.Rendering then
            rSettings.Rendering.QualityLevel = Enum.QualityLevel.Level01
        end
    end)

    task.spawn(function()
        while Globals.AntiLag do
            local TowersFolder = workspace:FindFirstChild("Towers")
            local ClientUnits = workspace:FindFirstChild("ClientUnits")

            if TowersFolder then
                for _, tower in ipairs(TowersFolder:GetChildren()) do
                    local anims = tower:FindFirstChild("Animations")
                    local weapon = tower:FindFirstChild("Weapon")
                    local projectiles = tower:FindFirstChild("Projectiles")

                    if anims then anims:Destroy() end
                    if projectiles then projectiles:Destroy() end
                    if weapon then weapon:Destroy() end
                end
            end
            if ClientUnits then
                for _, unit in ipairs(ClientUnits:GetChildren()) do
                    unit:Destroy()
                end
            end
            
            task.wait(0.5)
        end
        AntiLagRunning = false
    end)
end

local function StartAutoChain()
    if AutoChainRunning or not Globals.AutoChain then return end
    AutoChainRunning = true

    task.spawn(function()
        local idx = 1

        while Globals.AutoChain do
            local commander = {}
            local TowersFolder = workspace:FindFirstChild("Towers")

            if TowersFolder then
                for _, towers in ipairs(TowersFolder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Commander"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 2 then
                        commander[#commander + 1] = towers.Parent
                    end
                end
            end

            if #commander >= 3 then
                if idx > #commander then idx = 1 end

                local CurrentCommander = commander[idx]
                local replicator = CurrentCommander:FindFirstChild("TowerReplicator")
                local UpgradeLevel = replicator and replicator:GetAttribute("Upgrade") or 0

                if UpgradeLevel >= 4 and Globals.SupportCaravan then
                    RemoteFunc:InvokeServer(
                        "Troops",
                        "Abilities",
                        "Activate",
                        { Troop = CurrentCommander, Name = "Support Caravan", Data = {} }
                    )
                    task.wait(0.1) 
                end

                local response = RemoteFunc:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    { Troop = CurrentCommander, Name = "Call Of Arms", Data = {} }
                )

                if response then
                    idx += 1

                    local hotbar = PlayerGui:FindFirstChild("ReactUniversalHotbar")
                    local TimescaleFrame = hotbar and hotbar.Frame:FindFirstChild("timescale")

                    if TimescaleFrame and TimescaleFrame.Visible then
                        if TimescaleFrame:FindFirstChild("Lock") then
                            task.wait(10.3)
                        else
                            task.wait(5.25)
                        end
                    else
                        task.wait(10.3)
                    end
                else
                    task.wait(0.5)
                end
            else
                task.wait(1)
            end
        end

        AutoChainRunning = false
    end)
end

local function StartAutoDjBooth()
    if AutoDjRunning or not Globals.AutoDJ then return end
    AutoDjRunning = true

    task.spawn(function()
        while Globals.AutoDJ do
            local DJ = nil
            local TowersFolder = workspace:FindFirstChild("Towers")

            if TowersFolder then
                for _, towers in ipairs(TowersFolder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "DJ Booth"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 3 then
                        DJ = towers.Parent
                    end
                end
            end

            if DJ then
                RemoteFunc:InvokeServer(
                    "Troops",
                    "Abilities",
                    "Activate",
                    { Troop = DJ, Name = "Drop The Beat", Data = {} }
                )
            end

            task.wait(1)
        end

        AutoDjRunning = false
    end)
end

local function StartAutoNecro()
    if AutoNecroRunning or not Globals.AutoNecro then return end
    AutoNecroRunning = true

    local lastActivation = 0
    local ownerId = game.Players.LocalPlayer.UserId

    local function getNecros(towersFolder)
        local list = {}
        if not towersFolder then
            return list
        end
        for _, rep in ipairs(towersFolder:GetDescendants()) do
            if rep:IsA("Folder") and rep.Name == "TowerReplicator"
            and rep:GetAttribute("Name") == "Necromancer"
            and rep:GetAttribute("OwnerId") == ownerId then
                list[#list + 1] = rep.Parent
            end
        end
        return list
    end

    local function pickMaxGraves(rep, graveStore, up)
        local maxGraves = rep and rep:GetAttribute("Max_Graves")
        if graveStore then
            local gMax = graveStore:GetAttribute("Max_Graves")
            if type(gMax) == "number" and gMax > 0 then
                maxGraves = gMax
            end
        end
        if not maxGraves or maxGraves < 2 then
            if up >= 4 then
                maxGraves = 9
            elseif up >= 2 then
                maxGraves = 6
            else
                maxGraves = 3
            end
        end
        return maxGraves
    end

    local function countGraves(graveStore)
        if not graveStore then
            return 0
        end
        local cnt = 0
        for k, v in pairs(graveStore:GetAttributes()) do
            if type(k) == "string" and #k > 20 then
                local isDestroy = false
                if type(v) == "table" then
                    for _, elem in pairs(v) do
                        if tostring(elem) == "Destroy" then
                            isDestroy = true
                            break
                        end
                    end
                elseif tostring(v):find("Destroy") then
                    isDestroy = true
                end
                if isDestroy then
                    graveStore:SetAttribute(k, nil)
                else
                    cnt += 1
                end
            end
        end
        return cnt
    end

    local function cleanAllGraves(list)
        for _, necro in ipairs(list) do
            local rep = necro and necro:FindFirstChild("TowerReplicator")
            local store = rep and rep:FindFirstChild("GraveStone")
            if store then
                countGraves(store)
            end
        end
    end

    task.spawn(function()
        local idx = 1

        while Globals.AutoNecro do
            local TowersFolder = workspace:FindFirstChild("Towers")
            local necromancer = getNecros(TowersFolder)
            cleanAllGraves(necromancer)

            if #necromancer >= 1 then
                if idx > #necromancer then idx = 1 end
                local CurrentNecromancer = necromancer[idx]
                local replicator = CurrentNecromancer:FindFirstChild("TowerReplicator")

                local up = replicator and (replicator:GetAttribute("Upgrade") or 0) or 0
                local graveStore = replicator and replicator:FindFirstChild("GraveStone")
                local maxGraves = pickMaxGraves(replicator, graveStore, up)
                local graveCount = countGraves(graveStore)
                local debounce = (replicator and replicator:GetAttribute("AbilityDebounce")) or 5
                local now = os.clock()

                if maxGraves and graveCount >= maxGraves and (now - lastActivation >= debounce) then
                    local response = RemoteFunc:InvokeServer(
                        "Troops",
                        "Abilities",
                        "Activate",
                        { Troop = CurrentNecromancer, Name = "Raise The Dead", Data = {} }
                    )

                    if response then 
                        lastActivation = now
                        idx += 1
                        task.wait(1)
                    else
                        task.wait(0.5)
                    end
                else
                    task.wait(0.1)
                end
            else
                task.wait(1)
            end
        end

        AutoNecroRunning = false
    end)
end

local function StartAutoMercenary()
    if not Globals.AutoMercenary and not Globals.AutoMilitary then return end

    if AutoMercenaryBaseRunning then return end
    AutoMercenaryBaseRunning = true

    task.spawn(function()
        while Globals.AutoMercenary do
            local TowersFolder = workspace:FindFirstChild("Towers")

            if TowersFolder then
                for _, towers in ipairs(TowersFolder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Mercenary Base"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 5 then

                        RemoteFunc:InvokeServer(
                            "Troops",
                            "Abilities",
                            "Activate",
                            { 
                                Troop = towers.Parent, 
                                Name = "Air-Drop", 
                                Data = {
                                    pathName = 1, 
                                    directionCFrame = CFrame.new(), 
                                    dist = Globals.MercenaryPath or 195
                                } 
                            }
                        )

                        task.wait(0.5)

                        if not Globals.AutoMercenary then break end
                    end
                end
            end

            task.wait(0.5)
        end

        AutoMercenaryBaseRunning = false
    end)
end

local function StartAutoMilitary()
    if not Globals.AutoMilitary then return end

    if AutoMilitaryBaseRunning then return end
    AutoMilitaryBaseRunning = true

    task.spawn(function()
        while Globals.AutoMilitary do
            local TowersFolder = workspace:FindFirstChild("Towers")
            if TowersFolder then
                for _, towers in ipairs(TowersFolder:GetDescendants()) do
                    if towers:IsA("Folder") and towers.Name == "TowerReplicator"
                    and towers:GetAttribute("Name") == "Military Base"
                    and towers:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId
                    and (towers:GetAttribute("Upgrade") or 0) >= 4 then

                        RemoteFunc:InvokeServer(
                            "Troops",
                            "Abilities",
                            "Activate",
                            { 
                                Troop = towers.Parent, 
                                Name = "Airstrike", 
                                Data = {
                                    pathName = 1, 
                                    pointToEnd = CFrame.new(), 
                                    dist = Globals.MilitaryPath or 195
                                } 
                            }
                        )

                        task.wait(0.5)

                        if not Globals.AutoMilitary then break end
                    end
                end
            end

            task.wait(0.5)
        end

        AutoMilitaryBaseRunning = false
    end)
end

local function StartSellFarm()
    if SellFarmsRunning or not Globals.SellFarms or GameState ~= "GAME" then return end
    SellFarmsRunning = true

    task.spawn(function()
        while Globals.SellFarms do
            local CurrentWave = GetCurrentWave()
            if Globals.SellFarmsWave and CurrentWave < Globals.SellFarmsWave then
                task.wait(1)
                continue
            end

            local TowersFolder = workspace:FindFirstChild("Towers")
            if TowersFolder then
                for _, replicator in ipairs(TowersFolder:GetDescendants()) do
                    if replicator:IsA("Folder") and replicator.Name == "TowerReplicator" then
                        local IsFarm = replicator:GetAttribute("Name") == "Farm"
                        local IsMine = replicator:GetAttribute("OwnerId") == game.Players.LocalPlayer.UserId

                        if IsFarm and IsMine then
                            local TowerModel = replicator.Parent
                            RemoteFunc:InvokeServer("Troops", "Sell", { Troop = TowerModel })

                            task.wait(0.2)
                        end
                    end
                end
            end

            task.wait(1)
        end
        SellFarmsRunning = false
    end)
end

local AutoMedicModule = nil

local function StartMedicChain()
    if Globals.AutoMedic then
        if AutoMedicModule and AutoMedicModule.State and AutoMedicModule.State.Running then 
            return 
        end
        if not AutoMedicModule then
            local success, loadedLib = pcall(function()
                local url = "https://raw.githubusercontent.com/AmonguszzZ/ModdedAether/refs/heads/main/AutoAbilities/AutoMedicNew.lua"
                return loadstring(game:HttpGet(url))()
            end)
            if success and loadedLib then
                AutoMedicModule = loadedLib
            end
        end
        if AutoMedicModule then
            AutoMedicModule.Chaining()
        end
    else
        if AutoMedicModule and AutoMedicModule.State then
            AutoMedicModule.State.Running = false
        end
    end
end

function TDS:RemoveIndex()
    self.PlacedTowers = {}
    self.PlacedTraps = {}
    self.MapInteractions = {}
  
    if UpgradeHistory then
        table.clear(UpgradeHistory)
    end
    
    Logger:Log("CLEARED EVERYTHING: All indexes, upgrade histories, and automated execution loops have been completely reset.")
end

function TDS:Rejoin()
SmartTeleportToLobby()
end

task.spawn(function()
    task.wait(2)
    while true do
        if Globals.AutoPickups and not AutoPickupsRunning then
            StartAutoPickups()
        end

        if Globals.AutoSkip and not AutoSkipRunning then
            StartAutoSkip()
        end

        if Globals.TimeScaleEnabled and not TimeScaleRunning then
            StartTimeScale()
        end

        if Globals.AutoChain and not AutoChainRunning then
            StartAutoChain()
        end

        if Globals.AutoDJ and not AutoDjRunning then
            StartAutoDjBooth()
        end

        if Globals.AutoNecro and not AutoNecroRunning then
            StartAutoNecro()
        end

        if Globals.AutoMercenary and not AutoMercenaryBaseRunning then
            StartAutoMercenary()
        end

        if Globals.AutoMilitary and not AutoMilitaryBaseRunning then
            StartAutoMilitary()
        end

        if Globals.SellFarms and not SellFarmsRunning then
            StartSellFarm()
        end

        if Globals.AntiLag and not AntiLagRunning then
            StartAntiLag()
        end

       if (Globals.AutoRejoin or Globals.AutoRestart or Globals.AutoRematch) and not BackToLobbyRunning then
            StartBackToLobby()
        end

        if Globals.AutoGatling and not AutoGatlingRunning then
            StartAutoGatling()
        end

        if Globals.Gatlify and not GatlifyRunning then
            StartGatlify()
        end

        if Globals.AutoPremium and not AutoPremiumRunning then
            StartAutoPremium()
        end

        if Globals.AutoOpenCrates and not AutoOpenRunning then
            StartAutoOpenCrates()
        end

        if Globals.AutoReady and not AutoReadyRunning then
            StartAutoReady()
        end

        if Globals.Easy and not EasyModeRunning then
            StartEasyMode()
        end

         if Globals.AutoMedic and not AutoMedicRunning then
            StartMedicChain()
        end

        task.wait(1)
    end
end)

if Globals.ClaimRewards and not AutoClaimRewards then
    StartClaimRewards()
end

MissionsUIFix()

return TDS
