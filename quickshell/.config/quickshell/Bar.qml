import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts

import "config.js" as Config

Scope {
	id: root

	// CPU / memory: read straight from /proc via FileView instead of forking a shell.
	property int cpuUsage: 0
	property int memUsage: 0
	property var lastCpuIdle: 0
	property var lastCpuTotal: 0

	FileView {
		id: statFile
		path: "/proc/stat"
	}

	FileView {
		id: memFile
		path: "/proc/meminfo"
	}

	readonly property string statText: statFile.text()
	onStatTextChanged: root.parseCpuStat(statText)

	readonly property string memText: memFile.text()
	onMemTextChanged: root.parseMemInfo(memText)

	function parseCpuStat(text) {
		if (!text) return
		const line = text.split("\n")[0]
		const parts = line.trim().split(/\s+/)
		const user = parseInt(parts[1]) || 0
		const nice = parseInt(parts[2]) || 0
		const system = parseInt(parts[3]) || 0
		const idle = parseInt(parts[4]) || 0
		const iowait = parseInt(parts[5]) || 0
		const irq = parseInt(parts[6]) || 0
		const softirq = parseInt(parts[7]) || 0

		const total = user + nice + system + idle + iowait + irq + softirq
		const idleTime = idle + iowait

		if (lastCpuTotal > 0) {
			const totalDiff = total - lastCpuTotal
			const idleDiff = idleTime - lastCpuIdle
			if (totalDiff > 0) {
				cpuUsage = Math.round(100 * (totalDiff - idleDiff) / totalDiff)
			}
		}
		lastCpuTotal = total
		lastCpuIdle = idleTime
	}

	function parseMemInfo(text) {
		if (!text) return
		const totalMatch = text.match(/MemTotal:\s*(\d+)/)
		const availMatch = text.match(/MemAvailable:\s*(\d+)/)
		if (!totalMatch || !availMatch) return
		const total = parseInt(totalMatch[1]) || 1
		const avail = parseInt(availMatch[1]) || 0
		memUsage = Math.round(100 * (total - avail) / total)
	}

	Timer {
		interval: 2000
		running: true
		repeat: true
		onTriggered: {
			statFile.reload()
			memFile.reload()
		}
	}

	// Disk: no native Quickshell API, so use a Process polled infrequently.
	property int diskUsage: 0

	Process {
		id: diskProc
		command: ["sh", "-c", "df / | tail -1"]
		stdout: SplitParser {
			onRead: data => {
				if (!data) return
				var parts = data.trim().split(/\s+/)
				var percentStr = parts[4] || "0%"
				diskUsage = parseInt(percentStr.replace('%', '')) || 0
			}
		}
		Component.onCompleted: running = true
	}

	Timer {
		interval: 30000
		running: true
		repeat: true
		onTriggered: diskProc.running = true
	}

	// Volume: native Pipewire binding, no polling.
	readonly property var audioSink: Pipewire.defaultAudioSink
	readonly property int volumeLevel: (audioSink && audioSink.ready && audioSink.audio)
		? Math.round(audioSink.audio.volume * 100) : 0
	readonly property bool volumeMuted: (audioSink && audioSink.audio) ? audioSink.audio.muted : false

	PwObjectTracker {
		objects: root.audioSink ? [root.audioSink] : []
	}

	// Battery: native UPower binding, event driven, no polling.
	readonly property var battery: UPower.displayDevice
	readonly property bool batteryPresent: battery ? battery.isPresent : false
	readonly property int batteryLevel: battery ? Math.round(battery.percentage * 100) : 0
	readonly property int batteryState: battery ? battery.state : UPowerDeviceState.Unknown
	readonly property double timeToEmpty: battery ? battery.timeToEmpty : 0
	readonly property double timeToFull: battery ? battery.timeToFull : 0

	function batteryIcon() {
		if (batteryState === UPowerDeviceState.Charging) return "\uf0e7"
		if (batteryState === UPowerDeviceState.FullyCharged) return "\uf240"
		if (batteryLevel >= 90) return "\uf240"
		if (batteryLevel >= 60) return "\uf241"
		if (batteryLevel >= 40) return "\uf242"
		if (batteryLevel >= 10) return "\uf243"
		return "\uf244"
	}

	function batteryColor() {
		if (batteryLevel <= 15) return Config.colors.bad
		if (batteryLevel <= 30) return Config.colors.warn
		return Config.colors.textMuted
	}

	function formatTime(sec) {
		sec = Math.max(0, Math.round(sec))
		const h = Math.floor(sec / 3600)
		const m = Math.floor((sec % 3600) / 60)
		return (h > 0 ? h + "h " : "") + m + "m"
	}

	function batteryTooltip() {
		if (!root.batteryPresent) return "No battery"
		var text = root.batteryLevel + "%"
		if (root.batteryState === UPowerDeviceState.Charging) {
			text += " · charging"
			if (root.timeToFull > 0) text += " · " + root.formatTime(root.timeToFull) + " to full"
		} else if (root.batteryState === UPowerDeviceState.Discharging) {
			if (root.timeToEmpty > 0) text += " · " + root.formatTime(root.timeToEmpty) + " remaining"
		} else if (root.batteryState === UPowerDeviceState.FullyCharged) {
			text += " · fully charged"
		}
		return text
	}

	// Media: native MPRIS binding, replaces playerctl entirely.
	readonly property var mprisPlayers: Mpris.players
	readonly property var activePlayer: (mprisPlayers && mprisPlayers.values.length > 0)
		? (mprisPlayers.values.find(p => p.isPlaying) || mprisPlayers.values[0])
		: null

	function playerIcon() {
		return (activePlayer && activePlayer.isPlaying) ? "\uf04c" : "\uf04b"
	}

	function playerLabel() {
		if (!activePlayer) return "No media"
		const artist = activePlayer.trackArtist || ""
		const title = activePlayer.trackTitle || ""
		if (artist && title) return artist + " - " + title
		return title || artist || "No media"
	}

	function togglePlayback() {
		if (activePlayer && activePlayer.canTogglePlaying) activePlayer.isPlaying = !activePlayer.isPlaying
	}
	function nextTrack() {
		if (activePlayer && activePlayer.canGoNext) activePlayer.next()
	}
	function prevTrack() {
		if (activePlayer && activePlayer.canGoPrevious) activePlayer.previous()
	}

	// Window title: reactive foreign-toplevel protocol, no polling.
	readonly property string activeWindowTitle: ToplevelManager.activeToplevel
		? (ToplevelManager.activeToplevel.title || "")
		: ""

	// Network: Quickshell's NetworkManager API isn't stable yet, so use a Process.
	property string wifiSSID: ""
	property int wifiSignal: 0
	property string networkType: "offline"

	function wifiIcon() {
		if (networkType === "ethernet") return "\uef09"
		if (networkType !== "wifi" || wifiSSID === "" || wifiSSID === "Offline") return "\uf05aa"
		if (wifiSignal >= 75) return "\udb82\udd28"
		if (wifiSignal >= 50) return "\udb82\udd25"
		if (wifiSignal >= 25) return "\udb82\udd22"
		return "\udb82\udd1f"
	}

	function wifiTooltip() {
		if (networkType === "ethernet") return "Ethernet · " + wifiSSID
		if (networkType === "wifi" && wifiSSID && wifiSSID !== "Offline")
			return wifiSSID + " · " + wifiSignal + "% signal"
		return "No network"
	}

	Process {
		id: wifiProc
		command: ["sh", "-c", "eth=$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2==\"ethernet\" && $3==\"connected\"{print $1; exit}'); if [ -n \"$eth\" ]; then econn=$(nmcli -t -f GENERAL.CONNECTION device show \"$eth\" 2>/dev/null | cut -d: -f2); echo \"ethernet|$econn|0\"; else dev=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2==\"wifi\"{print $1; exit}'); conn=$(nmcli -t -f GENERAL.CONNECTION device show \"$dev\" 2>/dev/null | cut -d: -f2); ssid=$(nmcli -t -f 802-11-wireless.ssid connection show \"$conn\" 2>/dev/null | cut -d: -f2); q=$(awk -v ifc=\"$dev:\" '$1==ifc{gsub(\"\\\\.\",\"\",$4); print $4}' /proc/net/wireless); echo \"wifi|$ssid|$q\"; fi"]
		stdout: SplitParser {
			onRead: data => {
				if (!data) return
				var parts = data.split("|")
				networkType = parts[0] || "offline"
				var label = parts[1] ? parts[1].trim() : ""
				if (networkType === "ethernet") {
					wifiSSID = label ? label : "Wired"
					wifiSignal = 100
				} else if (networkType === "wifi") {
					wifiSSID = label ? label : "Offline"
					// Signal level in dBm (e.g. -46). Convert to a 0-100
					// percentage so the bars track real signal strength.
					var dbm = parseInt(parts[2]) || 0
					wifiSignal = Math.max(0, Math.min(100, Math.round(2 * (dbm + 100))))
				} else {
					wifiSSID = "Offline"
					wifiSignal = 0
				}
			}
		}
		Component.onCompleted: running = true
	}

	Timer {
		interval: 5000
		running: true
		repeat: true
		onTriggered: wifiProc.running = true
	}

	// Right-hand stat readouts, joined into one compact segment
	property var statsModel: [
		{ label: "C", value: cpuUsage + "%" },
		{ label: "M", value: memUsage + "%" },
		{ label: "D", value: diskUsage + "%" },
		{ label: "V", value: volumeMuted ? "mute" : (volumeLevel + "%") }
	]

	function statsTooltip() {
		return "CPU " + cpuUsage + "%  ·  RAM " + memUsage + "%  ·  Disk " + diskUsage + "%  ·  Vol " +
			(volumeMuted ? "muted" : volumeLevel + "%")
	}

	function statusTooltip() {
		var parts = []
		if (batteryPresent) parts.push(root.batteryTooltip())
		if (networkType === "wifi" && wifiSSID && wifiSSID !== "Offline") parts.push(wifiSSID + " · " + wifiSignal + "%")
		else if (networkType === "ethernet") parts.push("Ethernet · " + wifiSSID)
		else parts.push("No network")
		return parts.join("  ·  ")
	}

	Variants {
		model: Quickshell.screens

		PanelWindow {
			id: barWindow
			property var modelData
			screen: modelData

			anchors {
				top: true
				left: true
				right: true
			}

			implicitHeight: Config.bar.height + Config.bar.margin
			color: "transparent"

			Item {
				anchors.fill: parent

				RowLayout {
					id: barRow
					anchors.top: parent.top
					anchors.left: parent.left
					anchors.right: parent.right
					height: Config.bar.height
					anchors.topMargin: Config.bar.margin / 2
					anchors.leftMargin: Config.bar.margin
					anchors.rightMargin: Config.bar.margin
					spacing: Config.bar.gap

					// Workspaces
					BarSegment {
						id: workspaceSeg
						Layout.preferredWidth: wsRow.implicitWidth + 16

						// Scroll to step through workspaces (wraps 1<->10). The
						MouseArea {
							anchors.fill: parent
							acceptedButtons: Qt.NoButton
							onWheel: (wheel) => {
								const current = Hyprland.focusedWorkspace?.id ?? 1
								const next = wheel.angleDelta.y > 0
									? (current === 1 ? 10 : current - 1)
									: (current === 10 ? 1 : current + 1)
								Hyprland.dispatch("hl.dsp.focus({ workspace = " + next + " })")
							}
						}

						RowLayout {
							id: wsRow
							anchors.centerIn: parent
							spacing: 10

							Repeater {
								model: 10

								Item {
									Layout.preferredWidth: 22
									Layout.preferredHeight: Config.bar.height

									property var workspace: Hyprland.workspaces.values.find(ws => ws.id === index + 1) ?? null
									property bool isActive: Hyprland.focusedWorkspace?.id === (index + 1)
									property bool hasWindows: workspace !== null

									Text {
										anchors.centerIn: parent
										text: index === 9 ? "0" : index + 1
										color: parent.isActive
											? Config.colors.accent
											: (parent.hasWindows ? Config.colors.textMuted : Config.colors.textDim)
										font.pixelSize: Config.bar.fontSize
										font.family: Config.bar.fontFamily
										font.bold: parent.isActive
									}

									Rectangle {
										visible: parent.isActive
										width: 6
										height: 6
										radius: 3
										color: Config.colors.accent
										anchors.horizontalCenter: parent.horizontalCenter
										anchors.bottom: parent.bottom
									}

									MouseArea {
										anchors.fill: parent
										hoverEnabled: true
										onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + (index + 1) + " })")
									}
								}
							}
						}
					}

					// Window title - takes remaining space
					BarSegment {
						Layout.fillWidth: true

						Text {
							anchors.fill: parent
							anchors.leftMargin: 16
							anchors.rightMargin: 16
							verticalAlignment: Text.AlignVCenter
							text: root.activeWindowTitle || "Desktop"
							color: Config.colors.textMuted
							font.pixelSize: Config.bar.fontSize
							font.family: Config.bar.fontFamily
							elide: Text.ElideRight
						}
					}

					// System stats
					BarSegment {
						id: statsSeg
						Layout.preferredWidth: statsRow.implicitWidth + 16

						RowLayout {
							id: statsRow
							anchors.centerIn: parent
							spacing: 10

							Repeater {
								model: root.statsModel

								RowLayout {
									required property var modelData
									spacing: 3

									Text {
										text: modelData.label
										color: Config.colors.textDim
										font.pixelSize: Config.bar.fontSize - 1
										font.family: Config.bar.fontFamily
									}
									Text {
										text: modelData.value
										color: Config.colors.text
										font.pixelSize: Config.bar.fontSize
										font.family: Config.bar.fontFamily
									}
								}
							}
						}

					}

					// System tray - native StatusNotifierItem binding, no polling
					BarSegment {
						id: traySeg
						visible: SystemTray.items.values.length > 0
						Layout.preferredWidth: trayRow.implicitWidth + 16

						RowLayout {
							id: trayRow
							anchors.centerIn: parent
							spacing: 10

							property string trayMatchQuery: ""

							Process {
								id: trayInspectProc
								command: ["hyprctl", "clients", "-j"]
								stdout: StdioCollector {
									onStreamFinished: {
										const sig = trayRow.trayMatchQuery
										if (!sig) return

										let clients
										try {
											clients = JSON.parse(text)
										} catch (e) {
											console.warn("tray kill: failed to parse hyprctl clients -j", e)
											return
										}

										const strip = (s) => (s || "").toLowerCase().replace(/[^a-z0-9]/g, "")

										const pids = clients
											.filter(c => {
												const cls = strip(c.class || c.initialClass)
												const title = strip(c.title || c.initialTitle)
												return cls.startsWith(sig) || title.startsWith(sig)
													|| (cls.length > 0 && sig.startsWith(cls)) || (title.length > 0 && sig.startsWith(title))
											})
											.map(c => String(c.pid))

										if (pids.length === 0) {
											console.warn("tray kill: no Hyprland window matched", sig)
											return
										}

										console.warn("tray kill: closing pid(s)", pids.join(","), "for", sig)
										trayKillProc.command = ["kill", "-TERM"].concat(pids)
										trayKillProc.running = true
									}
								}
							}

							Process { id: trayKillProc }

							Repeater {
								model: SystemTray.items

								Item {
									id: trayItem
									required property var modelData
									Layout.preferredWidth: 18
									Layout.preferredHeight: 18

									readonly property string tooltipText: {
										const raw = modelData.title || modelData.tooltipTitle || modelData.id || ""
										const firstLine = raw.split("\n")[0].trim()
										return firstLine.length > 40 ? firstLine.substring(0, 40) + "\u2026" : firstLine
									}

									Image {
										anchors.fill: parent
										anchors.margins: 1
										source: modelData.icon
										fillMode: Image.PreserveAspectFit
										smooth: true
										asynchronous: true
									}

									MouseArea {
										id: trayHover
										anchors.fill: parent
										hoverEnabled: true
										acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

										onClicked: (mouse) => {
											if (mouse.button === Qt.RightButton) {
												const sig = (modelData.title || modelData.id || "").toLowerCase().replace(/[^a-z0-9]/g, "").substring(0, 8)
												if (sig.length === 0) {
													console.warn("tray kill: no usable title/id for", modelData.id)
												} else {
													console.warn("tray kill: looking up window for", sig)
													trayRow.trayMatchQuery = sig
													trayInspectProc.running = true
												}
											} else if (mouse.button === Qt.MiddleButton) {
												modelData.secondaryActivate()
											} else {
												modelData.activate()
											}
										}

										onWheel: (wheel) => {
											modelData.scroll(wheel.angleDelta.y, false)
											wheel.accepted = true
										}
									}
									Rectangle {
										visible: trayHover.containsMouse && trayItem.tooltipText !== ""
										anchors.verticalCenter: parent.verticalCenter
										anchors.right: parent.left
										anchors.rightMargin: 6
										z: 100
										width: tooltipLabel.implicitWidth + 16
										height: tooltipLabel.implicitHeight + 10
										radius: Config.radius.small
										color: Config.colors.surface
										border.width: 1
										border.color: Config.colors.border

										Text {
											id: tooltipLabel
											anchors.centerIn: parent
											text: trayItem.tooltipText
											color: Config.colors.text
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize - 2
											wrapMode: Text.NoWrap
										}
									}
								}
							}
						}
					}

					// Battery + wifi
					BarSegment {
						id: statusSeg
						visible: root.batteryPresent || root.networkType !== "offline"
						alert: root.batteryPresent && root.batteryLevel <= 15
						Layout.preferredWidth: statusRow.implicitWidth + 16

						RowLayout {
							id: statusRow
							anchors.centerIn: parent
							spacing: 10

							// Battery
							RowLayout {
								id: batteryRow
								visible: root.batteryPresent
								spacing: 5

								Text {
									text: root.batteryIcon()
									color: root.batteryColor()
									font.family: Config.bar.iconFontFamily
									font.pixelSize: Config.bar.fontSize
								}
								Text {
									text: root.batteryLevel + "%"
									color: root.batteryLevel <= 15 ? Config.colors.bad : Config.colors.text
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize
								}

								// Thin charge/state underline
								Rectangle {
									width: batteryRow.width
									height: 3
									radius: 1.5
									color: root.batteryState === UPowerDeviceState.Charging
										? Config.colors.good
										: (root.batteryLevel <= 15 ? Config.colors.bad : Config.colors.border)
									Layout.alignment: Qt.AlignBottom
									Layout.bottomMargin: -3
								}
							}

							// Wifi
							RowLayout {
								id: wifiRow
								spacing: 5

						Text {
							text: root.wifiIcon()
							color: Config.colors.accent2
							font.family: Config.bar.iconFontFamily
							font.pixelSize: Config.bar.fontSize
						}
								Text {
									text: root.wifiSSID
									color: Config.colors.text
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize
									elide: Text.ElideRight
									Layout.maximumWidth: 110
								}
							}
						}

					}

					// Clock - the one accent-colored element on the bar
					BarSegment {
						id: clockSeg
						emphasized: true
						Layout.preferredWidth: clockText.implicitWidth + 16

						Text {
							id: clockText
							anchors.centerIn: parent
							text: Qt.formatDateTime(new Date(), "ddd dd MMM  HH:mm")
							color: Config.colors.accent
							font.pixelSize: Config.bar.fontSize
							font.family: Config.bar.fontFamily
							font.bold: false

							Timer {
								interval: 1000
								running: true
								repeat: true
								onTriggered: clockText.text = Qt.formatDateTime(new Date(), "ddd dd MMM  HH:mm")
							}
						}
					}
				}

				// Floating media pill, centered over the bar, only
				// shown when something is actually playing/paused.
				BarSegment {
					id: mediaPill
					visible: root.activePlayer !== null
					emphasized: true
					anchors.horizontalCenter: parent.horizontalCenter
					anchors.verticalCenter: barRow.verticalCenter
					implicitHeight: Config.bar.height
					implicitWidth: mediaRow.implicitWidth + 20

					RowLayout {
						id: mediaRow
						anchors.centerIn: parent
						spacing: 8

						Text {
							text: root.playerIcon()
							color: Config.colors.accent2
							font.pixelSize: Config.bar.fontSize
							font.family: Config.bar.fontFamily
						}

						Text {
							text: root.playerLabel()
							color: Config.colors.text
							font.pixelSize: Config.bar.fontSize
							font.family: Config.bar.fontFamily
							elide: Text.ElideRight
							Layout.maximumWidth: 320
						}
					}

					MouseArea {
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton
						onClicked: root.togglePlayback()
						onWheel: (wheel) => {
							if (wheel.angleDelta.y > 0) {
								root.nextTrack()
							} else {
								root.prevTrack()
							}
							wheel.accepted = true
						}
					}
				}
			}
		}
	}
}
