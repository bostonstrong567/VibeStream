--// VibeStream — single-file z3.fm search + resolve + download + play (executor-friendly)
--// Public API on _G.VibeStream:
--// Search(q, page?), PlayById(id, title?), SearchAndPlay(query, index?, page?),
--// Pause(), Resume(), TogglePause(), Stop(), Seek(sec), SetSpeed(rate), SetVolume(v),
--// OnEnded(fn), SetHistoryLimit(n), SwapToLastPlayed(), GetState(), GetLastResults(),
--// GetHistory(), ClearPlaying(), ClearLast(), ClearAll()

-- =================== Config ===================
local UA     = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36"
local COOKIE = "zvApp=detect2; zvLang=0; zvAuth=1"
local ROOT   = "VibeStream"
local DIR_PLAYING = ROOT.."/Playing"
local DIR_LAST    = ROOT.."/Last_Played"
local HISTORY_FILE = ROOT.."/history.json"
local MAX_HISTORY  = 30

-- =================== Services ===================
local HttpService  = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

-- =================== Utilities ===================
local function has(fname)
    local ok, f = pcall(function() return getfenv()[fname] end)
    return ok and typeof(f) == "function"
end

local function req(o)
    if syn and syn.request then return syn.request(o) end
    if request then return request(o) end
    if http and http.request then return http.request(o) end
    error("No HTTP request function found.")
end

local function httpget_url(url)
    if httpget then return httpget(url) end
    local ok, res = pcall(function() return game:HttpGet(url, true) end)
    if ok then return res end
    return nil
end

local function ensureDir(p) if not isfolder(p) then makefolder(p) end end
local function readf(p) if isfile(p) then return readfile(p) end end
local function writef(p, s) writefile(p, s) end
local function delf(p) if isfile(p) then delfile(p) end end
local function listdir(p) if isfolder(p) then return listfiles(p) else return {} end end
local function movefile(src, dst) local b=readf(src); if b then writef(dst,b); delf(src) end end

-- keep filenames executor-safe (ASCII only, no weird punctuation)
local function sanitize_filename(s)
    s = tostring(s or "audio")
    s = s:gsub("[\\/:*?\"<>|]", "_")
    s = s:gsub("[%z\1-\31]", "_")
    s = s:gsub("[^%w%._ %-]", "_") -- strip non-ASCII / em-dash etc.
    s = s:gsub("%s+", " "):gsub("^%s+",""):gsub("%s+$","")
    if #s == 0 then s = "audio" end
    return s
end

local function urlencode(s)
    return tostring(s):gsub("\n","\r\n"):gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
end

local function html_unescape(s)
    s = s
        :gsub("&amp;", "&"):gsub("&lt;", "<"):gsub("&gt;", ">")
        :gsub("&quot;", "\""):gsub("&#39;", "'")
    s = s:gsub("&#(%d+);", function(n) return string.char(tonumber(n)) end)
    return s
end

local function grab(h, k) if not h then return nil end return h[k] or h[k:lower()] or h[k:upper()] end
local function is_audio_headers(h)
    local ct = grab(h, "Content-Type"); if not ct then return false end
    ct = tostring(ct):lower()
    return ct:find("audio/") or ct:find("octet%-stream")
end

local function looks_like_mp3(bytes)
    if not bytes or #bytes < 3 then return false end
    if bytes:sub(1,3) == "ID3" then return true end
    local b1,b2 = bytes:byte(1,2)
    if b1 == 0xFF and b2 then
        local mask = bit32 and bit32.band(b2, 0xE0) or (b2 - (b2 % 0x20))
        return mask == 0xE0
    end
    return false
end

-- =================== State ===================
ensureDir(ROOT); ensureDir(DIR_PLAYING); ensureDir(DIR_LAST)
if not isfile(HISTORY_FILE) then writef(HISTORY_FILE, "[]") end

local state = {
    sound = nil,
    playing = false,
    current = nil,     -- { id, title, url, file }
    lastResults = {},  -- cache from last Search
    onEnded = nil,
    historyLimit = MAX_HISTORY,
}

-- =================== Sound ===================
local function ensureSound()
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
            movefile(c.file, lastPath)
        end
        if state.onEnded then
            local id = c and c.id
            task.spawn(state.onEnded, id)
        end
    end)
    state.sound = s
    return s
end

-- =================== History ===================
local function pushHistory(entry)
    local ok, tbl = pcall(function() return HttpService:JSONDecode(readf(HISTORY_FILE) or "[]") end)
    local hist = (ok and typeof(tbl)=="table") and tbl or {}
    hist[#hist+1] = entry
    local keep = state.historyLimit
    if #hist > keep then
        local drop = #hist - keep
        for i = 1, drop do
            local ev = hist[i]
            if ev and ev.file and isfile(ev.file) then pcall(delf, ev.file) end
        end
        local new = {}
        for i = drop+1, #hist do new[#new+1] = hist[i] end
        hist = new
    end
    writef(HISTORY_FILE, HttpService:JSONEncode(hist))
end

-- =================== Search Parsing ===================
local function parseResults(html)
    local out = {}
    for node in html:gmatch("<span[^>]-class=\"song%-play[^\"\n]*\"[^>]->") do
        local sid   = node:match("data%-sid=\"(%d+)\"")
        local secs  = tonumber(node:match("data%-time=\"(%d+)\"") or "0") or 0
        local title = node:match("data%-title=\"(.-)\"")
        if sid and title then
            title = html_unescape(title):gsub("<.->","")
            out[#out+1] = { id = tonumber(sid), title = title, artist = "", seconds = secs }
        end
    end
    local nextPage = html:match("href=\"/mp3/search%?keywords[^\"=]*=[^\"]-page=(%d+)\"[^>]-class=\"next")
    return out, (nextPage and tonumber(nextPage) or nil)
end

-- =================== Search ===================
local function search(query, page)
    page = page or 1
    local url = ("https://z3.fm/mp3/search?keywords=%s&page=%d&sort=views"):format(urlencode(query), page)

    local r = req({
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
        local r2 = req({
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

    local results, nextPage = parseResults(body)
    state.lastResults = results
    return results, nextPage
end

-- =================== Resolve direct MP3 ===================
local function extract_mp3_from_html(html)
    if not html or #html == 0 then return nil end
    local direct = html:match('href="(https?://[^"]+%.mp3[^"]*)"')
        or html:match("window%.location%s*=%s*['\"](https?://[^'\"]+%.mp3[^'\"]*)['\"]")
    if direct then return direct end
    local meta = html:match('<meta%s+http%-equiv=["\']refresh["\']%s+content=["\']%d+;url=(.-)["\']')
    if meta and meta:find("%.mp3") then return meta end
    return nil
end

local function resolve_request(id, headers)
    return req({
        Url = ("https://z3.fm/download/%s?play=on"):format(tostring(id)),
        Method = "GET", Headers = headers
    })
end

local function resolveMp3Url_or_body(id)
    local r1 = resolve_request(id, {
        ["User-Agent"] = UA, ["Cookie"] = COOKIE, ["Referer"] = "https://z3.fm/",
        ["Accept"] = "*/*", ["Accept-Language"] = "en-US,en;q=0.9", ["DNT"] = "1",
    })
    if r1 then
        local loc = grab(r1.Headers, "Location")
        if loc then if loc:sub(1,1)=="/" then loc="https://z3.fm"..loc end; return { url = loc } end
        if is_audio_headers(r1.Headers) and r1.Body and #r1.Body>0 then
            return { directBody = r1.Body, finalUrl = r1.Url or "" }
        end
        local h = extract_mp3_from_html(r1.Body); if h then return { url = h } end
    end

    local r2 = resolve_request(id, {
        ["User-Agent"] = UA, ["Cookie"] = COOKIE, ["Referer"] = "https://z3.fm/",
        ["Accept"] = "*/*", ["Range"] = "bytes=0-0", ["Accept-Language"] = "en-US,en;q=0.9", ["DNT"] = "1",
    })
    if r2 then
        local loc2 = grab(r2.Headers, "Location")
        if loc2 then if loc2:sub(1,1)=="/" then loc2="https://z3.fm"..loc2 end; return { url = loc2 } end
        if is_audio_headers(r2.Headers) and r2.Body and #r2.Body>0 then
            return { directBody = r2.Body, finalUrl = r2.Url or "" }
        end
        local h2 = extract_mp3_from_html(r2.Body); if h2 then return { url = h2 } end
    end

    local raw = httpget_url(("https://z3.fm/download/%s?play=on"):format(tostring(id)))
    if type(raw)=="string" and looks_like_mp3(raw) then
        return { directBody = raw, finalUrl = "" }
    elseif type(raw)=="string" then
        local inHtml = extract_mp3_from_html(raw); if inHtml then return { url = inHtml } end
    end

    local _ = req({
        Url = ("https://z3.fm/song/%s"):format(tostring(id)), Method = "GET",
        Headers = {
            ["User-Agent"] = UA, ["Cookie"] = COOKIE, ["Accept"] = "text/html,*/*",
            ["Accept-Language"] = "en-US,en;q=0.9", ["Referer"] = "https://z3.fm/", ["DNT"] = "1",
        }
    })
    local again = resolve_request(id, {
        ["User-Agent"] = UA, ["Cookie"] = COOKIE,
        ["Referer"] = ("https://z3.fm/song/%s"):format(tostring(id)),
        ["Accept"] = "*/*", ["Accept-Language"] = "en-US,en;q=0.9", ["DNT"] = "1",
    })
    if again then
        local loc3 = grab(again.Headers, "Location")
        if loc3 then if loc3:sub(1,1)=="/" then loc3="https://z3.fm"..loc3 end; return { url = loc3 } end
        if is_audio_headers(again.Headers) and again.Body and #again.Body>0 then
            return { directBody = again.Body, finalUrl = again.Url or "" }
        end
        local h3 = extract_mp3_from_html(again.Body); if h3 then return { url = h3 } end
    end

    return nil, "Could not resolve direct MP3 URL (no redirect or audio body)."
end

-- =================== Download ===================
local function downloadToPlaying(id, title)
    ensureDir(DIR_PLAYING)
    for _, f in ipairs(listdir(DIR_PLAYING)) do pcall(delf, f) end

    local resolved, err = resolveMp3Url_or_body(id)
    if not resolved then error(err or "MP3 resolve failed") end

    local nice = sanitize_filename(title or tostring(id))
    local filePath = ("%s/%s_%s.mp3"):format(DIR_PLAYING, tostring(id), nice)

    if resolved.directBody then
        writef(filePath, resolved.directBody)
    else
        local mp3Url = resolved.url
        local r = req({
            Url = mp3Url, Method = "GET",
            Headers = {
                ["User-Agent"] = UA, ["Accept"] = "*/*",
                ["Referer"] = "https://z3.fm/", ["Accept-Language"] = "en-US,en;q=0.9", ["DNT"] = "1",
            }
        })
        if not r or type(r.Body) ~= "string" or (r.StatusCode or 0) >= 400 then
            local raw2 = httpget_url(mp3Url)
            if type(raw2) == "string" and #raw2 > 0 then
                writef(filePath, raw2)
            else
                error(("Download failed (status %s)."):format(r and r.StatusCode or "nil"))
            end
        else
            writef(filePath, r.Body)
        end
    end

    local bytes = readf(filePath)
    if type(bytes) ~= "string" or #bytes == 0 then
        error("Downloaded file is empty or missing: "..tostring(filePath))
    end

    pushHistory({
        id = id, title = title or tostring(id),
        url = resolved.url or (resolved.finalUrl or ""), file = filePath, t = os.time()
    })
    return filePath, (resolved.url or resolved.finalUrl or "")
end

-- =================== Asset mapping (robust) ===================
-- Some executors only allow getcustomasset/getsynasset on files in the *workspace root*
-- and often choke on subfolders or unicode. We copy to a root, ASCII-only name and try again.
local function toasset(path, id)
    -- First try given path (subfolders may work on some executors)
    if has("getsynasset") then
        local ok, cid = pcall(getsynasset, path)
        if ok and type(cid)=="string" and #cid>0 then return cid end
        ok, cid = pcall(getsynasset, "./"..path)
        if ok and type(cid)=="string" and #cid>0 then return cid end
    end
    if has("getcustomasset") then
        local ok, cid = pcall(getcustomasset, path)
        if ok and type(cid)=="string" and #cid>0 then return cid end
        ok, cid = pcall(getcustomasset, "./"..path)
        if ok and type(cid)=="string" and #cid>0 then return cid end
    end

    -- Fallback: copy to workspace root with ASCII-only name
    local rootName = ("VS_%s.mp3"):format(sanitize_filename(tostring(id or "current")))
    writef(rootName, readf(path) or "")
    if has("getsynasset") then
        local ok, cid = pcall(getsynasset, rootName)
        if ok and type(cid)=="string" and #cid>0 then return cid end
    end
    if has("getcustomasset") then
        local ok, cid = pcall(getcustomasset, rootName)
        if ok and type(cid)=="string" and #cid>0 then return cid end
    end

    -- One more hail-mary: try absolute-ish variants some executors like
    local alts = { "/workspace/"..rootName, "workspace/"..rootName }
    for _, p in ipairs(alts) do
        if has("getsynasset") then
            local ok, cid = pcall(getsynasset, p)
            if ok and type(cid)=="string" and #cid>0 then return cid end
        end
        if has("getcustomasset") then
            local ok, cid = pcall(getcustomasset, p)
            if ok and type(cid)=="string" and #cid>0 then return cid end
        end
    end

    return nil
end

-- =================== Playback ===================
local function playLocal(path, meta)
    assert(type(path)=="string" and #path>0, "Invalid local path")
    assert(isfile(path), "Audio file not found at "..tostring(path))

    local s = ensureSound()
    s:Stop()

    local cid = toasset(path, meta.id)
    if not cid or #cid == 0 then
        error("getcustomasset/getsynasset failed to map path -> ContentId ("..tostring(path)..")")
    end

    s.SoundId = cid
    pcall(function() ContentProvider:PreloadAsync({s}) end)
    s.PlaybackSpeed = 1
    s.TimePosition  = 0
    s:Play()

    state.playing = true
    state.current = { id = meta.id, title = meta.title, url = meta.url, file = path }
end

-- =================== Public API ===================
local VS = {}

function VS.Search(q, page)
    return search(q, page)
end

function VS.PlayById(id, title)
    local filePath, url = downloadToPlaying(id, title)
    playLocal(filePath, { id = id, title = title or tostring(id), url = url })
end

function VS.SearchAndPlay(query, index, page)
    local rows = search(query, page)
    if not rows or #rows == 0 then return false, "no results" end
    local n = math.clamp(tonumber(index) or 1, 1, #rows)
    local row = rows[n]
    VS.PlayById(row.id, row.title)
    return true
end

function VS.Pause() local s=ensureSound(); s:Pause(); state.playing=false end
function VS.Resume() local s=ensureSound(); s:Resume(); state.playing=true end
function VS.TogglePause()
    local s=ensureSound()
    if s.IsPlaying then s:Pause(); state.playing=false else s:Resume(); state.playing=true end
end
function VS.Stop() local s=ensureSound(); s:Stop(); state.playing=false end
function VS.Seek(sec) local s=ensureSound(); s.TimePosition = math.max(0, tonumber(sec) or 0) end
function VS.SetSpeed(rate) local s=ensureSound(); s.PlaybackSpeed = math.clamp(tonumber(rate) or 1, 0.05, 4) end
function VS.SetVolume(v) local s=ensureSound(); s.Volume = math.clamp(tonumber(v) or 0.5, 0, 1) end

function VS.OnEnded(fn) state.onEnded = fn end
function VS.SetHistoryLimit(n) state.historyLimit = math.max(1, tonumber(n) or MAX_HISTORY) end

function VS.SwapToLastPlayed()
    local ok, tbl = pcall(function() return HttpService:JSONDecode(readf(HISTORY_FILE) or "[]") end)
    local hist = (ok and typeof(tbl)=="table") and tbl or {}
    if #hist == 0 then return false end
    local last = hist[#hist-1] or hist[#hist]
    if not last or not last.file or not isfile(last.file) then return false end
    for _, f in ipairs(listdir(DIR_PLAYING)) do pcall(delf, f) end
    local back = ("%s/%s.mp3"):format(DIR_PLAYING, tostring(last.id or "prev"))
    movefile(last.file, back)
    playLocal(back, { id = last.id, title = last.title, url = last.url })
    return true
end

function VS.GetState()
    local s = ensureSound()
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
    local ok, tbl = pcall(function() return HttpService:JSONDecode(readf(HISTORY_FILE) or "[]") end)
    return (ok and typeof(tbl)=="table") and tbl or {}
end

function VS.ClearPlaying() for _, f in ipairs(listdir(DIR_PLAYING)) do pcall(delf, f) end end
function VS.ClearLast() for _, f in ipairs(listdir(DIR_LAST)) do pcall(delf, f) end end
function VS.ClearAll() VS.ClearPlaying(); VS.ClearLast(); writef(HISTORY_FILE, "[]") end

_G.VibeStream = VS
