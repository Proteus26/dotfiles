import QtQuick

import "config.js" as Config

Item {
	id: root

	property real value: 0
	property real from: 0
	property real to: 100
	property real step: 1
	property real wheelStep: 5
	property bool enabled: true
	property color trackColor: Config.colors.surfaceAlt
	property color fillColor: Config.colors.accent
	property real trackHeight: 6
	property real handleSize: 14
	property bool showHandle: true

	readonly property bool hovered: area.containsMouse
	property bool holdVisual: false
	readonly property bool dragging: area.pressed || root.holdVisual
	readonly property real visualValue: root.dragging ? root.dragValue : root.value
	readonly property real ratio: root.to > root.from
		? Math.max(0, Math.min(1, (root.visualValue - root.from) / (root.to - root.from)))
		: 0
	readonly property real trackLeft: root.showHandle ? root.handleSize / 2 : 0
	readonly property real trackRight: root.width - (root.showHandle ? root.handleSize / 2 : 0)
	readonly property real trackWidth: Math.max(0, root.trackRight - root.trackLeft)

	property real dragValue: value

	signal moved(real value)
	signal committed(real value)

	implicitHeight: Math.max(root.trackHeight, root.showHandle ? root.handleSize : 0)
	opacity: root.enabled ? 1 : 0.35

	onValueChanged: if (!root.dragging) root.dragValue = root.value

	function clamp(v) {
		return Math.max(root.from, Math.min(root.to, v))
	}

	function quantize(v) {
		if (root.step <= 0) return root.clamp(v)
		return root.clamp(Math.round(v / root.step) * root.step)
	}

	function valueAt(x) {
		if (root.trackWidth <= 0) return root.from
		return root.quantize(root.from + ((x - root.trackLeft) / root.trackWidth) * (root.to - root.from))
	}

	function updateFromUser(v) {
		const next = root.quantize(v)
		root.holdVisual = true
		root.dragValue = next
		root.moved(next)
		return next
	}

	Rectangle {
		id: track
		x: root.trackLeft
		width: root.trackWidth
		height: root.trackHeight
		radius: height / 2
		anchors.verticalCenter: parent.verticalCenter
		color: root.trackColor
	}

	Rectangle {
		id: fill
		x: root.trackLeft
		width: root.trackWidth * root.ratio
		height: root.trackHeight
		radius: height / 2
		anchors.verticalCenter: parent.verticalCenter
		color: root.fillColor
	}

	Rectangle {
		id: handle
		visible: root.showHandle
		width: root.handleSize
		height: width
		radius: width / 2
		anchors.verticalCenter: parent.verticalCenter
		x: root.trackLeft + root.trackWidth * root.ratio - width / 2
		color: root.fillColor
	}

	Timer {
		id: settleTimer
		interval: 220
		onTriggered: root.holdVisual = false
	}

	MouseArea {
		id: area
		anchors.fill: parent
		enabled: root.enabled
		hoverEnabled: true
		cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

		onPressed: (mouse) => {
			settleTimer.stop()
			root.updateFromUser(root.valueAt(mouse.x))
		}

		onPositionChanged: (mouse) => {
			if (pressed) root.updateFromUser(root.valueAt(mouse.x))
		}

		onReleased: {
			const v = root.quantize(root.dragValue)
			root.dragValue = v
			settleTimer.restart()
			root.committed(v)
		}

		onWheel: (wheel) => {
			settleTimer.stop()
			const dir = wheel.angleDelta.y > 0 ? 1 : -1
			const next = root.updateFromUser(root.visualValue + dir * root.wheelStep)
			settleTimer.restart()
			root.committed(next)
			wheel.accepted = true
		}
	}
}
