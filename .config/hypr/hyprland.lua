local mod = "SUPER"

local terminal = "kitty --single-instance"
-- The Shift form of the Return bind opens the terminal as a FLOATING window.
-- kitty is told its own app_id at launch (`--class` sets the Wayland app_id, so
-- the kitty-float rule matches exactly the Shift-launched process).
local terminalFloat = "kitty --single-instance --instance-group=float --class=kitty-float"
local mainBrowser = "firefox"
local altBrowser = "chromium"
local musicApp = "youtube-music"

local volumeStep = "5%"
local brightnessStep = "5%"

-- GPU-wake pins (RTX 4060 Max-Q is runtime-suspended; see the AGS unit
-- templates for the full rationale). Session-wide so keybind/exec_cmd
-- launched apps (notes, Electron, …) never wake the dGPU by probing the
-- NVIDIA Vulkan ICD at startup. The launcher's prime-run button clears both
-- pins for explicit NVIDIA launches. Applies to processes spawned after
-- this config loads; AGS units pin themselves regardless of session env.
hl.env("VK_ICD_FILENAMES", "/usr/share/vulkan/icd.d/radeon_icd.json")
hl.env("__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/50_mesa.json")

hl.config({
    cursor = {
        -- Hyprland 0.56 defaults cursor:hide_on_touch to TRUE. This machine is a
        -- touchscreen convertible: folding the lid puts libinput into tablet
        -- mode, which suspends the touchpad, so touch is the only input left.
        -- The first touch then hides the pointer, and ONLY pointer motion
        -- clears that flag (InputManager clears it in onMouseMoved/onMouseWarp)
        -- — impossible while the touchpad is suspended, so the pointer stays
        -- invisible for the whole folded session, including across a resume.
        -- The hide policy is therefore pinned here instead of inherited from a
        -- default; the greeter compositor carries the same pin.
        hide_on_touch = false,
        hide_on_tablet = false,
        hide_on_key_press = false,
        inactive_timeout = 0,
        no_hardware_cursors = false
    },
    general = {
        gaps_out = 10,
        gaps_in = 4,
        border_size = 1,
        col = {
            active_border   = "rgba(ccccccff)",
            inactive_border = "rgba(00000000)",
        },
    },
    decoration = {
        rounding = 12,
        shadow = {
            enabled = false,
        },
        blur = {
            enabled = true,
            size = 4,
            passes = 2,
            new_optimizations = true,
        }
    },
    input = {
        accel_profile = "flat",
        touchpad = {
            tap_to_click = false,
            natural_scroll = true
        }
    },
    -- Tablet/touch mode: swipe from the touchscreen edge to move through workspaces
    gestures = {
        workspace_swipe_touch = true,
    },
    -- Route Hyprland's startup/banner log to $XDG_RUNTIME_DIR/hypr/.../hyprland.log
    -- instead of /dev/tty1 (post-login tty1 log spam).
    debug = {
        enable_stdout_logs = false,
    },
    misc = {
        -- "Application Not Responding" dialog: Hyprland draws it itself (no
        -- hook, no per-window rule upstream). Default 5 missed pings fires on
        -- apps that are merely busy (VS Code during heavy work). 10 keeps the
        -- Terminate/Wait choice for real hangs without the false positives.
        anr_missed_pings = 10,
    },
})

hl.on("hyprland.start", function()
    -- awww (swww successor) wallpaper daemon — displays ~/wallpapers (synced
    -- on demand with Proton Drive /my-files/Wallpapers via ~/.local/bin/
    -- wallpapers-sync pull|push; wallpapers-apply.service applies the
    -- greeter's wallpaper at login and wallpaper-cycle.timer rotates it every
    -- 10 min via `wallpapers-sync apply`). systemd user service
    -- (awww-daemon.service); started FIRST so the wallpaper paints as early
    -- as possible after the greeter handoff (belt-and-suspenders alongside
    -- the graphical-session target).
    hl.exec_cmd("systemctl --user start awww-daemon")
    -- Apply the SAME wallpaper the greeter showed, instantly, as early as
    -- possible (avoids the near-black default background flash between DRM
    -- takeover and the wallpaper layer mapping).
    hl.exec_cmd("sh -c '$HOME/.local/bin/wallpapers-sync apply-greeter'")
    -- The shell (tinshell-shell.service) — ALL apps in ONE instance (bus
    -- io.Astal.shell): the five surfaces (dock, launcher, notifications,
    -- keyboard, clipboard) + promptd + portal + polkit + the on-demand
    -- apps (notes, files, annotate, media). Belt-and-suspenders autostart
    -- The per-app units are DEV mode ONLY — never start them here,
    -- or a stray island runs beside the shell. The notifications surface is
    -- the shell's — the daemon claims org.freedesktop.Notifications, so the
    -- shell is its only owner, and the notifications island is DEV-only and
    -- never autostarted.
    -- Auto-rotate: rotate eDP-1 + touch input when in tablet mode
    -- (auto-rotate.service — accelerometer orientation via iio-sensor-proxy
    -- + the SW_TABLET_MODE switch; applies rotation through hyprctl eval).
    -- Rotation is only decided while the lid is open and no sleep cycle is in
    -- flight; a closed lid or an in-flight suspend holds transform 0.
    hl.exec_cmd("systemctl --user start auto-rotate")
    -- hyprgrass loads after config parse (the `plugin =` keyword is gone in
    -- 0.56) — hyprgrass-load.sh runtime-loads it and applies its settings +
    -- gesture binds via hyprctl eval.
    hl.exec_cmd("sh -c '$HOME/.config/hypr/hyprgrass-load.sh'")
    -- Idle/lock daemon through its systemd unit (NOT a bare exec — hypridle
    -- has no config hot-reload, and as an unsupervised process its errors
    -- (e.g. a failing lock_cmd) vanish into the Hyprland log. The unit gives
    -- journalctl --user -u hypridle + Restart=on-failure. graphical-session
    -- .target is inactive here, so the WantedBy= wiring needs this explicit
    -- start (same as the shell).
    hl.exec_cmd("systemctl --user start hypridle")
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
end)

hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal))
-- SUPER+SHIFT+Return: the same terminal as a floating window. The float kitty
-- gets its own instance group, so a repeated press opens another window in the
-- FLOAT process — the base bind's --single-instance group would hand the window
-- to the tiled process, whose app_id is the tiled one.
hl.bind(mod .. " + SHIFT + Return", hl.dsp.exec_cmd(terminalFloat))
-- Launcher (AGS). ensure-launcher-toggle.sh is NOT in PATH, so it needs an
-- absolute path (the ~/.local/bin absolute-path rule applies to any
-- out-of-PATH tool). It is a thin wrapper over the router (tinshell-route.sh
-- launcher toggle): shell first, dev launcher island second, cold-start +
-- servable-wait when neither — a press in the first ~1s after login lands
-- instead of silently dying.
hl.bind(mod .. " + Space", hl.dsp.exec_cmd("/home/tinoy/dev/tinshell/common/shell/ensure-launcher-toggle.sh"))
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + F", hl.dsp.exec_cmd(mainBrowser))
hl.bind(mod .. " + G", hl.dsp.exec_cmd(altBrowser))
hl.bind(mod .. " + Y", hl.dsp.exec_cmd(musicApp))
-- Notifications moved to mod+TAB (mod+N is the notes app's "new note" key).
-- The shell owns the notifications surface — toggling the centre goes
-- through the router: `tinshell-route.sh notifications toggle-centre`.
hl.bind(mod .. " + TAB", hl.dsp.exec_cmd("/home/tinoy/dev/tinshell/common/shell/tinshell-route.sh notifications toggle-centre"))
-- Clipboard manager picker (AGS surface) — mod+SHIFT+V (mod+V is the float
-- toggle, so the picker takes SHIFT+V). Routed the same as notifications:
-- `tinshell-route.sh clipboard toggle` (shell first, island second).
hl.bind(mod .. " + SHIFT + V", hl.dsp.exec_cmd("/home/tinoy/dev/tinshell/common/shell/tinshell-route.sh clipboard toggle"))
-- AGS notes (on-demand app, NOT a systemd unit — see notes/AGENTS.md).
-- ensure-new.sh: instant bus request when the app is up, cold start otherwise.
-- N = a guaranteed fresh EMPTY note (`notes fresh`), never the closed-note
-- history; SHIFT+N = the app's `new` action — reopen the most recently closed
-- note, else a fresh blank one.
hl.bind(mod .. " + N", hl.dsp.exec_cmd("/home/tinoy/dev/tinshell/apps/notes/ensure-new.sh fresh"))
hl.bind(mod .. " + SHIFT + N", hl.dsp.exec_cmd("/home/tinoy/dev/tinshell/apps/notes/ensure-new.sh new"))
-- AGS launcher emoji mode (mod+. — the conventional emoji slot). Wrapper over
-- the router (tinshell-route.sh launcher emoji): shell first, dev launcher island
-- second, cold-start when neither. The same key opens the launcher in emoji
-- mode, closes it when it is already in emoji mode, and switches it into emoji
-- mode otherwise (never closes) — see launcher/AGENTS.md.
-- Absolute path: keybind exec has no ~/.local/bin in PATH (the out-of-PATH
-- absolute-path rule).
hl.bind(mod .. " + period", hl.dsp.exec_cmd("/home/tinoy/dev/tinshell/common/shell/ensure-launcher-emoji.sh"))

-- The shell runs as a systemd user service (tinshell-shell.service, Restart=on-
-- failure) so it auto-relaunches after any crash. Process control goes
-- through systemctl: restart = systemctl --user restart tinshell-shell. systemd
-- SIGTERMs the old instance (the app's shutdown handler finalizes any
-- in-flight recording), then starts the new one; the service's ExecStartPre
-- (tinshell-bus-wait.sh shell) absorbs the bus-name release, so no manual sleep is
-- needed. shell registers its own bus (io.Astal.shell, instance "shell"); it
-- does NOT occupy the bare default "ags" name (multi-app home). The
-- per-app dev units (promptd/portal/polkit) are NEVER autostarted.
hl.bind(mod .. " + SHIFT + B", hl.dsp.exec_cmd("/home/tinoy/dev/tinshell/common/shell/restart-shell.sh"))

-- Frosted glass blur for AGS dock + applet popups
hl.layer_rule({ match = { namespace = "dock-.*" }, blur = true, ignore_alpha = 0.05 })
-- No compositor animation on dock layer surfaces (applet pill + popups)
hl.layer_rule({ match = { namespace = "dock-.*" }, no_anim = true })
-- Frosted glass blur for the AGS launcher (namespace "launcher", same frost
-- parameters as the dock).
hl.layer_rule({ match = { namespace = "launcher" }, blur = true, ignore_alpha = 0.2 })
-- Frosted glass blur for AGS promptd (namespace "promptd", same frost).
hl.layer_rule({ match = { namespace = "promptd" }, blur = true, ignore_alpha = 0.2 })
-- Frosted glass blur for the AGS session-transition overlay (namespace
-- "session-overlay": the full-screen "Locking..." / "Logging out..." scrim the
-- shell raises over a lock/logout handover), with no compositor animation so the
-- scrim is on screen at once instead of sliding in over the beat it covers.
hl.layer_rule({ match = { namespace = "session-overlay" }, blur = true, ignore_alpha = 0.2, no_anim = true })
-- Float yad dialogs (fallback windows for promptd clients) instead of tiling.
hl.window_rule({
    name  = "float-yad",
    match = { class = "^(yad)$" },
    float = true,
})
-- Floating windows keep border + rounding even when the w[tv1] smart-gaps
-- rule fires (fullscreen + floating on the same workspace): re-assert
-- decorations. rounding = 12 (the global value) so floats match tiled; placed
-- BEFORE notes/files so their rounding = 14 still wins (last match wins).
hl.window_rule({
    name     = "float-decorations",
    match    = { float = true },
    rounding = 12,
    decorate = true,
    border_size = 1,
})
-- SUPER+SHIFT+Return's floating terminal. kitty is told its own Wayland app_id
-- at launch, so this rule matches the Shift-launched terminal ONLY — a plain
-- SUPER+Return keeps tiling. Size is the floating footprint (1200x760), applied
-- at map, centred; the class is matched exactly, so a user-renamed kitty is not
-- affected.
hl.window_rule({
    name     = "kitty-float",
    match    = { class = "^(kitty-float)$" },
    float    = true,
    rounding = 12,
    size     = { 1200, 760 },
    center   = true,
    decorate = true,
    border_size = 1,
})
-- VS Code (class "code") frosted translucency is app-side: Vibrancy Continued
-- patches the Electron window to transparent:true + frameless and paints
-- translucent chrome over opaque glyphs; the GLOBAL blur above frosts the
-- backdrop through the window's own alpha. NO compositor opacity rule here —
-- a <1 multiplier would dim VSCode's glyphs, which is why the whole-window
-- opacity approach was rejected.

-- AGS notes (io.Astal.notes): floating desktop notes. Frost comes from the
-- GLOBAL blur setting + the translucent window (the Lua window_rule API has
-- no per-window blur/ignorealpha keys — those are layer rules only).
--
-- SIZE is pinned here ON PURPOSE: Hyprland sends its own
-- half-monitor default configure to fresh floating XDG windows whose first
-- commit loses the startup race, and GTK4 obeys the nonzero configure — the
-- app's gtk_window_set_default_size (config window.width/height) only
-- wins when the commit lands first, so new notes flapped between 250x250
-- and 720x900 (half the 1440x900@2x monitor in PHYSICAL px applied as
-- logical). GTK4 has no post-map resize API for XDG windows, so the rule is
-- the deterministic fix. The value is READ from the app's config so the
-- config files stay the source of truth; changes apply on hyprland reload.
local function configWindowSize(app, fallbackW, fallbackH)
    local paths = {
        os.getenv("HOME") .. "/.config/tinshell/" .. app .. ".json",
        os.getenv("HOME") .. "/dev/tinshell/apps/" .. app .. "/config.defaults.json",
    }
    for _, p in ipairs(paths) do
        local f = io.open(p, "r")
        if f then
            local s = f:read("*a")
            f:close()
            local w = tonumber(s:match('"width"%s*:%s*(%d+)')) or tonumber(s:match('"defaultWidth"%s*:%s*(%d+)'))
            local h = tonumber(s:match('"height"%s*:%s*(%d+)')) or tonumber(s:match('"defaultHeight"%s*:%s*(%d+)'))
            if w and h then return w, h end
        end
    end
    return fallbackW, fallbackH
end
local notesW, notesH = configWindowSize("notes", 250, 250)
local filesW, filesH = configWindowSize("files", 620, 390)
local mediaW, mediaH = configWindowSize("media", 670, 380)
local portalW, portalH = configWindowSize("portal", 630, 420)
local annotateW, annotateH = configWindowSize("annotate", 630, 450)

hl.window_rule({
    name     = "notes-float",
    match    = { class = "^(io\\.Astal\\.notes)$" },
    float    = true,
    rounding = 14,
    size     = { notesW, notesH },
    -- Re-assert decorations: the smart-gaps workspace rule (w[tv1]) sets
    -- no_border + decorate=false on immersive workspaces (single tiled or
    -- maximized window) — the note floats on those. decorate=true covers it.
    decorate = true,
    border_size = 1,
    -- `size` above pins the map size (see the Hyprland float-race comment
    -- above); user manual resize still works — the rule applies only at map.
})
-- AGS files (io.Astal.files): floating file browser. Same frosted-card
-- treatment as notes — float + rounding from GLOBAL blur on the translucent
-- window (NO per-window blur key in the window_rule API; no layerrule — it
-- is an XDG window, not a layer surface). `size` pins the map size from the
-- app config (880x560) — without it the startup race gives the browser
-- Hyprland's half-monitor configure (720x900, or 710x440 after a resize
-- race) instead of its configured size.
hl.window_rule({
    name     = "files-float",
    match    = { class = "^(io\\.Astal\\.files)$" },
    float    = true,
    rounding = 14,
    size     = { filesW, filesH },
    decorate = true,
    border_size = 1,
})
-- AGS media (io.Astal.media): the window owns the media output (video
-- renders inside it via GStreamer gtk4paintablesink) and the inline still
-- viewer. Same frosted-card treatment as files — float + rounding from
-- GLOBAL blur on the translucent window (NO per-window blur key; no
-- layerrule — it is an XDG window, not a layer surface). `size` pins the map
-- size from the app config (670x380) — the startup-race fix, same as
-- files-float.
hl.window_rule({
    name     = "media-float",
    match    = { class = "^(io\\.Astal\\.media)$" },
    float    = true,
    rounding = 14,
    size     = { mediaW, mediaH },
    decorate = true,
    border_size = 1,
})
-- Media multi-instance cascade: Hyprland overrides app sizes
-- for floats (GTK windows map ~720x900 regardless of config) and centers
-- them, so consecutive media windows stack invisibly. GTK4 has no position
-- API — offset each extra instance via title-matched `move` rules. window.tsx
-- titles the nth window "media-N". 40px down-right per instance.
hl.window_rule({ name = "media-2", match = { title = "^media-2$" }, move = { 400, 40 } })
hl.window_rule({ name = "media-3", match = { title = "^media-3$" }, move = { 440, 80 } })
hl.window_rule({ name = "media-4", match = { title = "^media-4$" }, move = { 480, 120 } })
hl.window_rule({ name = "media-5", match = { title = "^media-5$" }, move = { 520, 160 } })
hl.window_rule({ name = "media-6", match = { title = "^media-6$" }, move = { 560, 200 } })
-- AGS portal (io.Astal.portal): xdg-desktop-portal FileChooser backend dialog.
-- Same frosted-card treatment as files/media — float + rounding from GLOBAL
-- blur on the translucent window (NO per-window blur key; no layerrule — it
-- is an XDG window, not a layer surface). `size` pins the map size from the
-- app config (defaultWidth/defaultHeight = 900x600) — the startup-race fix,
-- same as files-float.
hl.window_rule({
    name     = "portal-float",
    match    = { class = "^(io\\.Astal\\.portal)$" },
    float    = true,
    rounding = 14,
    size     = { portalW, portalH },
    decorate = true,
    border_size = 1,
})
-- AGS annotate (io.Astal.annotate): screenshot annotation editor.
-- Same frosted-card treatment as files/portal — float + rounding from GLOBAL
-- blur on the translucent window (NO per-window blur key; no layerrule — it
-- is an XDG window, not a layer surface). `size` pins the map size from the
-- app config (defaultWidth/defaultHeight = 630x450) — the startup-race fix,
-- same as files-float. Opened from the ScreenGrab notification action
-- (annotate/ensure-open.sh) — no keybind.
hl.window_rule({
    name     = "annotate-float",
    match    = { class = "^(io\\.Astal\\.annotate)$" },
    float    = true,
    rounding = 14,
    size     = { annotateW, annotateH },
    decorate = true,
    border_size = 1,
})
-- Frosted glass blur for AGS notifications popups + control center (same frost)
hl.layer_rule({ match = { namespace = "notifications-.*" }, blur = true, ignore_alpha = 0.2 })
hl.layer_rule({ match = { namespace = "dock-pill" }, blur = true, ignore_alpha = 0.05 })
-- Frosted glass blur for the AGS on-screen keyboard (namespace "keyboard-.*",
-- same frost as the other apps). No keybind — touch-first (tablet auto-show,
-- dock applet summon).
hl.layer_rule({ match = { namespace = "keyboard-.*" }, blur = true, ignore_alpha = 0.2 })
-- Frosted glass blur for the AGS clipboard picker (namespace
-- "clipboard-picker", same frost as the launcher).
hl.layer_rule({ match = { namespace = "clipboard-picker" }, blur = true, ignore_alpha = 0.2 })

-- LOCKED media keys: the session lock is an ext-session-lock surface, which
-- takes the seat, and Hyprland's keybind manager then SKIPS every bind without
-- the `locked` flag (the key is delivered to the lock surface instead, which
-- has no use for it). The flag only relaxes that gate — nothing else about the
-- bind changes — so these are the same dispatcher, binary and step as before,
-- and the unlocked behaviour is untouched. Brightness can serve the locked
-- screen because logind authorizes a write from the OWNER of the ACTIVE seat
-- session, and locking does not deactivate the session. The mic-mute and
-- transport binds below stay session-only: they are not wanted on the lock
-- screen.
-- A held adjustment key must keep stepping: `repeating` re-runs the bind while
-- the key is down (the conf-syntax `repeat` flag). The toggles below are NOT
-- repeating — mute flips once per press.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ " .. volumeStep .. "+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ " .. volumeStep .. "-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))

hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))
hl.bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl stop"))

-- Same `locked` gate as the volume binds above: a machine that has just
-- resumed or booted is usually sitting on the lock screen, and the brightness
-- key has to work without unlocking first.
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set " .. brightnessStep .. "+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set " .. brightnessStep .. "-"), { locked = true, repeating = true })

-- Print: region capture through the live AGS instance that hosts the screen
-- grab applet, so the capture runs that applet's own pipeline — storage dir and
-- name template from the config, the frozen frame, the notification carrying the
-- Annotate action, and the clipboard copy. The freeze and the selection live in
-- the dock (apps/dock/screengrab/capture.ts): the notification's action is
-- dispatched in-process, so the capture has to run inside the instance.
-- Absolute path: keybind exec has no ~/.local/bin in PATH.
hl.bind("Print", hl.dsp.exec_cmd("/home/tinoy/dev/tinshell/common/shell/ensure-screengrab.sh"))

hl.bind(mod .. " + Left", hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + Right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + Up", hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + Down", hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }))

hl.bind(mod .. " + SHIFT + Left", hl.dsp.window.move({ direction = "l" }))
hl.bind(mod .. " + SHIFT + Right", hl.dsp.window.move({ direction = "r" }))
hl.bind(mod .. " + SHIFT + Up", hl.dsp.window.move({ direction = "u" }))
hl.bind(mod .. " + SHIFT + Down", hl.dsp.window.move({ direction = "d" }))

-- Generic window move/resize for EVERY window: SUPER+LMB drag = move,
-- SUPER+SHIFT+LMB drag = resize, SUPER+CTRL+arrows = 60px keyboard resize.
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + SHIFT + mouse:272", hl.dsp.window.resize(), { mouse = true })
hl.bind(mod .. " + CTRL + Left",  hl.dsp.window.resize({ x = -60, y = 0, relative = true }))
hl.bind(mod .. " + CTRL + Right", hl.dsp.window.resize({ x = 60,  y = 0, relative = true }))
hl.bind(mod .. " + CTRL + Up",    hl.dsp.window.resize({ x = 0, y = -60, relative = true }))
hl.bind(mod .. " + CTRL + Down",  hl.dsp.window.resize({ x = 0, y = 60,  relative = true }))

-- Smart gaps: zero gaps & no decorations when only one tiled visible window.
-- No floating equivalent: floated windows keep the global rounding (12) +
-- border (1) + active-border color, so they match tiled.
hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0, no_border = true, no_rounding = true, decorate = false })

-- Resize/open animation: subtle spring
hl.curve("subtleSpring", { type = "spring", mass = 1, stiffness = 400, dampening = 25 })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4, spring = "subtleSpring", style = "slide" })
hl.animation({ leaf = "windowsIn",   enabled = true, speed = 4, spring = "subtleSpring", style = "popin 80%" })

-- Workspace transition: slidefade with a light spring bounce
hl.curve("wsSpring", { type = "spring", mass = 1, stiffness = 400, dampening = 30 })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, spring = "wsSpring", style = "slidefade" })

for workspace = 1, 9 do
    hl.bind(mod .. " + " .. workspace, hl.dsp.focus({ workspace = workspace }))
    hl.bind(mod .. " + SHIFT + " .. workspace, hl.dsp.window.move({ workspace = workspace }))
end

-- SUPER+0 = workspace 10 (the workspaces slider applet's 10th step)
hl.bind(mod .. " + 0", hl.dsp.focus({ workspace = 10 }))
hl.bind(mod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))
-- SUPER+- = workspace 11 (the 11th slider step)
hl.bind(mod .. " + MINUS", hl.dsp.focus({ workspace = 11 }))
hl.bind(mod .. " + SHIFT + MINUS", hl.dsp.window.move({ workspace = 11 }))

-- Tablet/tent mode: trackpad 3-finger swipe left/right through workspaces
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
