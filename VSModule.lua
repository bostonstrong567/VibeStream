local UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36"
local COOKIE = "zvApp=detect2; zvLang=0; zvAuth=1"
local ROOT = "VibeStream"
local DIR_PLAYING = ROOT.."/Playing"
local DIR_LAST = ROOT.."/Last_Played"
local HISTORY_FILE = ROOT.."/history.json"
local MAX_HISTORY = 30

local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local function Has(fname)
	local ok, f = pcall(function() return getfenv()[fname] end)
	return ok and typeof(f) == "function"
end

local function Req(o)
	if syn and syn.request then return syn.request(o) end
	if request then return request(o) end
	if http and http.request then return http.request(o) end
	error("No HTTP request function found.")
end

local function HttpGetUrl(url)
	if httpget then return httpget(url) end
	local ok, res = pcall(function() return game:HttpGet(url, true) end)
	if ok then return res end
	return nil
end

local function EnsureDir(p) if not isfolder(p) then makefolder(p) end end
local function ReadF(p) if isfile(p) then return readfile(p) end end
local function WriteF(p, s) writefile(p, s) end
local function DelF(p) if isfile(p) then delfile(p) end end
local function ListDir(p) if isfolder(p) then return listfiles(p) else return {} end end
local function MoveFile(src, dst) local b=ReadF(src); if b then WriteF(dst,b); DelF(src) end end

local function SanitizeFilename(s)
	s = tostring(s or "audio")
	s = s:gsub("[\\/:*?\"<>|]", "_")
	s = s:gsub("[%z\1-\31]", "_")
	s = s:gsub("[^%w%._ %-]", "_")
	s = s:gsub("%s+", " "):gsub("^%s+",""):gsub("%s+$","")
	if #s == 0 then s = "audio" end
	return s
end

local function UrlEncode(s)
	return tostring(s):gsub("\n","\r\n"):gsub("([^%w%-_%.~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
end

local function HtmlUnescape(s)
	s = s:gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", "\""):gsub("&#39;", "'")
	s = s:gsub("&#(%d+);", function(n) return string.char(tonumber(n)) end)
	return s
end

local function Grab(h, k) if not h then return nil end return h[k] or h[k:lower()] or h[k:upper()] end
local function IsAudioHeaders(h)
	local ct = Grab(h, "Content-Type"); if not ct then return false end
	ct = tostring(ct):lower()
	return ct:find("audio/") or ct:find("octet%-stream")
end

local function LooksLikeMp3(bytes)
	if not bytes or #bytes < 3 then return false end
	if bytes:sub(1,3) == "ID3" then return true end
	local b1,b2 = bytes:byte(1,2)
	if b1 == 0xFF and b2 then
		local mask = bit32 and bit32.band(b2, 0xE0) or (b2 - (b2 % 0x20))
		return mask == 0xE0
	end
	return false
end

EnsureDir(ROOT); EnsureDir(DIR_PLAYING); EnsureDir(DIR_LAST)
if not isfile(HISTORY_FILE) then WriteF(HISTORY_FILE, "[]") end

local state = {
	sound = nil,
	playing = false,
	current = nil,
	lastResults = {},
	onEnded = nil,
	historyLimit = MAX_HISTORY,
	ui = { container = nil, rowTemplate = nil, rowFactory = nil, query = nil, nextPage = nil }
}

state.ui.map = {}

local function GetFromPath(root, path)
    if not root or not path or #path == 0 then return nil end
    local cur = root
    for seg in string.gmatch(path, "[^%.]+") do
        local name, idx = seg:match("^([^%[]+)%[(%d+)%]$")
        if name then
            local n = 0
            for _, ch in ipairs(cur:GetChildren()) do
                if ch.Name == name then
                    n = n + 1
                    if n == tonumber(idx) then cur = ch break end
                end
            end
        else
            cur = cur:FindFirstChild(seg)
        end
        if not cur then return nil end
    end
    return cur
end

local function EnsureSound()
	if state.sound and state.sound.Parent then return state.sound end
	local s = Instance.new("Sound")
	s.Name = "VibeStreamSound"
	s.Parent = SoundService
	s.Volume = 0.5
	s.Looped = false
	s.Ended:Connect(function()
		state.playing = false
		local c = state.current
		if c and c.file and isfile(c.file) then
			local lastPath = ("%s/%s.mp3"):format(DIR_LAST, tostring(c.id or "last"))
			MoveFile(c.file, lastPath)
		end
		if state.onEnded then
			local id = c and c.id
			task.spawn(state.onEnded, id)
		end
	end)
	state.sound = s
	return s
end

local function PushHistory(entry)
	local ok, tbl = pcall(function() return HttpService:JSONDecode(ReadF(HISTORY_FILE) or "[]") end)
	local hist = (ok and typeof(tbl)=="table") and tbl or {}
	hist[#hist+1] = entry
	local keep = state.historyLimit
	if #hist > keep then
		local drop = #hist - keep
		for i = 1, drop do
			local ev = hist[i]
			if ev and ev.file and isfile(ev.file) then pcall(DelF, ev.file) end
		end
		local new = {}
		for i = drop+1, #hist do new[#new+1] = hist[i] end
		hist = new
	end
	WriteF(HISTORY_FILE, HttpService:JSONEncode(hist))
end

local function ParseResults(html)
	local out = {}
	for node in html:gmatch("<span[^>]-class=\"song%-play[^\"\n]*\"[^>]->") do
		local sid = node:match("data%-sid=\"(%d+)\"")
		local secs = tonumber(node:match("data%-time=\"(%d+)\"") or "0") or 0
		local title = node:match("data%-title=\"(.-)\"")
		if sid and title then
			title = HtmlUnescape(title):gsub("<.->","")
			out[#out+1] = { id = tonumber(sid), title = title, artist = "", seconds = secs }
		end
	end
	local nextPage = html:match("href=\"/mp3/search%?keywords[^\"=]*=[^\"]-page=(%d+)\"[^>]-class=\"next")
	return out, (nextPage and tonumber(nextPage) or nil)
end

local function SearchImpl(query, page)
	page = page or 1
	local url = ("https://z3.fm/mp3/search?keywords=%s&page=%d&sort=views"):format(UrlEncode(query), page)
	local r = Req({
		Url = url, Method = "GET",
		Headers = {
			["User-Agent"] = UA,
			["Cookie"] = COOKIE,
			["X-Requested-With"] = "XMLHttpRequest",
			["X-PJAX"] = "true",
			["Accept"] = "*/*",
			["Accept-Language"] = "en-US,en;q=0.9",
			["Referer"] = "https://z3.fm/", ["DNT"] = "1",
		}
	})
	local body = (r and r.Body) or ""
	if #body < 400 then
		local r2 = Req({
			Url = url, Method = "GET",
			Headers = {
				["User-Agent"] = UA, ["Cookie"] = COOKIE,
				["Accept"] = "text/html,application/xhtml+xml",
				["Accept-Language"] = "en-US,en;q=0.9",
				["Referer"] = "https://z3.fm/", ["DNT"] = "1",
			}
		})
		body = (r2 and r2.Body) or body
	end
	local results, nextPage = ParseResults(body)
	state.lastResults = results
	return results, nextPage
end

local function ExtractMp3FromHtml(html)
	if not html or #html == 0 then return nil end
	local direct = html:match('href="(https?://[^"]+%.mp3[^"]*)"') or html:match("window%.location%s*=%s*['\"](https?://[^'\"]+%.mp3[^'\"]*)['\"]")
	if direct then return direct end
	local meta = html:match('<meta%s+http%-equiv=["\']refresh["\']%s+content=["\']%d+;url=(.-)["\']')
	if meta and meta:find("%.mp3") then return meta end
	return nil
end

local function ResolveRequest(id, headers)
	return Req({ Url = ("https://z3.fm/download/%s?play=on"):format(tostring(id)), Method = "GET", Headers = headers })
end

local function ResolveMp3UrlOrBody(id)
	local r1 = ResolveRequest(id, {
		["User-Agent"] = UA, ["Cookie"] = COOKIE, ["Referer"] = "https://z3.fm/",
		["Accept"] = "*/*", ["Accept-Language"] = "en-US,en;q=0.9", ["DNT"] = "1",
	})
	if r1 then
		local loc = Grab(r1.Headers, "Location")
		if loc then if loc:sub(1,1)=="/" then loc="https://z3.fm"..loc end; return { url = loc } end
		if IsAudioHeaders(r1.Headers) and r1.Body and #r1.Body>0 then
			return { directBody = r1.Body, finalUrl = r1.Url or "" }
		end
		local h = ExtractMp3FromHtml(r1.Body); if h then return { url = h } end
	end
	local r2 = ResolveRequest(id, {
		["User-Agent"] = UA, ["Cookie"] = COOKIE, ["Referer"] = "https://z3.fm/",
		["Accept"] = "*/*", ["Range"] = "bytes=0-0", ["Accept-Language"] = "en-US,en;q=0.9", ["DNT"] = "1",
	})
	if r2 then
		local loc2 = Grab(r2.Headers, "Location")
		if loc2 then if loc2:sub(1,1)=="/" then loc2="https://z3.fm"..loc2 end; return { url = loc2 } end
		if IsAudioHeaders(r2.Headers) and r2.Body and #r2.Body>0 then
			return { directBody = r2.Body, finalUrl = r2.Url or "" }
		end
		local h2 = ExtractMp3FromHtml(r2.Body); if h2 then return { url = h2 } end
	end
	local raw = HttpGetUrl(("https://z3.fm/download/%s?play=on"):format(tostring(id)))
	if type(raw)=="string" and LooksLikeMp3(raw) then
		return { directBody = raw, finalUrl = "" }
	elseif type(raw)=="string" then
		local inHtml = ExtractMp3FromHtml(raw); if inHtml then return { url = inHtml } end
	end
	local _ = Req({
		Url = ("https://z3.fm/song/%s"):format(tostring(id)), Method = "GET",
		Headers = {
			["User-Agent"] = UA, ["Cookie"] = COOKIE, ["Accept"] = "text/html,*/*",
			["Accept-Language"] = "en-US,en;q=0.9", ["Referer"] = "https://z3.fm/", ["DNT"] = "1",
		}
	})
	local again = ResolveRequest(id, {
		["User-Agent"] = UA, ["Cookie"] = COOKIE,
		["Referer"] = ("https://z3.fm/song/%s"):format(tostring(id)),
		["Accept"] = "*/*", ["Accept-Language"] = "en-US,en;q=0.9", ["DNT"] = "1",
	})
	if again then
		local loc3 = Grab(again.Headers, "Location")
		if loc3 then if loc3:sub(1,1)=="/" then loc3="https://z3.fm"..loc3 end; return { url = loc3 } end
		if IsAudioHeaders(again.Headers) and again.Body and #again.Body>0 then
			return { directBody = again.Body, finalUrl = again.Url or "" }
		end
		local h3 = ExtractMp3FromHtml(again.Body); if h3 then return { url = h3 } end
	end
	return nil, "Could not resolve direct MP3 URL (no redirect or audio body)."
end

local function DownloadToPlaying(id, title)
	EnsureDir(DIR_PLAYING)
	for _, f in ipairs(ListDir(DIR_PLAYING)) do pcall(DelF, f) end
	local resolved, err = ResolveMp3UrlOrBody(id)
	if not resolved then error(err or "MP3 resolve failed") end
	local nice = SanitizeFilename(title or tostring(id))
	local filePath = ("%s/%s_%s.mp3"):format(DIR_PLAYING, tostring(id), nice)
	if resolved.directBody then
		WriteF(filePath, resolved.directBody)
	else
		local mp3Url = resolved.url
		local r = Req({
			Url = mp3Url, Method = "GET",
			Headers = {
				["User-Agent"] = UA, ["Accept"] = "*/*",
				["Referer"] = "https://z3.fm/", ["Accept-Language"] = "en-US,en;q=0.9", ["DNT"] = "1",
			}
		})
		if not r or type(r.Body) ~= "string" or (r.StatusCode or 0) >= 400 then
			local raw2 = HttpGetUrl(mp3Url)
			if type(raw2) == "string" and #raw2 > 0 then
				WriteF(filePath, raw2)
			else
				error(("Download failed (status %s)."):format(r and r.StatusCode or "nil"))
			end
		else
			WriteF(filePath, r.Body)
		end
	end
	local bytes = ReadF(filePath)
	if type(bytes) ~= "string" or #bytes == 0 then
		error("Downloaded file is empty or missing: "..tostring(filePath))
	end
	PushHistory({ id = id, title = title or tostring(id), url = resolved.url or (resolved.finalUrl or ""), file = filePath, t = os.time() })
	return filePath, (resolved.url or resolved.finalUrl or "")
end

local function ToAsset(path, id)
	if Has("getsynasset") then
		local ok, cid = pcall(getsynasset, path)
		if ok and type(cid)=="string" and #cid>0 then return cid end
		ok, cid = pcall(getsynasset, "./"..path)
		if ok and type(cid)=="string" and #cid>0 then return cid end
	end
	if Has("getcustomasset") then
		local ok, cid = pcall(getcustomasset, path)
		if ok and type(cid)=="string" and #cid>0 then return cid end
		ok, cid = pcall(getcustomasset, "./"..path)
		if ok and type(cid)=="string" and #cid>0 then return cid end
	end
	local rootName = ("VS_%s.mp3"):format(SanitizeFilename(tostring(id or "current")))
	WriteF(rootName, ReadF(path) or "")
	if Has("getsynasset") then
		local ok, cid = pcall(getsynasset, rootName)
		if ok and type(cid)=="string" and #cid>0 then return cid end
	end
	if Has("getcustomasset") then
		local ok, cid = pcall(getcustomasset, rootName)
		if ok and type(cid)=="string" and #cid>0 then return cid end
	end
	local alts = { "/workspace/"..rootName, "workspace/"..rootName }
	for _, p in ipairs(alts) do
		if Has("getsynasset") then
			local ok, cid = pcall(getsynasset, p)
			if ok and type(cid)=="string" and #cid>0 then return cid end
		end
		if Has("getcustomasset") then
			local ok, cid = pcall(getcustomasset, p)
			if ok and type(cid)=="string" and #cid>0 then return cid end
		end
	end
	return nil
end

local function PlayLocal(path, meta)
	assert(type(path)=="string" and #path>0, "Invalid local path")
	assert(isfile(path), "Audio file not found at "..tostring(path))
	local s = EnsureSound()
	s:Stop()
	local cid = ToAsset(path, meta.id)
	if not cid or #cid == 0 then
		error("getcustomasset/getsynasset failed to map path -> ContentId ("..tostring(path)..")")
	end
	s.SoundId = cid
	pcall(function() ContentProvider:PreloadAsync({s}) end)
	s.PlaybackSpeed = 1
	s.TimePosition = 0
	s:Play()
	state.playing = true
	state.current = { id = meta.id, title = meta.title, url = meta.url, file = path }
end

local function FormatTime(secs)
	secs = tonumber(secs) or 0
	local m = math.floor(secs/60)
	local s = secs%60
	return string.format("%d:%02d", m, s)
end

local function DefaultRowFactory(parent)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -6, 0, 30)
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.BackgroundTransparency = 0.1
	b.Name = "SongRow"
    b.Visible = true
	b.Parent = parent
	return b
end

local function MakeRow(parent)
	if typeof(state.ui.rowFactory) == "function" then
		local r = state.ui.rowFactory(parent)
		if r then return r end
	end
	if state.ui.rowTemplate and state.ui.rowTemplate:IsA("Instance") then
		local c = state.ui.rowTemplate:Clone()
		c.Name = "SongRow"
		c.Parent = parent
		return c
	end
	return DefaultRowFactory(parent)
end

local function ClearContainer(container)
	for _, c in ipairs(container:GetChildren()) do
		if c:IsA("GuiObject") and c.Name == "SongRow" then
			c:Destroy()
		end
	end
end

local function RenderList(container, rows, replace)
    if replace then
        for _, c in ipairs(container:GetChildren()) do
            if c:IsA("GuiObject") and c.Name == "SongRow" then c:Destroy() end
        end
    end
    if not rows or #rows == 0 then
        local holder = MakeRow(container)
        local root = holder:FindFirstChild("Row") or holder
        if state.ui.map and state.ui.map.TitleLabel then
            local t = GetFromPath(root, state.ui.map.TitleLabel)
            if t and t:IsA("TextLabel") then t.Text = "No results." end
        elseif holder:IsA("TextButton") then
            holder.Text = "No results."
        end
        return
    end
    for i, row in ipairs(rows) do
        local holder = MakeRow(container)
        local root = holder:FindFirstChild("Row") or holder

        if state.ui.map and state.ui.map.TitleLabel then
            local tl = GetFromPath(root, state.ui.map.TitleLabel)
            if tl and tl:IsA("TextLabel") then
                tl.Text = tostring(row.title or ("ID "..tostring(row.id)))
            end
        elseif holder:IsA("TextButton") then
            holder.Text = string.format("%d) %s  [%s]", i, row.title or ("ID "..tostring(row.id)), FormatTime(row.seconds or 0))
        end

        if state.ui.map and state.ui.map.TimeLabel then
            local tm = GetFromPath(root, state.ui.map.TimeLabel)
            if tm and tm:IsA("TextLabel") then
                tm.Text = FormatTime(row.seconds or 0)
            end
        end

        local function Play()
            task.spawn(function()
                local ok, err = pcall(function() VS.PlayById(row.id, row.title) end)
                if not ok then warn(err) end
            end)
        end

        local target = nil
        if state.ui.map and state.ui.map.PlayButton then
            target = GetFromPath(root, state.ui.map.PlayButton)
        end

        if target and target:IsA("GuiButton") then
            target.MouseButton1Click:Connect(Play)
        elseif holder:IsA("GuiButton") then
            holder.MouseButton1Click:Connect(Play)
        else
            holder.InputBegan:Connect(function(inp)
                if inp.UserInputType == Enum.UserInputType.MouseButton1 then Play() end
            end)
        end
    end
end

local VS = {}

function VS.SetRowMap(map)
    state.ui.map = map or {} 
end

function VS.Search(q, page)
	return SearchImpl(q, page)
end

function VS.PlayById(id, title)
	local filePath, url = DownloadToPlaying(id, title)
	PlayLocal(filePath, { id = id, title = title or tostring(id), url = url })
end

function VS.SearchAndPlay(query, index, page)
	local rows = SearchImpl(query, page)
	if not rows or #rows == 0 then return false, "no results" end
	local n = math.clamp(tonumber(index) or 1, 1, #rows)
	local row = rows[n]
	VS.PlayById(row.id, row.title)
	return true
end

function VS.Pause() local s=EnsureSound(); s:Pause(); state.playing=false end
function VS.Resume() local s=EnsureSound(); s:Resume(); state.playing=true end
function VS.TogglePause() local s=EnsureSound(); if s.IsPlaying then s:Pause(); state.playing=false else s:Resume(); state.playing=true end end
function VS.Stop() local s=EnsureSound(); s:Stop(); state.playing=false end
function VS.Seek(sec) local s=EnsureSound(); s.TimePosition = math.max(0, tonumber(sec) or 0) end
function VS.SetSpeed(rate) local s=EnsureSound(); s.PlaybackSpeed = math.clamp(tonumber(rate) or 1, 0.05, 4) end
function VS.SetVolume(v) local s=EnsureSound(); s.Volume = math.clamp(tonumber(v) or 0.5, 0, 1) end

function VS.OnEnded(fn) state.onEnded = fn end
function VS.SetHistoryLimit(n) state.historyLimit = math.max(1, tonumber(n) or MAX_HISTORY) end

function VS.SwapToLastPlayed()
	local ok, tbl = pcall(function() return HttpService:JSONDecode(ReadF(HISTORY_FILE) or "[]") end)
	local hist = (ok and typeof(tbl)=="table") and tbl or {}
	if #hist == 0 then return false end
	local last = hist[#hist-1] or hist[#hist]
	if not last or not last.file or not isfile(last.file) then return false end
	for _, f in ipairs(ListDir(DIR_PLAYING)) do pcall(DelF, f) end
	local back = ("%s/%s.mp3"):format(DIR_PLAYING, tostring(last.id or "prev"))
	MoveFile(last.file, back)
	PlayLocal(back, { id = last.id, title = last.title, url = last.url })
	return true
end

function VS.GetState()
	local s = EnsureSound()
	local c = state.current or {}
	local playbackState = "Unknown"
	pcall(function() playbackState = s.PlaybackState and s.PlaybackState.Name or (s.IsPlaying and "Playing" or "Stopped") end)
	return {
		id=c.id, title=c.title, url=c.url, file=c.file,
		isPlaying=state.playing, time=s.TimePosition, length=s.TimeLength,
		volume=s.Volume, speed=s.PlaybackSpeed, playbackState=playbackState,
	}
end

function VS.GetLastResults() return state.lastResults end
function VS.GetHistory()
	local ok, tbl = pcall(function() return HttpService:JSONDecode(ReadF(HISTORY_FILE) or "[]") end)
	return (ok and typeof(tbl)=="table") and tbl or {}
end

function VS.ClearPlaying() for _, f in ipairs(ListDir(DIR_PLAYING)) do pcall(DelF, f) end end
function VS.ClearLast() for _, f in ipairs(ListDir(DIR_LAST)) do pcall(DelF, f) end end
function VS.ClearAll() VS.ClearPlaying(); VS.ClearLast(); WriteF(HISTORY_FILE, "[]") end

function VS.SetRowFactory(fn) state.ui.rowFactory = fn end
function VS.SetRowTemplate(template) state.ui.rowTemplate = template end
function VS.SetResultsContainer(container) state.ui.container = container end

function VS.RenderResultsTo(container, results)
	state.ui.container = container or state.ui.container
	if not state.ui.container then return end
	RenderList(state.ui.container, results, true)
end

function VS.AppendResultsTo(container, results)
	local c = container or state.ui.container
	if not c then return end
	RenderList(c, results, false)
end

function VS.ClearResults(container)
	local c = container or state.ui.container
	if not c then return end
	ClearContainer(c)
end

function VS.SearchTo(container, q, page)
	state.ui.container = container or state.ui.container
	if not state.ui.container then return end
	if not q or q == "" then return end
	task.spawn(function()
		local ok, res, np = pcall(function() return VS.Search(q, page) end)
		if not ok then
			RenderList(state.ui.container, {}, true)
			return
		end
		state.ui.query = q
		state.ui.nextPage = np
		RenderList(state.ui.container, res, true)
	end)
end

function VS.NextPage(container)
	state.ui.container = container or state.ui.container
	if not state.ui.container then return end
	if not state.ui.query then return end
	if not state.ui.nextPage then return end
	local q = state.ui.query
	local p = tonumber(state.ui.nextPage)
	task.spawn(function()
		local ok, res, np = pcall(function() return VS.Search(q, p) end)
		if not ok then return end
		state.ui.nextPage = np
		RenderList(state.ui.container, res, false)
	end)
end

function VS.PlayFirstOfLast()
	local last = VS.GetLastResults()
	if last and last[1] then
		VS.PlayById(last[1].id, last[1].title)
		return true
	end
	return false
end

function VS.PlayAtIndex(i)
	local rows = state.lastResults or {}
	if not rows or #rows == 0 then return false end
	local n = math.clamp(tonumber(i) or 1, 1, #rows)
	local row = rows[n]
	VS.PlayById(row.id, row.title)
	return true
end

function VS.WireSearchUi(args)
    local SearchBox = args.SearchBox
    local SearchButton = args.SearchButton
    local ResultsContainer = args.ResultsContainer
    local RowTemplate = args.RowTemplate
    local Map = args.Map
    if RowTemplate then VS.SetRowTemplate(RowTemplate) end
    if ResultsContainer then VS.SetResultsContainer(ResultsContainer) end
    if Map then VS.SetRowMap(Map) end
    if SearchButton then
        SearchButton.Activated:Connect(function()
            VS.SearchTo(ResultsContainer, SearchBox and SearchBox.Text or "", 1)
        end)
    end
    if SearchBox and SearchBox:IsA("TextBox") then
        SearchBox.FocusLost:Connect(function(enter)
            if enter then VS.SearchTo(ResultsContainer, SearchBox.Text, 1) end
        end)
    end
end

return VS
