import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

import "config.js" as Config

Scope {
	id: root

	//sysinfo properties
	property int cpuUsage: 0
	property int memUsage: 0
	property int diskUsage: 0
	property int volumeLevel: 0
	property string activeWindow: "Window"
	property var lastCpuIdle: 0
	property var lastCpuTotal: 0
	property int batteryLevel: 100
	property string batteryStatus: "Unknown"
	property string wifiSSID: ""
	property int wifiSignal: 0
	property string networkType: "offline"
	property string playerStatus: ""
	property string playerArtist: ""
	property string playerTitle: ""

	function batteryIcon() {
		if (batteryStatus === "Charging") return "\uf0e7"
		if (batteryLevel >= 90) return "\uf240"
		if (batteryLevel >= 60) return "\uf241"
		if (batteryLevel >= 40) return "\uf242"
		if (batteryLevel >= 10) return "\uf243"
		return "\uf244"
	}

	function playerIcon() {
		return playerStatus === "Playing" ? "\uf04c" : "\uf04b"
	}

	function wifiIcon() {
		if (networkType === "ethernet") return "\udb80\ude00"
		if (networkType !== "wifi" || wifiSSID === "" || wifiSSID === "Offline") return "\udb82\udd2d"
		if (wifiSignal >= 80) return "\udb82\udd28"
		if (wifiSignal >= 55) return "\udb82\udd25"
		if (wifiSignal >= 30) return "\udb82\udd22"
		return "\udb82\udd1f"
	}

	function playerLabel() {
		if (playerStatus === "") return "No media"
		if (playerArtist && playerTitle) return playerArtist + " - " + playerTitle
		return playerTitle || playerArtist || "No media"
	}

	//cpu usage
	Process {
		id: cpuProc
		command: ["sh", "-c", "head -1 /proc/stat"]
		stdout: SplitParser {
			onRead: data => {
				if (!data) return
				var parts = data.trim().split(/\s+/)
				var user = parseInt(parts[1]) || 0
				var nice = parseInt(parts[2]) || 0
				var system = parseInt(parts[3]) || 0
				var idle = parseInt(parts[4]) || 0
				var iowait = parseInt(parts[5]) || 0
				var irq = parseInt(parts[6]) || 0
				var softirq = parseInt(parts[7]) || 0

				var total = user + nice + system + idle + iowait + irq + softirq
				var idleTime = idle + iowait

				if (lastCpuTotal > 0) {
					var totalDiff = total - lastCpuTotal
					var idleDiff = idleTime - lastCpuIdle
					if (totalDiff > 0) {
						cpuUsage = Math.round(100 * (totalDiff - idleDiff) / totalDiff)
					}
				}
				lastCpuTotal = total
				lastCpuIdle = idleTime
			}
		}
		Component.onCompleted: running = true
	}

	//mem usage
	Process {
		id: memProc
		command: ["sh", "-c", "free | grep Mem"]
		stdout: SplitParser {
			onRead: data => {
				if (!data) return
				var parts = data.trim().split(/\s+/)
				var total = parseInt(parts[1]) || 1
				var used = parseInt(parts[2]) || 0
				memUsage = Math.round(100 * used / total)
			}
		}
		Component.onCompleted: running = true
	}

	//disk usage
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

	//volume level
	Process {
		id: volProc
		command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
		stdout: SplitParser {
			onRead: data => {
				if (!data) return
				var match = data.match(/Volume:\s*([\d.]+)/)
				if (match) {
					volumeLevel = Math.round(parseFloat(match[1]) * 100)
				}
			}
		}
		Component.onCompleted: running = true
	}

	//battery level + charging status
	Process {
		id: battProc
		command: ["sh", "-c", "cap=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1); st=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1); echo \"$cap $st\""]
		stdout: SplitParser {
			onRead: data => {
				if (!data) return
				var parts = data.trim().split(/\s+/)
				batteryLevel = parseInt(parts[0]) || 0
				batteryStatus = parts[1] || "Unknown"
			}
		}
		Component.onCompleted: running = true
	}

	//network: ethernet (priority) or wifi ssid + signal strength
	Process {
		id: wifiProc
		command: ["sh", "-c", "eth=$(nmcli -t -f DEVICE,TYPE,STATE device status | awk -F: '$2==\"ethernet\" && $3==\"connected\"{print $1; exit}'); if [ -n \"$eth\" ]; then econn=$(nmcli -t -f GENERAL.CONNECTION device show \"$eth\" 2>/dev/null | cut -d: -f2); echo \"ethernet|$econn|0\"; else dev=$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2==\"wifi\"{print $1; exit}'); conn=$(nmcli -t -f GENERAL.CONNECTION device show \"$dev\" 2>/dev/null | cut -d: -f2); ssid=$(nmcli -t -f 802-11-wireless.ssid connection show \"$conn\" 2>/dev/null | cut -d: -f2); q=$(awk -v ifc=\"$dev:\" '$1==ifc{gsub(\"\\\\.\",\"\",$3); print $3}' /proc/net/wireless); echo \"wifi|$ssid|$q\"; fi"]
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
					var quality = parseInt(parts[2]) || 0
					wifiSignal = Math.min(100, Math.round(quality / 70 * 100))
				} else {
					wifiSSID = "Offline"
					wifiSignal = 0
				}
			}
		}
		Component.onCompleted: running = true
	}

	//playerctl metadata
	Process {
		id: playerProc
		command: ["sh", "-c", "st=$(playerctl status 2>/dev/null); ar=$(playerctl metadata artist 2>/dev/null); ti=$(playerctl metadata title 2>/dev/null); echo \"$st|$ar|$ti\""]
		stdout: SplitParser {
			onRead: data => {
				if (!data) return
				var parts = data.split("|")
				playerStatus = parts[0] || ""
				playerArtist = parts[1] || ""
				playerTitle = parts[2] || ""
			}
		}
		Component.onCompleted: running = true
	}

	Process {
		id: playPauseProc
		command: ["playerctl", "play-pause"]
		onExited: playerProc.running = true
	}

	Process {
		id: nextTrackProc
		command: ["playerctl", "next"]
		onExited: playerProc.running = true
	}

	Process {
		id: prevTrackProc
		command: ["playerctl", "previous"]
		onExited: playerProc.running = true
	}

	Timer {
		interval: 1000
		running: true
		repeat: true
		onTriggered: playerProc.running = true
	}

	//window title
	Process {
		id: windowProc
		command: ["sh", "-c", "hyprctl activewindow -j | jq -r '.title // empty'"]
		stdout: SplitParser {
			onRead: data => {
				if (data && data.trim()) {
					activeWindow = data.trim()
				}
			}
		}
		Component.onCompleted: running = true
	}

	//system stat timers
	Timer {
		interval: 2000
		running: true
		repeat: true
		onTriggered: {
			cpuProc.running = true
			memProc.running = true
			diskProc.running = true
			volProc.running = true
			battProc.running = true
			wifiProc.running = true
		}
	}

	//event based update for window
	Connections {
		target: Hyprland
		function onRawEvent(event) {
			windowProc.running = true
		}
	}

	//backup for window
	Timer {
		interval: 200
		running: true
		repeat: true
		onTriggered: {
			windowProc.running = true
		}
	}

	//layout from here onwards
	Variants {
		model: Quickshell.screens

		PanelWindow {
			property var modelData
			screen: modelData

			anchors {
				top: true
				left: true
				right: true
			}

			implicitHeight: 30
			color: Config.colors.base

			margins {
				top: 0
				bottom: 0
				left: 0
				right: 0
			}

			Rectangle {
				anchors.fill: parent
				color: Config.colors.base

				RowLayout {
					anchors.fill: parent
					spacing: 0

					Item { width: 4 }

					Repeater {
						model: 10 

						Rectangle {
							Layout.preferredWidth: 20
							Layout.preferredHeight: parent.height
							color: "transparent"

							property var workspace: Hyprland.workspaces.values.find(ws => ws.id === index + 1) ?? null
							property bool isActive: Hyprland.focusedWorkspace?.id === (index + 1)
							property bool hasWindows: workspace !== null

							Text {
								text: index === 9 ? "0" : index + 1
								color: parent.isActive ? Config.colors.sapphire : (parent.hasWindows ? Config.colors.sapphire : Config.colors.subtext0)
								font.pixelSize: Config.bar.fontSize
								font.family: Config.bar.fontFamily
								font.bold: true
								anchors.centerIn: parent
							}

							Rectangle {
								width: 20
								height: 2
								color: parent.isActive ? Config.colors.mauve : ""
								anchors.horizontalCenter: parent.horizontalCenter
								anchors.bottom: parent.bottom
							}

							MouseArea {
								anchors.fill: parent
								onClicked: Hyprland.dispatch("workspace " + (index + 1))
							}
						}
					}

					Rectangle {
						Layout.preferredWidth: 1
						Layout.preferredHeight: 16
						Layout.alignment: Qt.AlignVCenter
						Layout.leftMargin: 4
						Layout.rightMargin: 4
						color: Config.colors.overlay0
					}

					Text {
						text: activeWindow
						color: Config.colors.mauve
						font.pixelSize: Config.bar.fontSize
						font.family: Config.bar.fontFamily
						font.bold: true
						Layout.maximumWidth: 320
						Layout.leftMargin: 8
						elide: Text.ElideRight
						maximumLineCount: 1
					}

					// Expanding spacer to push right-side modules
					Item { Layout.fillWidth: true }

					Text {
						text: "  " + cpuUsage + "%"
						color: Config.colors.yellow
						font.pixelSize: Config.bar.fontSize
						font.family: Config.bar.fontFamily
						font.bold: true
					}

					Rectangle {
						Layout.preferredWidth: 1
						Layout.preferredHeight: 16
						Layout.alignment: Qt.AlignVCenter
						Layout.leftMargin: 8
						Layout.rightMargin: 8
						color: Config.colors.overlay0
					}

					Text {
						text: "  " + memUsage + "%"
						color: Config.colors.peach
						font.pixelSize: Config.bar.fontSize
						font.family: Config.bar.fontFamily
						font.bold: true
					}

					Rectangle {
						Layout.preferredWidth: 1
						Layout.preferredHeight: 16
						Layout.alignment: Qt.AlignVCenter
						Layout.leftMargin: 8
						Layout.rightMargin: 8
						color: Config.colors.overlay0
					}

					Text {
						text: "  " + diskUsage + "%"
						color: Config.colors.blue
						font.pixelSize: Config.bar.fontSize
						font.family: Config.bar.fontFamily
						font.bold: true
					}

					Rectangle {
						Layout.preferredWidth: 1
						Layout.preferredHeight: 16
						Layout.alignment: Qt.AlignVCenter
						Layout.leftMargin: 8
						Layout.rightMargin: 8
						color: Config.colors.overlay0
					}

					Text {
						text: "  " + volumeLevel + "%"
						color: Config.colors.mauve
						font.pixelSize: Config.bar.fontSize
						font.family: Config.bar.fontFamily
						font.bold: true
					}

					Rectangle {
						Layout.preferredWidth: 1
						Layout.preferredHeight: 16
						Layout.alignment: Qt.AlignVCenter
						Layout.leftMargin: 8
						Layout.rightMargin: 8
						color: Config.colors.overlay0
					}

					Text {
						text: root.batteryIcon() + "  " + batteryLevel + "%"
						color: Config.colors.green
						font.pixelSize: Config.bar.fontSize
						font.family: Config.bar.fontFamily
						font.bold: true
					}

					Rectangle {
						Layout.preferredWidth: 1
						Layout.preferredHeight: 16
						Layout.alignment: Qt.AlignVCenter
						Layout.leftMargin: 8
						Layout.rightMargin: 8
						color: Config.colors.overlay0
					}

					Text {
						text: root.wifiIcon() + "  " + wifiSSID
						color: Config.colors.teal
						font.pixelSize: Config.bar.fontSize
						font.family: Config.bar.fontFamily
						font.bold: true
						elide: Text.ElideRight
						Layout.maximumWidth: 160
					}

					Rectangle {
						Layout.preferredWidth: 1
						Layout.preferredHeight: 16
						Layout.alignment: Qt.AlignVCenter
						Layout.leftMargin: 8
						Layout.rightMargin: 8
						color: Config.colors.overlay0
					}

					Text {
						id: clockText
						text: Qt.formatDateTime(new Date(), "ddd, MMM dd - HH:mm")
						color: Config.colors.sapphire
						font.pixelSize: Config.bar.fontSize
						font.family: Config.bar.fontFamily
						font.bold: true
						Layout.rightMargin: 4

						Timer {
							interval: 1000
							running: true
							repeat: true
							onTriggered: clockText.text = Qt.formatDateTime(new Date(), "ddd, MMM dd - HH:mm")
						}
					}

					Item { width: 4 }
				}

				RowLayout {
					id: playerRow
					anchors.centerIn: parent
					spacing: 6

					Text {
						text: root.playerIcon()
						color: Config.colors.sky
						font.pixelSize: Config.bar.fontSize
						font.family: Config.bar.fontFamily
						font.bold: true
						Layout.rightMargin: 3
					}

					Text {
						text: root.playerLabel()
						color: Config.colors.sky
						font.pixelSize: Config.bar.fontSize
						font.family: Config.bar.fontFamily
						font.bold: true
						elide: Text.ElideRight
						Layout.maximumWidth: 260
					}
				}

				Rectangle {
					width: playerRow.width
					height: 2
					color: Config.colors.sky
					anchors.horizontalCenter: playerRow.horizontalCenter
					anchors.top: playerRow.bottom
					anchors.topMargin: 4
				}

				MouseArea {
					anchors.fill: playerRow
					anchors.margins: -6
					acceptedButtons: Qt.LeftButton
					onClicked: playPauseProc.running = true
					onWheel: (wheel) => {
						if (wheel.angleDelta.y > 0) {
							nextTrackProc.running = true
						} else {
							prevTrackProc.running = true
						}
						wheel.accepted = true
					}
				}
			}
		}
	}
}
