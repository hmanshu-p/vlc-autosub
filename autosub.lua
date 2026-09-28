-- AutoSub: generate subtitles for the playing video with whisper.cpp.
-- The work runs in autosub.sh; this extension just starts it. See README.md.

local LANGS = {
  { "auto", "Auto-detect" }, { "en", "English" }, { "hi", "Hindi" },
  { "es", "Spanish" }, { "fr", "French" }, { "de", "German" },
  { "it", "Italian" }, { "pt", "Portuguese" }, { "ru", "Russian" },
  { "ja", "Japanese" }, { "ko", "Korean" }, { "zh", "Chinese" },
  { "ar", "Arabic" }, { "ta", "Tamil" }, { "te", "Telugu" },
}

local DIR, dlg, status_label, lang_dd, translate_cb

function descriptor()
  return {
    title = "AutoSub - Generate Subtitles",
    version = "1.1",
    shortdesc = "AutoSub",
    description = "Transcribes the playing video offline with whisper.cpp and loads the subtitles.",
    url = "https://github.com/hmanshu-p/vlc-autosub",
  }
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

-- Single-quote for the shell.
local function q(s)
  return "'" .. (s:gsub("'", "'\\''")) .. "'"
end

local function set_status(text)
  status_label:set_text(text)
  dlg:update()
end

local function current_path()
  local item = vlc.input.item()
  local uri = item and item:uri()
  if uri and uri:match("^file://") then
    return vlc.strings.decode_uri(uri:sub(8))
  end
end

local function job_running()
  local pid = (read_file(DIR .. "/pid") or ""):match("^%d+")
  local r = pid and os.execute("kill -0 " .. pid .. " 2>/dev/null")
  return r == 0 or r == true -- Lua 5.1 returns 0, 5.2+ returns true
end

local function generate()
  local path = current_path()
  if not path then
    return set_status("Open a local video file first.")
  end
  if job_running() then
    return set_status("Already running.")
  end
  local out = path:gsub("%.[^./]*$", "") .. ".autosub.srt"
  if read_file(out) then
    vlc.input.add_subtitle(out, true)
    return set_status("Loaded the saved subtitles.")
  end
  local lang = LANGS[lang_dd:get_value()][1]
  local translate = translate_cb:get_checked() and "1" or "0"
  os.execute("/bin/bash " .. q(DIR .. "/autosub.sh") .. " " .. q(path) .. " " .. q(lang)
    .. " " .. translate .. " >/dev/null 2>&1 &")
  set_status("Started. You can close this.")
end

function activate()
  -- VLC loads extensions without the os/io libraries, so resolve paths here.
  DIR = os.getenv("HOME") .. "/Library/Application Support/vlc-autosub"
  dlg = vlc.dialog("AutoSub")
  dlg:add_label("Spoken language:", 1, 1, 1, 1)
  lang_dd = dlg:add_dropdown(2, 1, 1, 1)
  for i, l in ipairs(LANGS) do lang_dd:add_value(l[2], i) end
  translate_cb = dlg:add_check_box("Translate to English", false, 1, 2, 2, 1)
  dlg:add_button("Generate subtitles", generate, 1, 3, 2, 1)
  status_label = dlg:add_label(job_running() and "Running (see progress window)."
    or "Play a video, then press Generate.", 1, 4, 2, 1)
  dlg:show()
end

function deactivate()
  if dlg then dlg:delete() end
end

function close()
  vlc.deactivate()
end
