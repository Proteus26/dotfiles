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

	property var actions: [
		{ icon: "\uf023", label: "Lock",     accentColor: Config.colors.accent2,   confirm: false, run: function() { lockProc.running = true } },
		{ icon: "\uf2f5", label: "Logout",   accentColor: Config.colors.accent,    confirm: false, run: function() { logoutProc.running = true } },
		{ icon: "\uf186", label: "Suspend",  accentColor: Config.colors.textMuted, confirm: false, run: function() { suspendProc.running = true } },
		{ icon: "\uf021", label: "Reboot",   accentColor: Config.colors.warn,      confirm: true,  run: function() { rebootProc.running = true } },
		{ icon: "\uf011", label: "Shutdown", accentColor: Config.colors.bad,       confirm: true,  run: function() { poweroffProc.running = true } }
	]

	IpcHandler {
		target: "powermenu"

		function toggle(): void {
			if (!root.menuOpen) root.closeOtherPanels()
			root.menuOpen = !root.menuOpen
		}

		function show(): void {
			root.closeOtherPanels()
			root.menuOpen = true
		}

		function hide(): void {
			root.menuOpen = false
		}
	}

	function close() { root.menuOpen = false }

	function ipcCall(target, fn) {
		Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", target, fn])
	}

	function closeOtherPanels() {
		root.ipcCall("launcher", "hide")
		root.ipcCall("clipboard", "hide")
		root.ipcCall("notifications", "hide")
		root.ipcCall("controlcenter", "hide")
	}

	onMenuOpenChanged: if (root.menuOpen) root.currentIndex = 0

	Process { id: lockProc;     command: ["loginctl", "lock-session"] }
	Process { id: suspendProc;  command: ["systemctl", "suspend"] }
	Process { id: logoutProc;   command: ["hyprctl", "dispatch", "hl.dsp.exit()"] }
	Process { id: rebootProc;   command: ["systemctl", "reboot"] }
	Process { id: poweroffProc; command: ["systemctl", "poweroff"] }

	Variants {
		model: Quickshell.screens

		PanelWindow {
			id: powerWindow
			required property var modelData
			screen: modelData

			readonly property var monitor: Hyprland.monitorFor(modelData)
			readonly property bool isFocusedMonitor: monitor?.name === Hyprland.focusedMonitor?.name

			visible: root.menuOpen && isFocusedMonitor
			color: "transparent"
			exclusionMode: ExclusionMode.Ignore

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
				color: Qt.rgba(0.02, 0.02, 0.04, 0.62)
				opacity: powerWindow.visible ? 1 : 0
				Behavior on opacity { NumberAnimation { duration: Config.motion.normal } }

				MouseArea {
					anchors.fill: parent
					onClicked: root.close()
				}
			}

			Item {
				id: keyHandler
				anchors.fill: parent
				focus: true

				Keys.onEscapePressed: root.close()
				Keys.onLeftPressed: root.currentIndex = (root.currentIndex + root.actions.length - 1) % root.actions.length
				Keys.onRightPressed: root.currentIndex = (root.currentIndex + 1) % root.actions.length
				Keys.onReturnPressed: {
					const button = buttonRepeater.itemAt(root.currentIndex)
					if (button) button.activate()
				}
				Keys.onEnterPressed: {
					const button = buttonRepeater.itemAt(root.currentIndex)
					if (button) button.activate()
				}
			}

			Rectangle {
				id: card
				anchors.centerIn: parent
				width: cardColumn.implicitWidth + Config.panel.padding * 2 + 12
				height: cardColumn.implicitHeight + Config.panel.padding * 2
				radius: Config.radius.xlarge
				color: Config.colors.base
				border.width: 1
				border.color: Config.colors.border
				opacity: powerWindow.visible ? 1 : 0
				scale: powerWindow.visible ? 1 : 0.97

				Behavior on opacity { NumberAnimation { duration: Config.motion.normal } }
				Behavior on scale { NumberAnimation { duration: Config.motion.normal; easing.type: Easing.OutCubic } }

				MouseArea { anchors.fill: parent; onClicked: {} }

				ColumnLayout {
					id: cardColumn
					anchors.centerIn: parent
					spacing: 16

					RowLayout {
						Layout.fillWidth: true
						spacing: 10

						ColumnLayout {
							Layout.fillWidth: true
							spacing: 0

							Text {
								text: "Power"
								color: Config.colors.text
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize + 2
								font.weight: 700
							}

							Text {
								text: "Choose what happens next"
								color: Config.colors.textDim
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 3
							}
						}

					}

					RowLayout {
						id: buttonRow
						spacing: 12

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

								onHovered: root.currentIndex = index
								onActivated: {
									root.close()
									modelData.run()
								}
							}
						}
					}

					Rectangle {
						Layout.fillWidth: true
						Layout.preferredHeight: 1
						color: Config.colors.borderMuted
					}

					RowLayout {
						Layout.fillWidth: true
						spacing: 12

						Text {
							Layout.fillWidth: true
							text: "\u2190\u2192 navigate   \u23ce select   \u238b close"
							color: Config.colors.textDim
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 3
							elide: Text.ElideRight
						}

						Text {
							text: "Destructive actions ask for confirmation"
							color: Config.colors.textDim
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 4
						}
					}
				}
			}
		}
	}
}
