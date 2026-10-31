import Quickshell
import QtQuick
import QtQuick.Layouts

import "config.js" as Config

PopupWindow {
	id: root

	property var parentPanel
	property Item anchorItem
	property real value: 0
	property bool muted: false

	signal volumeChanged(real value)
	signal muteToggled()

	implicitWidth: 300
	implicitHeight: 106
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
			spacing: 10

			RowLayout {
				Layout.fillWidth: true
				spacing: 8

				Text {
					text: root.muted ? "\uf026" : "\uf028"
					color: root.muted ? Config.colors.textDim : Config.colors.accent
					font.family: Config.bar.iconFontFamily
					font.pixelSize: Config.bar.fontSize + 2
				}

				Text {
					Layout.fillWidth: true
					text: "Volume"
					color: Config.colors.text
					font.family: Config.bar.fontFamily
					font.pixelSize: Config.bar.fontSize - 1
					font.weight: 600
				}

				Text {
					text: root.muted ? "Muted" : Math.round(root.value) + "%"
					color: Config.colors.textMuted
					font.family: Config.bar.fontFamily
					font.pixelSize: Config.bar.fontSize - 2
					font.weight: 600
				}

				IconButton {
					icon: root.muted ? "\uf026" : "\uf028"
					iconSize: Config.bar.fontSize
					iconColor: Config.colors.textMuted
					onClicked: root.muteToggled()
				}
			}

			Slider {
				Layout.fillWidth: true
				implicitHeight: 20
				from: 0
				to: 100
				step: 1
				value: root.value
				trackHeight: 6
				handleSize: 14
				fillColor: root.muted ? Config.colors.textDim : Config.colors.accent
				onMoved: (v) => root.volumeChanged(v)
				onCommitted: (v) => root.volumeChanged(v)
			}
		}
	}
}
