import QtQuick
import QtQuick.Layouts

import "config.js" as Config

Rectangle {
	id: root

	property string icon: ""
	property string label: ""
	property string detail: ""
	property bool active: false
	property color accentColor: Config.colors.accent
	property color iconColor: Config.colors.textMuted
	property bool interactive: true

	signal clicked()

	implicitHeight: 56
	radius: Config.radius.medium
	color: root.active ? Config.colors.accentFaint : Config.colors.surface
	border.width: 1
	border.color: root.active
		? Config.colors.accentDim
		: area.containsMouse
			? Config.colors.hoverBorder
			: Config.colors.borderMuted

	Behavior on color { ColorAnimation { duration: Config.motion.fast } }
	Behavior on border.color { ColorAnimation { duration: Config.motion.fast } }

	RowLayout {
		anchors.fill: parent
		anchors.leftMargin: 12
		anchors.rightMargin: 12
		spacing: 10

		Text {
			Layout.alignment: Qt.AlignVCenter
			text: root.icon
			color: root.active ? root.accentColor : root.iconColor
			font.family: Config.bar.iconFontFamily
			font.pixelSize: Config.bar.fontSize + 4
			Behavior on color { ColorAnimation { duration: Config.motion.fast } }
		}

		ColumnLayout {
			Layout.fillWidth: true
			Layout.alignment: Qt.AlignVCenter
			spacing: 1

			Text {
				Layout.fillWidth: true
				text: root.label
				color: Config.colors.text
				font.family: Config.bar.fontFamily
				font.pixelSize: Config.bar.fontSize - 1
				font.weight: 600
				elide: Text.ElideRight
			}

			Text {
				Layout.fillWidth: true
				visible: root.detail !== ""
				text: root.detail
				color: root.active ? root.accentColor : Config.colors.textDim
				font.family: Config.bar.fontFamily
				font.pixelSize: Config.bar.fontSize - 4
				elide: Text.ElideRight
			}
		}
	}

	MouseArea {
		id: area
		anchors.fill: parent
		hoverEnabled: root.interactive
		cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
		onClicked: root.clicked()
	}
}
