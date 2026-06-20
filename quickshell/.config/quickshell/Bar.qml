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

					Rectangle {
						Layout.preferredWidth: 24
						Layout.preferredHeight: 24
						color: "transparent"

						Image {
							anchors.fill: parent
							source: "file:///home/proteus/Pictures/pokeball.png"
							fillMode: Image.PreserveAspectFit
						}
					}

					Item { width: 4 }

					Repeater {
						model: 9

						Rectangle {
							Layout.preferredWidth: 20
							Layout.preferredHeight: parent.height
							color: "transparent"

							property var workspace: Hyprland.workspaces.values.find(ws => ws.id === index + 1) ?? null
							property bool isActive: Hyprland.focusedWorkspace?.id === (index + 1)
							property bool hasWindows: workspace !== null

							Text {
								text: index + 1
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
						Layout.fillWidth: true
						Layout.leftMargin: 8
						elide: Text.ElideRight
						maximumLineCount: 1
					}

					Text {
						text: "  " + cpuUsage + "%"
						color: Config.colors.yellow
						font.pixelSize: Config.bar.fontSize
						font.family: Config.bar.fontFamily
						font.bold: true
						Layout.rightMargin: 8
					}

					Rectangle {
						Layout.preferredWidth: 1
						Layout.preferredHeight: 16
						Layout.alignment: Qt.AlignVCenter
						Layout.leftMargin: 2
						Layout.rightMargin: 10
						color: Config.colors.overlay0
					}

					Text {
						text: "  " + memUsage + "%"
						color: Config.colors.peach
						font.pixelSize: Config.bar.fontSize
						font.family: Config.bar.fontFamily
						font.bold: true
						Layout.rightMargin: 8
					}

					Rectangle {
						Layout.preferredWidth: 1
						Layout.preferredHeight: 16
						Layout.alignment: Qt.AlignVCenter
						Layout.leftMargin: 0
						Layout.rightMargin: 10
						color: Config.colors.overlay0
					}

					Text {
						text: "  " + diskUsage + "%"
						color: Config.colors.blue
						font.pixelSize: Config.bar.fontSize
						font.family: Config.bar.fontFamily
						font.bold: true
						Layout.rightMargin: 8
					}

					Rectangle {
						Layout.preferredWidth: 1
						Layout.preferredHeight: 16
						Layout.alignment: Qt.AlignVCenter
						Layout.leftMargin: 0
						Layout.rightMargin: 8
						color: Config.colors.overlay0
					}

					Text {
						text: "  " + volumeLevel + "%"
						color: Config.colors.mauve
						font.pixelSize: Config.bar.fontSize
						font.family: Config.bar.fontFamily
						font.bold: true
						Layout.rightMargin: 8
					}

					Rectangle {
						Layout.preferredWidth: 1
						Layout.preferredHeight: 16
						Layout.alignment: Qt.AlignVCenter
						Layout.leftMargin: 0
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
						Layout.rightMargin: 8

						Timer {
							interval: 1000
							running: true
							repeat: true
							onTriggered: clockText.text = Qt.formatDateTime(new Date(), "ddd, MMM dd - HH:mm")
						}
					}

					Item { width: 4 }
				}
			}
		}
	}
}
