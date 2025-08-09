--[[
    VibeStream – Dark Audio Player UI (single script)
    Requires _G.VibeStream from the previous script:
      - Search, PlayById, Pause/Resume/TogglePause, Seek, SetVolume, SetSpeed,
        GetState, GetHistory, GetLastResults, SwapToLastPlayed

    Features:
      • Search bar with debounced search + result list
      • Play/Pause/Stop, Prev (swap to last), Seek bar w/ elapsed/remaining
      • Volume + Speed sliders
      • “Last Played” tab rendering history
      • Now Playing section with safe text truncation
      • Sleek dark theme, draggable window, keyboard space=play/pause
      • Text clipping/truncation to keep layout clean
--]]

--============ Services & Helpers ============--
local Players            = game:GetService("Players")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local function uiParent()
    local ok, cg = pcall(function()
        if gethui then return gethui() end
        return game:GetService("CoreGui")
    end)
    return ok and cg or game:GetService("CoreGui")
end

-- Load module if not already present
local VS = _G.VibeStream
if not VS then
    VS = loadstring(game:HttpGet("https://raw.githubusercontent.com/bostonstrong567/VibeStream/refs/heads/main/VSModule.lua"))()
    _G.VibeStream = VS
end

if not VS then
    warn("[VibeStream UI] _G.VibeStream not found. Load the core script first.")
end

-- Safe truncate helper (roblox already has TextTruncate)
local function applyTextRules(lbl)
    lbl.TextWrapped = false
    pcall(function() lbl.TextTruncate = Enum.TextTruncate.AtEnd end)
    lbl.ClipsDescendants = true
end

local function makeDraggable(headerFrame, dragTarget)
    dragTarget = dragTarget or headerFrame
    local dragging, dragStart, startPos
    headerFrame.InputBegan:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = io.Position
            startPos = dragTarget.Position
            io.Changed:Connect(function()
                if io.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    headerFrame.InputChanged:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseMovement then
            if dragging then
                local delta = io.Position - dragStart
                dragTarget.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end
    end)
end

--============ Theme ============--
local theme = {
    bg      = Color3.fromRGB(22, 24, 28),
    bg2     = Color3.fromRGB(28, 30, 36),
    card    = Color3.fromRGB(32, 35, 42),
    accent  = Color3.fromRGB(86, 156, 214),
    accent2 = Color3.fromRGB(156, 214, 125),
    text    = Color3.fromRGB(230, 233, 240),
    sub     = Color3.fromRGB(162, 168, 181),
    stroke  = Color3.fromRGB(55, 60, 70)
}

local function corner(inst, r) local c = Instance.new("UICorner") c.CornerRadius = UDim.new(0, r or 10) c.Parent = inst return c end
local function stroke(inst, t) local s = Instance.new("UIStroke") s.Thickness = t or 1 s.Color = theme.stroke s.Transparency = 0.35 s.Parent = inst return s end
local function padding(inst, l,t,r,b)
    local p = Instance.new("UIPadding")
    p.PaddingLeft   = UDim.new(0, l or 0)
    p.PaddingTop    = UDim.new(0, t or 0)
    p.PaddingRight  = UDim.new(0, r or 0)
    p.PaddingBottom = UDim.new(0, b or 0)
    p.Parent = inst
    return p
end

--============ Root Gui ============--
local SG = Instance.new("ScreenGui")
SG.Name = "VibeStream_UI"
SG.ResetOnSpawn = false
SG.IgnoreGuiInset = false
SG.ZIndexBehavior = Enum.ZIndexBehavior.Global
SG.Parent = uiParent()

local Root = Instance.new("Frame")
Root.Name = "Root"
Root.Size = UDim2.fromOffset(620, 420)
Root.Position = UDim2.new(0.5, -310, 0.5, -210)
Root.BackgroundColor3 = theme.bg
Root.Parent = SG
corner(Root, 14); stroke(Root, 1.2); padding(Root, 10, 10, 10, 10)

-- Header
local Header = Instance.new("Frame")
Header.Name = "Header"
Header.BackgroundTransparency = 1
Header.Size = UDim2.new(1, 0, 0, 34)
Header.Parent = Root

local Title = Instance.new("TextLabel")
Title.BackgroundTransparency = 1
Title.Text = "VibeStream Player"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.TextColor3 = theme.text
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Size = UDim2.new(1, -120, 1, 0)
Title.Position = UDim2.fromOffset(8, 0)
Title.Parent = Header
applyTextRules(Title)

local Close = Instance.new("TextButton")
Close.Size = UDim2.fromOffset(28, 28)
Close.Position = UDim2.new(1, -30, 0, 3)
Close.BackgroundColor3 = theme.card
Close.Text = "×"
Close.Font = Enum.Font.GothamBold
Close.TextSize = 18
Close.TextColor3 = theme.text
Close.AutoButtonColor = false
Close.Parent = Header
corner(Close, 8); stroke(Close)

local Min = Instance.new("TextButton")
Min.Size = UDim2.fromOffset(28, 28)
Min.Position = UDim2.new(1, -64, 0, 3)
Min.BackgroundColor3 = theme.card
Min.Text = "–"
Min.Font = Enum.Font.GothamBold
Min.TextSize = 18
Min.TextColor3 = theme.text
Min.AutoButtonColor = false
Min.Parent = Header
corner(Min, 8); stroke(Min)

makeDraggable(Header, Root)
Close.MouseButton1Click:Connect(function() SG:Destroy() end)
local minimized = false
Min.MouseButton1Click:Connect(function()
    minimized = not minimized
    local target = minimized and UDim2.new(Root.Size.X.Scale, Root.Size.X.Offset, 0, 42) or UDim2.fromOffset(620, 420)
    TweenService:Create(Root, TweenInfo.new(0.18, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {Size = target}):Play()
end)

--============ Main Layout ============--
local Body = Instance.new("Frame")
Body.Name = "Body"
Body.BackgroundTransparency = 1
Body.Size = UDim2.new(1, 0, 1, -40)
Body.Position = UDim2.fromOffset(0, 40)
Body.Parent = Root

local Left = Instance.new("Frame")
Left.Name = "Left"
Left.BackgroundColor3 = theme.bg2
Left.Size = UDim2.new(0.5, -6, 1, 0)
Left.Parent = Body
corner(Left, 12); stroke(Left); padding(Left, 10, 10, 10, 10)

local Right = Instance.new("Frame")
Right.Name = "Right"
Right.BackgroundColor3 = theme.bg2
Right.Size = UDim2.new(0.5, -6, 1, 0)
Right.Position = UDim2.new(0.5, 12, 0, 0)
Right.Parent = Body
corner(Right, 12); stroke(Right); padding(Right, 10, 10, 10, 10)

--============ Left: Search + Tabs + Results ============--
local Tabs = Instance.new("Frame")
Tabs.BackgroundTransparency = 1
Tabs.Size = UDim2.new(1, 0, 0, 28)
Tabs.Parent = Left

local function makeTab(txt, xoff)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = theme.card
    b.Size = UDim2.fromOffset(88, 28)
    b.Position = UDim2.fromOffset(xoff, 0)
    b.AutoButtonColor = false
    b.Text = txt
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.TextColor3 = theme.text
    b.Parent = Tabs
    corner(b, 8); stroke(b)
    return b
end

local TabSearch = makeTab("Search", 0)
local TabHistory = makeTab("Last Played", 96)

local SearchRow = Instance.new("Frame")
SearchRow.BackgroundTransparency = 1
SearchRow.Size = UDim2.new(1, 0, 0, 32)
SearchRow.Position = UDim2.fromOffset(0, 34)
SearchRow.Parent = Left

local SearchBox = Instance.new("TextBox")
SearchBox.Size = UDim2.new(1, -90, 1, 0)
SearchBox.BackgroundColor3 = theme.card
SearchBox.PlaceholderText = "Search songs..."
SearchBox.Text = ""
SearchBox.ClearTextOnFocus = false
SearchBox.TextColor3 = theme.text
SearchBox.PlaceholderColor3 = theme.sub
SearchBox.Font = Enum.Font.Gotham
SearchBox.TextSize = 14
SearchBox.TextXAlignment = Enum.TextXAlignment.Left
SearchBox.Parent = SearchRow
corner(SearchBox, 8); stroke(SearchBox); padding(SearchBox, 10, 0, 10, 0); applyTextRules(SearchBox)

local GoBtn = Instance.new("TextButton")
GoBtn.Size = UDim2.fromOffset(80, 32)
GoBtn.Position = UDim2.new(1, -80, 0, 0)
GoBtn.BackgroundColor3 = theme.accent
GoBtn.Text = "Go"
GoBtn.Font = Enum.Font.GothamBold
GoBtn.TextSize = 14
GoBtn.TextColor3 = Color3.new(1,1,1)
GoBtn.AutoButtonColor = false
GoBtn.Parent = SearchRow
corner(GoBtn, 8)

local Results = Instance.new("Frame")
Results.Name = "ResultsCard"
Results.BackgroundColor3 = theme.card
Results.Size = UDim2.new(1, 0, 1, -78)
Results.Position = UDim2.fromOffset(0, 72)
Results.ClipsDescendants = true
Results.Parent = Left
corner(Results, 10); stroke(Results); padding(Results, 6, 6, 6, 6)

local List = Instance.new("ScrollingFrame")
List.BackgroundTransparency = 1
List.Size = UDim2.new(1, 0, 1, 0)
List.CanvasSize = UDim2.new(0,0,0,0)
List.ScrollBarThickness = 6
List.AutomaticCanvasSize = Enum.AutomaticSize.None
List.Parent = Results
local UIL = Instance.new("UIListLayout")
UIL.Padding = UDim.new(0, 6)
UIL.SortOrder = Enum.SortOrder.LayoutOrder
UIL.Parent = List
local function updateCanvas() List.CanvasSize = UDim2.new(0, 0, 0, UIL.AbsoluteContentSize.Y + 4) end
UIL:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvas)

local EmptyLabel = Instance.new("TextLabel")
EmptyLabel.BackgroundTransparency = 1
EmptyLabel.Text = "Results will appear here."
EmptyLabel.TextColor3 = theme.sub
EmptyLabel.Font = Enum.Font.Gotham
EmptyLabel.TextSize = 14
EmptyLabel.Size = UDim2.new(1, 0, 0, 22)
EmptyLabel.Parent = Results
EmptyLabel.Position = UDim2.new(0, 8, 0, 6)

--============ Right: Now Playing + Controls ============--
local Now = Instance.new("Frame")
Now.Name = "Now"
Now.BackgroundColor3 = theme.card
Now.Size = UDim2.new(1, 0, 0, 120)
Now.Parent = Right
corner(Now, 10); stroke(Now); padding(Now, 10, 10, 10, 10)

local NowTitle = Instance.new("TextLabel")
NowTitle.BackgroundTransparency = 1
NowTitle.Text = "Not playing"
NowTitle.Font = Enum.Font.GothamBold
NowTitle.TextSize = 16
NowTitle.TextColor3 = theme.text
NowTitle.TextXAlignment = Enum.TextXAlignment.Left
NowTitle.Size = UDim2.new(1, 0, 0, 22)
NowTitle.Parent = Now
applyTextRules(NowTitle)

local StateLabel = Instance.new("TextLabel")
StateLabel.BackgroundTransparency = 1
StateLabel.Text = "—"
StateLabel.Font = Enum.Font.Gotham
StateLabel.TextSize = 13
StateLabel.TextColor3 = theme.sub
StateLabel.TextXAlignment = Enum.TextXAlignment.Left
StateLabel.Size = UDim2.new(1, 0, 0, 18)
StateLabel.Position = UDim2.fromOffset(0, 24)
StateLabel.Parent = Now

-- Control row
local ControlRow = Instance.new("Frame")
ControlRow.BackgroundTransparency = 1
ControlRow.Size = UDim2.new(1, 0, 0, 44)
ControlRow.Position = UDim2.fromOffset(0, 64)
ControlRow.Parent = Now

local function miniBtn(txt, x)
    local b = Instance.new("TextButton")
    b.AutoButtonColor = false
    b.Text = txt
    b.Font = Enum.Font.GothamBold
    b.TextSize = 14
    b.TextColor3 = theme.text
    b.Size = UDim2.fromOffset(76, 32)
    b.Position = UDim2.fromOffset(x, 6)
    b.BackgroundColor3 = theme.bg2
    b.Parent = ControlRow
    corner(b, 8); stroke(b)
    return b
end
local BtnPrev  = miniBtn("Prev",   0)
local BtnPlay  = miniBtn("Play",  86)
local BtnPause = miniBtn("Pause", 172)
local BtnStop  = miniBtn("Stop",  258)

-- Seek card
local SeekCard = Instance.new("Frame")
SeekCard.BackgroundColor3 = theme.card
SeekCard.Size = UDim2.new(1, 0, 0, 70)
SeekCard.Position = UDim2.fromOffset(0, 130)
SeekCard.Parent = Right
corner(SeekCard, 10); stroke(SeekCard); padding(SeekCard, 10, 10, 10, 10)

local TimeL = Instance.new("TextLabel")
TimeL.BackgroundTransparency = 1
TimeL.Text = "00:00"
TimeL.Font = Enum.Font.Gotham
TimeL.TextSize = 13
TimeL.TextColor3 = theme.sub
TimeL.Size = UDim2.fromOffset(60, 18)
TimeL.Parent = SeekCard

local TimeR = TimeL:Clone()
TimeR.Text = "-00:00"
TimeR.Position = UDim2.new(1, -60, 0, 0)
TimeR.TextXAlignment = Enum.TextXAlignment.Right
TimeR.Parent = SeekCard

-- A simple slider factory
local function makeSlider(parent, y, onChanged) -- onChanged(normalized 0..1, commit:boolean)
    local bar = Instance.new("Frame")
    bar.BackgroundColor3 = theme.bg2
    bar.Size = UDim2.new(1, 0, 0, 10)
    bar.Position = UDim2.new(0, 0, 0, y)
    bar.Parent = parent
    corner(bar, 6)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = theme.accent
    fill.Size = UDim2.new(0, 0, 1, 0)
    fill.Parent = bar
    corner(fill, 6)

    local knob = Instance.new("Frame")
    knob.BackgroundColor3 = theme.accent
    knob.Size = UDim2.fromOffset(14, 14)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.Position = UDim2.new(0, 0, 0.5, 0)
    knob.Parent = bar
    corner(knob, 7)

    local dragging = false
    local function setPos(norm)
        norm = math.clamp(norm, 0, 1)
        fill.Size = UDim2.new(norm, 0, 1, 0)
        knob.Position = UDim2.new(norm, 0, 0.5, 0)
    end

    local function updateFromMouse(commit)
        local absPos = bar.AbsolutePosition.X
        local w = bar.AbsoluteSize.X
        local x = UserInputService:GetMouseLocation().X
        local norm = (x - absPos) / math.max(1, w)
        norm = math.clamp(norm, 0, 1)
        setPos(norm)
        if onChanged then onChanged(norm, commit or false) end
    end

    bar.InputBegan:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            updateFromMouse(false)
        end
    end)
    bar.InputEnded:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
            updateFromMouse(true)
        end
    end)
    UserInputService.InputChanged:Connect(function(io)
        if dragging and io.UserInputType == Enum.UserInputType.MouseMovement then
            updateFromMouse(false)
        end
    end)

    return {
        Set = setPos
    }
end

local seeking = false
local SeekSlider = makeSlider(SeekCard, 26, function(norm, commit)
    seeking = true
    if commit and VS then
        local st = VS.GetState()
        local duration = tonumber(st.length) or 0
        VS.Seek(duration * norm)
        seeking = false
    end
end)

-- Vol + Speed card
local VSCard = Instance.new("Frame")
VSCard.BackgroundColor3 = theme.card
VSCard.Size = UDim2.new(1, 0, 0, 130)
VSCard.Position = UDim2.fromOffset(0, 210)
VSCard.Parent = Right
corner(VSCard, 10); stroke(VSCard); padding(VSCard, 10, 10, 10, 10)

local VLab = Instance.new("TextLabel")
VLab.BackgroundTransparency = 1
VLab.Text = "Volume"
VLab.Font = Enum.Font.GothamBold
VLab.TextSize = 14
VLab.TextColor3 = theme.text
VLab.Size = UDim2.fromOffset(120, 18)
VLab.Parent = VSCard

local VVal = Instance.new("TextLabel")
VVal.BackgroundTransparency = 1
VVal.Text = "70%"
VVal.Font = Enum.Font.Gotham
VVal.TextSize = 13
VVal.TextColor3 = theme.sub
VVal.Size = UDim2.fromOffset(60, 18)
VVal.Position = UDim2.new(1, -60, 0, 0)
VVal.TextXAlignment = Enum.TextXAlignment.Right
VVal.Parent = VSCard

local VolSlider = makeSlider(VSCard, 26, function(norm, commit)
    VVal.Text = string.format("%d%%", math.floor(norm * 100 + 0.5))
    if VS then VS.SetVolume(norm) end
end)
VolSlider.Set(0.7)

local SLab = VLab:Clone()
SLab.Text = "Speed"
SLab.Position = UDim2.fromOffset(0, 62)
SLab.Parent = VSCard

local SVal = VVal:Clone()
SVal.Text = "1.00x"
SVal.Position = UDim2.new(1, -60, 0, 62)
SVal.Parent = VSCard

local SpeedSlider = makeSlider(VSCard, 88, function(norm, commit)
    local speed = 0.5 + 1.5 * norm -- 0.5x..2.0x
    SVal.Text = string.format("%.2fx", speed)
    if VS then VS.SetSpeed(speed) end
end)
SpeedSlider.Set((1.0 - 0.5)/1.5)

--============ Logic ============--
local activeTab = "Search"
local searching = false
local searchToken = 0

local function clearList()
    for _, c in ipairs(List:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    updateCanvas()
end

local function mmss(t)
    t = math.max(0, math.floor(tonumber(t) or 0))
    local m = math.floor(t / 60)
    local s = t % 60
    return string.format("%02d:%02d", m, s)
end

local function addRow(textLeft, textRight, onPlay)
    local row = Instance.new("Frame")
    row.BackgroundColor3 = theme.bg2
    row.Size = UDim2.new(1, -4, 0, 40)
    row.Parent = List
    corner(row, 8); stroke(row); padding(row, 10, 6, 10, 6)

    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = textLeft
    l.Font = Enum.Font.Gotham
    l.TextSize = 14
    l.TextColor3 = theme.text
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Size = UDim2.new(1, -110, 1, 0)
    l.Parent = row
    applyTextRules(l)

    local r = Instance.new("TextLabel")
    r.BackgroundTransparency = 1
    r.Text = textRight or ""
    r.Font = Enum.Font.Gotham
    r.TextSize = 13
    r.TextColor3 = theme.sub
    r.TextXAlignment = Enum.TextXAlignment.Right
    r.Size = UDim2.new(0, 80, 1, 0)
    r.Position = UDim2.new(1, -90, 0, 0)
    r.Parent = row
    applyTextRules(r)

    local play = Instance.new("TextButton")
    play.AutoButtonColor = false
    play.BackgroundColor3 = theme.accent
    play.Text = "►"
    play.Font = Enum.Font.GothamBold
    play.TextSize = 14
    play.TextColor3 = Color3.new(1,1,1)
    play.Size = UDim2.fromOffset(28, 28)
    play.Position = UDim2.new(1, -34, 0, 6)
    play.Parent = row
    corner(play, 7)

    play.MouseButton1Click:Connect(function()
        if onPlay then onPlay() end
    end)
    row.InputBegan:Connect(function(io)
        if io.UserInputType == Enum.UserInputType.MouseButton1 then
            if onPlay then onPlay() end
        end
    end)
end

local function renderSearchResults(rows)
    clearList()
    if not rows or #rows == 0 then
        EmptyLabel.Text = "No results."
        EmptyLabel.Visible = true
        return
    end
    EmptyLabel.Visible = false
    for i, r in ipairs(rows) do
        local right = (r.seconds and r.seconds > 0) and mmss(r.seconds) or ""
        addRow(r.title, right, function()
            if VS then VS.PlayById(r.id, r.title) end
        end)
    end
    updateCanvas()
end

local function renderHistory()
    clearList()
    local hist = VS and VS.GetHistory() or {}
    if not hist or #hist == 0 then
        EmptyLabel.Text = "History empty."
        EmptyLabel.Visible = true
        return
    end
    EmptyLabel.Visible = false
    for i = #hist, 1, -1 do
        local h = hist[i]
        addRow(h.title or tostring(h.id), os.date("%m/%d %H:%M", h.t or os.time()), function()
            if VS then VS.PlayById(h.id, h.title) end
        end)
    end
    updateCanvas()
end

local function setActiveTab(name)
    activeTab = name
    if name == "Search" then
        TabSearch.BackgroundColor3 = theme.accent
        TabHistory.BackgroundColor3 = theme.card
        if VS and VS.GetLastResults then
            local rows = VS.GetLastResults()
            if rows and #rows > 0 then
                renderSearchResults(rows)
            else
                EmptyLabel.Text = "Type and press Go to search."
                EmptyLabel.Visible = true
                clearList()
            end
        end
    else
        TabSearch.BackgroundColor3 = theme.card
        TabHistory.BackgroundColor3 = theme.accent
        renderHistory()
    end
end
TabSearch.MouseButton1Click:Connect(function() setActiveTab("Search") end)
TabHistory.MouseButton1Click:Connect(function() setActiveTab("History") end)
setActiveTab("Search")

-- Debounced search
local function doSearch(query)
    if not VS then return end
    searching = true
    EmptyLabel.Text = "Searching..."
    EmptyLabel.Visible = true
    clearList()
    local my = tick(); searchToken = my
    task.spawn(function()
        local rows = VS.Search(query)
        if searchToken == my then renderSearchResults(rows) end
        searching = false
    end)
end

SearchBox.FocusLost:Connect(function(enterPressed)
    if enterPressed and #SearchBox.Text > 0 then
        setActiveTab("Search")
        doSearch(SearchBox.Text)
    end
end)
GoBtn.MouseButton1Click:Connect(function()
    if #SearchBox.Text > 0 then
        setActiveTab("Search")
        doSearch(SearchBox.Text)
    end
end)

-- Controls
BtnPlay.MouseButton1Click:Connect(function() if VS then VS.Resume() end end)
BtnPause.MouseButton1Click:Connect(function() if VS then VS.TogglePause() end end)
BtnStop.MouseButton1Click:Connect(function() if VS then VS.Stop() end end)
BtnPrev.MouseButton1Click:Connect(function()
    if VS and VS.SwapToLastPlayed() then
        -- UI will update on next heartbeat
    else
        StateLabel.Text = "No previous track."
    end
end)

-- Spacebar toggle
UserInputService.InputBegan:Connect(function(io, gpe)
    if gpe then return end
    if io.KeyCode == Enum.KeyCode.Space then
        if VS then VS.TogglePause() end
    end
end)

--============ State Updater (heartbeat) ============--
local lastTitle = ""
RunService.Heartbeat:Connect(function()
    if not VS then return end
    local st = VS.GetState()
    local playing = st.isPlaying
    local title = st.title or "Not playing"
    if title ~= lastTitle then
        NowTitle.Text = title
        lastTitle = title
    end
    StateLabel.Text = (st.playbackState or (playing and "Playing" or "Paused"))
    -- Time
    local cur = tonumber(st.time) or 0
    local len = tonumber(st.length) or 0
    TimeL.Text = mmss(cur)
    TimeR.Text = "-"..mmss(math.max(0, len - cur))
    if len > 0 and not seeking then
        local ratio = cur / math.max(1e-6, len)
        SeekSlider.Set(ratio)
    end
end)

-- Initial paint of left column with cached results/history
task.delay(0.1, function()
    if VS and VS.GetLastResults and #VS.GetLastResults() > 0 then
        renderSearchResults(VS.GetLastResults())
    else
        EmptyLabel.Text = "Type and press Go to search."
        EmptyLabel.Visible = true
    end
end)

