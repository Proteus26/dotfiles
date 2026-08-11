import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts

import "config.js" as Config

Scope {
	id: root

	property bool menuOpen: false
	property int currentIndex: 0

	function close() { root.menuOpen = false }

	onMenuOpenChanged: if (root.menuOpen) root.currentIndex = 0

	property var actions: [
		{ icon: "\uf023", label: "Lock",     accentColor: Config.colors.accent2,   confirm: false, run: function() { lockProc.running = true } },
		{ icon: "\uf2f5", label: "Logout",   accentColor: Config.colors.accent,    confirm: false, run: function() { logoutProc.running = true } },
		{ icon: "\uf186", label: "Suspend",  accentColor: Config.colors.textMuted, confirm: false, run: function() { suspendProc.running = true } },
		{ icon: "\uf021", label: "Reboot",   accentColor: Config.colors.warn,      confirm: true,  run: function() { rebootProc.running = true } },
		{ icon: "\uf011", label: "Shutdown", accentColor: Config.colors.bad,       confirm: true,  run: function() { poweroffProc.running = true } }
	]

	IpcHandler {
		target: "powermenu"

		function toggle() : void {
			root.menuOpen = !root.menuOpen
		}

		function show() : void {
			root.menuOpen = true
		}

		function hide() : void {
			root.menuOpen = false
		}
	}

	Process { id: lockProc;     command: ["loginctl", "lock-session"] }
	Process { id: suspendProc;  command: ["systemctl", "suspend"] }
	Process { id: logoutProc;   command: ["hyprctl", "dispatch", "exit"] }
	Process { id: rebootProc;   command: ["systemctl", "reboot"] }
	Process { id: poweroffProc; command: ["systemctl", "poweroff"] }

	Variants {
		model: Quickshell.screens

		PanelWindow {
			required property var modelData
			screen: modelData

			readonly property var monitor: Hyprland.monitorFor(modelData)
			readonly property bool isFocusedMonitor: monitor?.name === Hyprland.focusedMonitor?.name

			visible: root.menuOpen && isFocusedMonitor
			color: "transparent"

			WlrLayershell.layer: WlrLayer.Overlay
			WlrLayershell.namespace: "powermenu"
			WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

			anchors {
				top: true
				left: true
				right: true
				bottom: true
			}

			onVisibleChanged: {
				if (visible) keyHandler.forceActiveFocus()
			}

			Rectangle {
				anchors.fill: parent
				color: Qt.rgba(0, 0, 0, 0.55)

				MouseArea {
					anchors.fill: parent
					onClicked: root.close()
				}
			}

			Item {
				id: keyHandler
				anchors.fill: parent

				Keys.onEscapePressed: root.close()
				Keys.onLeftPressed: root.currentIndex = (root.currentIndex + root.actions.length - 1) % root.actions.length
				Keys.onRightPressed: root.currentIndex = (root.currentIndex + 1) % root.actions.length
				Keys.onReturnPressed: {
					const btn = buttonRepeater.itemAt(root.currentIndex)
					if (btn) btn.activate()
				}
				Keys.onEnterPressed: {
					const btn = buttonRepeater.itemAt(root.currentIndex)
					if (btn) btn.activate()
				}
			}

			Rectangle {
				id: card
				anchors.centerIn: parent
				width: cardColumn.implicitWidth + Config.panel.padding * 2
				height: cardColumn.implicitHeight + Config.panel.padding * 2
				radius: Config.radius.large
				color: Config.colors.base
				border.width: 1
				border.color: Config.colors.border

				MouseArea { anchors.fill: parent; onClicked: {} }

				ColumnLayout {
					id: cardColumn
					anchors.centerIn: parent
					spacing: 10

					RowLayout {
						Layout.fillWidth: true
						spacing: 8

						Rectangle {
							Layout.preferredWidth: 8
							Layout.preferredHeight: 8
							radius: 4
							color: Config.colors.accent
						}

						Text {
							Layout.fillWidth: true
							text: "power"
							color: Config.colors.text
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize
							font.bold: true
						}
					}

					RowLayout {
						id: buttonRow
						spacing: 14

						Repeater {
							id: buttonRepeater
							model: root.actions

							PowerButton {
								required property var modelData
								required property int index

								icon: modelData.icon
								label: modelData.label
								accentColor: modelData.accentColor
								confirm: modelData.confirm
								focused: index === root.currentIndex

								onActivated: { root.close(); modelData.run() }
							}
						}
					}

					Rectangle {
						Layout.fillWidth: true
						Layout.preferredHeight: 1
						color: Config.colors.border
					}

					Text {
						Layout.fillWidth: true
						text: "\u2190\u2192 navigate  \u23ce select  \u238b close"
						color: Config.colors.textDim
						font.family: Config.bar.fontFamily
						font.pixelSize: Config.bar.fontSize - 2
						elide: Text.ElideRight
					}
				}
			}
		}
	}
}
