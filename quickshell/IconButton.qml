import QtQuick
import QtQuick.Layouts

import "config.js" as Config

Rectangle {
	id: root

	property string icon: ""
	property string label: ""
	property bool showLabel: false
	property bool active: false
	property bool danger: false
	property color iconColor: Config.colors.textMuted
	property color labelColor: Config.colors.text
	property color activeColor: Config.colors.accent
	property int iconSize: Config.bar.fontSize + 2
	property int labelSize: Config.bar.fontSize
	property bool interactive: true
	property string accessibleName: label

	signal clicked()
	signal middleClicked()
	signal wheeled(int delta)

	readonly property bool hovered: area.containsMouse
	readonly property color currentIconColor: root.active
		? root.activeColor
		: root.danger && root.hovered
			? Config.colors.bad
			: root.hovered
				? Config.colors.text
				: root.iconColor

	implicitWidth: content.implicitWidth + (root.showLabel ? 18 : 14)
	implicitHeight: 30
	radius: Config.radius.small
	color: root.active
		? Config.colors.accentFaint
		: root.hovered
			? Config.colors.surface
			: "transparent"
	border.width: root.active ? 1 : 0
	border.color: Config.colors.accentDim

	Behavior on color { ColorAnimation { duration: Config.motion.fast } }
	Behavior on border.color { ColorAnimation { duration: Config.motion.fast } }

	RowLayout {
		id: content
		anchors.centerIn: parent
		spacing: 6

		Text {
			text: root.icon
			color: root.currentIconColor
			font.family: Config.bar.iconFontFamily
			font.pixelSize: root.iconSize
			Behavior on color { ColorAnimation { duration: Config.motion.fast } }
		}

		Text {
			visible: root.showLabel && root.label !== ""
			text: root.label
			color: root.active ? root.activeColor : root.labelColor
			font.family: Config.bar.fontFamily
			font.pixelSize: root.labelSize
			font.weight: 500
			elide: Text.ElideRight
		}
	}

	MouseArea {
		id: area
		anchors.fill: parent
		hoverEnabled: root.interactive
		acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
		cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

		onClicked: (mouse) => {
			if (mouse.button === Qt.LeftButton) root.clicked()
			else if (mouse.button === Qt.MiddleButton) root.middleClicked()
		}

		onWheel: (wheel) => {
			root.wheeled(wheel.angleDelta.y)
			wheel.accepted = true
		}
	}
}
