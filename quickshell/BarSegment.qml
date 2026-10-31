import QtQuick
import QtQuick.Layouts

import "config.js" as Config

Rectangle {
	id: root

	property bool emphasized: false
	property bool interactive: true
	property bool alert: false
	property bool elevated: false

	Layout.preferredHeight: Config.bar.height
	radius: Config.radius.large

	color: root.elevated
		? Config.colors.surface
		: root.hovered
			? Config.colors.surface
			: Config.colors.base
	border.width: 1
	border.color: root.alert
		? Config.colors.bad
		: root.emphasized
			? Config.colors.accentDim
			: root.hovered
				? Config.colors.hoverBorder
				: Config.colors.borderMuted

	readonly property bool hovered: root.interactive && (hoverArea.containsMouse || hoverArea.pressed)

	Behavior on color { ColorAnimation { duration: Config.motion.normal; easing.type: Easing.OutCubic } }
	Behavior on border.color { ColorAnimation { duration: Config.motion.normal; easing.type: Easing.OutCubic } }

	default property alias content: contentItem.data

	MouseArea {
		id: hoverArea
		anchors.fill: parent
		hoverEnabled: root.interactive
		acceptedButtons: Qt.NoButton
	}

	Item {
		id: contentItem
		anchors.fill: parent
	}
}
