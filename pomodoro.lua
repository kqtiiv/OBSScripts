obs = obslua

-- ==== Defaults ====
timer_source_name = "PomodoroTimer"
status_source_name = ""
session_source_name = ""
focus_minutes = 25
short_break_minutes = 5
long_break_minutes = 15
sessions_before_long = 4
daily_sessions = 0
show_mode_label = true
show_session_counter = true
session_label = "Session"
focus_message = "Focus"
short_break_message = "Short Break"
long_break_message = "Long Break"
stopped_message = "Timer Stopped"
paused_message = "Paused"
label_focus = "FOCUS"
label_short_break = "BREAK"
label_long_break = "LONG BREAK"

-- Start/end time display
show_start_time = true
start_time_label = "Started"
show_end_time = true
end_time_label = "Ends at"
end_time_inline = true
sep_char = "•"
use_24h = true

-- Sounds (non-blocking via media sources)
enable_sounds = true
sound_focus_file = ""
sound_short_file = ""
sound_long_file  = ""

-- Colors (for timer text source)
color_focus = 0x00FF00
color_short_break = 0xFFFF00
color_long_break = 0xFF0000
color_paused = 0xFFFFFF
color_stopped = 0xAAAAAA

-- Desktop notifications
enable_notifications = true

-- Auto-start / scene switching
auto_scene_name = ""
scene_on_break = ""
scene_on_focus = ""

-- State
mode = "stopped"      -- "focus" | "short_break" | "long_break" | "paused" | "stopped"
prev_mode = "focus"
time_left = 0
session_count = 0
timer_running = false
session_start_time = 0

-- Sound source handles
src_focus = nil
src_short = nil
src_long  = nil

-- Hotkeys
hk_start = obs.OBS_INVALID_HOTKEY_ID
hk_pause = obs.OBS_INVALID_HOTKEY_ID
hk_resume= obs.OBS_INVALID_HOTKEY_ID
hk_reset = obs.OBS_INVALID_HOTKEY_ID
hk_skip  = obs.OBS_INVALID_HOTKEY_ID

-- Utils 
local function file_exists(path)
    if not path or path == "" then return false end
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local function get_source(name)
    if not name or name == "" then return nil end
    return obs.obs_get_source_by_name(name)
end

local function set_text(name, text)
    local src = get_source(name)
    if src then
        local s = obs.obs_data_create()
        obs.obs_data_set_string(s, "text", text)
        obs.obs_source_update(src, s)
        obs.obs_data_release(s)
        obs.obs_source_release(src)
    end
end

local function set_color(name, color)
    local src = get_source(name)
    if src then
        local s = obs.obs_data_create()
        obs.obs_data_set_int(s, "color", color)
        obs.obs_source_update(src, s)
        obs.obs_data_release(s)
        obs.obs_source_release(src)
    end
end

local function fmt_mmss(sec)
    if sec < 0 then sec = 0 end
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    local s = sec % 60
    if h > 0 then return string.format("%d:%02d:%02d", h, m, s) else return string.format("%02d:%02d", m, s) end
end

local function fmt_clock(ts)
    return os.date(use_24h and "%H:%M" or "%I:%M %p", ts)
end

local function current_label()
    if mode == "focus" then return label_focus
    elseif mode == "short_break" then return label_short_break
    elseif mode == "long_break" then return label_long_break
    elseif mode == "paused" then return paused_message
    else return stopped_message end
end

local function session_text()
    if not show_session_counter then return "" end
    local m = (mode == "paused") and prev_mode or mode
    if m == "stopped" or mode == "stopped" then return "" end
    if m == "long_break" and daily_sessions == 0 then return "Cycle Complete" end
    local idx = session_count
    if m == "focus" then idx = session_count + 1 end
    local total = daily_sessions > 0 and daily_sessions or sessions_before_long
    if total > 0 then
        return string.format("%s %d of %d", session_label, idx, total)
    else
        return string.format("%s %d", session_label, idx)
    end
end

-- Desktop notifications
local _platform = nil
local function detect_platform()
    if _platform then return _platform end
    local f = io.popen("uname -s 2>/dev/null")
    if f then
        local s = (f:read("*l") or ""):lower(); f:close()
        if s:find("darwin") then _platform = "mac"
        elseif s ~= "" then _platform = "linux"
        else _platform = "windows" end
    else
        _platform = "windows"
    end
    return _platform
end

local function send_notification(title, body)
    if not enable_notifications then return end
    local t = title:gsub('[\'"]', '')
    local b = body:gsub('[\'"]', '')
    local plat = detect_platform()
    if plat == "mac" then
        os.execute(string.format("osascript -e 'display notification \"%s\" with title \"%s\"' &", b, t))
    elseif plat == "linux" then
        os.execute(string.format('notify-send "%s" "%s" &', t, b))
    else
        local ps = string.format(
            "Add-Type -AN System.Windows.Forms;" ..
            "$n=New-Object System.Windows.Forms.NotifyIcon;" ..
            "$n.Icon=[System.Drawing.SystemIcons]::Application;" ..
            "$n.Visible=$true;" ..
            "$n.ShowBalloonTip(8000,'%s','%s',[System.Windows.Forms.ToolTipIcon]::Info);" ..
            "Start-Sleep 10;$n.Dispose()", t, b)
        os.execute('start "" /b powershell -WindowStyle Hidden -NoProfile -Command "' .. ps .. '"')
    end
end

-- Sounds 
local function release_sound_sources()
    if src_focus then obs.obs_source_release(src_focus); src_focus = nil end
    if src_short then obs.obs_source_release(src_short); src_short = nil end
    if src_long  then obs.obs_source_release(src_long);  src_long  = nil end
end

local function create_media_source(path, tag)
    if not file_exists(path) then return nil end
    local s = obs.obs_data_create()
    obs.obs_data_set_string(s, "local_file", path)
    obs.obs_data_set_bool(s, "is_local_file", true)
    obs.obs_data_set_bool(s, "looping", false)
    obs.obs_data_set_bool(s, "restart_on_activate", true)
    local src = obs.obs_source_create_private("ffmpeg_source", "pomo_snd_"..tag, s)
    obs.obs_data_release(s)
    return src
end

local function rebuild_sound_sources()
    release_sound_sources()
    if enable_sounds and file_exists(sound_focus_file) then src_focus = create_media_source(sound_focus_file, "focus") end
    if enable_sounds and file_exists(sound_short_file) then src_short = create_media_source(sound_short_file, "short") end
    if enable_sounds and file_exists(sound_long_file)  then src_long  = create_media_source(sound_long_file,  "long")  end
end

local function play_source(src)
    if not src or not enable_sounds then return end
    -- Try native restart; if fails, briefly toggle visible in current scene to force play
    local ok = pcall(function() obs.obs_source_media_restart(src) end)
    if not ok then
        local cur = obs.obs_frontend_get_current_scene()
        if cur then
            local scene = obs.obs_scene_from_source(cur)
            if scene then
                local dup = obs.obs_scene_add(scene, src)
                if dup then
                    obs.obs_sceneitem_set_visible(dup, false)
                    obs.timer_add(function() obs.obs_sceneitem_set_visible(dup, true) end, 10)
                    obs.timer_add(function()
                        obs.obs_sceneitem_remove(dup)
                    end, 2000)
                end
            end
            obs.obs_source_release(cur)
        end
    end
end

local function play_cue_for_next(next_mode)
    if next_mode == "focus" then play_source(src_focus)
    elseif next_mode == "short_break" then play_source(src_short)
    elseif next_mode == "long_break" then play_source(src_long)
    end
end

local function switch_scene(name)
    if not name or name == "" then return end
    local src = obs.obs_get_source_by_name(name)
    if src then
        obs.obs_frontend_set_current_scene(src)
        obs.obs_source_release(src)
    end
end

-- Core 
local function next_mode_after_current()
    if mode == "focus" then
        local next_s = session_count + 1
        if sessions_before_long > 0 and (next_s % sessions_before_long == 0) then return "long_break" else return "short_break" end
    elseif mode == "short_break" or mode == "long_break" then
        return "focus"
    end
    return nil
end

local function push_display()
    local base = fmt_mmss(time_left)
    if show_mode_label and (mode == "focus" or mode == "short_break" or mode == "long_break") then
        base = current_label() .. " " .. sep_char .. " " .. base
    end
    if session_source_name ~= "" then set_text(session_source_name, session_text()) end
    if show_start_time and session_start_time > 0 and mode ~= "stopped" and mode ~= "paused" then
        local start_txt = string.format("%s %s", start_time_label, fmt_clock(session_start_time))
        if end_time_inline then
            base = base .. " " .. sep_char .. " " .. start_txt
        else
            base = base .. "\n" .. start_txt
        end
    end
    if show_end_time and mode ~= "stopped" and mode ~= "paused" then
        local end_txt = string.format("%s %s", end_time_label, fmt_clock(os.time() + time_left))
        if end_time_inline then
            base = base .. " " .. sep_char .. " " .. end_txt
        else
            base = base .. "\n" .. end_txt
        end
    end
    set_text(timer_source_name, base)
    local cmap = { focus=color_focus, short_break=color_short_break, long_break=color_long_break, paused=color_paused, stopped=color_stopped }
    set_color(timer_source_name, cmap[mode] or 0xFFFFFF)
    if status_source_name ~= "" then
        local m = { focus=focus_message, short_break=short_break_message, long_break=long_break_message, paused=paused_message, stopped=stopped_message }
        set_text(status_source_name, m[mode])
    end
end

local function set_mode(new_mode)
    mode = new_mode
    if mode == "focus" then time_left = math.max(1, focus_minutes) * 60
    elseif mode == "short_break" then time_left = math.max(1, short_break_minutes) * 60
    elseif mode == "long_break" then time_left = math.max(1, long_break_minutes) * 60
    end
    push_display()
end

local function end_of_segment()
    if mode == "focus" then
        session_count = session_count + 1
        if sessions_before_long > 0 and (session_count % sessions_before_long == 0) then
            send_notification("Pomodoro Timer", string.format("Cycle complete! Long break: %d min", long_break_minutes))
            switch_scene(scene_on_break)
            set_mode("long_break")
        else
            send_notification("Pomodoro Timer", string.format("Session %d done! Short break: %d min", session_count, short_break_minutes))
            switch_scene(scene_on_break)
            set_mode("short_break")
        end
    elseif mode == "long_break" then
        if daily_sessions == 0 then session_count = 0 end
        local next_s = session_count + 1
        send_notification("Pomodoro Timer", string.format("Break over — focus time! Session %d starting.", next_s))
        switch_scene(scene_on_focus)
        set_mode("focus")
    else
        send_notification("Pomodoro Timer", string.format("Break over — Session %d starting!", session_count + 1))
        switch_scene(scene_on_focus)
        set_mode("focus")
    end
end

local function tick()
    if not timer_running or mode == "paused" or mode == "stopped" then return end
    if time_left == 1 then
        local nm = next_mode_after_current()
        play_cue_for_next(nm)
    end
    time_left = time_left - 1
    if time_left <= 0 then end_of_segment() else push_display() end
end

-- Controls 
function start_pressed(pressed)
    if not pressed then return end
    timer_running = true
    session_count = 0
    session_start_time = os.time()
    set_mode("focus")
    obs.timer_add(tick, 1000)
end

function pause_pressed(pressed)
    if pressed and timer_running and (mode=="focus" or mode=="short_break" or mode=="long_break") then prev_mode = mode; mode="paused"; push_display() end
end

function resume_pressed(pressed)
    if pressed and mode=="paused" then mode = prev_mode or "focus"; push_display() end
end

function reset_pressed(pressed)
    if pressed then obs.timer_remove(tick); timer_running=false; mode="stopped"; session_count=0; session_start_time=0; time_left=0; push_display() end
end

function skip_pressed(pressed)
    if pressed and timer_running then end_of_segment(); push_display() end
end

-- OBS UI 
function script_properties()
    local p = obs.obs_properties_create()
    obs.obs_properties_add_text(p, "timer_source_name", "Timer Source", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(p, "status_source_name", "Status Source", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(p, "session_source_name", "Session Label Source", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_int(p, "focus_minutes", "Focus (min)", 1, 240, 1)
    obs.obs_properties_add_int(p, "short_break_minutes", "Short Break (min)", 1, 120, 1)
    obs.obs_properties_add_int(p, "long_break_minutes", "Long Break (min)", 1, 240, 1)
    obs.obs_properties_add_int(p, "sessions_before_long", "Sessions before Long Break", 1, 24, 1)
    obs.obs_properties_add_int(p, "daily_sessions", "Daily session goal (0 = off)", 0, 99, 1)

    obs.obs_properties_add_bool(p, "show_mode_label", "Show mode label")
    obs.obs_properties_add_bool(p, "show_session_counter", "Show session counter")
    obs.obs_properties_add_text(p, "session_label", "Session Label", obs.OBS_TEXT_DEFAULT)

    obs.obs_properties_add_bool(p, "show_start_time", "Show start time")
    obs.obs_properties_add_text(p, "start_time_label", "Start time label", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_bool(p, "show_end_time", "Show end time")
    obs.obs_properties_add_bool(p, "end_time_inline", "End time inline")
    obs.obs_properties_add_text(p, "end_time_label", "End time label", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(p, "sep_char", "Separator", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_bool(p, "use_24h", "Use 24h clock")

    obs.obs_properties_add_bool(p, "enable_notifications", "Enable desktop notifications")

    obs.obs_properties_add_bool(p, "enable_sounds", "Enable Sounds")
    obs.obs_properties_add_path(p, "sound_focus_file", "Sound: Focus", obs.OBS_PATH_FILE, "*.mp3;*.wav", nil)
    obs.obs_properties_add_path(p, "sound_short_file", "Sound: Short Break", obs.OBS_PATH_FILE, "*.mp3;*.wav", nil)
    obs.obs_properties_add_path(p, "sound_long_file",  "Sound: Long Break",  obs.OBS_PATH_FILE, "*.mp3;*.wav", nil)

    obs.obs_properties_add_color(p, "color_focus", "Color: Focus")
    obs.obs_properties_add_color(p, "color_short_break", "Color: Short Break")
    obs.obs_properties_add_color(p, "color_long_break", "Color: Long Break")
    obs.obs_properties_add_color(p, "color_paused", "Color: Paused")
    obs.obs_properties_add_color(p, "color_stopped", "Color: Stopped")

    obs.obs_properties_add_text(p, "auto_scene_name", "Auto-start on Scene", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(p, "scene_on_break", "Switch scene on Break", obs.OBS_TEXT_DEFAULT)
    obs.obs_properties_add_text(p, "scene_on_focus", "Switch scene on Focus", obs.OBS_TEXT_DEFAULT)

    obs.obs_properties_add_button(p, "btn_start", "▶ Start", start_pressed)
    obs.obs_properties_add_button(p, "btn_pause", "⏸ Pause", pause_pressed)
    obs.obs_properties_add_button(p, "btn_resume", "⏵ Resume", resume_pressed)
    obs.obs_properties_add_button(p, "btn_reset", "⟲ Reset", reset_pressed)
    obs.obs_properties_add_button(p, "btn_skip",  "⤼ Skip",  skip_pressed)
    return p
end

function script_update(s)
    timer_source_name    = obs.obs_data_get_string(s, "timer_source_name")
    status_source_name   = obs.obs_data_get_string(s, "status_source_name")
    session_source_name  = obs.obs_data_get_string(s, "session_source_name")

    focus_minutes = math.max(1, obs.obs_data_get_int(s, "focus_minutes"))
    short_break_minutes = math.max(1, obs.obs_data_get_int(s, "short_break_minutes"))
    long_break_minutes  = math.max(1, obs.obs_data_get_int(s, "long_break_minutes"))
    sessions_before_long= math.max(1, obs.obs_data_get_int(s, "sessions_before_long"))
    daily_sessions      = math.max(0, obs.obs_data_get_int(s, "daily_sessions"))

    show_mode_label = obs.obs_data_get_bool(s, "show_mode_label")
    show_session_counter = obs.obs_data_get_bool(s, "show_session_counter")
    session_label = obs.obs_data_get_string(s, "session_label")

    show_start_time = obs.obs_data_get_bool(s, "show_start_time")
    start_time_label = obs.obs_data_get_string(s, "start_time_label")
    show_end_time = obs.obs_data_get_bool(s, "show_end_time")
    end_time_inline = obs.obs_data_get_bool(s, "end_time_inline")
    end_time_label = obs.obs_data_get_string(s, "end_time_label")
    sep_char = obs.obs_data_get_string(s, "sep_char"); if sep_char == "" then sep_char = "•" end
    use_24h = obs.obs_data_get_bool(s, "use_24h")

    enable_notifications = obs.obs_data_get_bool(s, "enable_notifications")

    enable_sounds = obs.obs_data_get_bool(s, "enable_sounds")
    sound_focus_file = obs.obs_data_get_string(s, "sound_focus_file")
    sound_short_file = obs.obs_data_get_string(s, "sound_short_file")
    sound_long_file  = obs.obs_data_get_string(s, "sound_long_file")

    color_focus = obs.obs_data_get_int(s, "color_focus")
    color_short_break = obs.obs_data_get_int(s, "color_short_break")
    color_long_break  = obs.obs_data_get_int(s, "color_long_break")
    color_paused = obs.obs_data_get_int(s, "color_paused")
    color_stopped= obs.obs_data_get_int(s, "color_stopped")

    auto_scene_name = obs.obs_data_get_string(s, "auto_scene_name")
    scene_on_break  = obs.obs_data_get_string(s, "scene_on_break")
    scene_on_focus  = obs.obs_data_get_string(s, "scene_on_focus")

    rebuild_sound_sources()
    push_display()
end

-- Hotkeys 
local function hk_load(settings, id, name)
    local arr = obs.obs_data_get_array(settings, name)
    obs.obs_hotkey_load(id, arr)
    obs.obs_data_array_release(arr)
end

local function hk_save(settings, id, name)
    local arr = obs.obs_hotkey_save(id)
    obs.obs_data_set_array(settings, name, arr)
    obs.obs_data_array_release(arr)
end

function script_load(settings)
    hk_start = obs.obs_hotkey_register_frontend("pomo_start", "Pomodoro Start", function(pressed) if pressed then start_pressed(true) end end)
    hk_pause = obs.obs_hotkey_register_frontend("pomo_pause", "Pomodoro Pause", function(pressed) if pressed then pause_pressed(true) end end)
    hk_resume= obs.obs_hotkey_register_frontend("pomo_resume","Pomodoro Resume",function(pressed) if pressed then resume_pressed(true) end end)
    hk_reset = obs.obs_hotkey_register_frontend("pomo_reset", "Pomodoro Reset", function(pressed) if pressed then reset_pressed(true) end end)
    hk_skip  = obs.obs_hotkey_register_frontend("pomo_skip",  "Pomodoro Skip",  function(pressed) if pressed then skip_pressed(true)  end end)

    hk_load(settings, hk_start, "pomo_start")
    hk_load(settings, hk_pause, "pomo_pause")
    hk_load(settings, hk_resume,"pomo_resume")
    hk_load(settings, hk_reset, "pomo_reset")
    hk_load(settings, hk_skip,  "pomo_skip")

    obs.obs_frontend_add_event_callback(function(ev)
        if ev == obs.OBS_FRONTEND_EVENT_SCENE_CHANGED and auto_scene_name ~= "" then
            local cur = obs.obs_frontend_get_current_scene()
            if cur then
                local nm = obs.obs_source_get_name(cur)
                if nm == auto_scene_name and not timer_running then start_pressed(true) end
                obs.obs_source_release(cur)
            end
        end
    end)
end

function script_save(settings)
    hk_save(settings, hk_start, "pomo_start")
    hk_save(settings, hk_pause, "pomo_pause")
    hk_save(settings, hk_resume,"pomo_resume")
    hk_save(settings, hk_reset, "pomo_reset")
    hk_save(settings, hk_skip,  "pomo_skip")
end

function script_unload()
    release_sound_sources()
end
