local mod = "SUPER"

-- The compositor's own colours come from the palette table rendered beside this
-- config, so no colour is written here: a palette change reaches the compositor
-- the next time it reads its configuration.
local palette = require("palette")

local terminal = "kitty --single-instance"
-- `--class` sets the Wayland app_id, so the kitty-float rule matches only the
-- Shift-launched process.
local terminalFloat = "kitty --single-instance --instance-group=float --class=kitty-float"
local mainBrowser = "firefox"
local altBrowser = "chromium"
local musicApp = "youtube-music"

local volumeStep = "5%"
local brightnessStep = "5%"

-- The tinshell tree root, derived from $HOME like the app-config lookups below.
-- Keybind exec has no ~/.local/bin in PATH, so each app command carries its
-- absolute path under that one root; a bind that needs an argument appends it.
local shellDir = os.getenv("HOME") .. "/dev/tinshell"
local launcher = shellDir .. "/common/shell/ensure-launcher-toggle.sh"
local launcherEmoji = shellDir .. "/common/shell/ensure-launcher-emoji.sh"
local clipboard = shellDir .. "/common/shell/tinshell-route.sh clipboard"
local notes = shellDir .. "/apps/notes/ensure-new.sh"
local notifications = shellDir .. "/common/shell/tinshell-route.sh notifications"
local shellRestart = shellDir .. "/common/shell/restart-shell.sh"
local screengrab = shellDir .. "/common/shell/ensure-screengrab.sh"

-- GPU-wake pins: the RTX 4060 Max-Q is runtime-suspended, and session-wide env
-- keeps exec_cmd-spawned apps from waking the dGPU by probing the NVIDIA Vulkan
-- ICD at startup. The launcher's prime-run button unsets both for an NVIDIA launch.
hl.env("VK_ICD_FILENAMES", "/usr/share/vulkan/icd.d/radeon_icd.json")
hl.env("__EGL_VENDOR_LIBRARY_FILENAMES", "/usr/share/glvnd/egl_vendor.d/50_mesa.json")
-- sudo-approve resolves the promptd router from SUDO_APPROVE_ROUTE and has no
-- home-directory default, so without this the approval path refuses by name.
hl.env("SUDO_APPROVE_ROUTE", "/home/tinoy/.local/bin/tinshell-route")

hl.config({
    cursor = {
        -- Hyprland 0.56 defaults this to true, but this machine is a touchscreen
        -- convertible: folded into tablet mode the touchpad is suspended, only
        -- pointer motion would clear the flag, and the pointer would stay hidden
        -- for the whole session. Pinned here; the greeter compositor matches.
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
            active_border   = palette.border_active,
            inactive_border = palette.border_inactive,
        },
    },
    decoration = {
        rounding = 14,
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
    -- Route Hyprland's log to $XDG_RUNTIME_DIR/hypr/.../hyprland.log, not /dev/tty1.
    debug = {
        enable_stdout_logs = false,
    },
    misc = {
        -- ANR dialog: the default 5 missed pings fires on merely-busy apps
        -- (VS Code under load); 10 keeps the Terminate/Wait choice for real hangs.
        anr_missed_pings = 10,
    },
})

hl.on("hyprland.start", function()
    -- awww wallpaper daemon (awww-daemon.service) over ~/wallpapers, which
    -- wallpapers-sync pulls/pushes and wallpaper-cycle.timer rotates; started
    -- first so the wallpaper paints as early as possible after the greeter handoff.
    hl.exec_cmd("systemctl --user start awww-daemon")
    -- The same wallpaper the greeter showed, applied at once to avoid the
    -- near-black flash between DRM takeover and the wallpaper layer mapping.
    hl.exec_cmd("sh -c '$HOME/.local/bin/wallpapers-sync apply-greeter'")
    -- The shell (tinshell-shell.service) is not autostarted from here, and the
    -- per-app dev units never are either: a stray island would run beside it.
    -- Auto-rotate: auto-rotate.service rotates eDP-1 + touch input in tablet mode
    -- (iio-sensor-proxy + the SW_TABLET_MODE switch, applied via hyprctl eval);
    -- a closed lid or an in-flight suspend holds transform 0.
    hl.exec_cmd("systemctl --user start auto-rotate")
    -- hyprgrass: the `plugin =` keyword is gone in 0.56, so hyprgrass-load.sh
    -- runtime-loads the plugin after config parse and applies its settings.
    hl.exec_cmd("sh -c '$HOME/.config/hypr/hyprgrass-load.sh'")
    -- hypridle runs as hypridle.service (journalctl --user -u hypridle,
    -- Restart=on-failure); it has no config hot-reload, and graphical-session
    -- .target is inactive here, so its WantedBy= wiring needs this explicit start.
    hl.exec_cmd("systemctl --user start hypridle")
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
end)

hl.bind(mod .. " + Return", hl.dsp.exec_cmd(terminal))
-- SUPER+SHIFT+Return: floating terminal. Its own instance group keeps repeated
-- presses in the float process, whose app_id the kitty-float rule matches.
hl.bind(mod .. " + SHIFT + Return", hl.dsp.exec_cmd(terminalFloat))
-- Launcher (tinshell): routes launcher toggle to the live instance, cold-starting
-- one when none is up.
hl.bind(mod .. " + Space", hl.dsp.exec_cmd(launcher))
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + F", hl.dsp.exec_cmd(mainBrowser))
hl.bind(mod .. " + G", hl.dsp.exec_cmd(altBrowser))
hl.bind(mod .. " + Y", hl.dsp.exec_cmd(musicApp))
-- Notifications centre on mod+TAB (mod+N is the notes "new note" key), via the router.
hl.bind(mod .. " + TAB", hl.dsp.exec_cmd(notifications .. " toggle-centre"))
-- Clipboard picker (tinshell surface) on mod+SHIFT+V (mod+V is the float toggle), same routing.
hl.bind(mod .. " + SHIFT + V", hl.dsp.exec_cmd(clipboard .. " toggle"))
-- tinshell notes (on-demand, no systemd unit). N opens a fresh EMPTY note (`fresh`);
-- SHIFT+N reopens the most recently closed note, else a fresh blank one.
hl.bind(mod .. " + N", hl.dsp.exec_cmd(notes .. " fresh"))
hl.bind(mod .. " + SHIFT + N", hl.dsp.exec_cmd(notes .. " new"))
-- tinshell launcher emoji mode (mod+.): opens the launcher in emoji mode, closes it
-- when already there, switches it otherwise.
hl.bind(mod .. " + period", hl.dsp.exec_cmd(launcherEmoji))

-- Restart the live shell (shell first, island second). The unit's ExecStartPre
-- (tinshell-bus-wait.sh shell) absorbs the bus-name release, so no manual sleep.
hl.bind(mod .. " + SHIFT + B", hl.dsp.exec_cmd(shellRestart))

-- Re-assert border + rounding on floats so they survive the w[tv1] smart-gaps
-- rule (no_border + decorate=false); kept inline because no surface owns it, and
-- placed before the generated rules just below, whose rounding = 14 wins (last
-- match wins).
hl.window_rule({
    name     = "float-decorations",
    match    = { float = true },
    rounding = 12,
    decorate = true,
    border_size = 1,
})
-- App-owned compositor rules are rendered into a directory beside this config, so
-- a rule belonging to an app travels with that app. Mounted directly after the
-- generic float rule: a window rule's keys apply over every earlier match and the
-- last match wins per key, so the fragments' `rounding = 14` has to out-rank
-- float-decorations' `rounding = 12`. The mount is guarded because a wildcard
-- require matching nothing raises, which would abort the rest of this file.
local configDir = os.getenv("HOME") .. "/.config/hypr"
pcall(require, configDir .. "/rules/*.lua")

-- The Shift-launched terminal only (its own app_id); 1200x760 at map, centred.
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
-- VS Code (class "code") frost is app-side (Vibrancy Continued makes the window
-- transparent + frameless); the global blur frosts through its own alpha. An
-- opacity rule would dim its glyphs, so there is none.

-- LOCKED media keys: the session lock is an ext-session-lock surface and takes
-- the seat, after which Hyprland skips every bind without the `locked` flag (the
-- key goes to the lock surface instead). The flag only relaxes that gate, so the
-- dispatcher and step are unchanged; volume and brightness can serve the lock
-- screen because logind authorizes writes from the owner of the active session.
-- The mic-mute and transport binds below stay session-only on purpose.
-- `repeating` re-runs a held adjustment key; the mute toggles are not repeating.
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ " .. volumeStep .. "+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ " .. volumeStep .. "-"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"))

hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))
hl.bind("XF86AudioStop", hl.dsp.exec_cmd("playerctl stop"))

-- Same `locked` gate as the volume binds: brightness works without unlocking first.
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set " .. brightnessStep .. "+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set " .. brightnessStep .. "-"), { locked = true, repeating = true })

-- Print: region capture inside the live instance that hosts the screengrab applet
-- (its notification action is dispatched in-process, so the capture must run there).
hl.bind("Print", hl.dsp.exec_cmd(screengrab))

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

-- Smart gaps: zero gaps + no decorations while a single tiled window is visible;
-- floated windows keep the global rounding (12) + border, so they still match tiled.
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
