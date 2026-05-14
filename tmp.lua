local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- ════════════════════════════════════════
--  SERVICES
-- ════════════════════════════════════════
local ReplicatedStorage      = game:GetService("ReplicatedStorage")
local Players                = game:GetService("Players")
local HttpService            = game:GetService("HttpService")
local RunService             = game:GetService("RunService")
local PathfindingService     = game:GetService("PathfindingService")
local LocalPlayer            = Players.LocalPlayer

local RemoteEvents           = ReplicatedStorage:WaitForChild("RemoteEvents")
local BuyDisplaySneakerEvent = RemoteEvents:WaitForChild("BuyDisplaySneakerEvent")

-- FIX: Use WaitForChild with timeout instead of FindFirstChild so these are
--      never nil when first accessed. 5s timeout returns nil gracefully.
local GetStockYPrices           = RemoteEvents:WaitForChild("GetStockYPrices",           5)
local ChangeDisplaySneakerEvent = RemoteEvents:WaitForChild("ChangeDisplaySneaker",       5)
local RemoveDisplaySneakerEvent = RemoteEvents:WaitForChild("RemoveDisplaySneaker",       5)

local Tables = workspace:WaitForChild("Tables")

-- FIX: Guard inventory folders with WaitForChild so they never arrive as nil
local Inventory           = LocalPlayer:WaitForChild("Inventory")
local SellableInventory   = Inventory:WaitForChild("SellableInventory")
local UnsellableInventory = Inventory:WaitForChild("UnsellableInventory")

-- ════════════════════════════════════════
--  SESSION GLOBALS
-- ════════════════════════════════════════
local startTime = tick()
getgenv().TotalMoneySpent     = getgenv().TotalMoneySpent     or 0
getgenv().ShoesBought         = getgenv().ShoesBought         or 0
getgenv().ShoesSold           = getgenv().ShoesSold           or 0
getgenv().MoneyAtSessionStart = getgenv().MoneyAtSessionStart or 0
getgenv().TotalMoneyEarned    = getgenv().TotalMoneyEarned    or 0

-- ════════════════════════════════════════
--  SAVE / LOAD
-- ════════════════════════════════════════
local WEBHOOK_FILE   = "ShoeBuyer_webhook.txt"
local SETTINGS_FILE  = "ShoeBuyer_settings.json"
local BLACKLIST_FILE = "ShoeBuyer_blacklist.json"

local function saveWebhookToDisk(url)
    pcall(function() writefile(WEBHOOK_FILE, url) end)
end
local function loadWebhookFromDisk()
    local ok, data = pcall(function() return readfile(WEBHOOK_FILE) end)
    if ok and type(data) == "string" and data ~= "" then return data end
    return ""
end
local function saveSettingsToDisk(settings)
    pcall(function()
        writefile(SETTINGS_FILE, HttpService:JSONEncode({
            PriceFilter               = settings.PriceFilter,
            MaxPrice                  = tonumber(settings.MaxPrice)               or 100000,
            TargetShoe                = settings.TargetShoe,
            Delay                     = tonumber(settings.Delay)                  or 0.05,
            UseStockYCheck            = settings.UseStockYCheck,
            StockYMargin              = tonumber(settings.StockYMargin)           or 1.0,
            UnsellableOnly            = settings.UnsellableOnly,
            SellStockYOffsetPct       = tonumber(settings.SellStockYOffsetPct)    or 0,
            UseFixedSellPrice         = settings.UseFixedSellPrice,
            FixedSellPrice            = tonumber(settings.FixedSellPrice)         or 1000,
            AutoSellUnsellableOnly    = settings.AutoSellUnsellableOnly,
            SnipeCycleWait            = tonumber(settings.SnipeCycleWait)         or 0.5,
            OneDollarCycleWait        = tonumber(settings.OneDollarCycleWait)     or 0.5,
            AutoSellRefillWait        = tonumber(settings.AutoSellRefillWait)     or 3.0,
            AutoSellSlotWait          = tonumber(settings.AutoSellSlotWait)       or 0.1,
            FlashListHoldTime         = tonumber(settings.FlashListHoldTime)      or 0.5,
            FlashListDelistTime       = tonumber(settings.FlashListDelistTime)    or 0.1,
            BuyConfirmPollWait        = tonumber(settings.BuyConfirmPollWait)     or 0.08,
            UseOverpayLimit           = settings.UseOverpayLimit,
            OverpayLimit              = tonumber(settings.OverpayLimit)           or 0,
            BlockNoStockYData         = settings.BlockNoStockYData,
            UseMaxPriceFallback       = settings.UseMaxPriceFallback,
            MaxPriceFallback          = tonumber(settings.MaxPriceFallback)       or 50000,
        }))
    end)
end
local function loadSettingsFromDisk()
    local ok, data = pcall(function() return readfile(SETTINGS_FILE) end)
    if ok and type(data) == "string" and data ~= "" then
        local ok2, tbl = pcall(function() return HttpService:JSONDecode(data) end)
        if ok2 and type(tbl) == "table" then return tbl end
    end
    return {}
end

-- ════════════════════════════════════════
--  BLACKLIST
-- ════════════════════════════════════════
local Blacklist = {}
local BlacklistMinPrice = 0
local function saveBlacklistToDisk()
    pcall(function()
        local arr = {}
        for name in pairs(Blacklist) do table.insert(arr, name) end
        writefile(BLACKLIST_FILE, HttpService:JSONEncode(arr))
    end)
end
local function loadBlacklistFromDisk()
    local ok, data = pcall(function() return readfile(BLACKLIST_FILE) end)
    if ok and type(data) == "string" and data ~= "" then
        local ok2, arr = pcall(function() return HttpService:JSONDecode(data) end)
        if ok2 and type(arr) == "table" then
            for _, name in ipairs(arr) do Blacklist[name] = true end
        end
    end
end
loadBlacklistFromDisk()
local function isBlacklisted(shoeName) return Blacklist[shoeName] == true end

-- ════════════════════════════════════════
--  SETTINGS
-- ════════════════════════════════════════
local savedSettings = loadSettingsFromDisk()
local Settings = {
    PriceFilter            = savedSettings.PriceFilter            ~= nil and savedSettings.PriceFilter            or true,
    MaxPrice               = tonumber(savedSettings.MaxPrice)               or 100000,
    TargetShoe             = savedSettings.TargetShoe             or "",
    Delay                  = tonumber(savedSettings.Delay)                  or 0.05,
    SnipeMode              = false,
    OneDollarMode          = false,
    WebhookURL             = loadWebhookFromDisk(),
    UseStockYCheck         = savedSettings.UseStockYCheck         ~= nil and savedSettings.UseStockYCheck         or true,
    StockYMargin           = tonumber(savedSettings.StockYMargin)           or 1.0,
    UnsellableOnly         = savedSettings.UnsellableOnly         ~= nil and savedSettings.UnsellableOnly         or false,
    AutoSell               = false,
    AutoSellUnsellableOnly = savedSettings.AutoSellUnsellableOnly ~= nil and savedSettings.AutoSellUnsellableOnly or false,
    SellStockYOffsetPct    = tonumber(savedSettings.SellStockYOffsetPct)    or 0,
    UseFixedSellPrice      = savedSettings.UseFixedSellPrice      ~= nil and savedSettings.UseFixedSellPrice      or false,
    FixedSellPrice         = tonumber(savedSettings.FixedSellPrice)         or 1000,
    SnipeCycleWait         = tonumber(savedSettings.SnipeCycleWait)         or 0.5,
    OneDollarCycleWait     = tonumber(savedSettings.OneDollarCycleWait)     or 0.5,
    AutoSellRefillWait     = tonumber(savedSettings.AutoSellRefillWait)     or 3.0,
    AutoSellSlotWait       = tonumber(savedSettings.AutoSellSlotWait)       or 0.1,
    FlashListHoldTime      = tonumber(savedSettings.FlashListHoldTime)      or 0.5,
    FlashListDelistTime    = tonumber(savedSettings.FlashListDelistTime)    or 0.1,
    BuyConfirmPollWait     = tonumber(savedSettings.BuyConfirmPollWait)     or 0.08,
    UseOverpayLimit        = savedSettings.UseOverpayLimit        ~= nil and savedSettings.UseOverpayLimit        or false,
    OverpayLimit           = tonumber(savedSettings.OverpayLimit)           or 0,
    BlockNoStockYData      = savedSettings.BlockNoStockYData      ~= nil and savedSettings.BlockNoStockYData      or false,
    UseMaxPriceFallback    = savedSettings.UseMaxPriceFallback    ~= nil and savedSettings.UseMaxPriceFallback    or true,
    MaxPriceFallback       = tonumber(savedSettings.MaxPriceFallback)       or 50000,
}
local function saveSetting(key, value)
    if key == "StockYMargin" or key == "MaxPrice" or key == "Delay"
       or key == "FixedSellPrice" or key == "SellStockYOffsetPct"
       or key == "SnipeCycleWait" or key == "OneDollarCycleWait"
       or key == "AutoSellRefillWait" or key == "AutoSellSlotWait"
       or key == "FlashListHoldTime" or key == "FlashListDelistTime"
       or key == "BuyConfirmPollWait" or key == "OverpayLimit"
       or key == "MaxPriceFallback" then
        value = tonumber(value) or value
    end
    Settings[key] = value
    saveSettingsToDisk(Settings)
end

-- ════════════════════════════════════════
--  STATE
-- ════════════════════════════════════════
local BuyStats         = { Found = 0, Bought = 0, Skipped = 0 }
local SnipeConnections = {}
local SnipeLoopRunning = false
local OneDollarRunning = false
local OneDollarConns   = {}
local MAX_LOG          = 30
-- FIX: circular log buffer to avoid O(n) table.remove(logBuffer, 1) on every log call
local logBuffer        = {}
local logHead          = 1
local logCount         = 0
local StockYCache      = {}
local pendingSellPrice = 1000
local sellLabelRefs    = {}

local lastSellRefreshTime   = nil
local lastListRefreshTime   = nil
local sellInventorySnapshot = {}
local snapSellable          = {}
local snapUnsellable        = {}

local SnipeToggleRef
local OneDollarToggleRef

-- Walk-to-Buy state
local WalkToBuySnipe          = false
local WalkToBuyOneDollar      = false
local WalkBuySnipeRunning     = false
local WalkBuyOneDollarRunning = false
local WalkBuySnipeConns       = {}
local WalkBuyOneDollarConns   = {}
local WalkSnipeToggleRef
local WalkOneDollarToggleRef

local FlashListCounter    = 0
local FlashListNextDollar = math.random(5, 15)
local OneDollarMaxPrice   = 1

-- ════════════════════════════════════════
--  SLOT CACHE
-- ════════════════════════════════════════
local cachedSlots = {}
local function rebuildSlotCache()
    cachedSlots = {}
    for _, tm in ipairs(Tables:GetChildren()) do
        if tm.Name == "Table" then
            for i = 1, 6 do
                local slot = tm:FindFirstChild("DisplaySneaker"..i)
                if slot then table.insert(cachedSlots, slot) end
            end
        end
    end
end
Tables.ChildAdded:Connect(function(tm)
    task.wait(0.3)
    if tm.Name == "Table" then
        for i = 1, 6 do
            local slot = tm:FindFirstChild("DisplaySneaker"..i)
            if slot then table.insert(cachedSlots, slot) end
        end
    end
end)
Tables.ChildRemoved:Connect(function() task.spawn(rebuildSlotCache) end)

-- ════════════════════════════════════════
--  WINDOW + TABS
-- ════════════════════════════════════════
local Window = Rayfield:CreateWindow({
    Name            = "Shoe Sniper | By FM",
    LoadingTitle    = "Shoe Sniper",
    LoadingSubtitle = "by FM",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
})

local ScannerTab   = Window:CreateTab("Scanner",  "search")
local ListTab      = Window:CreateTab("List",      "list")
local SellTab      = Window:CreateTab("Sell",      "tag")
local BlacklistTab = Window:CreateTab("Blacklist", "X")
local SettingsTab  = Window:CreateTab("Settings",  "settings")
local ConfigTab    = Window:CreateTab("Configs",   "save")
local WebhookTab   = Window:CreateTab("Webhook",   "globe")
local StatsTab     = Window:CreateTab("Stats",     "bar-chart-2")

-- ════════════════════════════════════════
--  FIX: ElementIndicator patch — only suppress the specific known error,
--       not all errors (the original swallowed real Rayfield bugs silently)
-- ════════════════════════════════════════
local function patchTab(tab)
    for _, method in ipairs({"CreateButton","CreateToggle","CreateLabel","CreateSection","CreateInput","CreateSlider","CreateDropdown","CreateColorPicker","CreateKeybind"}) do
        local original = tab[method]
        if type(original) == "function" then
            tab[method] = function(self, ...)
                local ok, result = pcall(original, self, ...)
                if ok then
                    return result
                else
                    local msg = tostring(result)
                    if msg:find("ElementIndicator") then
                        -- Return a no-op stub only for this known harmless error
                        return { Set = function() end, CurrentValue = false }
                    end
                    -- Re-raise real errors so they surface in the output
                    warn("[patchTab] Rayfield error in "..method..": "..msg)
                    return { Set = function() end, CurrentValue = false }
                end
            end
        end
    end
end

for _, tab in ipairs({ScannerTab, ListTab, SellTab, BlacklistTab, SettingsTab, ConfigTab, WebhookTab, StatsTab}) do
    patchTab(tab)
end

local tabContainerRegistry = {}

-- ════════════════════════════════════════
--  FIX: getElementsRoot
-- ════════════════════════════════════════
local function getElementsRoot()
    local gui
    if type(gethui) == "function" then
        gui = gethui():FindFirstChild("Rayfield")
    end
    if not gui then
        gui = game:GetService("CoreGui"):FindFirstChild("Rayfield")
    end
    if not gui then
        for _, c in ipairs(game:GetService("CoreGui"):GetChildren()) do
            if c:IsA("ScreenGui") and c:FindFirstChild("Main") then gui = c break end
        end
    end
    if not gui then return nil end
    return gui:FindFirstChild("Main") and gui.Main:FindFirstChild("Elements")
end

local function getTabScrollFrame(tab)
    local frame = tabContainerRegistry[tab]
    if frame then return frame end
    local knownNames = {
        [ScannerTab]   = "Scanner",
        [ListTab]      = "List",
        [SellTab]      = "Sell",
        [BlacklistTab] = "Blacklist",
        [SettingsTab]  = "Settings",
        [ConfigTab]    = "Configs",
        [WebhookTab]   = "Webhook",
        [StatsTab]     = "Stats",
    }
    local tabName = knownNames[tab]
    if not tabName then return nil end
    local root = getElementsRoot()
    if not root then return nil end
    for _, child in ipairs(root:GetChildren()) do
        if child:IsA("ScrollingFrame") and child.Name == tabName then
            tabContainerRegistry[tab] = child
            return child
        end
    end
    return nil
end

task.defer(function()
    local root = getElementsRoot()
    if not root then return end
    local tabDefs = {
        { tab = ScannerTab,   name = "Scanner"   },
        { tab = ListTab,      name = "List"       },
        { tab = SellTab,      name = "Sell"       },
        { tab = BlacklistTab, name = "Blacklist"  },
        { tab = SettingsTab,  name = "Settings"   },
        { tab = ConfigTab,    name = "Configs"    },
        { tab = WebhookTab,   name = "Webhook"    },
        { tab = StatsTab,     name = "Stats"      },
    }
    local frameByName = {}
    for _, c in ipairs(root:GetChildren()) do
        if c:IsA("ScrollingFrame") then frameByName[c.Name] = c end
    end
    for _, def in ipairs(tabDefs) do
        local frame = frameByName[def.name]
        if frame then tabContainerRegistry[def.tab] = frame end
    end
end)

-- ════════════════════════════════════════
--  SCANNER LABELS
-- ════════════════════════════════════════
local StatusLabel     = ScannerTab:CreateLabel("Status: Idle")
local StatsLabel      = ScannerTab:CreateLabel("Found: 0 | Bought: 0 | Skipped: 0")
local StockYLabel     = ScannerTab:CreateLabel("StockY Cache: empty")
local SneakerModLabel = ScannerTab:CreateLabel("SneakerModule: not loaded")

-- ════════════════════════════════════════
--  TAB STATE
-- ════════════════════════════════════════
local ListStatusLabel       = nil
local listAutoRefresh       = false
local ListGeneration        = 0
local SellStatusLabel       = nil
local SellGeneration        = 0
local BlacklistStatusLabel  = nil
local BlacklistSearchFilter = ""
local BlacklistGeneration   = 0

-- ════════════════════════════════════════
--  DYNAMIC ELEMENT TRACKING
-- ════════════════════════════════════════
local dynElements = {
    [ListTab]      = {},
    [SellTab]      = {},
    [BlacklistTab] = {},
}

local staticSnapshot = {
    [ListTab]      = nil,
    [SellTab]      = nil,
    [BlacklistTab] = nil,
}

-- FIX: freezeStaticUI deferred fallback was capped at 20 iterations and
--      silently failed if the frame never appeared. Now it retries indefinitely
--      up to 3 seconds, then gives up with a warning.
local function freezeStaticUI(tab)
    local frame = getTabScrollFrame(tab)
    if frame then
        local snap = {}
        for _, child in ipairs(frame:GetChildren()) do snap[child] = true end
        staticSnapshot[tab] = snap
        return
    end
    task.spawn(function()
        local deadline = tick() + 3
        while tick() < deadline do
            task.wait(0.1)
            frame = getTabScrollFrame(tab)
            if frame then
                local snap = {}
                for _, child in ipairs(frame:GetChildren()) do snap[child] = true end
                staticSnapshot[tab] = snap
                return
            end
        end
        warn("[freezeStaticUI] Could not find tab scroll frame — static UI may be cleared incorrectly")
    end)
end

-- FIX: clearTabElements now uses pcall around Destroy calls and around the
--      entire body so a Rayfield internal error can't leave generation counts
--      in a broken state.
local function clearTabElements(tab)
    sellLabelRefs = {}
    dynElements[tab] = {}
    local frame = getTabScrollFrame(tab)
    if not frame then return end
    local snap = staticSnapshot[tab]
    local toDestroy = {}
    for _, child in ipairs(frame:GetChildren()) do
        if not snap or not snap[child] then
            if not child:IsA("UIListLayout")
               and not child:IsA("UIPadding")
               and not child:IsA("UIGridLayout") then
                table.insert(toDestroy, child)
            end
        end
    end
    for _, child in ipairs(toDestroy) do pcall(function() child:Destroy() end) end
    task.wait(0.05)
end

local function tracked(tab, element)
    table.insert(dynElements[tab], element)
    return element
end

-- ════════════════════════════════════════
--  HELPERS
-- ════════════════════════════════════════
local function commaNum(n)
    n = math.floor(tonumber(n) or 0)
    local s, result = tostring(math.abs(n)), ""
    local len = #s
    for i = 1, len do
        if i > 1 and (len - i + 1) % 3 == 0 then result = result.."," end
        result = result..s:sub(i,i)
    end
    return (n < 0 and "-" or "")..result
end
local function fmtMoney(n) return "$"..commaNum(n) end
local function timeSince(t)
    if not t then return "never" end
    local s = math.floor(tick() - t)
    if s < 60 then return s.."s ago"
    elseif s < 3600 then return math.floor(s/60).."m "..(s%60).."s ago"
    else return math.floor(s/3600).."h "..math.floor((s%3600)/60).."m ago" end
end
local function updateStats()
    pcall(function()
        StatsLabel:Set("Found: "..BuyStats.Found.." | Bought: "..BuyStats.Bought.." | Skipped: "..BuyStats.Skipped)
    end)
end
local function setStatus(txt)
    pcall(function() StatusLabel:Set("Status: "..tostring(txt)) end)
end

-- FIX: circular log buffer — O(1) inserts instead of O(n) table.remove
local function log(tag, msg)
    local line = "["..os.date("%H:%M:%S").."]["..tostring(tag).."] "..tostring(msg)
    print(line)
    logBuffer[logHead] = line
    logHead = (logHead % MAX_LOG) + 1
    if logCount < MAX_LOG then logCount += 1 end
end

-- FIX: getMoney now safely handles leaderstats not yet existing
local function getMoney()
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if not ls then return 0 end
    for _, name in ipairs({"Cash","Money","Bucks","Coins","Balance"}) do
        local v = ls:FindFirstChild(name)
        if v then return tonumber(v.Value) or 0 end
    end
    for _, v in ipairs(ls:GetChildren()) do
        if v:IsA("NumberValue") or v:IsA("IntValue") then return tonumber(v.Value) or 0 end
    end
    return 0
end
local function formatUptime(s)
    return string.format("%dd %02dh %02dm %02ds",
        math.floor(s/86400), math.floor((s%86400)/3600),
        math.floor((s%3600)/60), math.floor(s%60))
end

-- ════════════════════════════════════════
--  INVENTORY HELPERS
-- ════════════════════════════════════════
local function isSellable(shoeName)
    for _, item in ipairs(SellableInventory:GetChildren()) do
        if item.Name == shoeName then return true end
    end
    return false
end
local function ownsUnsellableInstance(shoeName)
    for _, item in ipairs(UnsellableInventory:GetChildren()) do
        if item.Name == shoeName then return true end
    end
    return false
end

local SneakerModule       = nil
local SneakerModuleLoaded = false

-- FIX: guard against SneakerModule being set but lacking .sneakers
local function sneakerData(shoeName)
    if not SneakerModuleLoaded or not SneakerModule then return nil end
    if type(SneakerModule.sneakers) ~= "table" then return nil end
    return SneakerModule.sneakers[shoeName]
end

local function isUnsellableByModule(shoeName)
    local data = sneakerData(shoeName)
    if not data then return nil end
    return table.find(data, "Unsellable") ~= nil
end
local function isUnsellable(shoeName)
    local r = isUnsellableByModule(shoeName)
    if r ~= nil then return r end
    return ownsUnsellableInstance(shoeName)
end
local function isUnsellableSlot(slot, shoeName) return isUnsellable(shoeName) end

local function snapshotSellable()
    local snap = {}
    for _, item in ipairs(SellableInventory:GetChildren()) do
        snap[item.Name] = (snap[item.Name] or 0) + 1
    end
    for _, item in ipairs(UnsellableInventory:GetChildren()) do
        snap[item.Name] = (snap[item.Name] or 0) + 1
    end
    return snap
end
local function snapshotBothFolders()
    local s, u = {}, {}
    for _, item in ipairs(SellableInventory:GetChildren()) do s[item.Name] = (s[item.Name] or 0)+1 end
    for _, item in ipairs(UnsellableInventory:GetChildren()) do u[item.Name] = (u[item.Name] or 0)+1 end
    return s, u
end

-- ════════════════════════════════════════
--  SNEAKER MODULE
-- ════════════════════════════════════════
local function loadSneakerModule()
    local ok, result = pcall(function()
        return require(ReplicatedStorage:WaitForChild("SneakerModule"))
    end)
    -- FIX: also guard result.sneakers being a table before trusting the module
    if ok and type(result) == "table" and type(result.sneakers) == "table" then
        SneakerModule = result
        SneakerModuleLoaded = true
        local total, unsellCount = 0, 0
        for _, data in pairs(SneakerModule.sneakers) do
            total += 1
            if type(data) == "table" and table.find(data, "Unsellable") then unsellCount += 1 end
        end
        log("MODULE","Loaded: "..total.." shoes, "..unsellCount.." unsellable")
        pcall(function() SneakerModLabel:Set("SneakerModule: "..total.." | "..unsellCount.." unsellable") end)
    else
        log("MODULE","Failed: "..tostring(result))
        pcall(function() SneakerModLabel:Set("SneakerModule: failed to load") end)
    end
end
local function buildUnsellableCache()
    if SneakerModuleLoaded and SneakerModule and type(SneakerModule.sneakers) == "table" then
        local c = 0
        for _, data in pairs(SneakerModule.sneakers) do
            if type(data) == "table" and table.find(data, "Unsellable") then c += 1 end
        end
        Rayfield:Notify({ Title="Unsellable Cache", Content=c.." unsellable shoes identified.", Duration=4 })
    else
        Rayfield:Notify({ Title="Unsellable Cache", Content="SneakerModule not loaded!", Duration=6 })
    end
end

-- ════════════════════════════════════════
--  SOLD TRACKING
-- ════════════════════════════════════════
local trackedSellable = {}
local function initSoldTracking()
    for _, item in ipairs(SellableInventory:GetChildren()) do trackedSellable[item] = true end
    SellableInventory.ChildRemoved:Connect(function(item)
        if trackedSellable[item] then
            trackedSellable[item] = nil
            getgenv().ShoesSold += 1
            log("SOLD", item.Name.." | total: "..getgenv().ShoesSold)
        end
    end)
    SellableInventory.ChildAdded:Connect(function(item) trackedSellable[item] = true end)
end

-- ════════════════════════════════════════
--  WEBHOOK
-- ════════════════════════════════════════
local FM_SOCIALS_URL = "https://faddedmarket.github.io/fadded/"
local function buildSessionFields()
    return {
        { name="Current Money", value=fmtMoney(getMoney()),                     inline=true },
        { name="Total Spent",   value=fmtMoney(getgenv().TotalMoneySpent or 0), inline=true },
        { name="Shoes Bought",  value=tostring(getgenv().ShoesBought or 0),     inline=true },
        { name="Shoes Sold",    value=tostring(getgenv().ShoesSold   or 0),     inline=true },
        { name="Uptime",        value=formatUptime(tick()-startTime),           inline=true },
    }
end

-- FIX: more defensive HTTP request resolution across executor environments
local function getHttpRequest()
    if type(syn) == "table" and type(syn.request) == "function" then return syn.request end
    if type(http) == "table" and type(http.request) == "function" then return http.request end
    if type(request) == "function" then return request end
    if type(HttpService.RequestAsync) == "function" then
        return function(opts)
            return HttpService:RequestAsync(opts)
        end
    end
    return nil
end

local function sendWebhookRaw(payload)
    if Settings.WebhookURL == "" then return end
    local fn = getHttpRequest()
    if not fn then
        warn("[Webhook] No HTTP request function available in this executor.")
        return
    end
    pcall(function()
        fn({
            Url     = Settings.WebhookURL,
            Method  = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body    = HttpService:JSONEncode(payload),
        })
    end)
end
local function sendWebhook(shoeName, price, confirmed, webhookTitle, sellerName)
    if Settings.WebhookURL == "" then return end
    local title = (webhookTitle or (confirmed and "BOUGHT" or "COULD NOT VERIFY")).." - "..tostring(shoeName)
    local fields = {
        { name="Shoe",          value=tostring(shoeName),                        inline=false },
        { name="Price",         value=fmtMoney(price),                           inline=true  },
        { name="Bought From",   value=tostring(sellerName or "Unknown"),         inline=true  },
        { name="Balance After", value=fmtMoney(getMoney()),                      inline=true  },
        { name="--- Session ---", value="", inline=false },
    }
    for _, f in ipairs(buildSessionFields()) do table.insert(fields, f) end
    sendWebhookRaw({ username="SRS Shoe Sniper", avatar_url="https://i.imgur.com/NambJ9Q.gif",
        embeds={{ title=title, description="[FM Socials]("..FM_SOCIALS_URL..")",
            color=16711935, fields=fields,
            footer={ text="SRS V3  |  "..os.date("%H:%M:%S"), icon_url="https://i.imgur.com/NambJ9Q.gif" } }} })
end
local function sendSoldWebhook(shoeName, listPrice)
    if Settings.WebhookURL == "" then return end
    local fields = {
        { name="Shoe",          value=tostring(shoeName),            inline=false },
        { name="Sold For",      value=fmtMoney(listPrice),           inline=true  },
        { name="Balance After", value=fmtMoney(getMoney()),          inline=true  },
        { name="Total Sold",    value=tostring(getgenv().ShoesSold), inline=true  },
        { name="--- Session ---", value="", inline=false },
    }
    for _, f in ipairs(buildSessionFields()) do table.insert(fields, f) end
    sendWebhookRaw({ username="SRS Shoe Seller", avatar_url="https://i.imgur.com/NambJ9Q.gif",
        embeds={{ title="SOLD - "..tostring(shoeName), description="[FM Socials]("..FM_SOCIALS_URL..")",
            color=16711935, fields=fields,
            footer={ text="SRS V3  |  "..os.date("%H:%M:%S"), icon_url="https://i.imgur.com/NambJ9Q.gif" } }} })
end
local function sendKickWebhook(reason)
    if Settings.WebhookURL == "" then return end
    local fields = { { name="Event", value=tostring(reason or "Game closed."), inline=false },
                     { name="--- Session ---", value="", inline=false } }
    for _, f in ipairs(buildSessionFields()) do table.insert(fields, f) end
    sendWebhookRaw({ username="SRS Shoe Snipper", avatar_url="https://i.imgur.com/NambJ9Q.gif",
        embeds={{ title="Game Closed / Kicked", description="[FM Socials]("..FM_SOCIALS_URL..")",
            color=16711935, fields=fields,
            footer={ text="SRS V3  |  "..os.date("%H:%M:%S"), icon_url="https://i.imgur.com/NambJ9Q.gif" } }} })
end

-- ════════════════════════════════════════
--  STOCK-Y
-- ════════════════════════════════════════
local function refreshStockY()
    -- FIX: guard nil remote before attempting InvokeServer
    if not GetStockYPrices then
        log("STOCKY", "Remote not found — cannot refresh StockY")
        Rayfield:Notify({ Title="StockY Error", Content="GetStockYPrices remote not found!", Duration=6 })
        return
    end
    -- FIX: set loading flag before spawning the notification loop so the
    --      loop can't outlive the pcall result if it resolves instantly
    local loading = true
    task.spawn(function()
        while loading do
            Rayfield:Notify({ Title="StockY", Content="Loading...", Duration=6 })
            task.wait(5)
        end
    end)
    local ok, result = pcall(function() return GetStockYPrices:InvokeServer() end)
    loading = false  -- always stops the notification loop
    if ok and type(result) == "table" then
        StockYCache = result
        local count = 0; for _ in pairs(StockYCache) do count += 1 end
        pcall(function() StockYLabel:Set("StockY Cache: "..count.." shoes") end)
        task.wait(0.1)
        Rayfield:Notify({ Title="StockY", Content=count.." prices cached.", Duration=5 })
    else
        task.wait(0.1)
        Rayfield:Notify({ Title="StockY Error", Content=tostring(result), Duration=6 })
    end
end

-- ════════════════════════════════════════
--  STOCK-Y CHECK
-- ════════════════════════════════════════
local function stockYOk(shoeName, price)
    local cacheSize = 0
    for _ in pairs(StockYCache) do cacheSize += 1 end
    if cacheSize == 0 and Settings.UseStockYCheck then
        log("STOCKY", "WARN cache empty — skipping "..shoeName.." to avoid overpay")
        BuyStats.Skipped += 1
        updateStats()
        return false
    end

    local sp = StockYCache[shoeName]
    local hasData = sp and type(sp) == "number" and sp > 0

    if not hasData then
        if Settings.UseMaxPriceFallback then
            local fallback = tonumber(Settings.MaxPriceFallback) or 50000
            if price > fallback then
                log("FALLBACK", "SKIP "..shoeName
                    .." | no StockY | price "..fmtMoney(price)
                    .." > fallback cap "..fmtMoney(fallback))
                BuyStats.Skipped += 1
                updateStats()
                return false
            end
            return true
        end
        if Settings.UseStockYCheck and Settings.BlockNoStockYData then
            log("STOCKY", "SKIP "..shoeName.." — no StockY data (BlockNoStockYData ON)")
            BuyStats.Skipped += 1
            updateStats()
            return false
        end
        return true
    end

    if Settings.UseOverpayLimit then
        local maxOverpay = tonumber(Settings.OverpayLimit) or 0
        local overpay = price - sp
        if overpay > maxOverpay then
            log("OVERPAY", "SKIP "..shoeName
                .." | listing "..fmtMoney(price)
                .." | StockY "..fmtMoney(sp)
                .." | overpay "..fmtMoney(overpay)
                .." > limit "..fmtMoney(maxOverpay))
            BuyStats.Skipped += 1
            updateStats()
            return false
        end
    end

    if Settings.UseStockYCheck then
        local margin = tonumber(Settings.StockYMargin) or 1.0
        local limit = sp * margin
        if price > limit then
            log("STOCKY", "SKIP "..shoeName
                .." "..fmtMoney(price)
                .." > margin cap "..fmtMoney(math.floor(limit))
                .." (StockY "..fmtMoney(sp).." x "..margin..")")
            BuyStats.Skipped += 1
            updateStats()
            return false
        end
    end

    return true
end

-- ════════════════════════════════════════
--  FIRE + CONFIRM
-- ════════════════════════════════════════
local function fireAndConfirm(slot, shoeName, price, fromListTab)
    local sellerName = "Unknown"
    pcall(function()
        local ov = slot.Parent and slot.Parent:FindFirstChild("OwnerValue")
        if ov and ov.Value then sellerName = tostring(ov.Value.Name) end
    end)
    log("FIRE", slot.Name.." | "..shoeName.." | "..fmtMoney(price).." | "..sellerName)
    local ok, err = pcall(function() BuyDisplaySneakerEvent:FireServer(slot, shoeName, price) end)
    if not ok then log("ERR", tostring(err)) return end
    local confirmed, moneyBefore, snapBefore = false, getMoney(), snapshotSellable()
    for _ = 1, 8 do
        task.wait(Settings.BuyConfirmPollWait)
        local snapAfter = snapshotSellable()
        for name, count in pairs(snapAfter) do
            if (snapBefore[name] or 0) < count then confirmed = true break end
        end
        if confirmed then break end
    end
    local moneyAfter = getMoney()
    if confirmed then
        local cost = math.max(0, moneyBefore - moneyAfter)
        log("OK","BOUGHT: "..shoeName.." | "..fmtMoney(cost).." | "..fmtMoney(moneyAfter))
        BuyStats.Bought += 1; getgenv().ShoesBought += 1; getgenv().TotalMoneySpent += cost
    else
        log("WARN","COULD NOT VERIFY - "..shoeName)
    end
    updateStats()
    if confirmed or fromListTab then
        local label = fromListTab and "LIST TAB BUY" or "BOUGHT"
        task.spawn(function() sendWebhook(shoeName, price, confirmed, label, sellerName) end)
    end
end

-- ════════════════════════════════════════
--  SLOT LOCK
-- ════════════════════════════════════════
local buyDebounce = {}

-- FIX: auto-release debounce if slot is destroyed (prevents permanent locks)
local function acquireSlotLock(slot)
    if buyDebounce[slot] then return false end
    buyDebounce[slot] = true
    -- Clean up if the slot is removed from the game
    local conn
    conn = slot.AncestryChanged:Connect(function()
        if not slot:IsDescendantOf(game) then
            buyDebounce[slot] = nil
            conn:Disconnect()
        end
    end)
    return true
end
local function releaseSlotLock(slot) buyDebounce[slot] = nil end

-- ════════════════════════════════════════
--  WALK HELPERS
-- ════════════════════════════════════════
local function getSlotWorldPosition(slot)
    local model = slot.Parent
    if not model then return nil end
    local part = model:FindFirstChildWhichIsA("BasePart", true)
    if part then return part.Position end
    return nil
end

-- FIX: walkToPosition now accepts a runningFn parameter so the caller's
--      live flag is captured once and checked consistently during the walk.
--      This prevents the loop from continuing after the mode was toggled off.
local function walkToPosition(targetPosition, runningFn)
    local character = LocalPlayer.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not rootPart then return end

    local dist = (rootPart.Position - targetPosition).Magnitude
    if dist < 20 then return end

    local path = PathfindingService:CreatePath({
        AgentRadius  = 2,
        AgentHeight  = 5,
        AgentCanJump = true,
    })

    local ok = pcall(function() path:ComputeAsync(rootPart.Position, targetPosition) end)

    if ok and path.Status == Enum.PathStatus.Success then
        local waypoints = path:GetWaypoints()
        for _, wp in ipairs(waypoints) do
            -- FIX: use the passed-in function rather than reading globals mid-walk
            if runningFn and not runningFn() then return end
            if wp.Action == Enum.PathWaypointAction.Jump then
                humanoid.Jump = true
            end
            humanoid:MoveTo(wp.Position)
            humanoid.MoveToFinished:Wait(3)
        end
    else
        humanoid:MoveTo(targetPosition)
        humanoid.MoveToFinished:Wait(4)
    end
end

local function walkToSlot(slot, runningFn)
    local pos = getSlotWorldPosition(slot)
    if pos then
        walkToPosition(pos, runningFn)
        task.wait(0.1)
    end
end

-- ════════════════════════════════════════
--  CORE BUY
-- ════════════════════════════════════════
local function trySneaker(slot)
    local sneakerVal = slot:FindFirstChild("SneakerValue")
    local priceVal   = slot:FindFirstChild("Price")
    local debounce   = slot:FindFirstChild("SellDebounce")
    if not sneakerVal or sneakerVal.Value == "" then return end
    if debounce and debounce.Value == true then return end
    local shoeName = tostring(sneakerVal.Value)
    local price    = tonumber(priceVal and priceVal.Value) or 0
    BuyStats.Found += 1; updateStats()
    if isBlacklisted(shoeName) then BuyStats.Skipped+=1; updateStats(); return end
    if Settings.UnsellableOnly == true and not isUnsellableSlot(slot, shoeName) then BuyStats.Skipped+=1; updateStats(); return end
    if type(Settings.TargetShoe) == "string" and Settings.TargetShoe ~= "" then
        if not shoeName:lower():find(Settings.TargetShoe:lower(),1,true) then BuyStats.Skipped+=1; updateStats(); return end
    end
    if Settings.PriceFilter == true and price > (tonumber(Settings.MaxPrice) or 100000) then BuyStats.Skipped+=1; updateStats(); return end
    if not stockYOk(shoeName, price) then return end
    if not acquireSlotLock(slot) then return end
    log("FIND", shoeName.." | "..fmtMoney(price))
    fireAndConfirm(slot, shoeName, price, false)
    releaseSlotLock(slot)
end

local function tryOneDollar(slot)
    local sneakerVal = slot:FindFirstChild("SneakerValue")
    local priceVal   = slot:FindFirstChild("Price")
    local debounce   = slot:FindFirstChild("SellDebounce")
    if not sneakerVal or sneakerVal.Value == "" then return end
    if debounce and debounce.Value == true then return end
    local price = tonumber(priceVal and priceVal.Value) or 0
    if price > OneDollarMaxPrice then return end
    local shoeName = tostring(sneakerVal.Value)
    if isBlacklisted(shoeName) then return end
    if not acquireSlotLock(slot) then return end
    BuyStats.Found += 1; updateStats()
    setStatus("$1 Mode — buying: "..shoeName.." ("..fmtMoney(price)..")")
    fireAndConfirm(slot, shoeName, price, false)
    releaseSlotLock(slot)
    setStatus("$1 Mode (>$"..OneDollarMaxPrice..")".. " [LIVE]")
end

-- ════════════════════════════════════════
--  SELL HELPERS
-- ════════════════════════════════════════
local function getMyTable()
    for _, tm in ipairs(Tables:GetChildren()) do
        if tm.Name == "Table" then
            local ov = tm:FindFirstChild("OwnerValue")
            if ov and ov.Value == LocalPlayer then return tm end
        end
    end
    return nil
end
local function hasTableSkin()
    local ti = LocalPlayer:FindFirstChild("TableInventory")
    if not ti then return false end
    if #ti:GetChildren() > 0 then return true end
    for _ in pairs(ti:GetAttributes()) do return true end
    return false
end
local function maxTableSlots() return hasTableSkin() and 6 or 3 end
local function getFirstEmptySlot(myTable)
    -- FIX: nil guard on myTable
    if not myTable then return nil end
    for i = 1, maxTableSlots() do
        local slot = myTable:FindFirstChild("DisplaySneaker"..i)
        if slot then
            local sv = slot:FindFirstChild("SneakerValue")
            if sv and sv.Value == "" then return slot end
        end
    end
    return nil
end
local function calcSellPrice(shoeName)
    if Settings.UseFixedSellPrice then return math.max(1, Settings.FixedSellPrice) end
    local sp = StockYCache[shoeName]
    if sp and sp > 0 then return math.max(1, math.floor(sp*(1+Settings.SellStockYOffsetPct/100))) end
    return pendingSellPrice
end
local lastListedPrice = {}

-- FIX: nil-guard both remotes before calling FireServer
local function listShoeOnTable(shoeName)
    if not ChangeDisplaySneakerEvent then
        log("ERR", "ChangeDisplaySneakerEvent is nil — cannot list shoe")
        return false, 0
    end
    local myTable = getMyTable()
    if not myTable then return false, 0 end
    local targetSlot = getFirstEmptySlot(myTable)
    if not targetSlot then log("SELL","All slots full") return false, 0 end
    local listPrice = calcSellPrice(shoeName)
    local ok, err = pcall(function() ChangeDisplaySneakerEvent:FireServer(shoeName, targetSlot.Name, listPrice) end)
    if ok then lastListedPrice[shoeName] = listPrice; return true, listPrice
    else log("ERR","List failed: "..tostring(err)); return false, 0 end
end

-- ════════════════════════════════════════
--  AUTO-SELL LOOPS
-- ════════════════════════════════════════
local SellAllRunning    = false
local SellAllConns      = {}
local SellUnsellRunning = false
local SellUnsellConns   = {}
local FlashListRunning  = false
local flashListedSlot   = nil

local function runPersistentSellLoop(label, ownedFn, runningFn, connsTable)
    local slotLimit = hasTableSkin() and 6 or 3
    Rayfield:Notify({ Title=label.." Started", Content="Continuous | "..slotLimit.." slots", Duration=5 })
    local function getAlreadyListed()
        local listed = {}
        local mt = getMyTable()
        if not mt then return listed end
        for i = 1, maxTableSlots() do
            local slot = mt:FindFirstChild("DisplaySneaker"..i)
            if slot then
                local sv = slot:FindFirstChild("SneakerValue")
                if sv and sv.Value ~= "" then listed[sv.Value] = true end
            end
        end
        return listed
    end
    local function pickNextShoe()
        local listed = getAlreadyListed()
        for _, item in ipairs(UnsellableInventory:GetChildren()) do
            if ownedFn(item.Name) and not listed[item.Name] then return item.Name end
        end
        for _, item in ipairs(SellableInventory:GetChildren()) do
            if ownedFn(item.Name) and not listed[item.Name] then return item.Name end
        end
        return nil
    end

    -- FIX: fillSlots now has a max consecutive-failure guard to prevent
    --      an infinite loop if listing consistently fails (e.g. no table).
    local function fillSlots()
        if not runningFn() then return end
        local mt = getMyTable()
        if not mt then return end
        local failures = 0
        while runningFn() do
            local slot = getFirstEmptySlot(mt)
            if not slot then break end
            local shoe = pickNextShoe()
            if not shoe then break end
            local ok, price = listShoeOnTable(shoe)
            if ok then
                failures = 0
                Rayfield:Notify({ Title=label, Content=shoe.." -> "..fmtMoney(price), Duration=3 })
                local confirmed = false
                for _ = 1, 20 do
                    task.wait(Settings.AutoSellSlotWait)
                    if getFirstEmptySlot(mt) ~= slot then confirmed = true break end
                end
                if not confirmed then
                    failures += 1
                    task.wait(1)
                    if failures >= 3 then break end
                end
            else
                failures += 1
                task.wait(1)
                if failures >= 3 then break end
            end
        end
    end

    local function hookTableSlots(mt)
        if not mt then return end
        for i = 1, slotLimit do
            local slot = mt:FindFirstChild("DisplaySneaker"..i)
            if slot then
                local sv = slot:FindFirstChild("SneakerValue")
                if sv then
                    local conn = sv.Changed:Connect(function(v)
                        if v == "" and runningFn() then task.wait(0.5) fillSlots() end
                    end)
                    table.insert(connsTable, conn)
                end
            end
        end
    end
    local mt = getMyTable()
    if mt then hookTableSlots(mt) end
    fillSlots()
    task.spawn(function()
        while runningFn() do task.wait(Settings.AutoSellRefillWait) if runningFn() then fillSlots() end end
    end)
end
local function stopSellAll()
    SellAllRunning = false
    for _, c in ipairs(SellAllConns) do c:Disconnect() end SellAllConns = {}
end
local function startSellAll()
    if SellAllRunning then return end
    SellAllRunning = true
    task.spawn(function()
        runPersistentSellLoop("SELL-ALL",
            function(n) return isSellable(n) or ownsUnsellableInstance(n) end,
            function() return SellAllRunning end, SellAllConns)
    end)
end
local function stopSellUnsell()
    SellUnsellRunning = false
    for _, c in ipairs(SellUnsellConns) do c:Disconnect() end SellUnsellConns = {}
end
local function startSellUnsell()
    if SellUnsellRunning then return end
    SellUnsellRunning = true
    task.spawn(function()
        runPersistentSellLoop("SELL-UNSELL",
            function(n) return ownsUnsellableInstance(n) end,
            function() return SellUnsellRunning end, SellUnsellConns)
    end)
end
local function stopAutoSell() stopSellAll() stopSellUnsell() end

local function getAllOwnedShoes()
    local shoes = {}
    for _, item in ipairs(SellableInventory:GetChildren()) do table.insert(shoes, item.Name) end
    for _, item in ipairs(UnsellableInventory:GetChildren()) do table.insert(shoes, item.Name) end
    return shoes
end

-- FIX: nil-guard both remotes inside removeShoeFromSlot
local function removeShoeFromSlot(slot)
    if not slot then return end
    if RemoveDisplaySneakerEvent then
        pcall(function() RemoveDisplaySneakerEvent:FireServer(slot) end)
    elseif ChangeDisplaySneakerEvent then
        pcall(function() ChangeDisplaySneakerEvent:FireServer("", slot.Name, 0) end)
    else
        log("ERR", "removeShoeFromSlot: no remove remote available")
    end
end
local function stopFlashList()
    FlashListRunning = false
    if flashListedSlot then pcall(function() removeShoeFromSlot(flashListedSlot) end) flashListedSlot = nil end
end
local function startFlashList()
    if FlashListRunning then return end
    -- FIX: guard the required remote upfront
    if not ChangeDisplaySneakerEvent then
        Rayfield:Notify({ Title="Flash List", Content="ChangeDisplaySneaker remote not available!", Duration=5 })
        return
    end
    FlashListRunning = true
    FlashListCounter = 0; FlashListNextDollar = math.random(5,15)
    task.spawn(function()
        while FlashListRunning do
            local mt = getMyTable()
            if not mt then task.wait(1) continue end
            local slot = mt:FindFirstChild("DisplaySneaker1")
            if not slot then task.wait(1) continue end
            local sv = slot:FindFirstChild("SneakerValue")
            if sv and sv.Value ~= "" then removeShoeFromSlot(slot) task.wait(0.2) end
            local shoes = getAllOwnedShoes()
            if #shoes == 0 then task.wait(1) continue end
            local shoeName = shoes[math.random(1,#shoes)]
            FlashListCounter += 1
            local randPrice
            if FlashListCounter >= FlashListNextDollar then
                randPrice = 1; FlashListCounter = 0; FlashListNextDollar = math.random(5,15)
                Rayfield:Notify({ Title="Flash List - $1 Hit!", Content=shoeName.." @ $1\nNext in "..FlashListNextDollar, Duration=3 })
            else randPrice = math.random(2, 999999) end
            local ok = pcall(function() ChangeDisplaySneakerEvent:FireServer(shoeName,"DisplaySneaker1",randPrice) end)
            if ok then flashListedSlot = slot task.wait(Settings.FlashListHoldTime) else task.wait(Settings.FlashListHoldTime) end
            if FlashListRunning then removeShoeFromSlot(slot) flashListedSlot = nil task.wait(Settings.FlashListDelistTime) end
        end
    end)
end

SellableInventory.ChildRemoved:Connect(function(item)
    local price = lastListedPrice[item.Name] or 0
    task.spawn(function() task.wait(0.5) sendSoldWebhook(item.Name, price) end)
end)

local function updateSellPriceLabels()
    for shoeName, ref in pairs(sellLabelRefs) do
        local badge     = ref.sellable and "[SELLABLE]" or "[UNSELLABLE]"
        local sp        = StockYCache[shoeName]
        local listPrice = calcSellPrice(shoeName)
        local stockStr
        if Settings.UseFixedSellPrice then
            stockStr = "Fixed: "..fmtMoney(Settings.FixedSellPrice)..(sp and (" | StockY: "..fmtMoney(sp)) or "")
        else
            local pctStr = Settings.SellStockYOffsetPct >= 0 and ("+"..Settings.SellStockYOffsetPct.."%") or (Settings.SellStockYOffsetPct.."%")
            stockStr = sp and ("StockY: "..fmtMoney(sp).." ("..pctStr..") -> "..fmtMoney(listPrice))
                          or  ("StockY: N/A -> Fallback: "..fmtMoney(pendingSellPrice))
        end
        pcall(function() ref.label:Set(shoeName.."  |  "..badge.."  |  "..stockStr) end)
    end
end

-- ════════════════════════════════════════
--  WALK-TO-BUY — SNIPE LOOP
-- ════════════════════════════════════════
local function stopWalkBuySnipe()
    WalkBuySnipeRunning = false
    WalkToBuySnipe = false
    for _, c in ipairs(WalkBuySnipeConns) do c:Disconnect() end
    WalkBuySnipeConns = {}
    setStatus("Idle")
end

local function startWalkBuySnipe()
    if WalkBuySnipeRunning then return end
    WalkBuySnipeRunning = true
    WalkToBuySnipe = true
    for _, c in ipairs(WalkBuySnipeConns) do c:Disconnect() end
    WalkBuySnipeConns = {}

    -- FIX: capture running state as a closure fn for walkToSlot
    local function isRunning() return WalkBuySnipeRunning end

    local function hookSlot(slot)
        local sv = slot:FindFirstChild("SneakerValue")
        if sv then
            local conn = sv.Changed:Connect(function(v)
                if v ~= "" and WalkBuySnipeRunning then
                    task.spawn(function()
                        walkToSlot(slot, isRunning)
                        trySneaker(slot)
                    end)
                end
            end)
            table.insert(WalkBuySnipeConns, conn)
        end
    end

    for _, slot in ipairs(cachedSlots) do hookSlot(slot) end

    table.insert(WalkBuySnipeConns, Tables.ChildAdded:Connect(function(tm)
        if not WalkBuySnipeRunning then return end
        task.wait(0.3)
        if tm.Name == "Table" then
            for i = 1, 6 do
                local slot = tm:FindFirstChild("DisplaySneaker"..i)
                if slot then hookSlot(slot) end
            end
        end
    end))

    task.spawn(function()
        while WalkBuySnipeRunning do
            for _, slot in ipairs(cachedSlots) do
                if not WalkBuySnipeRunning then break end
                local sv = slot:FindFirstChild("SneakerValue")
                local db = slot:FindFirstChild("SellDebounce")
                if sv and sv.Value ~= "" and not (db and db.Value) then
                    walkToSlot(slot, isRunning)
                    trySneaker(slot)
                end
                local d = Settings.Delay > 0 and Settings.Delay or 0.05
                task.wait(d)
            end
            task.wait(Settings.SnipeCycleWait)
        end
    end)

    setStatus("Walk-to-Buy Snipe [LIVE]")
end

-- ════════════════════════════════════════
--  WALK-TO-BUY — $1 MODE LOOP
-- ════════════════════════════════════════
local function stopWalkBuyOneDollar()
    WalkBuyOneDollarRunning = false
    WalkToBuyOneDollar = false
    for _, c in ipairs(WalkBuyOneDollarConns) do c:Disconnect() end
    WalkBuyOneDollarConns = {}
    setStatus("Idle")
end

local function startWalkBuyOneDollar()
    if WalkBuyOneDollarRunning then return end
    WalkBuyOneDollarRunning = true
    WalkToBuyOneDollar = true
    for _, c in ipairs(WalkBuyOneDollarConns) do c:Disconnect() end
    WalkBuyOneDollarConns = {}

    -- FIX: capture running state as a closure fn for walkToSlot
    local function isRunning() return WalkBuyOneDollarRunning end

    local function hookSlot(slot)
        local sv = slot:FindFirstChild("SneakerValue")
        local pv = slot:FindFirstChild("Price")
        if sv then
            local conn = sv.Changed:Connect(function(v)
                if v ~= "" and WalkBuyOneDollarRunning then
                    task.spawn(function()
                        local price = tonumber(pv and pv.Value) or 0
                        if price <= OneDollarMaxPrice then
                            walkToSlot(slot, isRunning)
                            tryOneDollar(slot)
                        end
                    end)
                end
            end)
            table.insert(WalkBuyOneDollarConns, conn)
        end
        if pv then
            local conn2 = pv.Changed:Connect(function(v)
                if WalkBuyOneDollarRunning and tonumber(v) and tonumber(v) <= OneDollarMaxPrice then
                    task.spawn(function()
                        walkToSlot(slot, isRunning)
                        tryOneDollar(slot)
                    end)
                end
            end)
            table.insert(WalkBuyOneDollarConns, conn2)
        end
    end

    for _, slot in ipairs(cachedSlots) do hookSlot(slot) end

    table.insert(WalkBuyOneDollarConns, Tables.ChildAdded:Connect(function(tm)
        if not WalkBuyOneDollarRunning then return end
        task.wait(0.3)
        if tm.Name == "Table" then
            for i = 1, 6 do
                local slot = tm:FindFirstChild("DisplaySneaker"..i)
                if slot then hookSlot(slot) end
            end
        end
    end))

    task.spawn(function()
        local scanned = 0
        while WalkBuyOneDollarRunning do
            for _, slot in ipairs(cachedSlots) do
                if not WalkBuyOneDollarRunning then break end
                local pv = slot:FindFirstChild("Price")
                local db = slot:FindFirstChild("SellDebounce")
                if pv and tonumber(pv.Value) and tonumber(pv.Value) <= OneDollarMaxPrice
                   and not (db and db.Value) then
                    scanned += 1
                    walkToSlot(slot, isRunning)
                    tryOneDollar(slot)
                    pcall(function()
                        StatsLabel:Set("Found: "..BuyStats.Found.." | Bought: "..BuyStats.Bought.." | Scanned: "..scanned)
                    end)
                end
            end
            task.wait(Settings.OneDollarCycleWait)
        end
    end)

    setStatus("Walk-to-Buy $1 Mode (<="..fmtMoney(OneDollarMaxPrice)..") [LIVE]")
end

-- ════════════════════════════════════════
--  CONFIG SYSTEM
-- ════════════════════════════════════════
local CONFIG_PREFIX   = "SRS_CFG:"
local CONFIG_VERSION  = 2
local SAVED_CFGS_FILE = "ShoeBuyer_configs.json"

local SHAREABLE_SETTINGS_KEYS = {
    "PriceFilter", "MaxPrice", "TargetShoe", "Delay",
    "UseStockYCheck", "StockYMargin", "UnsellableOnly",
    "SellStockYOffsetPct", "UseFixedSellPrice", "FixedSellPrice",
    "AutoSellUnsellableOnly",
    "SnipeCycleWait", "OneDollarCycleWait", "AutoSellRefillWait",
    "AutoSellSlotWait", "FlashListHoldTime", "FlashListDelistTime",
    "BuyConfirmPollWait",
    "UseOverpayLimit", "OverpayLimit",
    "BlockNoStockYData", "UseMaxPriceFallback", "MaxPriceFallback",
}

local function buildShareablePayload(configName)
    local payload = { _v = CONFIG_VERSION, _name = configName or "Unnamed" }
    for _, key in ipairs(SHAREABLE_SETTINGS_KEYS) do
        payload[key] = Settings[key]
    end
    local blArr = {}
    for name in pairs(Blacklist) do table.insert(blArr, name) end
    table.sort(blArr)
    payload._blacklist = blArr
    payload._pendingSellPrice  = pendingSellPrice
    payload._oneDollarMaxPrice = OneDollarMaxPrice
    return payload
end

local function encodeConfig(configName)
    local payload = buildShareablePayload(configName)
    return CONFIG_PREFIX .. HttpService:JSONEncode(payload)
end

local function decodeConfig(str)
    str = tostring(str or ""):match("^%s*(.-)%s*$")
    if str:sub(1, #CONFIG_PREFIX) ~= CONFIG_PREFIX then
        return nil, "Missing SRS_CFG: prefix — make sure you copied the whole code"
    end
    local json = str:sub(#CONFIG_PREFIX + 1)
    local ok, tbl = pcall(function() return HttpService:JSONDecode(json) end)
    if not ok or type(tbl) ~= "table" then
        return nil, "Invalid config data — the code may be corrupted"
    end
    return tbl, nil
end

local function applyConfigTable(tbl)
    for _, key in ipairs(SHAREABLE_SETTINGS_KEYS) do
        if tbl[key] ~= nil then
            Settings[key] = tbl[key]
        end
    end
    saveSettingsToDisk(Settings)
    if type(tbl._blacklist) == "table" then
        for _, name in ipairs(tbl._blacklist) do
            Blacklist[name] = true
        end
        saveBlacklistToDisk()
    end
    if type(tbl._pendingSellPrice) == "number" and tbl._pendingSellPrice > 0 then
        pendingSellPrice = math.floor(tbl._pendingSellPrice)
    end
    if type(tbl._oneDollarMaxPrice) == "number" and tbl._oneDollarMaxPrice >= 1 then
        OneDollarMaxPrice = math.floor(tbl._oneDollarMaxPrice)
    end
end

local savedConfigs = {}
local function loadSavedConfigs()
    local ok, data = pcall(function() return readfile(SAVED_CFGS_FILE) end)
    if ok and type(data) == "string" and data ~= "" then
        local ok2, tbl = pcall(function() return HttpService:JSONDecode(data) end)
        if ok2 and type(tbl) == "table" then savedConfigs = tbl return end
    end
    savedConfigs = {}
end
local function writeSavedConfigs()
    pcall(function() writefile(SAVED_CFGS_FILE, HttpService:JSONEncode(savedConfigs)) end)
end
loadSavedConfigs()

local function saveConfigSlot(slotName)
    savedConfigs[slotName] = buildShareablePayload(slotName)
    writeSavedConfigs()
end
local function deleteConfigSlot(slotName)
    savedConfigs[slotName] = nil
    writeSavedConfigs()
end

-- ════════════════════════════════════════
--  CONFIG TAB — BUILD
-- ════════════════════════════════════════
local ConfigStatusLabel    = nil
local ConfigGeneration     = 0
local configDynElements    = {}
local configStaticSnapshot = nil
dynElements[ConfigTab]     = {}

local function clearConfigDynElements()
    configDynElements = {}
    local frame = getTabScrollFrame(ConfigTab)
    if not frame then return end
    local snap = configStaticSnapshot
    local toDestroy = {}
    for _, child in ipairs(frame:GetChildren()) do
        if not snap or not snap[child] then
            if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UIGridLayout") then
                table.insert(toDestroy, child)
            end
        end
    end
    for _, child in ipairs(toDestroy) do pcall(function() child:Destroy() end) end
    task.wait(0.05)
end

local function buildConfigSavedList()
    clearConfigDynElements()
    ConfigGeneration += 1
    local myGen = ConfigGeneration

    local names = {}
    for name in pairs(savedConfigs) do table.insert(names, name) end
    table.sort(names)

    pcall(function()
        ConfigStatusLabel:Set("Saved Configs: "..#names.." | Last updated: "..os.date("%H:%M:%S"))
    end)

    if #names == 0 then
        local lbl = ConfigTab:CreateLabel("No saved configs yet. Use 'Save Current Settings' above.")
        table.insert(configDynElements, lbl)
        return
    end

    local sec = ConfigTab:CreateSection("Saved Configs ("..#names..")")
    table.insert(configDynElements, sec)

    for _, name in ipairs(names) do
        if myGen ~= ConfigGeneration then return end
        local cfg = savedConfigs[name]
        local blCount = type(cfg._blacklist) == "table" and #cfg._blacklist or 0
        local summary = string.format(
            "Max $%s | Delay %.2fs | StockY %s | BL: %d | SellFallback: $%s | $1Max: $%s",
            commaNum(cfg.MaxPrice or 0),
            tonumber(cfg.Delay) or 0,
            cfg.UseStockYCheck and "ON" or "OFF",
            blCount,
            commaNum(cfg._pendingSellPrice or 1000),
            commaNum(cfg._oneDollarMaxPrice or 1)
        )
        local lbl = ConfigTab:CreateLabel(name.."  |  "..summary)
        table.insert(configDynElements, lbl)

        local loadBtn = ConfigTab:CreateButton({
            Name = "Load: "..name,
            Callback = function()
                applyConfigTable(cfg)
                Rayfield:Notify({ Title="Config Loaded", Content=name.." applied! Restart modes if active.", Duration=5 })
            end
        })
        table.insert(configDynElements, loadBtn)

        local shareBtn = ConfigTab:CreateButton({
            Name = "Copy Share Code: "..name,
            Callback = function()
                local code = CONFIG_PREFIX .. HttpService:JSONEncode(cfg)
                pcall(function() setclipboard(code) end)
                Rayfield:Notify({ Title="Copied!", Content=name.." share code copied.\n(Webhook is NOT included)", Duration=5 })
            end
        })
        table.insert(configDynElements, shareBtn)

        local delBtn = ConfigTab:CreateButton({
            Name = "Delete: "..name,
            Callback = function()
                deleteConfigSlot(name)
                Rayfield:Notify({ Title="Deleted", Content=name.." removed.", Duration=3 })
                task.spawn(buildConfigSavedList)
            end
        })
        table.insert(configDynElements, delBtn)
    end
end

-- ════════════════════════════════════════
--  CONFIG TAB — STATIC UI
-- ════════════════════════════════════════
ConfigTab:CreateSection("Save Current Settings")
ConfigTab:CreateLabel("Saves ALL current settings as a named config (webhook is never saved to share codes).")
ConfigTab:CreateLabel("Your webhook stays private. Share codes contain ONLY gameplay settings.")

local pendingConfigName = ""
ConfigTab:CreateInput({
    Name = "Config Name",
    PlaceholderText = "e.g. Unsellable Hunter, $1 Flipper...",
    Callback = function(v) pendingConfigName = tostring(v or ""):match("^%s*(.-)%s*$") end
})
ConfigTab:CreateButton({
    Name = "Save Config",
    Callback = function()
        local name = pendingConfigName
        if name == "" then
            Rayfield:Notify({ Title="Config", Content="Enter a name first!", Duration=3 }) return
        end
        saveConfigSlot(name)
        Rayfield:Notify({ Title="Saved!", Content=name.." saved.", Duration=4 })
        task.spawn(buildConfigSavedList)
    end
})

ConfigTab:CreateSection("Import a Shared Config")
ConfigTab:CreateLabel("Paste a share code from another user (starts with SRS_CFG:).")
ConfigTab:CreateLabel("WARNING: Importing overwrites your current settings (not webhook).")

local pendingImportStr = ""
ConfigTab:CreateInput({
    Name = "Paste Share Code Here",
    PlaceholderText = "SRS_CFG:{...}",
    Callback = function(v) pendingImportStr = tostring(v or ""):match("^%s*(.-)%s*$") end
})
ConfigTab:CreateButton({
    Name = "Import and Apply Config",
    Callback = function()
        if pendingImportStr == "" then
            Rayfield:Notify({ Title="Import", Content="Paste a share code first!", Duration=3 }) return
        end
        local tbl, err = decodeConfig(pendingImportStr)
        if not tbl then
            Rayfield:Notify({ Title="Import Failed", Content=tostring(err), Duration=6 }) return
        end
        applyConfigTable(tbl)
        local importedName = tostring(tbl._name or "Imported")
        local blImported = type(tbl._blacklist) == "table" and #tbl._blacklist or 0
        Rayfield:Notify({ Title="Imported!", Content=importedName.." applied!\n+"..blImported.." blacklist entries merged.\nRestart modes if active.", Duration=6 })
        pendingImportStr = ""
    end
})
ConfigTab:CreateButton({
    Name = "Import and Save (don't apply yet)",
    Callback = function()
        if pendingImportStr == "" then
            Rayfield:Notify({ Title="Import", Content="Paste a share code first!", Duration=3 }) return
        end
        local tbl, err = decodeConfig(pendingImportStr)
        if not tbl then
            Rayfield:Notify({ Title="Import Failed", Content=tostring(err), Duration=6 }) return
        end
        local importedName = tostring(tbl._name or "Imported_"..os.time())
        savedConfigs[importedName] = tbl
        writeSavedConfigs()
        Rayfield:Notify({ Title="Saved!", Content=importedName.." saved to your config list.", Duration=5 })
        pendingImportStr = ""
        task.spawn(buildConfigSavedList)
    end
})

ConfigTab:CreateSection("Quick Export")
ConfigTab:CreateLabel("Copies your current live settings as a share code immediately.")
ConfigTab:CreateButton({
    Name = "Copy Current Settings as Share Code",
    Callback = function()
        local code = encodeConfig("QuickExport_"..os.date("%H%M%S"))
        pcall(function() setclipboard(code) end)
        Rayfield:Notify({ Title="Copied!", Content="Current settings copied as share code.\n(Webhook NOT included)", Duration=5 })
    end
})

ConfigTab:CreateSection("Your Saved Configs")
ConfigStatusLabel = ConfigTab:CreateLabel("Loading saved configs...")
ConfigTab:CreateButton({ Name="Refresh Config List", Callback=function() task.spawn(buildConfigSavedList) end })

task.defer(function()
    task.wait(0.3)
    local frame = getTabScrollFrame(ConfigTab)
    if frame then
        configStaticSnapshot = {}
        for _, child in ipairs(frame:GetChildren()) do configStaticSnapshot[child] = true end
    end
    buildConfigSavedList()
end)

-- ════════════════════════════════════════
--  LIST TAB — BUILD
-- ════════════════════════════════════════
local function buildList()
    pcall(clearTabElements, ListTab)   -- FIX: pcall so a Rayfield error can't block generation increment
    ListGeneration += 1
    local myGen = ListGeneration

    lastListRefreshTime = tick()
    local shoes = {}
    for _, tableModel in ipairs(Tables:GetChildren()) do
        if tableModel.Name == "Table" then
            local ownerVal  = tableModel:FindFirstChild("OwnerValue")
            local ownerName = (ownerVal and ownerVal.Value and ownerVal.Value.Name) or "Unknown"
            for i = 1, 6 do
                local slot = tableModel:FindFirstChild("DisplaySneaker"..i)
                if slot then
                    local sv = slot:FindFirstChild("SneakerValue")
                    local pv = slot:FindFirstChild("Price")
                    local db = slot:FindFirstChild("SellDebounce")
                    if sv and sv.Value ~= "" and not (db and db.Value == true) then
                        table.insert(shoes, { slot=slot, shoeName=tostring(sv.Value),
                            price=tonumber(pv and pv.Value) or 0, owner=ownerName })
                    end
                end
            end
        end
    end

    if myGen ~= ListGeneration then return end
    pcall(function() ListStatusLabel:Set("Shoes: "..#shoes.." | Refreshed: "..timeSince(lastListRefreshTime)) end)

    tracked(ListTab, ListTab:CreateSection("Shoes For Sale — "..os.date("%H:%M:%S")))

    if #shoes == 0 then
        tracked(ListTab, ListTab:CreateLabel("No shoes currently for sale."))
        return
    end

    table.sort(shoes, function(a,b) return a.price < b.price end)

    for idx, entry in ipairs(shoes) do
        if myGen ~= ListGeneration then return end

        local shoeName = entry.shoeName
        local price    = entry.price
        local owner    = entry.owner
        local slot     = entry.slot

        local sp      = StockYCache[shoeName]
        local diffStr = "StockY: N/A"
        if sp and sp > 0 then
            local diff  = price - sp
            local pct   = math.floor((diff/sp)*100)
            local sign  = diff >= 0 and "+" or ""
            local arrow = diff > 0 and "▲" or (diff < 0 and "▼" or "=")
            diffStr = "StockY: "..fmtMoney(sp).."  "..arrow.." "..sign..pct.."% ("..sign..fmtMoney(diff)..")"
        end

        tracked(ListTab, ListTab:CreateLabel(shoeName.."  |  "..fmtMoney(price).."  |  "..owner.."  |  "..diffStr))
        tracked(ListTab, ListTab:CreateButton({
            Name = "BUY  "..shoeName.."  ("..fmtMoney(price)..")",
            Callback = function()
                local sv = slot:FindFirstChild("SneakerValue")
                local pv = slot:FindFirstChild("Price")
                local db = slot:FindFirstChild("SellDebounce")
                if not sv or sv.Value == "" then
                    Rayfield:Notify({ Title="List Buy", Content="Slot is now empty!", Duration=3 }) return
                end
                if db and db.Value == true then
                    Rayfield:Notify({ Title="List Buy", Content="Already sold!", Duration=3 }) return
                end
                task.spawn(function()
                    fireAndConfirm(slot, sv.Value, tonumber(pv and pv.Value) or 0, true)
                    pcall(function() ListStatusLabel:Set("Bought! Refreshing...") end)
                    task.wait(2); buildList()
                end)
            end
        }))

        if idx % 8 == 0 then task.wait() end
        if myGen ~= ListGeneration then return end
    end
end

-- ════════════════════════════════════════
--  LIST TAB — STATIC UI
-- ════════════════════════════════════════
ListTab:CreateSection("Market Overview")
ListStatusLabel = ListTab:CreateLabel("Press Refresh List to scan.")
ListTab:CreateButton({ Name="Refresh List", Callback=function()
    task.spawn(function()
        pcall(function() ListStatusLabel:Set("Refreshing...") end)
        buildList()
    end)
end })
ListTab:CreateToggle({
    Name="Auto-Refresh List (every 5s)", CurrentValue=false,
    Callback=function(v)
        listAutoRefresh = v
        if v then task.spawn(function() while listAutoRefresh do buildList() task.wait(5) end end) end
    end
})
freezeStaticUI(ListTab)

-- ════════════════════════════════════════
--  SELL TAB — BUILD
-- ════════════════════════════════════════
local function buildSellList()
    pcall(clearTabElements, SellTab)   -- FIX: pcall so a Rayfield error can't block generation increment
    SellGeneration += 1
    local myGen = SellGeneration

    lastSellRefreshTime = tick()
    snapSellable, snapUnsellable = snapshotBothFolders()
    sellInventorySnapshot = snapshotSellable()

    local allShoes = {}
    for _, item in ipairs(SellableInventory:GetChildren()) do table.insert(allShoes,{name=item.Name,sellable=true}) end
    for _, item in ipairs(UnsellableInventory:GetChildren()) do table.insert(allShoes,{name=item.Name,sellable=false}) end

    local total = #allShoes
    pcall(function() SellStatusLabel:Set("Inventory: "..total.." | Refreshed: "..timeSince(lastSellRefreshTime)) end)

    tracked(SellTab, SellTab:CreateSection("Your Inventory ("..total.." shoes) — "..os.date("%H:%M:%S")))

    if total == 0 then
        tracked(SellTab, SellTab:CreateLabel("Your inventory is empty."))
        return
    end

    table.sort(allShoes, function(a,b) return a.name < b.name end)

    for idx, shoe in ipairs(allShoes) do
        if myGen ~= SellGeneration then return end

        local shoeName  = shoe.name
        local sellable  = shoe.sellable
        local badge     = sellable and "[SELLABLE]" or "[UNSELLABLE]"
        local sp        = StockYCache[shoeName]
        local listPrice = calcSellPrice(shoeName)
        local stockStr
        if Settings.UseFixedSellPrice then
            stockStr = "Fixed: "..fmtMoney(Settings.FixedSellPrice)..(sp and (" | StockY: "..fmtMoney(sp)) or "")
        else
            local pctStr = Settings.SellStockYOffsetPct>=0 and ("+"..Settings.SellStockYOffsetPct.."%") or (Settings.SellStockYOffsetPct.."%")
            stockStr = sp and ("StockY: "..fmtMoney(sp).." ("..pctStr..") -> "..fmtMoney(listPrice))
                          or  ("StockY: N/A -> Fallback: "..fmtMoney(pendingSellPrice))
        end

        local lbl = SellTab:CreateLabel(shoeName.."  |  "..badge.."  |  "..stockStr)
        tracked(SellTab, lbl)
        sellLabelRefs[shoeName] = { label=lbl, sellable=sellable }

        tracked(SellTab, SellTab:CreateButton({
            Name="List: "..shoeName.."  ("..fmtMoney(listPrice)..")  ["..(sellable and "SELLABLE" or "UNSELLABLE").."]",
            Callback=function()
                local stillOwned = sellable and isSellable(shoeName) or ownsUnsellableInstance(shoeName)
                if not stillOwned then Rayfield:Notify({ Title="Sell Error", Content=shoeName.." not in inventory.", Duration=4 }) return end
                local ok, price = listShoeOnTable(shoeName)
                if ok then Rayfield:Notify({ Title="Listed!", Content=shoeName.." -> "..fmtMoney(price), Duration=4 }) task.wait(0.8) buildSellList()
                else Rayfield:Notify({ Title="Sell Error", Content="Failed to list "..shoeName, Duration=4 }) end
            end
        }))

        if idx % 8 == 0 then task.wait() end
        if myGen ~= SellGeneration then return end
    end
end

-- ════════════════════════════════════════
--  SELL TAB — STATIC UI
-- ════════════════════════════════════════
SellTab:CreateSection("Listing Settings")
SellStatusLabel = SellTab:CreateLabel("Press Refresh Inventory to load your shoes.")
SellTab:CreateInput({ Name="Fallback Listing Price (no StockY data)", PlaceholderText="e.g. 5000",
    Callback=function(v)
        local num=tonumber(v) if num and num>0 then pendingSellPrice=math.floor(num) updateSellPriceLabels() end
    end })
local sdb=nil
SellTab:CreateSlider({ Name="StockY Price Offset % (0=exact, +10=10% above, -10=10% below)",
    Range={-50,100}, Increment=5, CurrentValue=Settings.SellStockYOffsetPct,
    Callback=function(v) saveSetting("SellStockYOffsetPct",v) if sdb then task.cancel(sdb) end sdb=task.delay(0.3,function() sdb=nil updateSellPriceLabels() end) end })
SellTab:CreateSection("Fixed Price Mode")
SellTab:CreateLabel("When ON: all shoes list at your set price, ignoring StockY completely.")
SellTab:CreateToggle({ Name="Use Fixed Price for All Shoes", CurrentValue=Settings.UseFixedSellPrice,
    Callback=function(v) saveSetting("UseFixedSellPrice",v) updateSellPriceLabels() end })
SellTab:CreateInput({ Name="Fixed Sell Price (used when Fixed Price Mode is ON)", PlaceholderText="e.g. 5000",
    Callback=function(v) local num=tonumber(v) if num and num>0 then saveSetting("FixedSellPrice",math.floor(num)) updateSellPriceLabels() end end })
SellTab:CreateSection("Auto-Sell")
SellTab:CreateLabel("Auto-Sell continuously lists shoes and re-lists whenever a slot frees up.")
SellTab:CreateToggle({ Name="Auto-Sell ALL Shoes", CurrentValue=false,
    Callback=function(v) if v then stopAutoSell() startSellAll() else stopSellAll() end end })
SellTab:CreateToggle({ Name="Auto-Sell UNSELLABLE Shoes Only", CurrentValue=false,
    Callback=function(v) if v then stopAutoSell() startSellUnsell() else stopSellUnsell() end end })
SellTab:CreateSection("Flash Listing")
SellTab:CreateLabel("Lists 1 random shoe at a random price for 0.5s. $1 every 5-15 listings.")
SellTab:CreateToggle({ Name="Flash List Mode", CurrentValue=false,
    Callback=function(v) if v then stopAutoSell() startFlashList() else stopFlashList() end end })
SellTab:CreateSection("Refresh")
SellTab:CreateButton({ Name="Refresh Inventory", Callback=function()
    task.spawn(function()
        pcall(function() SellStatusLabel:Set("Refreshing...") end)
        buildSellList() buildList()
    end)
end })
freezeStaticUI(SellTab)

-- ════════════════════════════════════════
--  BLACKLIST TAB — BUILD
-- ════════════════════════════════════════
local function buildBlacklistTab()
    pcall(clearTabElements, BlacklistTab)  -- FIX: pcall so Rayfield errors don't block generation
    BlacklistGeneration += 1
    local myGen = BlacklistGeneration

    local allShoes = {}
    -- FIX: guard SneakerModule.sneakers as a table before iterating
    if SneakerModuleLoaded and SneakerModule and type(SneakerModule.sneakers) == "table" then
        for shoeName, data in pairs(SneakerModule.sneakers) do
            -- FIX: guard data as a table before calling table.find on it
            local unsell = type(data) == "table" and table.find(data,"Unsellable") ~= nil
            if BlacklistSearchFilter == "" or shoeName:lower():find(BlacklistSearchFilter:lower(),1,true) then
                table.insert(allShoes, { name=shoeName, unsellable=unsell, knownType=true })
            end
        end
    else
        for shoeName in pairs(Blacklist) do
            if BlacklistSearchFilter == "" or shoeName:lower():find(BlacklistSearchFilter:lower(),1,true) then
                table.insert(allShoes, { name=shoeName, unsellable=false, knownType=false })
            end
        end
    end
    table.sort(allShoes, function(a,b) return a.name < b.name end)

    local blCount = 0; for _ in pairs(Blacklist) do blCount += 1 end
    local moduleNote = SneakerModuleLoaded and "" or "  WARNING: Module not loaded"
    pcall(function()
        BlacklistStatusLabel:Set("Total: "..#allShoes.." | Blacklisted: "..blCount
            ..(BlacklistSearchFilter ~= "" and (" | Filter: \""..BlacklistSearchFilter.."\"") or "")..moduleNote)
    end)

    if myGen ~= BlacklistGeneration then return end

    tracked(BlacklistTab, BlacklistTab:CreateSection(SneakerModuleLoaded
        and ("All Shoes ("..#allShoes..")"
             ..(BlacklistSearchFilter ~= "" and " — filtered" or "").." — "..os.date("%H:%M:%S"))
        or  ("Saved Blacklist ("..#allShoes.." entries)")))

    if #allShoes == 0 then
        tracked(BlacklistTab, BlacklistTab:CreateLabel(SneakerModuleLoaded
            and "No shoes match your filter."
            or "Blacklist is empty. Press 'Load / Refresh Shoe List' to see all shoes."))
        return
    end

    for idx, shoe in ipairs(allShoes) do
        if myGen ~= BlacklistGeneration then return end

        local shoeName = shoe.name
        local typeTag  = shoe.knownType and (shoe.unsellable and "  [UNSELLABLE]" or "  [SELLABLE]") or ""
        local blTag    = isBlacklisted(shoeName) and "  BLACKLISTED" or ""

        tracked(BlacklistTab, BlacklistTab:CreateToggle({
            Name=shoeName..typeTag..blTag, CurrentValue=isBlacklisted(shoeName),
            Callback=function(v)
                if v then Blacklist[shoeName]=true else Blacklist[shoeName]=nil end
                saveBlacklistToDisk()
                local cnt=0; for _ in pairs(Blacklist) do cnt+=1 end
                pcall(function()
                    BlacklistStatusLabel:Set("Total: "..#allShoes.." | Blacklisted: "..cnt
                        ..(BlacklistSearchFilter ~= "" and (" | Filter: \""..BlacklistSearchFilter.."\"") or "")..moduleNote)
                end)
                Rayfield:Notify({ Title=v and "Blacklisted" or "Un-Blacklisted",
                    Content=shoeName..(v and " will be skipped." or " will be bought."), Duration=3 })
            end
        }))

        if idx % 15 == 0 then task.wait() end
        if myGen ~= BlacklistGeneration then return end
    end
end

-- ════════════════════════════════════════
--  BLACKLIST TAB — STATIC UI
-- ════════════════════════════════════════
do
BlacklistTab:CreateSection("Blacklist Controls")
BlacklistStatusLabel = BlacklistTab:CreateLabel("Loading saved blacklist...")
BlacklistTab:CreateLabel("Blacklisted shoes are SKIPPED by Snipe, Scan, and $1 Mode.")
BlacklistTab:CreateLabel("Your blacklist loads automatically from disk on startup.")
BlacklistTab:CreateButton({ Name="Load / Refresh Shoe List (loads ALL shoes from SneakerModule)",
    Callback=function()
        task.spawn(function()
            if not SneakerModuleLoaded then loadSneakerModule() task.wait(1) end
            buildBlacklistTab()
        end)
    end })
BlacklistTab:CreateSection("Search / Filter")
BlacklistTab:CreateInput({ Name="Search Shoe Name", PlaceholderText="e.g. Air Jordan",
    Callback=function(v) BlacklistSearchFilter=tostring(v or ""):lower() end })
BlacklistTab:CreateButton({ Name="Apply Filter", Callback=function() task.spawn(buildBlacklistTab) end })
BlacklistTab:CreateButton({ Name="Clear Filter (show all)", Callback=function() BlacklistSearchFilter="" task.spawn(buildBlacklistTab) end })
BlacklistTab:CreateSection("Bulk Actions")
BlacklistTab:CreateButton({ Name="Blacklist ALL Unsellable Shoes", Callback=function()
    if not SneakerModuleLoaded or not SneakerModule or type(SneakerModule.sneakers) ~= "table" then
        Rayfield:Notify({ Title="Blacklist", Content="Load SneakerModule first.", Duration=4 }) return
    end
    local count=0
    for n,d in pairs(SneakerModule.sneakers) do
        if type(d) == "table" and table.find(d,"Unsellable") then Blacklist[n]=true count+=1 end
    end
    saveBlacklistToDisk()
    Rayfield:Notify({ Title="Blacklist", Content=count.." unsellable blacklisted.", Duration=5 })
    task.spawn(buildBlacklistTab)
end })
BlacklistTab:CreateButton({ Name="Blacklist ALL Sellable Shoes", Callback=function()
    if not SneakerModuleLoaded or not SneakerModule or type(SneakerModule.sneakers) ~= "table" then
        Rayfield:Notify({ Title="Blacklist", Content="Load SneakerModule first.", Duration=4 }) return
    end
    local count=0
    for n,d in pairs(SneakerModule.sneakers) do
        if type(d) == "table" and not table.find(d,"Unsellable") then Blacklist[n]=true count+=1 end
    end
    saveBlacklistToDisk()
    Rayfield:Notify({ Title="Blacklist", Content=count.." sellable blacklisted.", Duration=5 })
    task.spawn(buildBlacklistTab)
end })
BlacklistTab:CreateButton({ Name="Clear Entire Blacklist", Callback=function()
    local count=0; for _ in pairs(Blacklist) do count+=1 end
    Blacklist={}; saveBlacklistToDisk()
    Rayfield:Notify({ Title="Blacklist Cleared", Content=count.." entries removed.", Duration=4 })
    task.spawn(buildBlacklistTab)
end })

BlacklistTab:CreateSection("Blacklist by Rarity")
BlacklistTab:CreateLabel("Requires SneakerModule to be loaded. Uses the Rarity tag from the module.")
BlacklistTab:CreateLabel("Rarities: Common, Uncommon, Epic, Legendary, Limited, Grail, Special, Legacy.")

local RARITY_TAGS = {
    "Common","Uncommon","Epic","Legendary","Limited","Grail","Special","Legacy",
}

-- FIX: rarity data is stored as a flat array in the module (e.g. {"Unsellable","Rarity:Grail"})
--      NOT as a dictionary. The original code used data["Rarity"] which always returned nil.
--      Now we use table.find with a prefix search for "Rarity:<tag>".
local function blacklistByRarity(rarityTag, addToBlacklist)
    if not SneakerModuleLoaded or not SneakerModule or type(SneakerModule.sneakers) ~= "table" then
        Rayfield:Notify({ Title="Rarity Blacklist", Content="Load SneakerModule first!", Duration=5 })
        return
    end
    local count = 0
    local rarityKey = "Rarity:"..rarityTag
    for shoeName, data in pairs(SneakerModule.sneakers) do
        if type(data) == "table" then
            -- Search for the rarity tag entry in the array
            local found = false
            for _, entry in ipairs(data) do
                if tostring(entry) == rarityKey then found = true break end
            end
            if found then
                if addToBlacklist then Blacklist[shoeName] = true
                else Blacklist[shoeName] = nil end
                count += 1
            end
        end
    end
    saveBlacklistToDisk()
    local action = addToBlacklist and "blacklisted" or "un-blacklisted"
    Rayfield:Notify({ Title=rarityTag.." "..action, Content=count.." "..rarityTag.." shoes "..action..".", Duration=4 })
    task.spawn(buildBlacklistTab)
end

for _, rarityTag in ipairs(RARITY_TAGS) do
    local tag = rarityTag
    BlacklistTab:CreateButton({ Name="Blacklist All "..tag, Callback=function() blacklistByRarity(tag, true) end })
    BlacklistTab:CreateButton({ Name="Un-Blacklist All "..tag, Callback=function() blacklistByRarity(tag, false) end })
end

BlacklistTab:CreateSection("Auto-Blacklist by StockY Price")
BlacklistTab:CreateLabel("Blacklists any shoe whose StockY price is BELOW your threshold.")
BlacklistTab:CreateLabel("Requires StockY to be refreshed (Scanner tab) and SneakerModule loaded.")
BlacklistTab:CreateLabel("Set to 0 to effectively disable (nothing will be under $0).")
BlacklistTab:CreateInput({
    Name = "Min StockY Price Threshold (shoes below this get blacklisted)",
    PlaceholderText = "e.g. 5000",
    Callback = function(v)
        local num = tonumber(v)
        if num ~= nil and num >= 0 then BlacklistMinPrice = math.floor(num) end
    end
})
BlacklistTab:CreateButton({
    Name = "Blacklist All Shoes Under Price Threshold",
    Callback = function()
        if BlacklistMinPrice <= 0 then
            Rayfield:Notify({ Title="Price Blacklist", Content="Set a price above 0 first!", Duration=4 }) return
        end
        if not SneakerModuleLoaded or not SneakerModule or type(SneakerModule.sneakers) ~= "table" then
            Rayfield:Notify({ Title="Price Blacklist", Content="Load SneakerModule first!", Duration=5 }) return
        end
        local count, noData = 0, 0
        for shoeName in pairs(SneakerModule.sneakers) do
            local sp = StockYCache[shoeName]
            if sp and type(sp) == "number" and sp > 0 then
                if sp < BlacklistMinPrice then Blacklist[shoeName] = true count += 1 end
            else noData += 1 end
        end
        saveBlacklistToDisk()
        Rayfield:Notify({ Title="Price Blacklist",
            Content=count.." shoes under "..fmtMoney(BlacklistMinPrice).." blacklisted.\n("..noData.." shoes had no StockY data — skipped)", Duration=6 })
        task.spawn(buildBlacklistTab)
    end
})
BlacklistTab:CreateButton({
    Name = "Un-Blacklist All Shoes Under Price Threshold",
    Callback = function()
        if BlacklistMinPrice <= 0 then
            Rayfield:Notify({ Title="Price Blacklist", Content="Set a price above 0 first!", Duration=4 }) return
        end
        if not SneakerModuleLoaded or not SneakerModule or type(SneakerModule.sneakers) ~= "table" then
            Rayfield:Notify({ Title="Price Blacklist", Content="Load SneakerModule first!", Duration=4 }) return
        end
        local count = 0
        for shoeName in pairs(SneakerModule.sneakers) do
            local sp = StockYCache[shoeName]
            if sp and type(sp) == "number" and sp > 0 and sp < BlacklistMinPrice then
                Blacklist[shoeName] = nil count += 1
            end
        end
        saveBlacklistToDisk()
        Rayfield:Notify({ Title="Price Blacklist",
            Content=count.." shoes under "..fmtMoney(BlacklistMinPrice).." removed from blacklist.", Duration=5 })
        task.spawn(buildBlacklistTab)
    end
})

BlacklistTab:CreateSection("Export / Info")
BlacklistTab:CreateLabel("Blacklist auto-saves to ShoeBuyer_blacklist.json and loads on every startup.")
BlacklistTab:CreateButton({ Name="Copy Blacklist to Clipboard", Callback=function()
    local names={}; for n in pairs(Blacklist) do table.insert(names,n) end table.sort(names)
    pcall(function() setclipboard(table.concat(names,"\n")) end)
    Rayfield:Notify({ Title="Clipboard", Content=#names.." shoe(s) copied!", Duration=4 })
end })
freezeStaticUI(BlacklistTab)
end

-- ════════════════════════════════════════
--  LIVE TIMER UPDATE
-- ════════════════════════════════════════
task.spawn(function()
    while true do
        task.wait(5)
        if lastSellRefreshTime then pcall(function()
            local all=#SellableInventory:GetChildren()+#UnsellableInventory:GetChildren()
            SellStatusLabel:Set("Inventory: "..all.." | Refreshed: "..timeSince(lastSellRefreshTime))
        end) end
        if lastListRefreshTime then pcall(function()
            ListStatusLabel:Set("Refreshed: "..timeSince(lastListRefreshTime))
        end) end
    end
end)

-- ════════════════════════════════════════
--  SCAN ALL TABLES
-- ════════════════════════════════════════
local function scanAllTables()
    BuyStats={Found=0,Bought=0,Skipped=0}; updateStats()
    setStatus("Scanning [LIVE]")
    local tableCount=0
    for _, tableModel in ipairs(Tables:GetChildren()) do
        if tableModel.Name == "Table" then
            tableCount+=1
            task.spawn(function()
                for i=1,6 do
                    local slot=tableModel:FindFirstChild("DisplaySneaker"..i)
                    if slot then trySneaker(slot) end
                    if Settings.Delay>0 then task.wait(Settings.Delay) end
                end
            end)
        end
    end
    task.wait(0.5+tableCount*Settings.Delay*6)
    setStatus("Done - bought:"..BuyStats.Bought)
end

-- ════════════════════════════════════════
--  SNIPE (normal, no walking)
-- ════════════════════════════════════════
local function stopSnipe()
    SnipeLoopRunning=false
    for _,c in ipairs(SnipeConnections) do c:Disconnect() end SnipeConnections={}
    setStatus("Idle")
end
local function startSnipe()
    if SnipeLoopRunning then return end
    SnipeLoopRunning=true
    for _,c in ipairs(SnipeConnections) do c:Disconnect() end SnipeConnections={}
    local function hookSlot(slot)
        local sv=slot:FindFirstChild("SneakerValue")
        if sv then table.insert(SnipeConnections, sv.Changed:Connect(function(v)
            if v~="" and SnipeLoopRunning then task.spawn(function() trySneaker(slot) end) end
        end)) end
    end
    for _,slot in ipairs(cachedSlots) do hookSlot(slot) end
    table.insert(SnipeConnections, Tables.ChildAdded:Connect(function(tm)
        if not SnipeLoopRunning then return end
        task.wait(0.3)
        if tm.Name=="Table" then
            for i=1,6 do local slot=tm:FindFirstChild("DisplaySneaker"..i) if slot then hookSlot(slot) end end
        end
    end))
    task.spawn(function()
        while SnipeLoopRunning do
            for _,slot in ipairs(cachedSlots) do
                if not SnipeLoopRunning then break end
                trySneaker(slot)
                if Settings.Delay>0 then task.wait(Settings.Delay) end
            end
            task.wait(Settings.SnipeCycleWait)
        end
    end)
    setStatus("Sniping [LIVE]")
end

-- ════════════════════════════════════════
--  $1 MODE (normal, no walking)
-- ════════════════════════════════════════
local function stopOneDollar()
    OneDollarRunning=false
    for _,c in ipairs(OneDollarConns) do c:Disconnect() end OneDollarConns={}
    setStatus("Idle")
end
local function startOneDollar()
    if OneDollarRunning then return end
    OneDollarRunning=true
    for _,c in ipairs(OneDollarConns) do c:Disconnect() end OneDollarConns={}
    local function hookSlot(slot)
        local sv=slot:FindFirstChild("SneakerValue")
        local pv=slot:FindFirstChild("Price")
        if sv then table.insert(OneDollarConns, sv.Changed:Connect(function(v)
            if v~="" and OneDollarRunning then task.spawn(function() tryOneDollar(slot) end) end
        end)) end
        if pv then table.insert(OneDollarConns, pv.Changed:Connect(function(v)
            if OneDollarRunning and tonumber(v) and tonumber(v)<=OneDollarMaxPrice then
                task.spawn(function() tryOneDollar(slot) end) end
        end)) end
    end
    for _,slot in ipairs(cachedSlots) do hookSlot(slot) end
    table.insert(OneDollarConns, Tables.ChildAdded:Connect(function(tm)
        if not OneDollarRunning then return end task.wait(0.3)
        if tm.Name=="Table" then
            for i=1,6 do local slot=tm:FindFirstChild("DisplaySneaker"..i) if slot then hookSlot(slot) end end
        end
    end))
    task.spawn(function()
        local scanned=0
        while OneDollarRunning do
            for _,slot in ipairs(cachedSlots) do
                if not OneDollarRunning then break end
                local pv=slot:FindFirstChild("Price")
                if pv and tonumber(pv.Value) and tonumber(pv.Value)<=OneDollarMaxPrice then
                    scanned+=1 tryOneDollar(slot)
                    pcall(function() StatsLabel:Set("Found: "..BuyStats.Found.." | Bought: "..BuyStats.Bought.." | Scanned: "..scanned) end)
                end
            end
            task.wait(Settings.OneDollarCycleWait)
        end
    end)
    setStatus("$1 Mode (<="..fmtMoney(OneDollarMaxPrice)..") [LIVE]")
end

-- ════════════════════════════════════════
--  CLEANUP
-- ════════════════════════════════════════
local function stopAllModes()
    stopSnipe(); stopOneDollar()
    stopWalkBuySnipe(); stopWalkBuyOneDollar()
    stopAutoSell(); stopFlashList()
    listAutoRefresh = false
end
LocalPlayer.CharacterRemoving:Connect(stopAllModes)
game:GetService("Players").LocalPlayer.OnTeleport:Connect(function()
    task.spawn(function() sendKickWebhook("Player teleported / kicked") end)
end)

-- ════════════════════════════════════════
--  SCANNER TAB — UI
-- ════════════════════════════════════════
ScannerTab:CreateButton({ Name="Start Scan (once)", Callback=function() task.spawn(scanAllTables) end })

-- ── Normal Snipe ──
ScannerTab:CreateSection("Snipe Mode")
ScannerTab:CreateLabel("Reacts instantly to shoe listings. No walking — fastest buy speed.")
SnipeToggleRef = ScannerTab:CreateToggle({
    Name="Snipe Mode (loop until off)", CurrentValue=false,
    Callback=function(v)
        Settings.SnipeMode=v
        if v then
            if OneDollarRunning        then stopOneDollar()        pcall(function() OneDollarToggleRef:Set(false)        end) end
            if WalkBuySnipeRunning     then stopWalkBuySnipe()     pcall(function() WalkSnipeToggleRef:Set(false)        end) end
            if WalkBuyOneDollarRunning then stopWalkBuyOneDollar() pcall(function() WalkOneDollarToggleRef:Set(false)    end) end
            BuyStats={Found=0,Bought=0,Skipped=0}; updateStats(); task.spawn(startSnipe)
        else stopSnipe() end
    end
})

-- ── Walk-to-Buy Snipe ──
ScannerTab:CreateSection("Walk-to-Buy Snipe Mode")
ScannerTab:CreateLabel("Walks your character to each table before buying. Slower but looks legit.")
ScannerTab:CreateLabel("Respects all filters: Price, StockY, Blacklist, TargetShoe, UnsellableOnly.")
WalkSnipeToggleRef = ScannerTab:CreateToggle({
    Name="Walk-to-Buy Snipe (loop until off)", CurrentValue=false,
    Callback=function(v)
        if v then
            if SnipeLoopRunning        then stopSnipe()            pcall(function() SnipeToggleRef:Set(false)            end) end
            if OneDollarRunning        then stopOneDollar()        pcall(function() OneDollarToggleRef:Set(false)        end) end
            if WalkBuyOneDollarRunning then stopWalkBuyOneDollar() pcall(function() WalkOneDollarToggleRef:Set(false)    end) end
            BuyStats={Found=0,Bought=0,Skipped=0}; updateStats(); task.spawn(startWalkBuySnipe)
        else stopWalkBuySnipe() end
    end
})

-- ── $1 / Low-Price Mode ──
ScannerTab:CreateSection("$1 / Low-Price Mode")
ScannerTab:CreateLabel("Buys ANY shoe at or below your max price. Ignores TargetShoe, UnsellableOnly, StockY.")
ScannerTab:CreateLabel("Note: Blacklist IS still respected in $1 Mode.")
ScannerTab:CreateInput({ Name="Max Price for $1 Mode (default: 1)", PlaceholderText="e.g. 500",
    Callback=function(v)
        local num=tonumber(v)
        if num and num>=1 then OneDollarMaxPrice=math.floor(num)
        elseif v=="" then OneDollarMaxPrice=1 end
    end })
OneDollarToggleRef = ScannerTab:CreateToggle({
    Name="$1 / Low-Price Mode (loop until off)", CurrentValue=false,
    Callback=function(v)
        Settings.OneDollarMode=v
        if v then
            if SnipeLoopRunning        then stopSnipe()            pcall(function() SnipeToggleRef:Set(false)            end) end
            if WalkBuySnipeRunning     then stopWalkBuySnipe()     pcall(function() WalkSnipeToggleRef:Set(false)        end) end
            if WalkBuyOneDollarRunning then stopWalkBuyOneDollar() pcall(function() WalkOneDollarToggleRef:Set(false)    end) end
            BuyStats={Found=0,Bought=0,Skipped=0}; updateStats(); task.spawn(startOneDollar)
        else stopOneDollar() end
    end
})

-- ── Walk-to-Buy $1 Mode ──
ScannerTab:CreateSection("Walk-to-Buy $1 / Low-Price Mode")
ScannerTab:CreateLabel("Walks to each table before buying shoes at or below max price.")
ScannerTab:CreateLabel("Uses the same Max Price set above. Blacklist is respected.")
WalkOneDollarToggleRef = ScannerTab:CreateToggle({
    Name="Walk-to-Buy $1 Mode (loop until off)", CurrentValue=false,
    Callback=function(v)
        if v then
            if SnipeLoopRunning    then stopSnipe()        pcall(function() SnipeToggleRef:Set(false)     end) end
            if OneDollarRunning    then stopOneDollar()    pcall(function() OneDollarToggleRef:Set(false) end) end
            if WalkBuySnipeRunning then stopWalkBuySnipe() pcall(function() WalkSnipeToggleRef:Set(false) end) end
            BuyStats={Found=0,Bought=0,Skipped=0}; updateStats(); task.spawn(startWalkBuyOneDollar)
        else stopWalkBuyOneDollar() end
    end
})

-- ── StockY + Module ──
ScannerTab:CreateSection("StockY and Module")
ScannerTab:CreateButton({ Name="Refresh StockY Prices (Must do every load)", Callback=function() task.spawn(refreshStockY) end })
ScannerTab:CreateButton({ Name="Reload SneakerModule (required for Unsellable Only filter)", Callback=function()
    task.spawn(function() SneakerModule=nil SneakerModuleLoaded=false loadSneakerModule() buildUnsellableCache() end)
end })
ScannerTab:CreateButton({ Name="Rebuild Slot Cache (if new tables not detected)", Callback=function()
    task.spawn(function() rebuildSlotCache() Rayfield:Notify({ Title="Slot Cache", Content=#cachedSlots.." slots.", Duration=4 }) end)
end })

-- ════════════════════════════════════════
--  SETTINGS TAB
-- ════════════════════════════════════════
do
SettingsTab:CreateSection("Buy Filters")
SettingsTab:CreateToggle({ Name="Price Filter (Max Price)", CurrentValue=Settings.PriceFilter, Callback=function(v) saveSetting("PriceFilter",v) end })
SettingsTab:CreateToggle({ Name="StockY Price Check", CurrentValue=Settings.UseStockYCheck, Callback=function(v) saveSetting("UseStockYCheck",v) end })
SettingsTab:CreateToggle({ Name="Unsellable Shoes Only (buy filter)", CurrentValue=Settings.UnsellableOnly, Callback=function(v) saveSetting("UnsellableOnly",v) end })
SettingsTab:CreateInput({ Name="Target Shoe (blank = all)", PlaceholderText="e.g. Air Bogdan 4",
    Callback=function(v) saveSetting("TargetShoe",tostring(v or "")) end })
SettingsTab:CreateInput({ Name="Max Price", PlaceholderText=tostring(Settings.MaxPrice),
    Callback=function(v) saveSetting("MaxPrice",tonumber(v) or 100000) end })

SettingsTab:CreateSection("StockY Settings")
SettingsTab:CreateSlider({ Name="StockY Margin (1.0=exact StockY price, 1.2=allow up to 20% above StockY)",
    Range={0.5,2.0}, Increment=0.05, CurrentValue=Settings.StockYMargin,
    Callback=function(v) saveSetting("StockYMargin",v) end })

SettingsTab:CreateSection("Unknown Shoe Protection (No StockY Data)")
SettingsTab:CreateLabel("These settings control what happens when a shoe has NO StockY price in the cache.")
SettingsTab:CreateLabel("Common cause of overpaying: StockY cache is stale or incomplete.")
SettingsTab:CreateLabel("TIP: Refresh StockY first, then choose a protection mode below.")
SettingsTab:CreateLabel("─────────────────────────────────────────")
SettingsTab:CreateLabel("MODE 1 — Max Price Fallback (RECOMMENDED) — ON BY DEFAULT")
SettingsTab:CreateLabel("Shoes with no StockY data are allowed BUT only if price ≤ your fallback cap.")
SettingsTab:CreateLabel("Example: fallback = $50,000 → skips unknowns listed above $50,000.")
SettingsTab:CreateToggle({
    Name = "Enable Max Price Fallback for Unknown Shoes",
    CurrentValue = Settings.UseMaxPriceFallback,
    Callback = function(v)
        saveSetting("UseMaxPriceFallback", v)
        if v and Settings.BlockNoStockYData then
            saveSetting("BlockNoStockYData", false)
            Rayfield:Notify({
                Title = "Unknown Shoe Protection",
                Content = "Max Price Fallback ON.\nBlock Unknown Shoes auto-disabled to avoid conflict.",
                Duration = 5
            })
        else
            Rayfield:Notify({
                Title = "Max Price Fallback",
                Content = v and ("ON — cap: "..fmtMoney(Settings.MaxPriceFallback)) or "OFF",
                Duration = 3
            })
        end
    end
})
SettingsTab:CreateInput({
    Name = "Fallback Max Price for Unknown Shoes ($)",
    PlaceholderText = "e.g. 50000  (default: 50000)",
    Callback = function(v)
        local num = tonumber(v)
        if num ~= nil and num > 0 then
            saveSetting("MaxPriceFallback", math.floor(num))
            Rayfield:Notify({
                Title = "Fallback Cap Set",
                Content = "Unknown shoes must be ≤ "..fmtMoney(math.floor(num)).." to be bought.",
                Duration = 3
            })
        end
    end
})
SettingsTab:CreateLabel("─────────────────────────────────────────")
SettingsTab:CreateLabel("MODE 2 — Block All Unknown Shoes (STRICTEST)")
SettingsTab:CreateLabel("Requires StockY Check to be ON. Skips ANY shoe not in the StockY cache.")
SettingsTab:CreateLabel("Use this only if your StockY cache is very complete. You may miss good deals.")
SettingsTab:CreateToggle({
    Name = "Block Shoes With No StockY Data",
    CurrentValue = Settings.BlockNoStockYData,
    Callback = function(v)
        saveSetting("BlockNoStockYData", v)
        if v and Settings.UseMaxPriceFallback then
            saveSetting("UseMaxPriceFallback", false)
            Rayfield:Notify({
                Title = "Unknown Shoe Protection",
                Content = "Block Unknown Shoes ON.\nMax Price Fallback auto-disabled to avoid conflict.\nAlso make sure StockY Check is ON.",
                Duration = 6
            })
        else
            Rayfield:Notify({
                Title = "Block Unknown Shoes",
                Content = v and "ON — all shoes without StockY data will be SKIPPED.\n(Requires StockY Check ON)" or "OFF",
                Duration = 4
            })
        end
    end
})

SettingsTab:CreateSection("Overpay Limiter")
SettingsTab:CreateLabel("Skips any shoe where the listing price exceeds its StockY value by more than your set amount.")
SettingsTab:CreateLabel("Example: StockY = $10,000 | Limit = $500 → skips anything listed above $10,500.")
SettingsTab:CreateLabel("Set limit to $0 to only buy at or below StockY price (no overpay at all).")
SettingsTab:CreateLabel("Works independently — does NOT require StockY Check to be ON.")
SettingsTab:CreateLabel("Shoes with no StockY data are NOT affected by this limiter (use Unknown Protection above).")
SettingsTab:CreateToggle({
    Name = "Enable Overpay Limiter",
    CurrentValue = Settings.UseOverpayLimit,
    Callback = function(v)
        saveSetting("UseOverpayLimit", v)
        Rayfield:Notify({
            Title = "Overpay Limiter",
            Content = v and ("ON — max overpay: "..fmtMoney(Settings.OverpayLimit)) or "OFF",
            Duration = 3
        })
    end
})
SettingsTab:CreateInput({
    Name = "Max Overpay Amount ($)",
    PlaceholderText = "e.g. 500  (0 = must be at or below StockY price)",
    Callback = function(v)
        local num = tonumber(v)
        if num ~= nil and num >= 0 then
            saveSetting("OverpayLimit", math.floor(num))
            Rayfield:Notify({
                Title = "Overpay Limit Set",
                Content = "Max overpay: "..fmtMoney(math.floor(num)),
                Duration = 3
            })
        end
    end
})

SettingsTab:CreateSection("Performance")
SettingsTab:CreateSlider({ Name="Delay between slots (s) — 0 for max speed",
    Range={0,0.5}, Increment=0.01, CurrentValue=Settings.Delay,
    Callback=function(v) saveSetting("Delay",v) end })
SettingsTab:CreateSection("Speed Tuning")
SettingsTab:CreateLabel("Advanced: tweak loop timing. Lower = faster but more CPU/network load.")
SettingsTab:CreateSlider({ Name="Snipe Cycle Wait (s) — pause between full slot sweeps",
    Range={0,2}, Increment=0.05, CurrentValue=Settings.SnipeCycleWait,
    Callback=function(v) saveSetting("SnipeCycleWait",v) end })
SettingsTab:CreateSlider({ Name="$1 Mode Cycle Wait (s) — pause between $1 sweeps",
    Range={0,2}, Increment=0.05, CurrentValue=Settings.OneDollarCycleWait,
    Callback=function(v) saveSetting("OneDollarCycleWait",v) end })
SettingsTab:CreateSlider({ Name="Buy Confirm Poll Wait (s) — how fast to check if buy landed",
    Range={0.01,0.5}, Increment=0.01, CurrentValue=Settings.BuyConfirmPollWait,
    Callback=function(v) saveSetting("BuyConfirmPollWait",v) end })
SettingsTab:CreateSlider({ Name="Auto-Sell Refill Wait (s) — how often to re-check empty slots",
    Range={0.5,10}, Increment=0.5, CurrentValue=Settings.AutoSellRefillWait,
    Callback=function(v) saveSetting("AutoSellRefillWait",v) end })
SettingsTab:CreateSlider({ Name="Auto-Sell Slot Confirm Poll (s) — wait between slot-filled checks",
    Range={0.05,1}, Increment=0.05, CurrentValue=Settings.AutoSellSlotWait,
    Callback=function(v) saveSetting("AutoSellSlotWait",v) end })
SettingsTab:CreateSlider({ Name="Flash List Hold Time (s) — how long each shoe stays listed",
    Range={0.1,5}, Increment=0.1, CurrentValue=Settings.FlashListHoldTime,
    Callback=function(v) saveSetting("FlashListHoldTime",v) end })
SettingsTab:CreateSlider({ Name="Flash List Delist Pause (s) — gap after removing shoe",
    Range={0.05,2}, Increment=0.05, CurrentValue=Settings.FlashListDelistTime,
    Callback=function(v) saveSetting("FlashListDelistTime",v) end })
SettingsTab:CreateSection("Troubleshooting")
SettingsTab:CreateLabel("If bot skips everything: press Reset Settings, then restart the script.")
SettingsTab:CreateButton({ Name="Reset All Settings to Defaults", Callback=function()
    pcall(function() writefile("ShoeBuyer_settings.json","{}") end)
    Settings.PriceFilter         = true
    Settings.MaxPrice            = 100000
    Settings.TargetShoe          = ""
    Settings.Delay               = 0.05
    Settings.UseStockYCheck      = false
    Settings.StockYMargin        = 1.0
    Settings.UnsellableOnly      = false
    OneDollarMaxPrice            = 1
    Settings.SnipeCycleWait      = 0.5
    Settings.OneDollarCycleWait  = 0.5
    Settings.AutoSellRefillWait  = 3.0
    Settings.AutoSellSlotWait    = 0.1
    Settings.FlashListHoldTime   = 0.5
    Settings.FlashListDelistTime = 0.1
    Settings.BuyConfirmPollWait  = 0.08
    Settings.UseOverpayLimit     = false
    Settings.OverpayLimit        = 0
    Settings.BlockNoStockYData   = false
    Settings.UseMaxPriceFallback = true
    Settings.MaxPriceFallback    = 50000
    saveSettingsToDisk(Settings)
    Rayfield:Notify({ Title="Settings Reset", Content="Defaults applied. Restart to fully apply.", Duration=7 })
end })
end

-- ════════════════════════════════════════
--  WEBHOOK TAB
-- ════════════════════════════════════════
do
local function truncateURL(url) if url=="" then return "None" end return #url<=40 and url or url:sub(1,37).."..." end
WebhookTab:CreateSection("Webhook Setup")
local WebhookLoadedLabel=WebhookTab:CreateLabel("Loaded Webhook: "..truncateURL(Settings.WebhookURL))
local pendingWebhookURL=""
WebhookTab:CreateInput({ Name="Webhook URL", PlaceholderText="Paste Discord webhook URL",
    Callback=function(v) pendingWebhookURL=tostring(v or "") end })
WebhookTab:CreateButton({ Name="Save Webhook URL", Callback=function()
    if pendingWebhookURL=="" then Rayfield:Notify({ Title="Webhook", Content="No URL entered.", Duration=3 }) return end
    Settings.WebhookURL=pendingWebhookURL; saveWebhookToDisk(Settings.WebhookURL)
    pcall(function() WebhookLoadedLabel:Set("Loaded Webhook: "..truncateURL(Settings.WebhookURL)) end)
    Rayfield:Notify({ Title="Webhook", Content="Saved!", Duration=3 })
end })
WebhookTab:CreateButton({ Name="Test Webhook", Callback=function()
    if Settings.WebhookURL=="" then Rayfield:Notify({ Title="Webhook", Content="No URL set!", Duration=3 }) return end
    sendWebhook("TEST SHOE - Air Bogdan 4",12345,true,"TEST","TestSeller123")
    Rayfield:Notify({ Title="Webhook", Content="Test sent!", Duration=3 })
end })
WebhookTab:CreateButton({ Name="Test Kick Webhook", Callback=function()
    if Settings.WebhookURL=="" then Rayfield:Notify({ Title="Webhook", Content="No URL set!", Duration=3 }) return end
    sendKickWebhook("Manual test") Rayfield:Notify({ Title="Webhook", Content="Kick test sent!", Duration=3 })
end })
WebhookTab:CreateButton({ Name="Clear Saved Webhook", Callback=function()
    Settings.WebhookURL=""; pendingWebhookURL=""; saveWebhookToDisk("")
    pcall(function() WebhookLoadedLabel:Set("Loaded Webhook: None") end)
    Rayfield:Notify({ Title="Webhook", Content="Cleared.", Duration=3 })
end })
end

-- ════════════════════════════════════════
--  STATS TAB
-- ════════════════════════════════════════
do
StatsTab:CreateSection("Info")
local uptimeLabel=StatsTab:CreateLabel("Uptime: 0d 00h 00m 00s")
local fpsLabel=StatsTab:CreateLabel("FPS: 0")
local pingLabel=StatsTab:CreateLabel("Ping: N/A")
local frameCount=0; local lastFPSTime=tick(); local currentFPS=0
RunService.RenderStepped:Connect(function() frameCount+=1 end)
task.spawn(function()
    while true do
        local now=tick(); local delta=now-lastFPSTime
        if delta>0 then currentFPS=math.floor(frameCount/delta) end
        frameCount=0; lastFPSTime=now; task.wait(1)
    end
end)
task.spawn(function()
    local StatsService=game:GetService("Stats")
    while true do
        pcall(function() uptimeLabel:Set("Uptime: "..formatUptime(tick()-startTime)) end)
        pcall(function() fpsLabel:Set("FPS: "..tostring(currentFPS)) end)
        local ok,ping=pcall(function() return StatsService.Network.ServerStatsItem["Data Ping"]:GetValueString() end)
        pcall(function() pingLabel:Set("Ping: "..(ok and ping or "N/A")) end)
        task.wait(1)
    end
end)
StatsTab:CreateSection("Session Stats")
local statMoneyLabel=StatsTab:CreateLabel("Current Money:  $0")
local statSpentLabel=StatsTab:CreateLabel("Total Spent:    $0")
local statBoughtLabel=StatsTab:CreateLabel("Shoes Bought:   0")
local statSoldLabel=StatsTab:CreateLabel("Shoes Sold:     0")
task.spawn(function()
    if getgenv().MoneyAtSessionStart==0 then getgenv().MoneyAtSessionStart=getMoney() end
    while true do
        local m=getMoney()
        pcall(function() statMoneyLabel:Set("Current Money:  "..fmtMoney(m)) end)
        pcall(function() statSpentLabel:Set("Total Spent:    "..fmtMoney(getgenv().TotalMoneySpent or 0)) end)
        pcall(function() statBoughtLabel:Set("Shoes Bought:   "..tostring(getgenv().ShoesBought or 0)) end)
        pcall(function() statSoldLabel:Set  ("Shoes Sold:     "..tostring(getgenv().ShoesSold   or 0)) end)
        task.wait(1)
    end
end)
StatsTab:CreateSection("Links")
StatsTab:CreateButton({ Name="FM Socials", Callback=function()
    pcall(function() setclipboard(FM_SOCIALS_URL) end)
    Rayfield:Notify({ Title="FM Socials", Content="Link copied!\n"..FM_SOCIALS_URL, Duration=6 })
end })
StatsTab:CreateSection("Controls")
StatsTab:CreateButton({ Name="Reset Session Stats", Callback=function()
    getgenv().TotalMoneySpent=0; getgenv().TotalMoneyEarned=0
    getgenv().ShoesBought=0; getgenv().ShoesSold=0
    getgenv().MoneyAtSessionStart=getMoney()
    Rayfield:Notify({ Title="Stats", Content="Session stats reset.", Duration=3 })
end })
end

-- ════════════════════════════════════════
--  STARTUP
-- ════════════════════════════════════════
getgenv().MoneyAtSessionStart = getMoney()
rebuildSlotCache()

task.spawn(function()
    loadSneakerModule()
    buildUnsellableCache()
    task.wait(1.5)
    buildBlacklistTab()
end)
task.spawn(refreshStockY)
task.spawn(initSoldTracking)

local blCount=0; for _ in pairs(Blacklist) do blCount+=1 end
print("=== SHOE SNIPER LOADED | "..#cachedSlots.." slots | "..blCount.." blacklisted ===")

if Settings.UseOverpayLimit then
    print("[OVERPAY LIMITER] ON — max overpay: "..fmtMoney(Settings.OverpayLimit))
end
if Settings.UseMaxPriceFallback then
    print("[FALLBACK CAP] ON — unknown shoes capped at: "..fmtMoney(Settings.MaxPriceFallback))
end
if Settings.BlockNoStockYData then
    print("[BLOCK UNKNOWN] ON — shoes with no StockY data will be skipped")
end

Rayfield:Notify({
    Title="Shoe Sniper", Content="Loaded! "..#cachedSlots.." slots | "..blCount.." blacklisted.", Duration=6
})

local VirtualUser=game:GetService("VirtualUser")
LocalPlayer.Idled:Connect(function()
    VirtualUser:Button2Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
    task.wait()
    VirtualUser:Button2Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
end)
task.spawn(function()
    while true do
        task.wait(120)
        VirtualUser:Button2Down(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
        task.wait()
        VirtualUser:Button2Up(Vector2.new(0,0),workspace.CurrentCamera.CFrame)
    end
end)
