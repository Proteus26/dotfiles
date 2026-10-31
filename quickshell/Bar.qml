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

	// ---------------------------------------------------------------- helpers

	function ipcCall(target, fn) {
		Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", target, fn])
	}

	function closePopups(panel) {
		if (!panel) return
		panel.volumeOpen = false
		panel.calendarOpen = false
		panel.networkOpen = false
	}

	function usageColor(value) {
		if (value >= 85) return Config.colors.bad
		if (value >= 60) return Config.colors.warn
		return Config.colors.textMuted
	}

	// ------------------------------------------------------------- cpu / ram

	property int cpuUsage: 0
	property int memUsage: 0
	property var lastCpuIdle: 0
	property var lastCpuTotal: 0

	FileView { id: statFile; path: "/proc/stat" }
	FileView { id: memFile; path: "/proc/meminfo" }

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
			if (totalDiff > 0)
				cpuUsage = Math.round(100 * (totalDiff - idleDiff) / totalDiff)
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

	// ---------------------------------------------------------------- volume

	readonly property var audioSink: Pipewire.defaultAudioSink
	readonly property var audio: (audioSink && audioSink.ready) ? audioSink.audio : null
	readonly property int volumeLevel: root.audio ? Math.round(root.audio.volume * 100) : 0
	readonly property bool volumeMuted: root.audio ? root.audio.muted : false

	PwObjectTracker {
		objects: root.audioSink ? [root.audioSink] : []
	}

	function changeVolume(delta) {
		if (!root.audio) return
		root.audio.muted = false
		root.audio.volume = Math.max(0, Math.min(1, root.audio.volume + delta))
	}

	function setVolumePercent(percent) {
		if (!root.audio) return
		const value = Math.max(0, Math.min(100, percent)) / 100
		if (value > 0) root.audio.muted = false
		root.audio.volume = value
	}

	function toggleVolumeMute() {
		if (root.audio) root.audio.muted = !root.audio.muted
	}

	// --------------------------------------------------------------- battery

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

	// ----------------------------------------------------------------- media

	readonly property var mprisPlayers: Mpris.players
	readonly property var activePlayer: (mprisPlayers && mprisPlayers.values.length > 0)
		? (mprisPlayers.values.find(p => p.isPlaying) || mprisPlayers.values[0])
		: null

	function playerIcon() {
		return (activePlayer && activePlayer.isPlaying) ? "\uf04c" : "\uf04b"
	}

	function playerLabel() {
		if (!activePlayer) return ""
		const artist = activePlayer.trackArtist || ""
		const title = activePlayer.trackTitle || ""
		if (artist && title) return artist + " - " + title
		return title || artist || "Unknown track"
	}

	function togglePlayback() {
		if (activePlayer) activePlayer.isPlaying = !activePlayer.isPlaying
	}

	function nextTrack() {
		if (activePlayer && activePlayer.canGoNext) activePlayer.next()
	}

	function prevTrack() {
		if (activePlayer && activePlayer.canGoPrevious) activePlayer.previous()
	}

	// ------------------------------------------------------------- workspaces

	readonly property var workspaceIds: {
		const active = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0
		const ids = []
		const list = Hyprland.workspaces ? Hyprland.workspaces.values : []
		for (let i = 0; i < list.length; i++) {
			const id = list[i].id
			if (id > 0 && ids.indexOf(id) === -1) ids.push(id)
		}
		if (active > 0 && ids.indexOf(active) === -1) ids.push(active)
		ids.sort((a, b) => a - b)
		return ids
	}

	function focusWorkspace(id) {
		Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })")
	}

	function stepWorkspace(delta) {
		const current = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
		const next = delta > 0
			? (current <= 1 ? 10 : current - 1)
			: (current >= 10 ? 1 : current + 1)
		focusWorkspace(next)
	}

	// -------------------------------------------------------------- window

	readonly property var activeToplevel: ToplevelManager.activeToplevel
	readonly property string activeWindowTitle: activeToplevel ? (activeToplevel.title || "") : ""
	readonly property string activeAppId: activeToplevel ? (activeToplevel.appId || "") : ""
	readonly property string activeAppIcon: root.activeAppId !== ""
		? (Quickshell.iconPath(root.activeAppId, true) || "")
		: ""

	// -------------------------------------------------------------- network

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

	Process {
		id: wifiProc
		command: ["sh", "-c", "eth=$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2==\"ethernet\" && $3==\"connected\"{print $1; exit}'); if [ -n \"$eth\" ]; then econn=$(nmcli -t -f GENERAL.CONNECTION device show \"$eth\" 2>/dev/null | cut -d: -f2); echo \"ethernet|$econn|0\"; else dev=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2==\"wifi\"{print $1; exit}'); conn=$(nmcli -t -f GENERAL.CONNECTION device show \"$dev\" 2>/dev/null | cut -d: -f2); ssid=$(nmcli -t -f 802-11-wireless.ssid connection show \"$conn\" 2>/dev/null | cut -d: -f2); q=$(awk -v ifc=\"$dev:\" '$1==ifc{gsub(\"\\\\.\",\"\",$4); print $4}' /proc/net/wireless); echo \"wifi|$ssid|$q\"; fi"]
		stdout: SplitParser {
			onRead: data => {
				if (!data) return
				const parts = data.split("|")
				networkType = parts[0] || "offline"
				const label = parts[1] ? parts[1].trim() : ""
				if (networkType === "ethernet") {
					wifiSSID = label ? label : "Wired"
					wifiSignal = 100
				} else if (networkType === "wifi") {
					wifiSSID = label ? label : "Offline"
					const dbm = parseInt(parts[2]) || 0
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
		interval: 10000
		running: true
		repeat: true
		onTriggered: wifiProc.running = true
	}

	// ---------------------------------------------------------------- layout

	Variants {
		model: Quickshell.screens

		PanelWindow {
			id: barWindow
			required property var modelData
			property bool volumeOpen: false
			property bool calendarOpen: false
			property bool networkOpen: false
			screen: modelData

			anchors {
				top: true
				left: true
				right: true
			}

			implicitHeight: Config.bar.height + Config.bar.margin * 2
			color: "transparent"

			BarSegment {
				anchors.fill: parent
				anchors.margins: Config.bar.margin
				interactive: false

				RowLayout {
					id: barRow
					anchors.fill: parent
					anchors.leftMargin: 6
					anchors.rightMargin: 6
					spacing: 4

					// ----------------------------------------------- workspaces

					Item {
						id: wsWrap
						Layout.preferredWidth: wsRow.implicitWidth + 10
						Layout.fillHeight: true

						RowLayout {
							id: wsRow
							anchors.centerIn: parent
							spacing: 4

							Repeater {
								model: root.workspaceIds

								Rectangle {
									id: wsPill
									required property var modelData
									readonly property bool isActive: Hyprland.focusedWorkspace
										? Hyprland.focusedWorkspace.id === modelData
										: false

									Layout.preferredWidth: isActive ? Math.max(28, wsLabel.implicitWidth + 16) : 28
									Layout.preferredHeight: 26
									radius: height / 2
									color: isActive
										? Config.colors.accent
										: wsHover.containsMouse
											? Config.colors.surfaceAlt
											: Config.colors.surface
									border.width: 1
									border.color: isActive ? Config.colors.accent : Config.colors.borderMuted

									Behavior on color { ColorAnimation { duration: Config.motion.fast } }
									Behavior on Layout.preferredWidth { NumberAnimation { duration: Config.motion.normal; easing.type: Easing.OutCubic } }

									Text {
										id: wsLabel
										anchors.centerIn: parent
										text: wsPill.modelData
										color: wsPill.isActive ? Config.colors.onAccent : Config.colors.textMuted
										font.family: Config.bar.fontFamily
										font.pixelSize: Config.bar.fontSize - 2
										font.weight: wsPill.isActive ? 700 : 500
									}

									MouseArea {
										id: wsHover
										anchors.fill: parent
										hoverEnabled: true
										cursorShape: Qt.PointingHandCursor
										onClicked: root.focusWorkspace(wsPill.modelData)
									}
								}
							}
						}

						MouseArea {
							anchors.fill: parent
							acceptedButtons: Qt.NoButton
							onWheel: (wheel) => {
								root.stepWorkspace(wheel.angleDelta.y)
								wheel.accepted = true
							}
						}
					}

					Rectangle {
						Layout.alignment: Qt.AlignVCenter
						Layout.preferredWidth: 1
						Layout.preferredHeight: 18
						color: Config.colors.borderMuted
					}

					// --------------------------------------------------- title

					Item {
						Layout.fillWidth: true
						Layout.fillHeight: true

						RowLayout {
							anchors.fill: parent
							anchors.leftMargin: 8
							anchors.rightMargin: 8
							spacing: 8

							Image {
								Layout.preferredWidth: 18
								Layout.preferredHeight: 18
								Layout.alignment: Qt.AlignVCenter
								visible: root.activeAppIcon !== ""
								source: root.activeAppIcon
								fillMode: Image.PreserveAspectFit
								smooth: true
								asynchronous: true
							}

							Text {
								Layout.fillWidth: true
								Layout.alignment: Qt.AlignVCenter
								text: root.activeWindowTitle || "Desktop"
								color: root.activeWindowTitle !== "" ? Config.colors.textMuted : Config.colors.textDim
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 1
								font.weight: 500
								elide: Text.ElideRight
							}
						}
					}

					// --------------------------------------------------- media

					Rectangle {
						id: mediaChip
						visible: root.activePlayer !== null
						Layout.alignment: Qt.AlignVCenter
						Layout.preferredWidth: Math.min(250, mediaRow.implicitWidth + 20)
						Layout.preferredHeight: 30
						radius: Config.radius.small
						color: mediaMouse.containsMouse ? Config.colors.surface : "transparent"

						Behavior on color { ColorAnimation { duration: Config.motion.fast } }

						RowLayout {
							id: mediaRow
							anchors.fill: parent
							anchors.leftMargin: 8
							anchors.rightMargin: 8
							spacing: 6

							Text {
								text: root.playerIcon()
								color: mediaMouse.containsMouse ? Config.colors.accent : Config.colors.accent2
								font.family: Config.bar.iconFontFamily
								font.pixelSize: Config.bar.fontSize - 1
								Behavior on color { ColorAnimation { duration: Config.motion.fast } }
							}

							Text {
								Layout.fillWidth: true
								text: root.playerLabel()
								color: mediaMouse.containsMouse ? Config.colors.text : Config.colors.textMuted
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 2
								elide: Text.ElideRight
								Behavior on color { ColorAnimation { duration: Config.motion.fast } }
							}
						}

						MouseArea {
							id: mediaMouse
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor

							onClicked: root.togglePlayback()
							onWheel: (wheel) => {
								if (wheel.angleDelta.y > 0) root.nextTrack()
								else root.prevTrack()
								wheel.accepted = true
							}
						}
					}

					// ----------------------------------------------------- tray

					RowLayout {
						id: trayRow
						visible: SystemTray.items.values.length > 0
						Layout.alignment: Qt.AlignVCenter
						spacing: 2
						property var openMenu: null

						Repeater {
							model: SystemTray.items

							Item {
								id: trayItem
								required property var modelData
								Layout.preferredWidth: 26
								Layout.preferredHeight: 26

								function openTrayMenu() {
									if (!trayItem.modelData || !trayItem.modelData.hasMenu) return
									if (trayRow.openMenu && trayRow.openMenu !== trayMenu)
										trayRow.openMenu.close()
									const pos = trayItem.mapToItem(barWindow.contentItem, 0, 0)
									trayMenu.anchor.rect.x = pos.x
									trayMenu.anchor.rect.y = pos.y
									trayMenu.anchor.rect.width = trayItem.width
									trayMenu.anchor.rect.height = trayItem.height
									trayMenu.open()
									trayRow.openMenu = trayMenu
								}

								Rectangle {
									anchors.fill: parent
									radius: Config.radius.small
									color: trayHover.containsMouse ? Config.colors.surface : "transparent"

									Image {
										anchors.fill: parent
										anchors.margins: 5
										source: trayItem.modelData.icon
										fillMode: Image.PreserveAspectFit
										smooth: true
										asynchronous: true
									}
								}

								QsMenuAnchor {
									id: trayMenu
									menu: trayItem.modelData ? trayItem.modelData.menu : null
									anchor.window: barWindow
									anchor.edges: Edges.Bottom | Edges.Left
									anchor.gravity: Edges.Bottom | Edges.Left

									onClosed: if (trayRow.openMenu === trayMenu) trayRow.openMenu = null
								}

								MouseArea {
									anchors.fill: parent
									hoverEnabled: true
									acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
									cursorShape: Qt.PointingHandCursor

									onClicked: (mouse) => {
										if (mouse.button === Qt.RightButton) {
											if (trayRow.openMenu) {
												trayRow.openMenu.close()
												trayRow.openMenu = null
											}
											return
										}

										if (mouse.button === Qt.MiddleButton) {
											trayItem.modelData.secondaryActivate()
											return
										}

										if (trayItem.modelData.hasMenu) trayItem.openTrayMenu()
										else trayItem.modelData.activate()
									}

									onWheel: (wheel) => {
										trayItem.modelData.scroll(wheel.angleDelta.y, false)
										wheel.accepted = true
									}
								}
							}
						}
					}

					Rectangle {
						Layout.alignment: Qt.AlignVCenter
						Layout.preferredWidth: 1
						Layout.preferredHeight: 18
						color: Config.colors.borderMuted
						visible: SystemTray.items.values.length > 0
					}

					// ---------------------------------------------------- stats

					IconButton {
						Layout.alignment: Qt.AlignVCenter
						icon: "\uf2db"
						showLabel: true
						label: root.cpuUsage + "%"
						labelSize: Config.bar.fontSize - 2
						iconColor: root.usageColor(root.cpuUsage)
						iconSize: Config.bar.fontSize
						onClicked: { root.closePopups(barWindow); root.ipcCall("controlcenter", "show") }
					}

					IconButton {
						Layout.alignment: Qt.AlignVCenter
						icon: "\uf1c0"
						showLabel: true
						label: root.memUsage + "%"
						labelSize: Config.bar.fontSize - 2
						iconColor: root.usageColor(root.memUsage)
						iconSize: Config.bar.fontSize
						onClicked: { root.closePopups(barWindow); root.ipcCall("controlcenter", "show") }
					}

					// --------------------------------------------------- volume

					IconButton {
						id: volumeButton
						Layout.alignment: Qt.AlignVCenter
						icon: root.volumeMuted ? "\uf026" : "\uf028"
						showLabel: true
						label: root.volumeMuted ? "mute" : root.volumeLevel + "%"
						labelSize: Config.bar.fontSize - 2
						iconColor: root.volumeMuted ? Config.colors.textDim : Config.colors.accent
						iconSize: Config.bar.fontSize
						active: root.volumeMuted
						activeColor: Config.colors.textDim
						onClicked: {
							barWindow.calendarOpen = false
							barWindow.networkOpen = false
							barWindow.volumeOpen = !barWindow.volumeOpen
						}
						onMiddleClicked: root.toggleVolumeMute()
						onWheeled: (delta) => root.changeVolume(delta > 0 ? 0.05 : -0.05)
					}

					// -------------------------------------------------- network

					IconButton {
						id: networkButton
						Layout.alignment: Qt.AlignVCenter
						icon: root.wifiIcon()
						iconColor: root.networkType === "offline" ? Config.colors.textDim : Config.colors.accent2
						iconSize: Config.bar.fontSize
						onClicked: {
							barWindow.volumeOpen = false
							barWindow.calendarOpen = false
							barWindow.networkOpen = !barWindow.networkOpen
						}
					}

					// --------------------------------------------------- battery

					IconButton {
						visible: root.batteryPresent
						Layout.alignment: Qt.AlignVCenter
						icon: root.batteryIcon()
						showLabel: true
						label: root.batteryLevel + "%"
						labelSize: Config.bar.fontSize - 2
						iconColor: root.batteryColor()
						iconSize: Config.bar.fontSize
						danger: root.batteryLevel <= 15
						onClicked: { root.closePopups(barWindow); root.ipcCall("controlcenter", "show") }
					}

					// ----------------------------------------------------- clock

					Rectangle {
						id: clockButton
						Layout.alignment: Qt.AlignVCenter
						Layout.preferredWidth: clockColumn.implicitWidth + 18
						Layout.preferredHeight: 32
						radius: Config.radius.small
						color: clockMouse.containsMouse ? Config.colors.surface : "transparent"

						Behavior on color { ColorAnimation { duration: Config.motion.fast } }

						ColumnLayout {
							id: clockColumn
							anchors.centerIn: parent
							spacing: 0

							Text {
								id: clockTime
								Layout.alignment: Qt.AlignHCenter
								text: Qt.formatDateTime(new Date(), "HH:mm")
								color: Config.colors.text
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize
								font.weight: 700
							}

							Text {
								id: clockDate
								Layout.alignment: Qt.AlignHCenter
								text: Qt.formatDateTime(new Date(), "ddd dd MMM")
								color: Config.colors.textDim
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 5
								font.weight: 500
							}
						}

						Timer {
							interval: 1000
							running: true
							repeat: true
							onTriggered: {
								clockTime.text = Qt.formatDateTime(new Date(), "HH:mm")
								clockDate.text = Qt.formatDateTime(new Date(), "ddd dd MMM")
							}
						}

						MouseArea {
							id: clockMouse
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: {
								barWindow.volumeOpen = false
								barWindow.networkOpen = false
								barWindow.calendarOpen = !barWindow.calendarOpen
							}
						}
					}

					// ---------------------------------------------- quick actions

					IconButton {
						Layout.alignment: Qt.AlignVCenter
						icon: "\uf0f3"
						iconColor: Config.colors.textMuted
						iconSize: Config.bar.fontSize
						onClicked: { root.closePopups(barWindow); root.ipcCall("notifications", "toggle") }
					}

					IconButton {
						Layout.alignment: Qt.AlignVCenter
						icon: "\uf1de"
						iconColor: Config.colors.accent
						iconSize: Config.bar.fontSize
						onClicked: { root.closePopups(barWindow); root.ipcCall("controlcenter", "toggle") }
					}

					IconButton {
						Layout.alignment: Qt.AlignVCenter
						icon: "\uf011"
						iconColor: Config.colors.textMuted
						iconSize: Config.bar.fontSize
						danger: true
						onClicked: { root.closePopups(barWindow); root.ipcCall("powermenu", "toggle") }
					}
				}
			}

			VolumePopup {
				parentPanel: barWindow
				anchorItem: volumeButton
				visible: barWindow.volumeOpen
				value: root.volumeLevel
				muted: root.volumeMuted

				onVolumeChanged: (value) => root.setVolumePercent(value)
				onMuteToggled: root.toggleVolumeMute()
			}

			CalendarPopup {
				parentPanel: barWindow
				anchorItem: clockButton
				visible: barWindow.calendarOpen
			}

			NetworkPopup {
				parentPanel: barWindow
				anchorItem: networkButton
				visible: barWindow.networkOpen
				activeSsid: root.wifiSSID
				networkType: root.networkType
				activeSignal: root.wifiSignal
			}
		}
	}
}
