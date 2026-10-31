import QtQuick
import QtQuick.Layouts

import "config.js" as Config

Item {
	id: root

	property string icon: ""
	property string mutedIcon: ""
	property string label: ""
	property string valueText: Math.round(root.value) + "%"
	property real value: 0
	property real from: 0
	property real to: 100
	property real step: 1
	property bool muted: false
	property bool muteSupported: true
	property color accentColor: Config.colors.accent

	signal toggleMute()
	signal moved(real value)
	signal committed(real value)

	implicitHeight: 50

	RowLayout {
		anchors.fill: parent
		spacing: 10

		Rectangle {
			Layout.preferredWidth: 30
			Layout.preferredHeight: 30
			Layout.alignment: Qt.AlignVCenter
			radius: Config.radius.small
			color: muteArea.containsMouse ? Config.colors.surfaceAlt : Config.colors.surface
			border.width: 1
			border.color: Config.colors.borderMuted

			Behavior on color { ColorAnimation { duration: Config.motion.fast } }

			Text {
				anchors.centerIn: parent
				text: root.muted && root.mutedIcon !== "" ? root.mutedIcon : root.icon
				color: root.muted ? Config.colors.textDim : root.accentColor
				font.family: Config.bar.iconFontFamily
				font.pixelSize: Config.bar.fontSize + 1
			}

			MouseArea {
				id: muteArea
				anchors.fill: parent
				hoverEnabled: root.muteSupported
				enabled: root.muteSupported
				cursorShape: root.muteSupported ? Qt.PointingHandCursor : Qt.ArrowCursor
				onClicked: root.toggleMute()
			}
		}

		ColumnLayout {
			Layout.fillWidth: true
			spacing: 3

			RowLayout {
				Layout.fillWidth: true
				spacing: 8

				Text {
					Layout.fillWidth: true
					text: root.label
					color: Config.colors.textMuted
					font.family: Config.bar.fontFamily
					font.pixelSize: Config.bar.fontSize - 2
					elide: Text.ElideRight
				}

				Text {
					text: root.valueText
					color: root.muted ? Config.colors.textDim : Config.colors.text
					font.family: Config.bar.fontFamily
					font.pixelSize: Config.bar.fontSize - 2
					font.weight: 600
				}
			}

			Slider {
				Layout.fillWidth: true
				implicitHeight: 16
				from: root.from
				to: root.to
				step: root.step
				value: root.value
				trackHeight: 5
				handleSize: 13
				fillColor: root.muted ? Config.colors.textDim : root.accentColor
				onMoved: (v) => root.moved(v)
				onCommitted: (v) => root.committed(v)
			}
		}
	}
}
