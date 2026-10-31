import QtQuick
import QtQuick.Layouts

import "config.js" as Config

Rectangle {
	id: root

	property string icon: ""
	property string label: ""
	property color accentColor: Config.colors.textMuted
	property bool confirm: false
	property bool armed: false
	property bool focused: false

	signal activated()
	signal hovered()

	function activate() {
		if (root.confirm && !root.armed) {
			root.armed = true
			armTimer.restart()
		} else {
			armTimer.stop()
			root.armed = false
			root.activated()
		}
	}

	onFocusedChanged: if (!root.focused) { root.armed = false; armTimer.stop() }

	readonly property bool highlighted: hoverArea.containsMouse || root.focused

	implicitWidth: 96
	implicitHeight: 104
	radius: Config.radius.large
	color: root.armed
		? Config.colors.accentFaint
		: root.highlighted
			? Config.colors.surface
			: Config.colors.elevated
	border.width: root.armed || root.focused ? 2 : 1
	border.color: root.armed || root.focused
		? root.accentColor
		: root.highlighted
			? Config.colors.hoverBorder
			: Config.colors.borderMuted

	Behavior on color { ColorAnimation { duration: Config.motion.fast; easing.type: Easing.OutCubic } }
	Behavior on border.color { ColorAnimation { duration: Config.motion.fast; easing.type: Easing.OutCubic } }

	Timer {
		id: armTimer
		interval: 2500
		onTriggered: root.armed = false
	}

	ColumnLayout {
		anchors.centerIn: parent
		spacing: 9

		Rectangle {
			Layout.alignment: Qt.AlignHCenter
			Layout.preferredWidth: 46
			Layout.preferredHeight: 46
			radius: 15
			color: root.armed
				? Config.colors.accentSoft
				: root.highlighted
					? Config.colors.accentFaint
					: Config.colors.surface
			border.width: 1
			border.color: root.armed || root.highlighted
				? root.accentColor
				: Config.colors.borderMuted

			Behavior on color { ColorAnimation { duration: Config.motion.fast } }
			Behavior on border.color { ColorAnimation { duration: Config.motion.fast } }

			Text {
				anchors.centerIn: parent
				text: root.icon
				color: root.armed || root.highlighted ? root.accentColor : Config.colors.textMuted
				font.family: Config.bar.iconFontFamily
				font.pixelSize: Config.bar.fontSize + 9
				Behavior on color { ColorAnimation { duration: Config.motion.fast } }
			}
		}

		Text {
			Layout.alignment: Qt.AlignHCenter
			text: root.armed ? "Click again" : root.label
			color: root.armed
				? root.accentColor
				: root.highlighted
					? Config.colors.text
					: Config.colors.textMuted
			font.family: Config.bar.fontFamily
			font.pixelSize: Config.bar.fontSize - 2
			font.weight: root.armed ? 700 : 500
			Behavior on color { ColorAnimation { duration: Config.motion.fast } }
		}
	}

	Rectangle {
		visible: root.armed
		anchors.bottom: parent.bottom
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.margins: 10
		height: 3
		radius: 1.5
		color: Config.colors.surfaceAlt

		Rectangle {
			id: armBar
			height: parent.height
			radius: parent.radius
			color: root.accentColor
			width: parent.width

			NumberAnimation on width {
				running: root.armed
				from: parent.width
				to: 0
				duration: 2500
				easing.type: Easing.Linear
			}
		}
	}

	MouseArea {
		id: hoverArea
		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onEntered: root.hovered()
		onClicked: root.activate()
	}
}
