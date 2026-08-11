hl.monitor({
	output = "HDMI-A-1",
	mode = "2560x1440@144.00Hz",
	position = "0x0",
	scale = 1,
})

hl.monitor({
	output = "eDP-1",
	mode = "preferred",
	position = "auto",
	scale = 1,
})

for i = 1, 5 do
	hl.workspace_rule({ workspace = tostring(i), monitor = "HDMI-A-1" })
end

for i = 6, 10 do
	hl.workspace_rule({ workspace = tostring(i), monitor = "eDP-1" })
end

local terminal    = "kitty"
local fileManager = "nautilus"
local menu        = "qs ipc call launcher toggle"
local browser     = "firefox"

hl.on("hyprland.start", function()
	hl.exec_cmd("quickshell")
	hl.exec_cmd("hyprpaper")
	hl.exec_cmd("cliphist wipe")
	hl.exec_cmd("rm -rf \"" .. os.getenv("XDG_RUNTIME_DIR") .. "/quickshell-clip-thumbs/*\"")
	hl.exec_cmd("wl-paste --watch cliphist store")
end)

hl.env("XCURSOR_SIZE", "20")
hl.env("HYPRCURSOR_SIZE", "20")
hl.env("XCURSOR_THEME", "macOS")
hl.env("HYPRCURSOR_THEME", "macOS")

hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")

hl.on("hyprland.start", function()
	hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
	hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'catppuccin-mocha-mauve-standard'")
	hl.exec_cmd("gsettings set org.gnome.desktop.interface icon-theme 'Adwaita'")
	hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme 'macOS'")
	hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size 20")
end)

hl.env("HYPRSHOT_DIR", "/home/proteus/pictures/screenshots")

hl.config({
	general = {
		gaps_in          = 6,
		gaps_out         = 10,

		border_size      = 2,

		col              = {
			active_border = "rgba(89dcebee)",
			inactive_border = "rgba(7f849cee)",
		},

		resize_on_border = false,
		allow_tearing    = false,

		layout           = "scrolling",
	},

	decoration = {
		rounding         = 10,
		rounding_power   = 10,

		active_opacity   = 1,
		inactive_opacity = 1,

		shadow           = {
			enabled      = true,
			range        = 4,
			render_power = 3,
			color        = 0xee1a1a1a,
		},

		blur             = {
			enabled  = true,
			size     = 3,
			passes   = 1,
			vibrancy = 0.1696,
		},
	},

	animations = {
		enabled = true,
	},
})

hl.config({
	cursor = {
	}
})

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })
hl.curve("easy", { type = "spring", mass = 1, stiffness = 71.2633, dampening = 15.8273644 })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, spring = "easy" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 1, bezier = "default" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.21, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1.94, bezier = "almostLinear", style = "fade" })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 7, bezier = "quick" })

hl.config({
	dwindle = {
		preserve_split = true,
	},
})

hl.config({
	master = {
		new_status = "master",
	},
})

hl.config({
	scrolling = {
		fullscreen_on_one_column = true,
	},
})

hl.config({
	misc = {
		force_default_wallpaper = -1,
		disable_hyprland_logo   = false,
	},
})

hl.config({
	input = {
		kb_layout    = "us",
		kb_variant   = "",
		kb_model     = "",
		kb_options   = "",
		kb_rules     = "",

		follow_mouse = 1,
		sensitivity  = 0,

		touchpad     = {
			natural_scroll = false,
		},
	},
})

hl.gesture({
	fingers = 3,
	direction = "horizontal",
	action = "workspace"
})

hl.device({
	name        = "epic-mouse-v1",
	sensitivity = -0.5,
})

local mainMod = "SUPER"

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
local closeWindowBind = hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + ESCAPE",
	hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + Z", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SUPER_L", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("qs ipc call clipboard toggle"))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + N", hl.dsp.exec_cmd("qs ipc call notifications toggle"))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("qs ipc call powermenu toggle"))

hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + COMMA", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + PERIOD", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.layout("swapcol l"))
hl.bind(mainMod .. " + SHIFT + COMMA", hl.dsp.layout("swapcol l"))
hl.bind(mainMod .. " + SHIFT + PERIOD", hl.dsp.layout("swapcol r"))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.layout("swapcol r"))

hl.bind("SUPER + SLASH", function()
	local monitor = hl.get_active_monitor()
	local window = hl.get_active_window()

	if not monitor or not window or not window.size then return end

	local window_width = window.size.x
	local monitor_width = monitor.width

	local ratio = window_width / monitor_width

	if ratio > 0.90 then
		hl.dispatch(hl.dsp.layout("colresize 0.5"))
	else
		hl.dispatch(hl.dsp.layout("colresize 1.0"))
	end
end)

hl.bind(mainMod .. " + W", hl.dsp.exec_cmd(browser))

hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("pidof hyprlock || hyprlock"))
hl.bind("CTRL + ALT + DELETE", hl.dsp.exec_cmd("wlogout"))

hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("hyprctl reload"))

hl.bind("SHIFT + PRINT", hl.dsp.exec_cmd("hyprshot -zm region"))
hl.bind("PRINT", hl.dsp.exec_cmd("hyprshot -m output"))

for i = 1, 10 do
	local key = i % 10 -- 10 maps to key 0
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
	{ locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
	{ locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
	{ locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
	{ locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

local suppressMaximizeRule = hl.window_rule({
	name           = "suppress-maximize-events",
	match          = { class = ".*" },
	suppress_event = "maximize",
})

hl.window_rule({
	name     = "fix-xwayland-drags",
	match    = {
		class      = "^$",
		title      = "^$",
		xwayland   = true,
		float      = true,
		fullscreen = false,
		pin        = false,
	},
	no_focus = true,
})

hl.window_rule({
	match = { workspace = "w[tv1]s[true]" },
	opacity = "0.98 override 0.98 override"
})

hl.window_rule({
	name  = "move-hyprland-run",
	match = { class = "hyprland-run" },
	move  = "20 monitor_h-120",
	float = true,
})

hl.layer_rule({
	match = { namespace = "vicinae" },
	name = "vicinae-blur",
	blur = true,
	ignore_alpha = 0,
})

hl.layer_rule({
	match = { namespace = "vicinae" },
	name = "vicinae-no-animation",
	no_anim = true,
})

hl.config({
	xwayland = {
		force_zero_scaling = true,
	}
})
