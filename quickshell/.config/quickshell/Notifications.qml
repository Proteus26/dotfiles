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
				appIcon: n.appIcon || "",
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

			implicitWidth: 420
			implicitHeight: Math.max(1, column.implicitHeight)
			color: "transparent"

			exclusionMode: ExclusionMode.Normal

			ColumnLayout {
				id: column
				width: parent.width
				spacing: 8

				Repeater {
					model: server.trackedNotifications
					delegate: Item {
						id: card
						required property var modelData
						property bool isCritical: modelData.urgency === NotificationUrgency.Critical

						Timer {
							running: card.modelData.urgency != NotificationUrgency.Critical
							interval: Config.notifications.timeout
							onTriggered: card.modelData.dismiss()
						}

						Layout.fillWidth: true
						Layout.preferredHeight: layout.implicitHeight + 22

						Rectangle {
							anchors.fill: parent
							radius: Config.radius.medium
							color: Config.colors.base
							border.width: 1
							border.color: card.isCritical
								? Config.colors.bad
								: (cardHover.containsMouse ? Config.colors.hoverBorder : Config.colors.border)
							Behavior on border.color { ColorAnimation { duration: 140 } }
						}

						Rectangle {
							width: 2
							height: parent.height - 12
							anchors.verticalCenter: parent.verticalCenter
							anchors.left: parent.left
							anchors.leftMargin: 6
							color: card.isCritical ? Config.colors.bad : Config.colors.accent
						}

						RowLayout {
							id: layout
							anchors.fill: parent
							anchors.margins: 12
							anchors.leftMargin: 18
							spacing: 10

							Image {
								Layout.preferredHeight: 40
								Layout.preferredWidth: 40
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
									color: Config.colors.text
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize
									font.bold: true
									elide: Text.ElideRight
								}

								Text {
									Layout.fillWidth: true
									visible: text !== ""
									text: card.modelData.body
									color: Config.colors.textMuted
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize - 1
									wrapMode: Text.WordWrap
								}
							}
						}

						MouseArea {
							id: cardHover
							anchors.fill: parent
							hoverEnabled: true
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

			implicitWidth: 500
			implicitHeight: centerCol.implicitHeight + 24 
			color: "transparent"

			exclusionMode: ExclusionMode.Normal

			Rectangle {
				anchors.fill: parent
				radius: Config.radius.large
				color: Config.colors.base
				border.width: 1
				border.color: Config.colors.border

				ColumnLayout {
					id: centerCol
					anchors.fill: parent
					anchors.margins: Config.panel.padding
					spacing: 10

					RowLayout{
						Layout.fillWidth: true
						spacing: 8

						// Accent marker, mirrors the bar's active-workspace dot
						Rectangle {
							Layout.preferredWidth: 8
							Layout.preferredHeight: 8
							radius: 4
							color: Config.colors.accent
						}

						Text {
							Layout.fillWidth: true
							text: "notifications"
							color: Config.colors.text
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize
							font.bold: true
						}

						Text {
							visible: history.count > 0
							text: history.count
							color: Config.colors.textMuted
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 1
						}

						Text {
							text: "clear"
							visible: history.count > 0
							color: clearMouse.containsMouse ? Config.colors.bad : Config.colors.textDim
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 2
							Behavior on color { ColorAnimation { duration: 120 } }

							MouseArea {
								id: clearMouse
								anchors.fill: parent
								anchors.margins: -6
								hoverEnabled: true
								onClicked: history.clear()
							}
						}
					}

					Repeater {
						model: history
						delegate: Item {
							id: histCard
							property bool isCritical: urgency === NotificationUrgency.Critical

							Layout.fillWidth: true
							Layout.preferredHeight: histLayout.implicitHeight + 22

							Rectangle {
								anchors.fill: parent
								radius: Config.radius.small
								color: histHover.containsMouse
									? Config.colors.surfaceAlt
									: Config.colors.surface
								border.width: 1
								border.color: histCard.isCritical
									? Config.colors.bad
									: (histHover.containsMouse ? Config.colors.hoverBorder : Config.colors.borderMuted)
								Behavior on color { ColorAnimation { duration: 140 } }
								Behavior on border.color { ColorAnimation { duration: 140 } }
							}

							Rectangle {
								visible: histCard.isCritical
								width: 3
								height: parent.height - 14
								radius: 1.5
								anchors.verticalCenter: parent.verticalCenter
								anchors.left: parent.left
								anchors.leftMargin: 5
								color: Config.colors.bad
							}

							RowLayout {
								id: histLayout
								anchors.fill: parent
								anchors.margins: 14
								anchors.leftMargin: histCard.isCritical ? 18 : 14
								spacing: 12

								Image {
									Layout.preferredWidth: 34
									Layout.preferredHeight: 34
									Layout.alignment: Qt.AlignTop
									fillMode: Image.PreserveAspectFit
									visible: source.toString() !== ""
									source: model.appIcon !== "" ? (Quickshell.iconPath(model.appIcon, true) || "") : ""
								}

								ColumnLayout {
									Layout.fillWidth: true
									Layout.alignment: Qt.AlignTop
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
											color: Config.colors.textDim
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize - 3
										}

										Text {
											text: "\u2715"
											color: delMouse.containsMouse ? Config.colors.bad : Config.colors.textDim
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize - 2
											Behavior on color { ColorAnimation { duration: 120 } }

											MouseArea {
												id: delMouse
												anchors.fill: parent
												anchors.margins: -6
												hoverEnabled: true
												onClicked: history.remove(index)
											}
										}
									}

									Text {
										Layout.fillWidth: true
										visible: body !== ""
										text: body
										color: Config.colors.textMuted
										font.family: Config.bar.fontFamily
										font.pixelSize: Config.bar.fontSize - 1
										wrapMode: Text.WordWrap
									}

									Text {
										visible: model.appName !== "" && model.appIcon === ""
										text: model.appName
										color: Config.colors.textDim
										font.family: Config.bar.fontFamily
										font.pixelSize: Config.bar.fontSize - 3
									}
								}
							}

							MouseArea {
								id: histHover
								anchors.fill: parent
								hoverEnabled: true
								acceptedButtons: Qt.NoButton
							}
						}
					}
				}
			}
		}
	}
}
