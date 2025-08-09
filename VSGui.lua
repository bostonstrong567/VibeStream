local VS = loadstring(game:HttpGet("https://raw.githubusercontent.com/bostonstrong567/VibeStream/refs/heads/main/VSModule.lua"))()

local Players=game:GetService("Players")
local TweenService=game:GetService("TweenService")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local SoundService=game:GetService("SoundService")

local function uiParent()
    local ok,cg=pcall(function() if gethui then return gethui() end return game:GetService("CoreGui") end)
    return ok and cg or game:GetService("CoreGui")
end

local theme={bg=Color3.fromRGB(22,24,28),bg2=Color3.fromRGB(28,30,36),card=Color3.fromRGB(32,35,42),accent=Color3.fromRGB(86,156,214),text=Color3.fromRGB(230,233,240),sub=Color3.fromRGB(162,168,181),stroke=Color3.fromRGB(55,60,70)}
local function corner(p,r)local c=Instance.new("UICorner")c.CornerRadius=UDim.new(0,r or 10)c.Parent=p return c end
local function stroke(p,t)local s=Instance.new("UIStroke")s.Thickness=t or 1 s.Color=theme.stroke s.Transparency=.35 s.Parent=p return s end
local function pad(p,l,t,r,b)local x=Instance.new("UIPadding")x.PaddingLeft=UDim.new(0,l or 0)x.PaddingTop=UDim.new(0,t or 0)x.PaddingRight=UDim.new(0,r or 0)x.PaddingBottom=UDim.new(0,b or 0)x.Parent=p return x end
local function label(txt,size,bold,color,align)
    local a=Instance.new("TextLabel")
    a.BackgroundTransparency=1
    a.Font=bold and Enum.Font.GothamBold or Enum.Font.Gotham
    a.TextSize=size or 14
    a.TextColor3=color or theme.text
    a.TextXAlignment=align or Enum.TextXAlignment.Left
    a.Text=txt or ""
    a.ClipsDescendants=true
    pcall(function() a.TextTruncate=Enum.TextTruncate.AtEnd end)
    return a
end
local function button(txt,w,h,bg,tc)
    local b=Instance.new("TextButton")
    b.AutoButtonColor=false
    b.Text=txt or ""
    b.Font=Enum.Font.GothamBold
    b.TextSize=14
    b.TextColor3=tc or theme.text
    b.Size=UDim2.fromOffset(w or 80,h or 32)
    b.BackgroundColor3=bg or theme.card
    corner(b,8)stroke(b)
    return b
end
local function card()
    local f=Instance.new("Frame")
    f.BackgroundColor3=theme.card
    corner(f,10)stroke(f)pad(f,10,10,10,10)
    return f
end

local SG=Instance.new("ScreenGui")
SG.IgnoreGuiInset=false
SG.ResetOnSpawn=false
SG.ZIndexBehavior=Enum.ZIndexBehavior.Global
SG.Name="VibeStream_UI"
SG.Parent=uiParent()

local Root=Instance.new("Frame")
Root.Size=UDim2.fromOffset(820,520)
Root.Position=UDim2.new(.5,-410,.5,-260)
Root.BackgroundColor3=theme.bg
Root.Parent=SG
corner(Root,14)stroke(Root,1.2)pad(Root,10,10,10,10)

local Header=Instance.new("Frame")
Header.Size=UDim2.new(1,0,0,36)
Header.BackgroundTransparency=1
Header.Parent=Root

local Title=label("VibeStream Player",18,true,theme.text)
Title.Size=UDim2.new(1,-120,1,0)
Title.Position=UDim2.fromOffset(8,0)
Title.Parent=Header

local BtnClose=button("x",28,28,theme.card,theme.text)
BtnClose.Position=UDim2.new(1,-30,0,4)BtnClose.Parent=Header

local BtnMin=button("-",28,28,theme.card,theme.text)
BtnMin.Position=UDim2.new(1,-64,0,4)BtnMin.Parent=Header

local Body=Instance.new("Frame")
Body.BackgroundTransparency=1
Body.Size=UDim2.new(1,0,1,-44)
Body.Position=UDim2.fromOffset(0,44)
Body.Parent=Root
local BodyHL=Instance.new("UIListLayout")
BodyHL.FillDirection=Enum.FillDirection.Horizontal
BodyHL.Padding=UDim.new(0,12)
BodyHL.Parent=Body

local Left=Instance.new("Frame")
Left.BackgroundColor3=theme.bg2
Left.Size=UDim2.new(.5,-6,1,0)
Left.Parent=Body
corner(Left,12)stroke(Left)pad(Left,10,10,10,10)

local RightScroll=Instance.new("ScrollingFrame")
RightScroll.BackgroundColor3=theme.bg2
RightScroll.Size=UDim2.new(.5,-6,1,0)
RightScroll.ScrollBarThickness=6
RightScroll.CanvasSize=UDim2.new(0,0,0,0)
RightScroll.Parent=Body
corner(RightScroll,12)stroke(RightScroll)pad(RightScroll,10,10,10,10)
local RightStack=Instance.new("Frame")
RightStack.BackgroundTransparency=1
RightStack.AutomaticSize=Enum.AutomaticSize.Y
RightStack.Size=UDim2.new(1,-2,0,0)
RightStack.Parent=RightScroll
local RSLayout=Instance.new("UIListLayout")
RSLayout.FillDirection=Enum.FillDirection.Vertical
RSLayout.Padding=UDim.new(0,10)
RSLayout.SortOrder=Enum.SortOrder.LayoutOrder
RSLayout.Parent=RightStack
RSLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    RightScroll.CanvasSize=UDim2.new(0,0,0,RSLayout.AbsoluteContentSize.Y+4)
end)

local function makeDraggable(bar,win)
    win=win or bar
    local drag=false; local origin; local start
    bar.InputBegan:Connect(function(io)
        if io.UserInputType==Enum.UserInputType.MouseButton1 then
            drag=true; origin=io.Position; start=win.Position
            io.Changed:Connect(function() if io.UserInputState==Enum.UserInputState.End then drag=false end end)
        end
    end)
    bar.InputChanged:Connect(function(io)
        if drag and io.UserInputType==Enum.UserInputType.MouseMovement then
            local d=io.Position-origin
            win.Position=UDim2.new(start.X.Scale,start.X.Offset+d.X,start.Y.Scale,start.Y.Offset+d.Y)
        end
    end)
end
makeDraggable(Header,Root)

local Resizer=Instance.new("Frame")
Resizer.Size=UDim2.fromOffset(14,14)
Resizer.BackgroundTransparency=1
Resizer.Position=UDim2.new(1,-12,1,-12)
Resizer.ZIndex=5
Resizer.Parent=Root
local ResizerHit=Instance.new("ImageLabel")
ResizerHit.Size=UDim2.fromScale(1,1)
ResizerHit.BackgroundTransparency=1
ResizerHit.Image="rbxassetid://7072718362"
ResizerHit.ImageColor3=theme.sub
ResizerHit.Parent=Resizer
local resizing=false; local startSize; local startPos
Resizer.InputBegan:Connect(function(io)
    if io.UserInputType==Enum.UserInputType.MouseButton1 then
        resizing=true
        startSize=Root.Size
        startPos=UserInputService:GetMouseLocation()
        io.Changed:Connect(function() if io.UserInputState==Enum.UserInputState.End then resizing=false end end)
    end
end)
UserInputService.InputChanged:Connect(function(io)
    if resizing and io.UserInputType==Enum.UserInputType.MouseMovement then
        local cur=UserInputService:GetMouseLocation()
        local dx=cur.X-startPos.X
        local dy=cur.Y-startPos.Y
        Root.Size=UDim2.fromOffset(math.max(720,startSize.X.Offset+dx),math.max(440,startSize.Y.Offset+dy))
    end
end)

local minimized=false
BtnMin.MouseButton1Click:Connect(function()
    minimized=not minimized
    Body.Visible=not minimized
    BtnMin.Text=minimized and "+" or "-"
    local t=minimized and UDim2.new(Root.Size.X.Scale,Root.Size.X.Offset,0,56) or UDim2.fromOffset(Root.Size.X.Offset,Root.Size.Y.Offset)
    TweenService:Create(Root,TweenInfo.new(.18,Enum.EasingStyle.Sine,Enum.EasingDirection.Out),{Size=t}):Play()
end)
BtnClose.MouseButton1Click:Connect(function() SG:Destroy() end)

local Tabs=Instance.new("Frame")
Tabs.Size=UDim2.new(1,0,0,30)
Tabs.BackgroundTransparency=1
Tabs.Parent=Left
local TabRow=Instance.new("UIListLayout")
TabRow.FillDirection=Enum.FillDirection.Horizontal
TabRow.Padding=UDim.new(0,8)
TabRow.Parent=Tabs
local TabSearch=button("Search",88,28,theme.card,theme.text)TabSearch.Parent=Tabs
local TabHistory=button("Last Played",108,28,theme.card,theme.text)TabHistory.Parent=Tabs
local TabPlaylists=button("Playlists",96,28,theme.card,theme.text)TabPlaylists.Parent=Tabs

local SearchRow=Instance.new("Frame")
SearchRow.Size=UDim2.new(1,0,0,34)
SearchRow.BackgroundTransparency=1
SearchRow.Parent=Left
local SRL=Instance.new("UIListLayout")
SRL.FillDirection=Enum.FillDirection.Horizontal
SRL.Padding=UDim.new(0,8)
SRL.Parent=SearchRow
local SearchBox=Instance.new("TextBox")
SearchBox.Size=UDim2.new(1,-188,1,0)
SearchBox.BackgroundColor3=theme.card
SearchBox.TextColor3=theme.text
SearchBox.PlaceholderColor3=theme.sub
SearchBox.TextXAlignment=Enum.TextXAlignment.Left
SearchBox.Font=Enum.Font.Gotham
SearchBox.TextSize=14
SearchBox.PlaceholderText="Search songs..."
SearchBox.ClearTextOnFocus=false
SearchBox.Parent=SearchRow
corner(SearchBox,8)stroke(SearchBox)pad(SearchBox,10,0,10,0)
pcall(function() SearchBox.TextTruncate=Enum.TextTruncate.AtEnd end)
local GoBtn=button("Go",80,34,theme.accent,Color3.new(1,1,1))GoBtn.Parent=SearchRow
local QueueBtn=button("Queue +",88,34,theme.card,theme.text)QueueBtn.Parent=SearchRow

local ResultsCard=card()
ResultsCard.Size=UDim2.new(1,0,1,-74)
ResultsCard.Position=UDim2.fromOffset(0,74)
ResultsCard.Parent=Left
local ResultsList=Instance.new("ScrollingFrame")
ResultsList.BackgroundTransparency=1
ResultsList.Size=UDim2.new(1,0,1,0)
ResultsList.ScrollBarThickness=6
ResultsList.CanvasSize=UDim2.new(0,0,0,0)
ResultsList.Parent=ResultsCard
local RL=Instance.new("UIListLayout")
RL.Padding=UDim.new(0,6)RL.SortOrder=Enum.SortOrder.LayoutOrderRL.Parent==ResultsList
RL:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    ResultsList.CanvasSize=UDim2.new(0,0,0,RL.AbsoluteContentSize.Y+4)
end)
local Placeholder=label("Type and press Go to search.",14,false,theme.sub)
Placeholder.Size=UDim2.new(1,0,0,20)
Placeholder.Position=UDim2.fromOffset(6,4)
Placeholder.Parent=ResultsCard

local NowCard=card()
NowCard.Size=UDim2.new(1,0,0,120)
NowCard.Parent=RightStack
local NowTitle=label("Not playing",16,true,theme.text)NowTitle.Parent=NowCard NowTitle.Size=UDim2.new(1,-40,0,22)
local NowSub=label("—",13,false,theme.sub)NowSub.Parent=NowCard NowSub.Position=UDim2.fromOffset(0,24) NowSub.Size=UDim2.new(1,0,0,18)
local ControlRow=Instance.new("Frame")
ControlRow.Size=UDim2.new(1,0,0,40)
ControlRow.BackgroundTransparency=1
ControlRow.Position=UDim2.fromOffset(0,60)
ControlRow.Parent=NowCard
local CRL=Instance.new("UIListLayout")
CRL.FillDirection=Enum.FillDirection.Horizontal
CRL.Padding=UDim.new(0,10)
CRL.Parent=ControlRow
local BtnPrev=button("Prev",76,32,theme.bg2,theme.text)BtnPrev.Parent=ControlRow
local BtnPlay=button("Play",76,32,theme.bg2,theme.text)BtnPlay.Parent=ControlRow
local BtnPause=button("Pause",76,32,theme.bg2,theme.text)BtnPause.Parent=ControlRow
local BtnStop=button("Stop",76,32,theme.bg2,theme.text)BtnStop.Parent=ControlRow

local SeekCard=card()
SeekCard.Size=UDim2.new(1,0,0,80)
SeekCard.Parent=RightStack
local TimeRow=Instance.new("Frame")
TimeRow.BackgroundTransparency=1
TimeRow.Size=UDim2.new(1,0,0,18)
TimeRow.Parent=SeekCard
local TRL=Instance.new("UIListLayout")
TRL.FillDirection=Enum.FillDirection.Horizontal
TRL.Padding=UDim.new(1,0)
TRL.Parent=TimeRow
local TimeL=label("00:00",13,false,theme.sub)TimeL.Parent=TimeRow TimeL.Size=UDim2.new(0,60,1,0)
local TimeSpacer=Instance.new("Frame")TimeSpacer.BackgroundTransparency=1 TimeSpacer.Size=UDim2.new(1,-120,1,0)TimeSpacer.Parent=TimeRow
local TimeR=label("-00:00",13,false,theme.sub,Enum.TextXAlignment.Right)TimeR.Parent=TimeRow TimeR.Size=UDim2.new(0,60,1,0)

local function slider(parent,height,default,onChanged)
    local bar=Instance.new("Frame")
    bar.BackgroundColor3=theme.bg2
    bar.Size=UDim2.new(1,0,0,height)
    corner(bar,6)bar.Parent=parent
    local fill=Instance.new("Frame")
    fill.BackgroundColor3=theme.accent
    fill.Size=UDim2.new(default or 0,0,1,0)
    corner(fill,6)fill.Parent=bar
    local knob=Instance.new("Frame")
    knob.BackgroundColor3=theme.accent
    knob.Size=UDim2.fromOffset(height+4,height+4)
    knob.AnchorPoint=Vector2.new(.5,.5)
    knob.Position=UDim2.new(default or 0,0,.5,0)
    corner(knob,(height+4)/2)knob.Parent=bar
    local dragging=false
    local function setp(p)p=math.clamp(p,0,1)fill.Size=UDim2.new(p,0,1,0)knob.Position=UDim2.new(p,0,.5,0)end
    local function update(commit)
        local a=bar.AbsolutePosition.X local w=bar.AbsoluteSize.X
        local x=UserInputService:GetMouseLocation().X
        local p=math.clamp((x-a)/math.max(1,w),0,1)
        setp(p) if onChanged then onChanged(p,commit) end
    end
    bar.InputBegan:Connect(function(io) if io.UserInputType==Enum.UserInputType.MouseButton1 then dragging=true update(false) end end)
    bar.InputEnded:Connect(function(io) if io.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false update(true) end end)
    UserInputService.InputChanged:Connect(function(io) if dragging and io.UserInputType==Enum.UserInputType.MouseMovement then update(false) end end)
    setp(default or 0)
    return{Set=setp}
end

local seeking=false
local SeekSlider=slider(SeekCard,10,0,function(p,commit)
    if commit and VS then
        local s=VS.GetState()
        local len=tonumber(s.length) or 0
        VS.Seek(len*p)seeking=false
    else seeking=true end
end)

local VSCard=card()
VSCard.Size=UDim2.new(1,0,0,120)
VSCard.Parent=RightStack
local RowA=Instance.new("Frame")RowA.BackgroundTransparency=1 RowA.Size=UDim2.new(1,0,0,18)RowA.Parent=VSCard
local RowB=Instance.new("Frame")RowB.BackgroundTransparency=1 RowB.Size=UDim2.new(1,0,0,32)RowB.Parent=VSCard
local RowC=Instance.new("Frame")RowC.BackgroundTransparency=1 RowC.Size=UDim2.new(1,0,0,18)RowC.Parent=VSCard
local RowD=Instance.new("Frame")RowD.BackgroundTransparency=1 RowD.Size=UDim2.new(1,0,0,32)RowD.Parent=VSCard
local RowAL=label("Volume",14,true,theme.text)RowAL.Parent=RowA RowAL.Size=UDim2.new(.5,-6,1,0)
local RowAR=label("70%",13,false,theme.sub,Enum.TextXAlignment.Right)RowAR.Parent=RowA RowAR.Size=UDim2.new(.5,-6,1,0)RowAR.Position=UDim2.new(.5,6,0,0)
local VolSlider=slider(RowB,10,.7,function(p)RowAR.Text=string.format("%d%%",math.floor(p*100+.5))if VS then VS.SetVolume(p) end end)
local RowCL=label("Speed",14,true,theme.text)RowCL.Parent=RowC RowCL.Size=UDim2.new(.5,-6,1,0)
local RowCR=label("1.00x",13,false,theme.sub,Enum.TextXAlignment.Right)RowCR.Parent=RowC RowCR.Size=UDim2.new(.5,-6,1,0)RowCR.Position=UDim2.new(.5,6,0,0)
local SpeedSlider=slider(RowD,10,(1-0.5)/1.5,function(p)local sp=0.5+1.5*p RowCR.Text=string.format("%.2fx",sp)if VS then VS.SetSpeed(sp) end end)

local OthersCard=card()
OthersCard.Size=UDim2.new(1,0,0,88)
OthersCard.Parent=RightStack
local MuteRow=Instance.new("Frame")MuteRow.BackgroundTransparency=1 MuteRow.Size=UDim2.new(1,0,0,24)MuteRow.Parent=OthersCard
local MuteBtn=button("Mute Others: Off",140,24,theme.bg2,theme.text)MuteBtn.Parent=MuteRow
local OtherVal=label("100%",13,false,theme.sub,Enum.TextXAlignment.Right)OtherVal.Parent=MuteRow OtherVal.Size=UDim2.new(1,-150,1,0)OtherVal.Position=UDim2.new(0,150,0,0)
local OtherSlider=slider(OthersCard,10,1,nil)

local QueueCard=card()
QueueCard.Size=UDim2.new(1,0,0,160)
QueueCard.Parent=RightStack
local QHeader=label("Queue",14,true,theme.text)QHeader.Parent=QueueCard QHeader.Size=UDim2.new(1,0,0,18)
local QList=Instance.new("ScrollingFrame")
QList.BackgroundTransparency=1
QList.Size=UDim2.new(1,0,1,-22)
QList.Position=UDim2.fromOffset(0,22)
QList.ScrollBarThickness=6
QList.CanvasSize=UDim2.new(0,0,0,0)
QList.Parent=QueueCard
local QL=Instance.new("UIListLayout")
QL.Padding=UDim.new(0,6)QL.SortOrder=Enum.SortOrder.LayoutOrderQL.Parent==QList
QL:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    QList.CanvasSize=UDim2.new(0,0,0,QL.AbsoluteContentSize.Y+4)
end)

local activeTab="Search"
local function setTab(t)
    activeTab=t
    TabSearch.BackgroundColor3=theme.card
    TabHistory.BackgroundColor3=theme.card
    TabPlaylists.BackgroundColor3=theme.card
    if t=="Search" then TabSearch.BackgroundColor3=theme.accent end
    if t=="History" then TabHistory.BackgroundColor3=theme.accent end
    if t=="Playlists" then TabPlaylists.BackgroundColor3=theme.accent end
    for _,c in ipairs(ResultsList:GetChildren())do if c:IsA("Frame") then c:Destroy() end end
    if t=="History" then
        Placeholder.Visible=false
        local hist=VS and VS.GetHistory() or {}
        if #hist==0 then Placeholder.Text="History empty." Placeholder.Visible=true end
        for i=#hist,1,-1 do
            local h=hist[i]
            local row=card()row.BackgroundColor3=theme.bg2 row.Size=UDim2.new(1,-4,0,40)pad(row,10,6,10,6)row.Parent=ResultsList
            local lt=label(h.title or tostring(h.id),14,false,theme.text)lt.Size=UDim2.new(1,-120,1,0)lt.Parent=row
            local rt=label(os.date("%m/%d %H:%M",h.t or os.time()),13,false,theme.sub,Enum.TextXAlignment.Right)rt.Size=UDim2.new(0,80,1,0)rt.Position=UDim2.new(1,-90,0,0)rt.Parent=row
            local play=button("►",28,28,theme.accent,Color3.new(1,1,1))play.Position=UDim2.new(1,-34,0,6)play.Parent=row
            play.MouseButton1Click:Connect(function() if VS then VS.PlayById(h.id,h.title) end end)
        end
    else
        Placeholder.Text="Type and press Go to search."
        Placeholder.Visible=true
    end
end
TabSearch.MouseButton1Click:Connect(function() setTab("Search") end)
TabHistory.MouseButton1Click:Connect(function() setTab("History") end)
TabPlaylists.MouseButton1Click:Connect(function() setTab("Playlists") end)
setTab("Search")

local selectedRow=nil
local queue={}
local function queueRefresh()
    for _,c in ipairs(QList:GetChildren())do if c:IsA("Frame") then c:Destroy() end end
    for i,ent in ipairs(queue)do
        local r=card()r.BackgroundColor3=theme.bg2 r.Size=UDim2.new(1,-4,0,38)pad(r,10,6,10,6)r.Parent=QList
        local t=label(ent.title,14,false,theme.text)t.Size=UDim2.new(1,-140,1,0)t.Parent=r
        local up=button("↑",24,24,theme.card,theme.text)up.Parent=r up.Position=UDim2.new(1,-100,0,4)
        local down=button("↓",24,24,theme.card,theme.text)down.Parent=r down.Position=UDim2.new(1,-70,0,4)
        local del=button("✕",24,24,theme.card,theme.text)del.Parent=r del.Position=UDim2.new(1,-40,0,4)
        up.MouseButton1Click:Connect(function() if i>1 then table.insert(queue,i-1,table.remove(queue,i)) queueRefresh() end end)
        down.MouseButton1Click:Connect(function() if i<#queue then table.insert(queue,i+1,table.remove(queue,i)) queueRefresh() end end)
        del.MouseButton1Click:Connect(function() table.remove(queue,i) queueRefresh() end)
    end
end

local rowCooldown=false
local function addResultRow(res)
    local row=Instance.new("Frame")
    row.BackgroundColor3=theme.bg2
    row.Size=UDim2.new(1,-4,0,44)
    row.Parent=ResultsList
    corner(row,8)stroke(row)pad(row,10,6,10,6)
    local l=label(res.title,14,false,theme.text)l.Size=UDim2.new(1,-150,1,0)l.Parent=row
    local r=label((res.seconds and res.seconds>0) and string.format("%02d:%02d",math.floor(res.seconds/60),res.seconds%60) or "",13,false,theme.sub,Enum.TextXAlignment.Right)r.Size=UDim2.new(0,70,1,0)r.Position=UDim2.new(1,-110,0,0)r.Parent=row
    local play=button("►",28,28,theme.accent,Color3.new(1,1,1))play.Position=UDim2.new(1,-72,0,6)play.Parent=row
    local add=button("+",28,28,theme.card,theme.text)add.Position=UDim2.new(1,-36,0,6)add.Parent=row
    play.MouseButton1Click:Connect(function()
        if rowCooldown then return end
        rowCooldown=true task.delay(.6,function() rowCooldown=false end)
        if VS then VS.PlayById(res.id,res.title) end
    end)
    add.MouseButton1Click:Connect(function() table.insert(queue,{id=res.id,title=res.title}) queueRefresh() end)
    row.InputBegan:Connect(function(io) if io.UserInputType==Enum.UserInputType.MouseButton1 then selectedRow=row end end)
end

local function renderSearch(rows)
    for _,c in ipairs(ResultsList:GetChildren())do if c:IsA("Frame") then c:Destroy() end end
    Placeholder.Visible=false
    if not rows or #rows==0 then Placeholder.Text="No results." Placeholder.Visible=true return end
    for _,r in ipairs(rows)do addResultRow(r) end
end

local currentSearchToken=0
local function doSearch(q)
    if not VS or #q==0 then return end
    local my=tick()currentSearchToken=my
    Placeholder.Text="Searching..." Placeholder.Visible=true
    for _,c in ipairs(ResultsList:GetChildren())do if c:IsA("Frame") then c:Destroy() end end
    task.spawn(function()
        local rows=VS.Search(q)
        if currentSearchToken==my and activeTab=="Search" then renderSearch(rows) end
    end)
end

SearchBox.FocusLost:Connect(function(enter) if enter and #SearchBox.Text>0 then setTab("Search") doSearch(SearchBox.Text) end end)
GoBtn.MouseButton1Click:Connect(function() if #SearchBox.Text>0 then setTab("Search") doSearch(SearchBox.Text) end end)
QueueBtn.MouseButton1Click:Connect(function()
    if selectedRow then
        for _,c in ipairs(selectedRow:GetChildren())do if c:IsA("TextLabel") then table.insert(queue,{id=0,title=c.Text}) break end end
        queueRefresh()
    end
end)

BtnPlay.MouseButton1Click:Connect(function() if VS then VS.Resume() end end)
BtnPause.MouseButton1Click:Connect(function() if VS then VS.TogglePause() end end)
BtnStop.MouseButton1Click:Connect(function() if VS then VS.Stop() end end)
BtnPrev.MouseButton1Click:Connect(function() if VS and not VS.SwapToLastPlayed() then NowSub.Text="No previous track." end end)
UserInputService.InputBegan:Connect(function(io,gpe) if gpe then return end if io.KeyCode==Enum.KeyCode.Space then if VS then VS.TogglePause() end end end)

local othersMuted=false
local othersVolumes=setmetatable({},{__mode="k"})
local otherLevel=1
local function applyOtherVolumes()
    for _,s in ipairs(SoundService:GetDescendants())do
        if s:IsA("Sound") then
            if tostring(s.Name)~="VibeStreamSound" then
                if not othersVolumes[s] then othersVolumes[s]=s.Volume end
                s.Volume=(othersMuted and 0) or ((othersVolumes[s] or s.Volume)*(otherLevel))
            end
        end
    end
end
SoundService.DescendantAdded:Connect(function(o) if o:IsA("Sound") then task.wait(.05) applyOtherVolumes() end end)
MuteBtn.MouseButton1Click:Connect(function() othersMuted=not othersMuted MuteBtn.Text="Mute Others: "..(othersMuted and "On" or "Off") applyOtherVolumes() end)
OtherSlider.Set(1)
OtherSlider=slider(OthersCard,10,1,function(p) otherLevel=p OtherVal.Text=string.format("%d%%",math.floor(p*100+.5)) applyOtherVolumes() end)

if VS and VS.OnEnded then
    VS.OnEnded(function()
        if #queue>0 then
            local nxt=table.remove(queue,1) queueRefresh()
            if nxt and nxt.id and nxt.id~=0 then VS.PlayById(nxt.id,nxt.title) end
        end
    end)
end

local lastTitle=""
RunService.Heartbeat:Connect(function()
    if not VS then return end
    local s=VS.GetState()
    if s.title~=lastTitle then lastTitle=s.title or "Not playing" NowTitle.Text=lastTitle end
    local st=s.playbackState or (s.isPlaying and "Playing" or "Paused")
    NowSub.Text=st
    local cur=tonumber(s.time) or 0
    local len=tonumber(s.length) or 0
    local function mmss(t)t=math.max(0,math.floor(t))return string.format("%02d:%02d",math.floor(t/60),t%60)end
    TimeL.Text=mmss(cur) TimeR.Text="-"..mmss(math.max(0,len-cur))
    if len>0 and not seeking then SeekSlider.Set(cur/math.max(1e-6,len)) end
end)

task.delay(.1,function()
    local last=VS and VS.GetLastResults and VS.GetLastResults() or {}
    if last and #last>0 then renderSearch(last) end
end)
