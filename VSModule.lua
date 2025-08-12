--// =========================
--// VibeStream Module (enhanced QoL)
--// =========================

--========== Constants
local UA            = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36"
local COOKIE        = "zvApp=detect2; zvLang=0; zvAuth=1"

local ROOT          = "VibeStream"
local DIR_LIBRARY   = ROOT.."/Library"       -- permanent store (avoid re-downloads)
local DIR_PLAYING   = ROOT.."/Playing"       -- legacy temp (not used for storage)
local DIR_LAST      = ROOT.."/Last_Played"
local HISTORY_FILE  = ROOT.."/history.json"
local CACHE_SEARCH  = ROOT.."/search_cache.json"
local LIB_INDEX     = ROOT.."/library.json"
local MAX_HISTORY   = 30

local IMAGE_PLAY    = "rbxassetid://135451326413860"
local IMAGE_PAUSE   = "rbxassetid://90193543893908"

--========== Services
local HttpService     = game:GetService("HttpService")
local SoundService    = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService    = game:GetService("TweenService")
local RunService      = game:GetService("RunService")

--========== Module
local VS = {}

--========== FS helpers
local function EnsureDir(p) if not isfolder(p) then makefolder(p) end end
local function ReadF(p) if isfile(p) then return readfile(p) end end
local function WriteF(p, s) writefile(p, s) end
local function DelF(p) if isfile(p) then delfile(p) end end
local function ListDir(p) if isfolder(p) then return listfiles(p) else return {} end end
local function CopyFile(src, dst) local b=ReadF(src); if b then writefile(dst,b) end end

local function ReadJson(path, defaultTbl)
	local ok, data = pcall(function()
		local raw = ReadF(path)
		return raw and HttpService:JSONDecode(raw) or nil
	end)
	if ok and typeof(data) == "table" then return data end
	return defaultTbl or {}
end

local function WriteJson(path, tbl)
	local ok, raw = pcall(function() return HttpService:JSONEncode(tbl) end)
	if ok and raw then WriteF(path, raw) end
end

--========== HTTP helpers
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

--========== Misc helpers
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

local function FormatTime(secs)
	secs = tonumber(secs) or 0
	local m = math.floor(secs/60)
	local s = secs%60
	return string.format("%d:%02d", m, s)
end

local function SafeCall(fn, ...)
	if not fn then return end
	local ok, err = pcall(fn, ...)
	if not ok then warn("[VS] callback error: "..tostring(err)) end
end

--========== Bootstrap storage
EnsureDir(ROOT); EnsureDir(DIR_LIBRARY); EnsureDir(DIR_PLAYING); EnsureDir(DIR_LAST)
if not isfile(HISTORY_FILE) then WriteF(HISTORY_FILE, "[]") end
if not isfile(CACHE_SEARCH) then WriteF(CACHE_SEARCH, "{}") end
if not isfile(LIB_INDEX) then WriteF(LIB_INDEX, "{}") end

--========== State
local State = {
	Sound        = nil,
	Playing      = false,
	Current      = nil,     -- { id, title, url, file }
	LastResults  = {},
	HistoryLimit = MAX_HISTORY,
	Autoplay     = false,

	UI = {
		Container     = nil,
		RowTemplate   = nil,
		RowFactory    = nil,
		Query         = nil,
		NextPage      = nil,
		Map           = {},   -- { PlayButton="A.B", TitleLabel="...", TimeLabel="...", AddButton="..." }
		ButtonById    = {},   -- id -> ImageButton
		RowById       = {},   -- id -> holder
		Placeholder   = nil,  -- frame shown when no query
		BusyIndicator = nil,  -- show while searching
		LiveDelay     = 0,    -- ms
		_liveConn     = nil,
	},

	Cache = {
		Searches  = ReadJson(CACHE_SEARCH, {}),   -- key -> {results, nextPage}
		Library   = ReadJson(LIB_INDEX, {}),      -- id -> {file, title, url}
	},

	Queue = {},

	OnEnded    = nil,
	OnError    = nil,
	OnQueueUpd = nil,
}

--========== UI path helper
local function GetFromPath(root, path)
	if not root or not path or #path == 0 then return nil end
	local cur = root
	for seg in string.gmatch(path, "[^%.]+") do
		local name, idx = seg:match("^([^%[]+)%[(%d+)%]$")
		if name then
			local n = 0
			for _, ch in ipairs(cur:GetChildren()) do
				if ch.Name == name then
					n += 1
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

local function TogglePlaceholder(show)
	local p = State.UI.Placeholder
	local c = State.UI.Container
	if p then p.Visible = (show == true) end
	if c then c.Visible = (show ~= true) end
end

local function SetBusy(active)
	local b = State.UI.BusyIndicator
	if not b then return end
	b.Visible = active and true or false
end

--========== Audio
local function EnsureSound()
	if State.Sound and State.Sound.Parent then return State.Sound end
	local s = Instance.new("Sound")
	s.Name = "VibeStreamSound"
	s.Parent = SoundService
	s.Volume = 0.5
	s.Looped = false
	s.Ended:Connect(function()
		State.Playing = false
		local c = State.Current
		if c and c.file and isfile(c.file) then
			local lastPath = ("%s/%s.mp3"):format(DIR_LAST, tostring(c.id or "last"))
			CopyFile(c.file, lastPath) -- keep library intact
		end

		VS.RefreshPlayButtons()
		VS.RefreshRowHighlight()

		if #State.Queue > 0 then
			VS.PlayNext() -- queue first
			return
		end
		if State.Autoplay then
			VS.PlayNext() -- from last results
		end

		SafeCall(State.OnEnded, c and c.id)
	end)
	State.Sound = s
	return s
end

local function ToAsset(path, id)
	if Has("getsynasset") then
		local ok, cid = pcall(getsynasset, path)
		if ok and type(cid)=="string" and #cid>0 then return cid end
	end
	if Has("getcustomasset") then
		local ok, cid = pcall(getcustomasset, path)
		if ok and type(cid)=="string" and #cid>0 then return cid end
	end
	-- try relative fallbacks
	if Has("getsynasset") then
		local ok, cid = pcall(getsynasset, "./"..path); if ok and cid and #cid>0 then return cid end
	end
	if Has("getcustomasset") then
		local ok, cid = pcall(getcustomasset, "./"..path); if ok and cid and #cid>0 then return cid end
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

	State.Playing = true
	State.Current = { id = meta.id, title = meta.title, url = meta.url, file = path }

	VS.RefreshPlayButtons()
	VS.RefreshRowHighlight()
end

--========== History & library
local function PushHistory(entry)
	local hist = ReadJson(HISTORY_FILE, {})
	hist[#hist+1] = entry
	if #hist > State.HistoryLimit then
		local start = #hist - State.HistoryLimit + 1
		local trimmed = {}
		for i = start, #hist do trimmed[#trimmed+1] = hist[i] end
		hist = trimmed
	end
	WriteJson(HISTORY_FILE, hist)
end

--========== Search/resolve
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

-- search with persistent cache
local function SearchImpl(query, page)
	page = tonumber(page) or 1
	local q = tostring(query or "")
	local key = (q:lower() .. "::" .. tostring(page))

	-- cached
	local cached = State.Cache.Searches[key]
	if cached and type(cached) == "table" and cached.results then
		State.LastResults = cached.results
		return cached.results, cached.nextPage
	end

	SetBusy(true)
	local url = ("https://z3.fm/mp3/search?keywords=%s&page=%d&sort=views"):format(UrlEncode(q), page)
	local r = Req({
		Url = url, Method = "GET",
		Headers = {
			["User-Agent"] = UA, ["Cookie"] = COOKIE,
			["X-Requested-With"] = "XMLHttpRequest", ["X-PJAX"] = "true",
			["Accept"] = "*/*", ["Accept-Language"] = "en-US,en;q=0.9", ["Referer"] = "https://z3.fm/", ["DNT"] = "1",
		}
	})
	local body = (r and r.Body) or ""
	if #body < 400 then
		local r2 = Req({
			Url = url, Method = "GET",
			Headers = {
				["User-Agent"] = UA, ["Cookie"] = COOKIE,
				["Accept"] = "text/html,application/xhtml+xml",
				["Accept-Language"] = "en-US,en;q=0.9", ["Referer"] = "https://z3.fm/", ["DNT"] = "1",
			}
		})
		body = (r2 and r2.Body) or body
	end
	SetBusy(false)

	local results, nextPage = ParseResults(body)
	State.Cache.Searches[key] = { results = results, nextPage = nextPage }
	WriteJson(CACHE_SEARCH, State.Cache.Searches)

	State.LastResults = results
	return results, nextPage
end

-- download or reuse from library
local function DownloadOrGetFromLibrary(id, title)
	id = tonumber(id)
	local lib = State.Cache.Library
	local entry = lib[tostring(id)]
	if entry and entry.file and isfile(entry.file) then
		return entry.file, entry.url or ""
	end

	local resolved, err = ResolveMp3UrlOrBody(id)
	if not resolved then error(err or "MP3 resolve failed") end

	local nice = SanitizeFilename(title or tostring(id))
	local filePath = ("%s/%s_%s.mp3"):format(DIR_LIBRARY, tostring(id), nice)

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

	lib[tostring(id)] = { file = filePath, title = title or tostring(id), url = (resolved.url or resolved.finalUrl or "") }
	WriteJson(LIB_INDEX, lib)

	PushHistory({ id = id, title = title or tostring(id), url = resolved.url or (resolved.finalUrl or ""), file = filePath, t = os.time() })

	return filePath, (resolved.url or resolved.finalUrl or "")
end

--========== UI build
local function ClearContainer(container)
	for _, c in ipairs(container:GetChildren()) do
		if c:IsA("GuiObject") and c.Name == "SongRow" then c:Destroy() end
	end
	State.UI.ButtonById = {}
	State.UI.RowById = {}
end

local function DefaultRowFactory(parent)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, -6, 0, 30)
	b.TextXAlignment = Enum.TextXAlignment.Left
	b.BackgroundTransparency = 0.1
	b.Name = "SongRow"
	b.Parent = parent
	return b
end

local function MakeRow(parent)
	if typeof(State.UI.RowFactory) == "function" then
		local r = State.UI.RowFactory(parent)
		if r then return r end
	end
	if State.UI.RowTemplate and State.UI.RowTemplate:IsA("Instance") then
		local c = State.UI.RowTemplate:Clone()
		c.Name = "SongRow"
		c.Visible = true
		c.Parent = parent
		return c
	end
	return DefaultRowFactory(parent)
end

local function SetButtonHover(btn)
	if not btn or not btn.MouseEnter then return end
	btn.MouseEnter:Connect(function()
		if btn:IsA("ImageButton") then
			TweenService:Create(btn, TweenInfo.new(0.12), { ImageTransparency = 0.05 }):Play()
		end
	end)
	btn.MouseLeave:Connect(function()
		if btn:IsA("ImageButton") then
			TweenService:Create(btn, TweenInfo.new(0.12), { ImageTransparency = 0 }):Play()
		end
	end)
	btn.MouseButton1Down:Connect(function()
		if btn:IsA("ImageButton") then
			TweenService:Create(btn, TweenInfo.new(0.06), { Size = btn.Size + UDim2.new(0,2,0,2) }):Play()
		end
	end)
	btn.MouseButton1Up:Connect(function()
		if btn:IsA("ImageButton") then
			TweenService:Create(btn, TweenInfo.new(0.06), { Size = btn.Size - UDim2.new(0,2,0,2) }):Play()
		end
	end)
end

function VS.RefreshPlayButtons()
	for id, btn in pairs(State.UI.ButtonById) do
		if btn and btn:IsA("ImageButton") then
			if State.Playing and State.Current and tonumber(id) == tonumber(State.Current.id) then
				btn.Image = IMAGE_PAUSE
			else
				btn.Image = IMAGE_PLAY
			end
		end
	end
end

function VS.RefreshRowHighlight()
	for id, row in pairs(State.UI.RowById) do
		if row and row:IsA("GuiObject") then
			local isActive = (State.Current and tonumber(id) == tonumber(State.Current.id))
			local t = isActive and 0.06 or 0.1
			if row.BackgroundTransparency ~= nil then
				row.BackgroundTransparency = t
			end
			-- if there's a UIStroke, make it pop a bit
			local stroke = row:FindFirstChildWhichIsA("UIStroke", true)
			if stroke then stroke.Transparency = isActive and 0.3 or 0.6 end
		end
	end
end

local function RenderList(container, rows, replace)
	if replace then ClearContainer(container) end

	if not rows or #rows == 0 then
		TogglePlaceholder(true)
		return
	end
	TogglePlaceholder(false)

	for i, row in ipairs(rows) do
		local holder = MakeRow(container)
		local root = holder:FindFirstChild("Row") or holder

		-- labels
		local tl = State.UI.Map and GetFromPath(root, State.UI.Map.TitleLabel)
		if tl and tl:IsA("TextLabel") then tl.Text = tostring(row.title or ("ID "..tostring(row.id))) end
		local tm = State.UI.Map and GetFromPath(root, State.UI.Map.TimeLabel)
		if tm and tm:IsA("TextLabel") then tm.Text = FormatTime(row.seconds or 0) end
		if holder:IsA("TextButton") and not tl then
			holder.Text = string.format("%d) %s  [%s]", i, row.title or ("ID "..tostring(row.id)), FormatTime(row.seconds or 0))
		end

		-- play button
		local pb = State.UI.Map and GetFromPath(root, State.UI.Map.PlayButton)
		if pb and pb:IsA("ImageButton") then
			pb.Image = IMAGE_PLAY
			SetButtonHover(pb)
			State.UI.ButtonById[tostring(row.id)] = pb
			State.UI.RowById[tostring(row.id)] = holder
			pb.MouseButton1Click:Connect(function()
				if State.Current and tonumber(State.Current.id) == tonumber(row.id) then
					if State.Playing then VS.Pause() else VS.Resume() end
					return
				end
				task.spawn(function()
					local ok, err = pcall(function() VS.PlayById(row.id, row.title) end)
					if not ok then
						warn(err)
						SafeCall(State.OnError, err)
					end
				end)
			end)
		elseif holder:IsA("GuiButton") then
			holder.MouseButton1Click:Connect(function()
				task.spawn(function()
					local ok, err = pcall(function() VS.PlayById(row.id, row.title) end)
					if not ok then
						warn(err)
						SafeCall(State.OnError, err)
					end
				end)
			end)
		end

		-- optional: add-to-queue button
		local addb = State.UI.Map and GetFromPath(root, State.UI.Map.AddButton)
		if addb and addb:IsA("GuiButton") then
			addb.MouseButton1Click:Connect(function()
				table.insert(State.Queue, { id=row.id, title=row.title, seconds=row.seconds })
				SafeCall(State.OnQueueUpd, State.Queue)
			end)
		end
	end

	VS.RefreshPlayButtons()
	VS.RefreshRowHighlight()
end

--========== Public API

-- mapping & UI
function VS.SetRowMap(map) State.UI.Map = map or {} end
function VS.SetRowFactory(fn) State.UI.RowFactory = fn end
function VS.SetRowTemplate(template) State.UI.RowTemplate = template end
function VS.SetResultsContainer(container) State.UI.Container = container end
function VS.BindPlaceholder(placeholderFrame) State.UI.Placeholder = placeholderFrame end
function VS.BindBusyIndicator(instance) State.UI.BusyIndicator = instance end
function VS.OnQueueChanged(fn) State.OnQueueUpd = fn end
function VS.OnError(fn) State.OnError = fn end
function VS.OnEnded(fn) State.OnEnded = fn end

-- config
function VS.SetHistoryLimit(n) State.HistoryLimit = math.max(1, tonumber(n) or MAX_HISTORY) end
function VS.SetAutoplay(on) State.Autoplay = (on == true) end
function VS.GetAutoplay() return State.Autoplay end

-- search + render
function VS.Search(q, page) return SearchImpl(q, page) end

function VS.RenderResultsTo(container, results)
	State.UI.Container = container or State.UI.Container
	if not State.UI.Container then return end
	RenderList(State.UI.Container, results, true)
end

function VS.AppendResultsTo(container, results)
	local c = container or State.UI.Container
	if not c then return end
	RenderList(c, results, false)
end

function VS.ClearResults(container)
	local c = container or State.UI.Container
	if not c then return end
	ClearContainer(c)
	TogglePlaceholder(true)
end

function VS.SearchTo(container, q, page)
	State.UI.Container = container or State.UI.Container
	if not State.UI.Container then return end

	local txt = tostring(q or ""):gsub("^%s+",""):gsub("%s+$","")
	if txt == "" then
		VS.ClearResults(State.UI.Container)
		return
	end

	task.spawn(function()
		local ok, res, np = pcall(function() return VS.Search(txt, page) end)
		if not ok then
			warn(res)
			SafeCall(State.OnError, res)
			VS.ClearResults(State.UI.Container)
			return
		end
		State.UI.Query = txt
		State.UI.NextPage = np
		RenderList(State.UI.Container, res, true)
	end)
end

function VS.NextPage(container)
	State.UI.Container = container or State.UI.Container
	if not State.UI.Container then return end
	if not State.UI.Query then return end
	if not State.UI.NextPage then return end
	local q = State.UI.Query
	local p = tonumber(State.UI.NextPage)
	task.spawn(function()
		local ok, res, np = pcall(function() return VS.Search(q, p) end)
		if not ok then return end
		State.UI.NextPage = np
		RenderList(State.UI.Container, res, false)
	end)
end

-- playback
function VS.PlayById(id, title)
	local filePath, url = DownloadOrGetFromLibrary(id, title)
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

function VS.Pause() local s=EnsureSound(); s:Pause(); State.Playing=false; VS.RefreshPlayButtons(); VS.RefreshRowHighlight() end
function VS.Resume() local s=EnsureSound(); s:Resume(); State.Playing=true; VS.RefreshPlayButtons(); VS.RefreshRowHighlight() end
function VS.TogglePause() if State.Playing then VS.Pause() else VS.Resume() end end
function VS.Stop() local s=EnsureSound(); s:Stop(); State.Playing=false; VS.RefreshPlayButtons(); VS.RefreshRowHighlight() end
function VS.Seek(sec) local s=EnsureSound(); s.TimePosition = math.max(0, tonumber(sec) or 0) end
function VS.SeekSafe(sec) local s=EnsureSound(); local t = math.clamp(tonumber(sec) or 0, 0, s.TimeLength or 0); s.TimePosition = t end
function VS.SetSpeed(rate) local s=EnsureSound(); s.PlaybackSpeed = math.clamp(tonumber(rate) or 1, 0.05, 4) end
function VS.SetVolume(v) local s=EnsureSound(); s.Volume = math.clamp(tonumber(v) or 0.5, 0, 1) end

function VS.SwapToLastPlayed()
	local hist = ReadJson(HISTORY_FILE, {})
	if #hist == 0 then return false end
	local last = hist[#hist-1] or hist[#hist]
	if not last or not last.file or not isfile(last.file) then return false end
	PlayLocal(last.file, { id = last.id, title = last.title, url = last.url })
	return true
end

function VS.PlayNext()
	-- queue first
	if #State.Queue > 0 then
		local item = table.remove(State.Queue, 1)
		SafeCall(State.OnQueueUpd, State.Queue)
		if item then VS.PlayById(item.id, item.title) return true end
	end
	-- then from last results
	local rows = State.LastResults or {}
	if not rows or #rows == 0 or not State.Current then return false end
	local idx = 1
	for i, r in ipairs(rows) do if tonumber(r.id) == tonumber(State.Current.id) then idx = i + 1 break end end
	if rows[idx] then VS.PlayById(rows[idx].id, rows[idx].title) return true end
	return false
end

function VS.PlayPrev()
	local rows = State.LastResults or {}
	if not rows or #rows == 0 or not State.Current then return false end
	local idx = 1
	for i, r in ipairs(rows) do if tonumber(r.id) == tonumber(State.Current.id) then idx = i - 1 break end end
	if idx >= 1 and rows[idx] then VS.PlayById(rows[idx].id, rows[idx].title) return true end
	return false
end

-- state
function VS.GetState()
	local s = EnsureSound()
	local c = State.Current or {}
	local playbackState = "Unknown"
	pcall(function() playbackState = s.PlaybackState and s.PlaybackState.Name or (s.IsPlaying and "Playing" or "Stopped") end)
	return {
		id=c.id, title=c.title, url=c.url, file=c.file,
		isPlaying=State.Playing, time=s.TimePosition, length=s.TimeLength,
		volume=s.Volume, speed=s.PlaybackSpeed, playbackState=playbackState,
	}
end

function VS.GetLastResults() return State.LastResults end
function VS.GetHistory() return ReadJson(HISTORY_FILE, {}) end
function VS.GetQueue() return State.Queue end

-- cleaners
function VS.ClearPlaying() for _, f in ipairs(ListDir(DIR_PLAYING)) do pcall(DelF, f) end end
function VS.ClearLast() for _, f in ipairs(ListDir(DIR_LAST)) do pcall(DelF, f) end end
function VS.ClearSearchCache() WriteF(CACHE_SEARCH, "{}"); State.Cache.Searches = {} end
function VS.ClearLibraryIndex() WriteF(LIB_INDEX, "{}"); State.Cache.Library = {} end
function VS.ClearAll()
	VS.ClearPlaying(); VS.ClearLast(); VS.ClearSearchCache(); VS.ClearLibraryIndex()
	WriteF(HISTORY_FILE, "[]")
end

-- wiring
function VS.WireSearchUi(args)
	local SearchBox        = args.SearchBox
	local SearchButton     = args.SearchButton
	local ResultsContainer = args.ResultsContainer
	local RowTemplate      = args.RowTemplate
	local Map              = args.Map
	local Placeholder      = args.Placeholder
	local LiveDelay        = tonumber(args.LiveDelay) or 0
	local BusyIndicator    = args.BusyIndicator

	if RowTemplate then VS.SetRowTemplate(RowTemplate) end
	if ResultsContainer then VS.SetResultsContainer(ResultsContainer) end
	if Map then VS.SetRowMap(Map) end
	if Placeholder then VS.BindPlaceholder(Placeholder) end
	if BusyIndicator then VS.BindBusyIndicator(BusyIndicator) end
	State.UI.LiveDelay = LiveDelay

	-- start with placeholder if nothing rendered
	TogglePlaceholder(true)

	if SearchButton then
		SearchButton.Activated:Connect(function()
			local q = (SearchBox and SearchBox.Text or "")
			VS.SearchTo(ResultsContainer, q, 1)
		end)
	end

	if SearchBox and SearchBox:IsA("TextBox") then
		-- Enter to search
		SearchBox.FocusLost:Connect(function(enter)
			if enter then VS.SearchTo(ResultsContainer, SearchBox.Text, 1) end
		end)

		-- live search debounce
		if State.UI.LiveDelay > 0 then
			if State.UI._liveConn then State.UI._liveConn:Disconnect() end
			local lastTick = 0
			State.UI._liveConn = SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
				local txt = tostring(SearchBox.Text or "")
				if txt:gsub("%s","") == "" then
					VS.ClearResults(ResultsContainer)
					return
				end
				lastTick = os.clock()
				local myTick = lastTick
				delay(State.UI.LiveDelay/1000, function()
					if myTick == lastTick then
						VS.SearchTo(ResultsContainer, txt, 1)
					end
				end)
			end)
		end
	end
end

--==========
return VS
