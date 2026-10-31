import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts

import "config.js" as Config

Scope {
	id: root

	property bool panelOpen: false

	IpcHandler {
		target: "controlcenter"

		function toggle(): void {
			if (!root.panelOpen) root.closeOtherPanels()
			root.panelOpen = !root.panelOpen
		}

		function show(): void {
			root.closeOtherPanels()
			root.panelOpen = true
		}

		function hide(): void {
			root.panelOpen = false
		}

		function setVolume(percent: string): void {
			root.setOutputVolume(parseFloat(percent))
		}

		function setBrightness(percent: string): void {
			root.setBrightnessPercent(parseFloat(percent))
		}
	}

	function ipcCall(target, fn) {
		Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", target, fn])
	}

	function closeOtherPanels() {
		root.ipcCall("launcher", "hide")
		root.ipcCall("clipboard", "hide")
		root.ipcCall("notifications", "hide")
		root.ipcCall("powermenu", "hide")
	}

	function usageColor(value) {
		if (value >= 85) return Config.colors.bad
		if (value >= 60) return Config.colors.warn
		return Config.colors.accent
	}

	// ---------------------------------------------------------------- audio

	readonly property var sink: Pipewire.defaultAudioSink
	readonly property var source: Pipewire.defaultAudioSource
	readonly property var sinkAudio: (sink && sink.ready) ? sink.audio : null
	readonly property var sourceAudio: (source && source.ready) ? source.audio : null

	property int outputVolume: 0
	property bool outputMuted: false
	property int micVolume: 0
	property bool micMuted: false

	PwObjectTracker {
		objects: {
			const arr = []
			if (root.sink) arr.push(root.sink)
			if (root.source) arr.push(root.source)
			return arr
		}
	}

	onSinkAudioChanged: root.syncOutput()
	onSourceAudioChanged: root.syncMic()

	function syncOutput() {
		if (!root.sinkAudio) return
		root.outputVolume = Math.round(root.sinkAudio.volume * 100)
		root.outputMuted = root.sinkAudio.muted
	}

	function syncMic() {
		if (!root.sourceAudio) return
		root.micVolume = Math.round(root.sourceAudio.volume * 100)
		root.micMuted = root.sourceAudio.muted
	}

	function setOutputVolume(value) {
		const clamped = Math.max(0, Math.min(100, Math.round(value)))
		root.outputVolume = clamped
		if (root.sinkAudio) {
			root.sinkAudio.volume = clamped / 100
			if (clamped > 0 && root.sinkAudio.muted) root.sinkAudio.muted = false
		}
	}

	function setMicVolume(value) {
		const clamped = Math.max(0, Math.min(100, Math.round(value)))
		root.micVolume = clamped
		if (root.sourceAudio) {
			root.sourceAudio.volume = clamped / 100
			if (clamped > 0 && root.sourceAudio.muted) root.sourceAudio.muted = false
		}
	}

	function toggleOutputMute() {
		root.outputMuted = !root.outputMuted
		if (root.sinkAudio) root.sinkAudio.muted = root.outputMuted
	}

	function toggleMicMute() {
		root.micMuted = !root.micMuted
		if (root.sourceAudio) root.sourceAudio.muted = root.micMuted
	}

	Connections {
		target: root.sinkAudio
		function onVolumesChanged() { root.syncOutput() }
		function onMutedChanged() { root.syncOutput() }
	}

	Connections {
		target: root.sourceAudio
		function onVolumesChanged() { root.syncMic() }
		function onMutedChanged() { root.syncMic() }
	}

	// ------------------------------------------------------------ brightness

	property int brightness: 0
	property int maxBrightness: 1
	readonly property int brightnessPercent: root.maxBrightness > 1
		? Math.round(root.brightness / root.maxBrightness * 100)
		: 0
	readonly property bool brightnessAvailable: root.backlightDevice !== ""

	Process {
		id: backlightFind
		command: ["sh", "-c", "ls /sys/class/backlight 2>/dev/null | head -1"]
		stdout: StdioCollector { id: backlightOut }
		Component.onCompleted: running = true
	}

	readonly property string backlightDevice: backlightOut.text.trim()

	FileView {
		id: brightnessFile
		path: root.backlightDevice !== ""
			? "/sys/class/backlight/" + root.backlightDevice + "/brightness"
			: ""
		watchChanges: true
		printErrors: false
	}

	FileView {
		id: maxBrightnessFile
		path: root.backlightDevice !== ""
			? "/sys/class/backlight/" + root.backlightDevice + "/max_brightness"
			: ""
		watchChanges: true
		printErrors: false
	}

	readonly property string brightnessText: brightnessFile.text()
	readonly property string maxBrightnessText: maxBrightnessFile.text()

	onMaxBrightnessTextChanged: {
		const value = parseInt(root.maxBrightnessText)
		if (value > 0) root.maxBrightness = value
	}

	onBrightnessTextChanged: {
		const value = parseInt(root.brightnessText)
		if (!isNaN(value)) root.brightness = value
	}

	Timer {
		id: brightnessWriteTimer
		interval: 70
		onTriggered: {
			if (!root.brightnessAvailable) return
			brightnessProc.command = [
				"busctl", "call",
				"org.freedesktop.login1",
				"/org/freedesktop/login1/session/auto",
				"org.freedesktop.login1.Session",
				"SetBrightness", "ssu",
				"backlight", root.backlightDevice, String(root.brightness)
			]
			brightnessProc.running = true
		}
	}

	Process {
		id: brightnessProc
		onExited: brightnessFile.reload()
	}

	function setBrightnessPercent(value) {
		if (!root.brightnessAvailable) return
		const percent = Math.max(1, Math.min(100, Math.round(value)))
		root.brightness = Math.max(1, Math.round(root.maxBrightness * percent / 100))
		brightnessWriteTimer.restart()
	}

	// ------------------------------------------------------------------- dnd

	readonly property string dndPath: (Quickshell.env("XDG_CACHE_HOME")
		|| (Quickshell.env("HOME") + "/.cache")) + "/quickshell/dnd"
	property bool dndEnabled: false

	FileView {
		id: dndFile
		path: root.dndPath
		watchChanges: true
		printErrors: false
	}

	readonly property string dndText: dndFile.text()

	Timer {
		interval: 1000
		running: true
		repeat: true
		onTriggered: dndFile.reload()
	}

	onDndTextChanged: root.dndEnabled = root.dndText.trim() === "1"

	Process {
		id: dndInit
		command: ["sh", "-c", "mkdir -p \"$(dirname \"$1\")\"; [ -f \"$1\" ] || printf '0' > \"$1\"", "--", root.dndPath]
		onExited: dndFile.reload()
		Component.onCompleted: running = true
	}

	Process {
		id: dndWrite
		onExited: dndFile.reload()
	}

	function toggleDnd() {
		root.dndEnabled = !root.dndEnabled
		dndWrite.command = [
			"sh", "-c",
			"mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"",
			"--", root.dndPath, root.dndEnabled ? "1" : "0"
		]
		dndWrite.running = true
	}

	// ----------------------------------------------------------------- wifi

	property bool wifiEnabled: false
	property string wifiSsid: ""
	property int wifiSignal: 0

	Process {
		id: wifiState
		command: ["sh", "-c",
			"state=$(nmcli radio wifi 2>/dev/null | head -n1); " +
			"active=$(nmcli -t -f ACTIVE,SSID,SIGNAL device wifi 2>/dev/null | awk -F: '$1==\"yes\"{print $2\"|\"$3; exit}'); " +
			"echo \"$state|$active\""
		]
		stdout: SplitParser {
			onRead: data => {
				if (!data) return
				const parts = data.split("|")
				root.wifiEnabled = (parts[0] || "").trim() === "enabled"
				root.wifiSsid = parts[1] || ""
				root.wifiSignal = parseInt(parts[2]) || 0
			}
		}
	}

	Process {
		id: wifiToggle
		onExited: wifiState.running = true
	}

	function toggleWifi() {
		root.wifiEnabled = !root.wifiEnabled
		wifiToggle.command = ["nmcli", "radio", "wifi", root.wifiEnabled ? "on" : "off"]
		wifiToggle.running = true
	}

	Timer {
		interval: 12000
		running: true
		repeat: true
		onTriggered: wifiState.running = true
	}

	// ------------------------------------------------------------- bluetooth

	property bool bluetoothEnabled: false

	Process {
		id: bluetoothState
		command: ["sh", "-c", "bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/{print $2; exit}'"]
		stdout: SplitParser {
			onRead: data => root.bluetoothEnabled = (data || "").trim() === "yes"
		}
	}

	Process {
		id: bluetoothToggle
		onExited: bluetoothState.running = true
	}

	function toggleBluetooth() {
		root.bluetoothEnabled = !root.bluetoothEnabled
		bluetoothToggle.command = ["bluetoothctl", "power", root.bluetoothEnabled ? "on" : "off"]
		bluetoothToggle.running = true
	}

	Timer {
		interval: 15000
		running: true
		repeat: true
		onTriggered: bluetoothState.running = true
	}

	// ------------------------------------------------------------------ lock

	Process {
		id: lockProc
		command: ["loginctl", "lock-session"]
	}

	// --------------------------------------------------------------- battery

	readonly property var battery: UPower.displayDevice
	readonly property bool batteryPresent: battery ? battery.isPresent : false
	readonly property int batteryLevel: battery ? Math.round(battery.percentage * 100) : 0
	readonly property int batteryState: battery ? battery.state : UPowerDeviceState.Unknown
	readonly property double timeToEmpty: battery ? battery.timeToEmpty : 0
	readonly property double timeToFull: battery ? battery.timeToFull : 0

	function formatDuration(seconds) {
		seconds = Math.max(0, Math.round(seconds))
		const h = Math.floor(seconds / 3600)
		const m = Math.floor((seconds % 3600) / 60)
		return (h > 0 ? h + "h " : "") + m + "m"
	}

	function batteryDetail() {
		if (!root.batteryPresent) return "No battery"
		if (root.batteryState === UPowerDeviceState.Charging)
			return root.batteryLevel + "% · charging" + (root.timeToFull > 0 ? " · " + root.formatDuration(root.timeToFull) : "")
		if (root.batteryState === UPowerDeviceState.Discharging)
			return root.batteryLevel + "% · " + (root.timeToEmpty > 0 ? root.formatDuration(root.timeToEmpty) + " left" : "discharging")
		if (root.batteryState === UPowerDeviceState.FullyCharged)
			return root.batteryLevel + "% · charged"
		return root.batteryLevel + "%"
	}

	// ------------------------------------------------------------ system use

	property int cpuUsage: 0
	property int memUsage: 0
	property int diskUsage: 0
	property var lastCpuIdle: 0
	property var lastCpuTotal: 0

	readonly property var statRows: [
		{ icon: "\uf2db", label: "CPU", value: root.cpuUsage },
		{ icon: "\uf1c0", label: "Memory", value: root.memUsage },
		{ icon: "\uf0a0", label: "Disk", value: root.diskUsage }
	]

	FileView { id: statFile; path: "/proc/stat" }
	FileView { id: memFile; path: "/proc/meminfo" }

	readonly property string statText: statFile.text()
	onStatTextChanged: root.parseCpuStat(statText)

	readonly property string memText: memFile.text()
	onMemTextChanged: root.parseMemInfo(memText)

	function parseCpuStat(text) {
		if (!text) return
		const parts = text.split("\n")[0].trim().split(/\s+/)
		const total = (parseInt(parts[1]) || 0) + (parseInt(parts[2]) || 0)
			+ (parseInt(parts[3]) || 0) + (parseInt(parts[4]) || 0)
			+ (parseInt(parts[5]) || 0) + (parseInt(parts[6]) || 0)
			+ (parseInt(parts[7]) || 0)
		const idle = (parseInt(parts[4]) || 0) + (parseInt(parts[5]) || 0)
		if (root.lastCpuTotal > 0) {
			const totalDiff = total - root.lastCpuTotal
			const idleDiff = idle - root.lastCpuIdle
			if (totalDiff > 0) root.cpuUsage = Math.round(100 * (totalDiff - idleDiff) / totalDiff)
		}
		root.lastCpuTotal = total
		root.lastCpuIdle = idle
	}

	function parseMemInfo(text) {
		if (!text) return
		const totalMatch = text.match(/MemTotal:\s*(\d+)/)
		const availMatch = text.match(/MemAvailable:\s*(\d+)/)
		if (!totalMatch || !availMatch) return
		const total = parseInt(totalMatch[1]) || 1
		const avail = parseInt(availMatch[1]) || 0
		root.memUsage = Math.round(100 * (total - avail) / total)
	}

	Process {
		id: diskProc
		command: ["sh", "-c", "df / | tail -1"]
		stdout: SplitParser {
			onRead: data => {
				if (!data) return
				const parts = data.trim().split(/\s+/)
				root.diskUsage = parseInt((parts[4] || "0%").replace("%", "")) || 0
			}
		}
	}

	Timer {
		interval: 2000
		running: true
		repeat: true
		onTriggered: {
			statFile.reload()
			memFile.reload()
			diskProc.running = true
		}
	}

	// ----------------------------------------------------------------- media

	readonly property var players: Mpris.players
	readonly property var player: (players && players.values.length > 0)
		? (players.values.find(p => p.isPlaying) || players.values[0])
		: null
	readonly property bool hasPlayer: root.player !== null
	readonly property real mediaPosition: root.player ? root.player.position : 0
	readonly property real mediaLength: root.player ? root.player.length : 0
	readonly property string artUrl: (root.player && root.player.trackArtUrl) ? root.player.trackArtUrl : ""

	function togglePlayback() {
		if (root.player) root.player.isPlaying = !root.player.isPlaying
	}

	function nextTrack() {
		if (root.player && root.player.canGoNext) root.player.next()
	}

	function prevTrack() {
		if (root.player && root.player.canGoPrevious) root.player.previous()
	}

	function seekTo(seconds) {
		if (!root.player || !root.player.canSeek || !root.player.positionSupported) return
		root.player.position = Math.max(0, Math.min(root.mediaLength, seconds))
	}

	Timer {
		interval: 1000
		running: root.hasPlayer && root.player.isPlaying
		repeat: true
		onTriggered: if (root.player) root.player.positionChanged()
	}

	// ---------------------------------------------------------------- panel

	Variants {
		model: Quickshell.screens

		PanelWindow {
			id: panelWindow

			required property var modelData
			screen: modelData

			readonly property var monitor: Hyprland.monitorFor(modelData)
			readonly property bool isFocusedMonitor: monitor?.name === Hyprland.focusedMonitor?.name

			visible: root.panelOpen && isFocusedMonitor
			implicitWidth: 440
			implicitHeight: cardContent.implicitHeight + Config.panel.padding * 2
			color: "transparent"
			exclusionMode: ExclusionMode.Ignore

			WlrLayershell.layer: WlrLayer.Overlay
			WlrLayershell.namespace: "controlcenter"
			WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

			anchors { top: true; right: true }
			margins {
				top: Config.bar.height + Config.bar.margin * 2 + 4
				right: Config.bar.margin
			}

			onVisibleChanged: {
				if (visible) {
					keyHandler.forceActiveFocus()
					wifiState.running = true
					bluetoothState.running = true
				}
			}

			Rectangle {
				id: card
				anchors.fill: parent
				radius: Config.radius.large
				color: Config.colors.base
				border.width: 1
				border.color: Config.colors.border
				opacity: panelWindow.visible ? 1 : 0
				scale: panelWindow.visible ? 1 : 0.97
				transformOrigin: Item.TopRight

				Behavior on opacity { NumberAnimation { duration: Config.motion.normal } }
				Behavior on scale { NumberAnimation { duration: Config.motion.normal; easing.type: Easing.OutCubic } }

				Item {
					id: keyHandler
					anchors.fill: parent
					focus: true
					Keys.onEscapePressed: root.panelOpen = false
				}

				ColumnLayout {
					id: cardContent
					anchors.fill: parent
					anchors.margins: Config.panel.padding
					spacing: Config.panel.gap

					// -------------------------------------------------- header

					RowLayout {
						Layout.fillWidth: true
						spacing: 8

						ColumnLayout {
							Layout.fillWidth: true
							spacing: 0

							Text {
								text: "Control Center"
								color: Config.colors.text
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize + 1
								font.weight: 700
							}

							Text {
								text: Qt.formatDateTime(new Date(), "dddd, dd MMMM")
								color: Config.colors.textDim
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 4
							}
						}

						IconButton {
							icon: "\uf00d"
							iconSize: Config.bar.fontSize
							iconColor: Config.colors.textDim
							onClicked: root.panelOpen = false
						}
					}

					// ------------------------------------------------- sliders

					Rectangle {
						Layout.fillWidth: true
						implicitHeight: sliderColumn.implicitHeight + 22
						radius: Config.radius.medium
						color: Config.colors.elevated
						border.width: 1
						border.color: Config.colors.borderMuted

						ColumnLayout {
							id: sliderColumn
							anchors.fill: parent
							anchors.margins: 11
							spacing: 2

							SliderRow {
								Layout.fillWidth: true
								icon: "\uf028"
								mutedIcon: "\uf026"
								label: "Output volume"
								value: root.outputVolume
								muted: root.outputMuted
								valueText: root.outputMuted ? "muted" : root.outputVolume + "%"
								onToggleMute: root.toggleOutputMute()
								onMoved: (v) => root.setOutputVolume(v)
								onCommitted: (v) => root.setOutputVolume(v)
							}

							Rectangle {
								Layout.fillWidth: true
								Layout.preferredHeight: 1
								color: Config.colors.borderMuted
							}

							SliderRow {
								Layout.fillWidth: true
								icon: "\uf130"
								mutedIcon: "\uf131"
								label: "Microphone"
								value: root.micVolume
								muted: root.micMuted
								valueText: root.micMuted ? "muted" : root.micVolume + "%"
								accentColor: Config.colors.accent2
								onToggleMute: root.toggleMicMute()
								onMoved: (v) => root.setMicVolume(v)
								onCommitted: (v) => root.setMicVolume(v)
							}

							Rectangle {
								Layout.fillWidth: true
								Layout.preferredHeight: 1
								color: Config.colors.borderMuted
								visible: root.brightnessAvailable
							}

							SliderRow {
								Layout.fillWidth: true
								visible: root.brightnessAvailable
								icon: "\uf185"
								label: "Brightness"
								value: root.brightnessPercent
								valueText: root.brightnessPercent + "%"
								accentColor: Config.colors.warn
								muteSupported: false
								onMoved: (v) => root.setBrightnessPercent(v)
								onCommitted: (v) => root.setBrightnessPercent(v)
							}
						}
					}

					// ------------------------------------------------ toggles

					RowLayout {
						Layout.fillWidth: true
						spacing: 10

						QuickToggle {
							Layout.fillWidth: true
							icon: "\udb82\udd28"
							label: "Wi-Fi"
							detail: root.wifiEnabled
								? (root.wifiSsid !== "" ? root.wifiSsid : "Not connected")
								: "Off"
							active: root.wifiEnabled
							onClicked: root.toggleWifi()
						}

						QuickToggle {
							Layout.fillWidth: true
							icon: "\uf293"
							label: "Bluetooth"
							detail: root.bluetoothEnabled ? "On" : "Off"
							active: root.bluetoothEnabled
							accentColor: Config.colors.accent2
							onClicked: root.toggleBluetooth()
						}
					}

					RowLayout {
						Layout.fillWidth: true
						spacing: 10

						QuickToggle {
							Layout.fillWidth: true
							icon: root.dndEnabled ? "\uf1f6" : "\uf0f3"
							label: "Do not disturb"
							detail: root.dndEnabled ? "Notifications paused" : "Notifications on"
							active: root.dndEnabled
							accentColor: Config.colors.warn
							onClicked: root.toggleDnd()
						}

						QuickToggle {
							Layout.fillWidth: true
							icon: "\uf023"
							label: "Lock"
							detail: "Lock this session"
							accentColor: Config.colors.accent3
							onClicked: lockProc.running = true
						}
					}

					// -------------------------------------------------- media

					Rectangle {
						Layout.fillWidth: true
						visible: root.hasPlayer
						implicitHeight: 88
						radius: Config.radius.medium
						color: Config.colors.elevated
						border.width: 1
						border.color: Config.colors.borderMuted

						RowLayout {
							anchors.fill: parent
							anchors.margins: 11
							spacing: 11

							Rectangle {
								Layout.preferredWidth: 58
								Layout.preferredHeight: 58
								radius: Config.radius.small
								color: Config.colors.surfaceAlt
								clip: true

								Image {
									anchors.fill: parent
									source: root.artUrl
									fillMode: Image.PreserveAspectCrop
									asynchronous: true
									visible: source.toString() !== ""
								}

								Text {
									anchors.centerIn: parent
									visible: root.artUrl === ""
									text: "\uf001"
									color: Config.colors.accent2
									font.family: Config.bar.iconFontFamily
									font.pixelSize: 24
								}
							}

							ColumnLayout {
								Layout.fillWidth: true
								spacing: 2

								RowLayout {
									Layout.fillWidth: true
									spacing: 6

									Text {
										Layout.fillWidth: true
										text: root.player ? (root.player.trackTitle || "Unknown track") : ""
										color: Config.colors.text
										font.family: Config.bar.fontFamily
										font.pixelSize: Config.bar.fontSize - 1
										font.weight: 600
										elide: Text.ElideRight
									}

									IconButton {
										icon: "\uf048"
										iconSize: 12
										implicitHeight: 24
										iconColor: Config.colors.textMuted
										onClicked: root.prevTrack()
									}

									IconButton {
										icon: root.player && root.player.isPlaying ? "\uf04c" : "\uf04b"
										iconSize: 12
										implicitHeight: 24
										iconColor: Config.colors.accent
										onClicked: root.togglePlayback()
									}

									IconButton {
										icon: "\uf051"
										iconSize: 12
										implicitHeight: 24
										iconColor: Config.colors.textMuted
										onClicked: root.nextTrack()
									}
								}

								Text {
									Layout.fillWidth: true
									text: root.player
										? ((root.player.trackArtist || "Unknown artist") + "  ·  " + root.player.trackAlbum)
										: ""
									color: Config.colors.textDim
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize - 3
									elide: Text.ElideRight
								}

								Slider {
									Layout.fillWidth: true
									Layout.topMargin: 4
									implicitHeight: 12
									from: 0
									to: root.mediaLength > 0 ? root.mediaLength : 1
									value: root.mediaPosition
									showHandle: false
									trackHeight: 4
									enabled: root.mediaLength > 0
									fillColor: Config.colors.accent2
									onCommitted: (v) => root.seekTo(v)
								}
							}
						}
					}

					// ------------------------------------------------- system

					Rectangle {
						Layout.fillWidth: true
						implicitHeight: systemColumn.implicitHeight + 22
						radius: Config.radius.medium
						color: Config.colors.elevated
						border.width: 1
						border.color: Config.colors.borderMuted

						ColumnLayout {
							id: systemColumn
							anchors.fill: parent
							anchors.margins: 12
							spacing: 7

							RowLayout {
								Layout.fillWidth: true
								spacing: 8

								Text {
									Layout.fillWidth: true
									text: "System"
									color: Config.colors.text
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize - 1
									font.weight: 700
								}

								Text {
									text: root.batteryDetail()
									color: root.batteryLevel <= 15 ? Config.colors.bad : Config.colors.textDim
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize - 3
								}
							}

							Repeater {
								model: root.statRows

								RowLayout {
									required property var modelData
									Layout.fillWidth: true
									spacing: 8

									Text {
										Layout.preferredWidth: 15
										text: modelData.icon
										color: root.usageColor(modelData.value)
										font.family: Config.bar.iconFontFamily
										font.pixelSize: Config.bar.fontSize - 2
										horizontalAlignment: Text.AlignHCenter
									}

									Text {
										Layout.preferredWidth: 55
										text: modelData.label
										color: Config.colors.textMuted
										font.family: Config.bar.fontFamily
										font.pixelSize: Config.bar.fontSize - 3
									}

									Rectangle {
										Layout.fillWidth: true
										Layout.preferredHeight: 5
										radius: 2.5
										color: Config.colors.surfaceAlt

										Rectangle {
											width: parent.width * Math.max(0, Math.min(100, modelData.value)) / 100
											height: parent.height
											radius: parent.radius
											color: root.usageColor(modelData.value)
											Behavior on width { NumberAnimation { duration: Config.motion.slow; easing.type: Easing.OutCubic } }
										}
									}

									Text {
										Layout.preferredWidth: 34
										text: modelData.value + "%"
										color: Config.colors.text
										font.family: Config.bar.fontFamily
										font.pixelSize: Config.bar.fontSize - 3
										horizontalAlignment: Text.AlignRight
									}
								}
							}
						}
					}

					// ------------------------------------------------- footer

					RowLayout {
						Layout.fillWidth: true
						spacing: 8

						IconButton {
							Layout.fillWidth: true
							showLabel: true
							icon: "\uf009"
							label: "apps"
							iconColor: Config.colors.accent
							labelSize: Config.bar.fontSize - 2
							onClicked: {
								root.panelOpen = false
								root.ipcCall("launcher", "toggle")
							}
						}

						IconButton {
							Layout.fillWidth: true
							showLabel: true
							icon: "\uf0ea"
							label: "clip"
							iconColor: Config.colors.accent2
							labelSize: Config.bar.fontSize - 2
							onClicked: {
								root.panelOpen = false
								root.ipcCall("clipboard", "toggle")
							}
						}

						IconButton {
							Layout.fillWidth: true
							showLabel: true
							icon: "\uf0f3"
							label: "notifs"
							iconColor: Config.colors.warn
							labelSize: Config.bar.fontSize - 2
							onClicked: {
								root.panelOpen = false
								root.ipcCall("notifications", "toggle")
							}
						}

						IconButton {
							Layout.fillWidth: true
							showLabel: true
							icon: "\uf011"
							label: "power"
							iconColor: Config.colors.bad
							labelSize: Config.bar.fontSize - 2
							danger: true
							onClicked: {
								root.panelOpen = false
								root.ipcCall("powermenu", "toggle")
							}
						}
					}
				}
			}
		}
	}

	Component.onCompleted: {
		root.syncOutput()
		root.syncMic()
		wifiState.running = true
		bluetoothState.running = true
		diskProc.running = true
	}
}
