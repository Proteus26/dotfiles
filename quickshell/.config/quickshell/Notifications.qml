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
	ListModel {
		id: history
	}

	NotificationServer {
		id: server
		actionsSupported: true
		bodySupported: true
		imageSupported: true

		onNotification: n => {
			history.insert(0, {
				summary: n.summary,
				body: n.body,
				appName: n.appName,
				urgency: n.urgency,
				time: Qt.formatDateTime(new Date(), "HH:mm")
			})
			n.tracked = true
		}
	}

	IpcHandler {
		target: "notifications"
		function toggle() : void { root.centerOpen = !root.centerOpen }
		function show() : void { root.centerOpen = true }
		function hide() : void { root.centerOpen = false }
	}

	// notification toasts
	Variants {
		model: Quickshell.screens

		PanelWindow {
			required property var modelData
			screen: modelData

			readonly property var monitor: Hyprland.monitorFor(modelData)
			readonly property bool isFocusedMonitor: monitor?.name === Hyprland.focusedMonitor?.name

			visible: isFocusedMonitor

			anchors { top: true; right: true }
			margins { top: 12; right: 12 }

			implicitWidth: 380
			implicitHeight: Math.max(1, column.implicitHeight)
			color: "transparent"

			exclusionMode: ExclusionMode.Normal

			ColumnLayout {
				id: column
				width: parent.width
				spacing: 10

				Repeater {
					model: server.trackedNotifications
					delegate: Rectangle {
						id: card
						required property var modelData

						Timer {
							running: card.modelData.urgency != NotificationUrgency.Critical
							interval: Config.notifications.timeout
							onTriggered: card.modelData.dismiss()
						}

						Layout.fillWidth: true
						Layout.preferredHeight: layout.implicitHeight + 20
						radius: 8
						color: Config.colors.base
						border.width: 2
						border.color: modelData.urgency === NotificationUrgency.Critical ? Config.colors.red : Config.colors.mauve

						RowLayout {
							id: layout
							anchors.fill: parent
							anchors.margins: 10
							spacing: 10

							Image {
								Layout.preferredHeight: 36
								Layout.preferredWidth: 36
								Layout.alignment: Qt.AlignTop
								fillMode: Image.PreserveAspectFit
								visible: source.toString() !== ""
								source: card.modelData.image || card.modelData.appIcon || ""
							}

							ColumnLayout {
								Layout.fillWidth: true
								spacing: 2

								Text {
									Layout.fillWidth: true
									text: card.modelData.summary
									color: Config.colors.sky
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize
									font.bold: true
									elide: Text.ElideRight
								}

								Text {
									Layout.fillWidth: true
									visible: text !== ""
									text: card.modelData.body
									color: Config.colors.text
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize - 1
									wrapMode: Text.WordWrap
								}
							}
						}

						MouseArea {
							anchors.fill: parent
							onClicked: card.modelData.dismiss()
						}
					}
				}
			}
		}
	}

	// notification center
	Variants {
		model: Quickshell.screens

		PanelWindow {
			required property var modelData
			screen: modelData

			readonly property var monitor: Hyprland.monitorFor(modelData)
			readonly property bool isFocusedMonitor: monitor?.name === Hyprland.focusedMonitor?.name

			visible: root.centerOpen && isFocusedMonitor
			
			anchors { top: true; right: true }
			margins { top: 12; right: 12 }

			implicitWidth: 380
			implicitHeight: centerCol.implicitHeight + 24 
			color: "transparent"

			exclusionMode: ExclusionMode.Normal

			Rectangle {
				anchors.fill: parent
				radius: 10
				color: Config.colors.base
				border.width: 2
				border.color: Config.colors.mauve

				ColumnLayout {
					id: centerCol
					anchors.fill: parent
					anchors.margins: 12
					spacing: 10

					RowLayout{
						Layout.fillWidth: true

						Text {
							Layout.fillWidth: true
							text: "Notifications"
							color: Config.colors.sky
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize + 1
							font.bold: true
						}

						Text {
							text: "Clear all"
							visible: history.count > 0
							color: Config.colors.red
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize
							font.bold: true
							MouseArea {
								anchors.fill: parent
								onClicked: history.clear()
							}
						}
					}

					Repeater {
						model: history
						delegate: Rectangle {
							Layout.fillWidth: true
							Layout.preferredHeight: histLayout.implicitHeight + 20
							radius: 8
							color: Config.colors.mantle 
							border.width: 1
							border.color: urgency === NotificationUrgency.Critical ? Config.colors.red : Config.colors.overlay2

							RowLayout {
								id: histLayout
								anchors.fill: parent
								anchors.margins: 10
								spacing: 10

								ColumnLayout {
									Layout.fillWidth: true
									spacing: 2

									RowLayout {
										Layout.fillWidth: true
										spacing: 6

										Text {
											Layout.fillWidth: true
											text: summary
											color: Config.colors.text
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize
											font.bold: true
											elide: Text.ElideRight
										}

										Text {
											text: model.time
											color: Config.colors.subtext0
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize - 3
										}

										Text {
											text: "󰅙"
											color: Config.colors.subtext0
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize - 1
											MouseArea {
												anchors.fill: parent
												onClicked: history.remove(index)
											}
										}
									}

									Text {
										Layout.fillWidth: true
										visible: body !== ""
										text: body
										color: Config.colors.text
										font.family: Config.bar.fontFamily
										font.pixelSize: Config.bar.fontSize - 1
										wrapMode: Text.WordWrap
									}

									Text {
										visible: model.appName !== ""
										text: model.appName
										color: Config.colors.subtext0
										font.family: Config.bar.fontFamily
										font.pixelSize: Config.bar.fontSize - 3
									}
								}
							}
						}
					}
				}
			}
		}
	}
}
