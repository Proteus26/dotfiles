import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

import "config.js" as Config

Scope {
	id: root

	property bool centerOpen: false
	property bool dndEnabled: false
	property bool headerClearArmed: false

	readonly property string dndPath: (Quickshell.env("XDG_CACHE_HOME")
		|| (Quickshell.env("HOME") + "/.cache")) + "/quickshell/dnd"

	ListModel {
		id: history
	}

	IpcHandler {
		target: "notifications"

		function toggle(): void {
			if (!root.centerOpen) root.closeOtherPanels()
			root.centerOpen = !root.centerOpen
		}

		function show(): void {
			root.closeOtherPanels()
			root.centerOpen = true
		}

		function hide(): void {
			root.centerOpen = false
		}
	}

	function ipcCall(target, fn) {
		Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", target, fn])
	}

	function closeOtherPanels() {
		root.ipcCall("launcher", "hide")
		root.ipcCall("clipboard", "hide")
		root.ipcCall("controlcenter", "hide")
		root.ipcCall("powermenu", "hide")
	}

	// ------------------------------------------------------------------- dnd

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

	onDndTextChanged: {
		const next = root.dndText.trim() === "1"
		if (next !== root.dndEnabled) {
			root.dndEnabled = next
			if (next) root.clearToasts()
		}
	}

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
		if (root.dndEnabled) root.clearToasts()
		dndWrite.command = [
			"sh", "-c",
			"mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"",
			"--", root.dndPath, root.dndEnabled ? "1" : "0"
		]
		dndWrite.running = true
	}

	function clearToasts() {
		if (!server.trackedNotifications || !server.trackedNotifications.values) return
		const list = server.trackedNotifications.values.slice()
		for (let i = 0; i < list.length; i++) list[i].dismiss()
	}

	// ---------------------------------------------------------------- server

	NotificationServer {
		id: server
		actionsSupported: true
		bodySupported: true
		imageSupported: true

		onNotification: n => {
			history.insert(0, {
				summary: n.summary || "",
				body: n.body || "",
				appName: n.appName || "",
				appIcon: n.appIcon || "",
				urgency: n.urgency,
				time: Qt.formatDateTime(new Date(), "HH:mm")
			})
			while (history.count > 120) history.remove(history.count - 1)

			if (!root.dndEnabled) n.tracked = true
		}
	}

	function iconSource(icon) {
		if (!icon) return ""
		if (icon.startsWith("/") || icon.startsWith("file:") || icon.startsWith("http"))
			return icon
		return Quickshell.iconPath(icon, true) || ""
	}

	// ----------------------------------------------------------------- toasts

	Variants {
		model: Quickshell.screens

		PanelWindow {
			required property var modelData
			screen: modelData

			readonly property var monitor: Hyprland.monitorFor(modelData)
			readonly property bool isFocusedMonitor: monitor?.name === Hyprland.focusedMonitor?.name

			visible: isFocusedMonitor && !root.centerOpen && server.trackedNotifications.values.length > 0

			anchors { top: true; right: true }
			margins {
				top: Config.bar.height + Config.bar.margin * 2 + 6
				right: Config.bar.margin
			}

			implicitWidth: Config.notifications.width
			implicitHeight: Math.max(1, toastColumn.implicitHeight)
			color: "transparent"
			exclusionMode: ExclusionMode.Ignore

			WlrLayershell.layer: WlrLayer.Overlay
			WlrLayershell.namespace: "notifications"
			WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

			ColumnLayout {
				id: toastColumn
				width: parent.width
				spacing: 8

				Repeater {
					model: server.trackedNotifications

					delegate: Item {
						id: toast
						required property var modelData
						property bool critical: modelData.urgency === NotificationUrgency.Critical
						property bool closing: false

						Layout.fillWidth: true
						Layout.preferredHeight: toastContent.implicitHeight + 26

						opacity: 0

						Component.onCompleted: intro.start()

						ParallelAnimation {
							id: intro
							NumberAnimation { target: toast; property: "opacity"; from: 0; to: 1; duration: Config.motion.normal }
							NumberAnimation { target: toastCard; property: "scale"; from: 0.97; to: 1; duration: Config.motion.normal; easing.type: Easing.OutCubic }
						}

						ParallelAnimation {
							id: outro
							NumberAnimation { target: toast; property: "opacity"; to: 0; duration: Config.motion.fast }
							NumberAnimation { target: toastCard; property: "scale"; to: 0.97; duration: Config.motion.fast }
							onFinished: toast.modelData.dismiss()
						}

						function close() {
							if (toast.closing) return
							toast.closing = true
							outro.start()
						}

						function defaultAction() {
							const actions = toast.modelData.actions || []
							const def = actions.find(a => a.identifier === "default") || actions[0]
							if (def) def.invoke()
							toast.close()
						}

						Timer {
							running: !toast.critical && !toast.closing && !cardHover.containsMouse
							interval: Config.notifications.timeout
							onTriggered: toast.close()
						}

						Rectangle {
							id: toastCard
							anchors.fill: parent
							radius: Config.radius.medium
							color: Config.colors.base
							border.width: 1
							border.color: toast.critical
								? Config.colors.bad
								: cardHover.containsMouse
									? Config.colors.hoverBorder
									: Config.colors.border
							Behavior on border.color { ColorAnimation { duration: Config.motion.normal } }
							Behavior on scale { NumberAnimation { duration: Config.motion.fast } }

						}

						RowLayout {
							id: toastContent
							anchors.fill: parent
							anchors.margins: 12
							spacing: 10

							Rectangle {
								Layout.preferredWidth: 34
								Layout.preferredHeight: 34
								Layout.alignment: Qt.AlignTop
								radius: Config.radius.small
								color: Config.colors.elevated
								border.width: 1
								border.color: Config.colors.borderMuted

								Image {
									anchors.fill: parent
									anchors.margins: 5
									source: root.iconSource(toast.modelData.image || toast.modelData.appIcon)
									fillMode: Image.PreserveAspectFit
									smooth: true
									asynchronous: true
									visible: source.toString() !== ""
								}

								Text {
									anchors.centerIn: parent
									visible: root.iconSource(toast.modelData.image || toast.modelData.appIcon) === ""
									text: "\uf0f3"
									color: toast.critical ? Config.colors.bad : Config.colors.accent
									font.family: Config.bar.iconFontFamily
									font.pixelSize: Config.bar.fontSize + 2
								}
							}

							ColumnLayout {
								Layout.fillWidth: true
								spacing: 3

								RowLayout {
									Layout.fillWidth: true
									spacing: 6

									Text {
										Layout.fillWidth: true
										text: toast.modelData.appName !== ""
											? toast.modelData.appName
											: "Notification"
										color: Config.colors.textDim
										font.family: Config.bar.fontFamily
										font.pixelSize: Config.bar.fontSize - 4
										font.weight: 600
										elide: Text.ElideRight
									}

									Text {
										text: "\uf00d"
										color: closeMouse.containsMouse ? Config.colors.bad : Config.colors.textDim
										font.family: Config.bar.iconFontFamily
										font.pixelSize: Config.bar.fontSize - 2
										Behavior on color { ColorAnimation { duration: Config.motion.fast } }

										MouseArea {
											id: closeMouse
											anchors.fill: parent
											anchors.margins: -7
											hoverEnabled: true
											cursorShape: Qt.PointingHandCursor
											onClicked: toast.close()
										}
									}
								}

								Text {
									Layout.fillWidth: true
									text: toast.modelData.summary
									color: Config.colors.text
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize
									font.weight: 700
									wrapMode: Text.WordWrap
									maximumLineCount: 2
									elide: Text.ElideRight
								}

								Text {
									Layout.fillWidth: true
									visible: text !== ""
									text: toast.modelData.body
									color: Config.colors.textMuted
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize - 1
									wrapMode: Text.WordWrap
									maximumLineCount: 4
									elide: Text.ElideRight
								}

								RowLayout {
									Layout.fillWidth: true
									Layout.topMargin: 4
									spacing: 6
									visible: (toast.modelData.actions || []).length > 0

									Repeater {
										model: toast.modelData.actions || []

										delegate: Rectangle {
											required property var modelData

											implicitWidth: actionLabel.implicitWidth + 18
											implicitHeight: 26
											radius: Config.radius.small
											color: actionMouse.containsMouse ? Config.colors.surfaceAlt : Config.colors.surface
											border.width: 1
											border.color: actionMouse.containsMouse ? Config.colors.hoverBorder : Config.colors.borderMuted

											Text {
												id: actionLabel
												anchors.centerIn: parent
												text: modelData.text
												color: Config.colors.text
												font.family: Config.bar.fontFamily
												font.pixelSize: Config.bar.fontSize - 3
												font.weight: 600
											}

											MouseArea {
												id: actionMouse
												anchors.fill: parent
												hoverEnabled: true
												cursorShape: Qt.PointingHandCursor
												onClicked: {
													modelData.invoke()
													toast.close()
												}
											}
										}
									}

									Item { Layout.fillWidth: true }
								}
							}
						}

						MouseArea {
							id: cardHover
							anchors.fill: parent
							hoverEnabled: true
							z: -1
							onClicked: toast.defaultAction()
						}
					}
				}
			}
		}
	}

	// ------------------------------------------------------------ center panel

	Timer {
		id: clearTimer
		interval: 2600
		onTriggered: root.headerClearArmed = false
	}

	Variants {
		model: Quickshell.screens

		PanelWindow {
			id: centerWindow
			required property var modelData
			screen: modelData

			readonly property var monitor: Hyprland.monitorFor(modelData)
			readonly property bool isFocusedMonitor: monitor?.name === Hyprland.focusedMonitor?.name

			visible: root.centerOpen && isFocusedMonitor

			anchors { top: true; right: true }
			margins {
				top: Config.bar.height + Config.bar.margin * 2 + 4
				right: Config.bar.margin
			}

			implicitWidth: 460
			implicitHeight: 600
			color: "transparent"
			exclusionMode: ExclusionMode.Ignore

			WlrLayershell.layer: WlrLayer.Overlay
			WlrLayershell.namespace: "notificationcenter"
			WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

			onVisibleChanged: if (visible) keyHandler.forceActiveFocus()

			Rectangle {
				id: centerCard
				anchors.fill: parent
				radius: Config.radius.large
				color: Config.colors.base
				border.width: 1
				border.color: Config.colors.border
				opacity: centerWindow.visible ? 1 : 0
				scale: centerWindow.visible ? 1 : 0.97
				transformOrigin: Item.TopRight

				Behavior on opacity { NumberAnimation { duration: Config.motion.normal } }
				Behavior on scale { NumberAnimation { duration: Config.motion.normal; easing.type: Easing.OutCubic } }

				Item {
					id: keyHandler
					anchors.fill: parent
					focus: true
					Keys.onEscapePressed: root.centerOpen = false
				}

				ColumnLayout {
					anchors.fill: parent
					anchors.margins: Config.panel.padding
					spacing: 12

					// -------------------------------------------------- header

					RowLayout {
						Layout.fillWidth: true
						spacing: 8

						ColumnLayout {
							Layout.fillWidth: true
							spacing: 0

							Text {
								text: "Notifications"
								color: Config.colors.text
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize + 1
								font.weight: 700
							}

							Text {
								text: root.dndEnabled ? "Do not disturb is on" : history.count + " saved"
								color: Config.colors.textDim
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 4
							}
						}

						Text {
							visible: history.count > 0
							text: root.headerClearArmed ? "clear?" : "clear"
							color: root.headerClearArmed
								? Config.colors.bad
								: headerClearMouse.containsMouse
									? Config.colors.text
									: Config.colors.textDim
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 3
							font.weight: root.headerClearArmed ? 700 : 500
							Behavior on color { ColorAnimation { duration: Config.motion.fast } }

							MouseArea {
								id: headerClearMouse
								anchors.fill: parent
								anchors.margins: -8
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: {
									if (!root.headerClearArmed) {
										root.headerClearArmed = true
										clearTimer.restart()
										return
									}
									root.headerClearArmed = false
									clearTimer.stop()
									history.clear()
								}
							}
						}

					}

					Rectangle {
						Layout.fillWidth: true
						Layout.preferredHeight: 1
						color: Config.colors.borderMuted
					}

					// ---------------------------------------------------- list

					ListView {
						id: centerList
						Layout.fillWidth: true
						Layout.fillHeight: true
						visible: history.count > 0
						model: history
						clip: true
						spacing: 6
						boundsBehavior: Flickable.StopAtBounds

						delegate: Item {
							id: historyItem
							width: ListView.view.width
							height: historyContent.implicitHeight + 24

							required property int index
							required property string summary
							required property string body
							required property string appName
							required property string appIcon
							required property int urgency
							required property string time

							property bool critical: historyItem.urgency === NotificationUrgency.Critical

							Rectangle {
								anchors.fill: parent
								radius: Config.radius.medium
								color: historyHover.containsMouse ? Config.colors.surface : Config.colors.elevated
								border.width: 1
								border.color: historyItem.critical
									? Config.colors.bad
									: historyHover.containsMouse
										? Config.colors.hoverBorder
										: Config.colors.borderMuted
								Behavior on color { ColorAnimation { duration: Config.motion.fast } }
								Behavior on border.color { ColorAnimation { duration: Config.motion.fast } }
							}

							RowLayout {
								id: historyContent
								anchors.fill: parent
								anchors.margins: 11
								spacing: 10

								Rectangle {
									Layout.preferredWidth: 30
									Layout.preferredHeight: 30
									Layout.alignment: Qt.AlignTop
									radius: Config.radius.small
									color: Config.colors.surface
									border.width: 1
									border.color: Config.colors.borderMuted

									Image {
										anchors.fill: parent
										anchors.margins: 5
										source: root.iconSource(historyItem.appIcon)
										fillMode: Image.PreserveAspectFit
										smooth: true
										asynchronous: true
										visible: source.toString() !== ""
									}

									Text {
										anchors.centerIn: parent
										visible: root.iconSource(historyItem.appIcon) === ""
										text: "\uf0f3"
										color: historyItem.critical ? Config.colors.bad : Config.colors.accent
										font.family: Config.bar.iconFontFamily
										font.pixelSize: Config.bar.fontSize
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
											text: historyItem.summary
											color: Config.colors.text
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize - 1
											font.weight: 700
											elide: Text.ElideRight
										}

										Text {
											text: historyItem.time
											color: Config.colors.textDim
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize - 4
										}

										Text {
											text: "\uf00d"
											color: historyDelete.containsMouse ? Config.colors.bad : Config.colors.textDim
											font.family: Config.bar.iconFontFamily
											font.pixelSize: Config.bar.fontSize - 3
											Behavior on color { ColorAnimation { duration: Config.motion.fast } }

											MouseArea {
												id: historyDelete
												anchors.fill: parent
												anchors.margins: -7
												hoverEnabled: true
												cursorShape: Qt.PointingHandCursor
												onClicked: history.remove(historyItem.index)
											}
										}
									}

									Text {
										Layout.fillWidth: true
										visible: historyItem.body !== ""
										text: historyItem.body
										color: Config.colors.textMuted
										font.family: Config.bar.fontFamily
										font.pixelSize: Config.bar.fontSize - 2
										wrapMode: Text.WordWrap
										maximumLineCount: 3
										elide: Text.ElideRight
									}

									Text {
										Layout.fillWidth: true
										visible: historyItem.appName !== ""
										text: historyItem.appName
										color: Config.colors.textDim
										font.family: Config.bar.fontFamily
										font.pixelSize: Config.bar.fontSize - 4
										elide: Text.ElideRight
									}
								}
							}

							MouseArea {
								id: historyHover
								anchors.fill: parent
								hoverEnabled: true
								z: -1
							}
						}
					}

					Item {
						Layout.fillWidth: true
						Layout.fillHeight: true
						visible: history.count === 0

						ColumnLayout {
							anchors.centerIn: parent
							spacing: 8

							Text {
								Layout.alignment: Qt.AlignHCenter
								text: "\uf0f3"
								color: Config.colors.textDim
								font.family: Config.bar.iconFontFamily
								font.pixelSize: 30
							}

							Text {
								Layout.alignment: Qt.AlignHCenter
								text: "You're all caught up"
								color: Config.colors.textDim
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 1
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
						spacing: 8

						Text {
							Layout.fillWidth: true
							text: root.dndEnabled
								? "Toasts are paused"
								: "Critical notifications stay until dismissed"
							color: Config.colors.textDim
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 4
							elide: Text.ElideRight
						}

						Text {
							text: "\u238b close"
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
