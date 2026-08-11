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

	implicitWidth: 92
	implicitHeight: 92
	radius: Config.radius.medium
	color: root.highlighted ? Config.colors.surface : Config.colors.base
	border.width: root.focused ? 2 : 1
	border.color: root.armed
		? root.accentColor
		: (root.highlighted ? root.accentColor : Config.colors.borderMuted)

	Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
	Behavior on border.color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }

	Timer {
		id: armTimer
		interval: 2500
		onTriggered: root.armed = false
	}

	ColumnLayout {
		anchors.centerIn: parent
		spacing: 8

		Text {
			Layout.alignment: Qt.AlignHCenter
			text: root.icon
			color: root.armed ? root.accentColor : (root.highlighted ? root.accentColor : Config.colors.textMuted)
			font.family: Config.bar.iconFontFamily
			font.pixelSize: Config.bar.fontSize + 8
		}
		Text {
			Layout.alignment: Qt.AlignHCenter
			text: root.armed ? "Confirm?" : root.label
			color: root.armed ? root.accentColor : (root.highlighted ? Config.colors.text : Config.colors.textMuted)
			font.family: Config.bar.fontFamily
			font.pixelSize: Config.bar.fontSize - 2
		}
	}

	MouseArea {
		id: hoverArea
		anchors.fill: parent
		hoverEnabled: true
		onClicked: root.activate()
	}
}
