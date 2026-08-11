import QtQuick
import QtQuick.Layouts

import "config.js" as Config

// A single floating, rounded bar segment with a quiet surface, thin border
// and a soft hover/border lift. Content is placed via the default property
// and positioned freely (anchors.centerIn / anchors.fill) inside the shell.
Rectangle {
	id: root

	// Show accent-tinted border regardless of hover (clock, media).
	property bool emphasized: false
	// Enable the hover/press feedback + mouse tracking.
	property bool interactive: true
	// Whether the segment carries a "bad" (warn) state for its border.
	property bool alert: false

	Layout.preferredHeight: Config.bar.height
	radius: Config.radius.medium

	color: root.hovered
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

	Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }
	Behavior on border.color { ColorAnimation { duration: 140; easing.type: Easing.OutCubic } }

	default property alias content: contentItem.data

	Item {
		id: contentItem
		anchors.fill: parent
	}

	MouseArea {
		id: hoverArea
		anchors.fill: parent
		hoverEnabled: root.interactive
		acceptedButtons: Qt.NoButton
	}
}
