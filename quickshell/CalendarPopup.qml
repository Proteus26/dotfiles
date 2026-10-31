import Quickshell
import QtQuick
import QtQuick.Layouts

import "config.js" as Config

PopupWindow {
	id: root

	property var parentPanel
	property Item anchorItem
	property int viewYear: new Date().getFullYear()
	property int viewMonth: new Date().getMonth()
	property var today: new Date()

	readonly property var days: {
		const first = new Date(root.viewYear, root.viewMonth, 1)
		const count = new Date(root.viewYear, root.viewMonth + 1, 0).getDate()
		const result = []
		for (let i = 0; i < first.getDay(); i++) result.push(0)
		for (let day = 1; day <= count; day++) result.push(day)
		return result
	}

	function changeMonth(delta) {
		const next = new Date(root.viewYear, root.viewMonth + delta, 1)
		root.viewYear = next.getFullYear()
		root.viewMonth = next.getMonth()
	}

	onVisibleChanged: {
		if (visible) {
			const now = new Date()
			root.today = now
			root.viewYear = now.getFullYear()
			root.viewMonth = now.getMonth()
		}
	}

	implicitWidth: 300
	implicitHeight: 310
	color: "transparent"

	anchor {
		window: root.parentPanel
		adjustment: PopupAdjustment.None
		gravity: Edges.Bottom | Edges.Right

		onAnchoring: {
			const pos = root.anchorItem.QsWindow.contentItem.mapFromItem(
				root.anchorItem,
				root.anchorItem.width / 2 - root.width / 2,
				root.anchorItem.height + 5
			)
			anchor.rect.x = pos.x
			anchor.rect.y = pos.y
		}
	}

	Rectangle {
		anchors.fill: parent
		radius: Config.radius.large
		color: Config.colors.base
		border.width: 1
		border.color: Config.colors.border

		ColumnLayout {
			anchors.fill: parent
			anchors.margins: 14
			spacing: 8

			RowLayout {
				Layout.fillWidth: true
				spacing: 4

				IconButton {
					icon: "\uf053"
					iconSize: Config.bar.fontSize - 1
					iconColor: Config.colors.textMuted
					onClicked: root.changeMonth(-1)
				}

				Text {
					Layout.fillWidth: true
					text: Qt.formatDateTime(new Date(root.viewYear, root.viewMonth, 1), "MMMM yyyy")
					color: Config.colors.text
					font.family: Config.bar.fontFamily
					font.pixelSize: Config.bar.fontSize
					font.weight: 700
					horizontalAlignment: Text.AlignHCenter
				}

				IconButton {
					icon: "\uf054"
					iconSize: Config.bar.fontSize - 1
					iconColor: Config.colors.textMuted
					onClicked: root.changeMonth(1)
				}
			}

			Rectangle {
				Layout.fillWidth: true
				Layout.preferredHeight: 1
				color: Config.colors.borderMuted
			}

			RowLayout {
				Layout.fillWidth: true
				spacing: 0

				Repeater {
					model: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

					Text {
						required property string modelData
						Layout.fillWidth: true
						text: modelData
						color: Config.colors.textDim
						font.family: Config.bar.fontFamily
						font.pixelSize: Config.bar.fontSize - 5
						font.weight: 600
						horizontalAlignment: Text.AlignHCenter
					}
				}
			}

			Grid {
				Layout.alignment: Qt.AlignHCenter
				columns: 7
				columnSpacing: 2
				rowSpacing: 2

				Repeater {
					model: root.days

					Rectangle {
						id: dayCell
						required property int modelData
						readonly property bool isToday: modelData > 0
							&& root.today.getFullYear() === root.viewYear
							&& root.today.getMonth() === root.viewMonth
							&& root.today.getDate() === modelData

						width: 36
						height: 29
						radius: Config.radius.small
						color: isToday ? Config.colors.accent : "transparent"

						Text {
							anchors.centerIn: parent
							text: dayCell.modelData > 0 ? dayCell.modelData : ""
							color: dayCell.isToday ? Config.colors.onAccent : Config.colors.textMuted
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 3
							font.weight: dayCell.isToday ? 700 : 400
						}
					}
				}
			}
		}
	}
}
