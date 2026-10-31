import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

import "config.js" as Config

Scope {
	id: root

	property bool clipOpen: false
	property var allEntries: []
	property var searchResults: []
	property int currentIndex: -1
	property string query: ""
	property bool clearArmed: false
	property int deletingId: -1

	property var thumbCache: ({})
	property var pendingQueue: []
	property bool thumbWorkerRunning: false

	readonly property string thumbDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-clip-thumbs"

	IpcHandler {
		target: "clipboard"

		function toggle(): void {
			if (!root.clipOpen) root.closeOtherPanels()
			root.clipOpen = !root.clipOpen
		}

		function show(): void {
			root.closeOtherPanels()
			root.clipOpen = true
		}

		function hide(): void {
			root.clipOpen = false
		}
	}

	function ipcCall(target, fn) {
		Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", target, fn])
	}

	function closeOtherPanels() {
		root.ipcCall("launcher", "hide")
		root.ipcCall("notifications", "hide")
		root.ipcCall("controlcenter", "hide")
		root.ipcCall("powermenu", "hide")
	}

	Component.onCompleted: mkdirProc.running = true

	Process {
		id: mkdirProc
		command: ["mkdir", "-p", root.thumbDir]
	}

	Timer {
		id: clearTimer
		interval: 2600
		onTriggered: root.clearArmed = false
	}

	// ---------------------------------------------------------------- loading

	function fuzzyScore(query, target) {
		if (!query || !target) return -1
		const q = query.toLowerCase()
		const t = target.toLowerCase()

		const idx = t.indexOf(q)
		if (idx !== -1) return 100 - idx + q.length * 2

		let ti = 0
		let score = 0
		for (let qi = 0; qi < q.length; qi++) {
			const found = t.indexOf(q[qi], ti)
			if (found === -1) return -1
			score += (found === ti) ? 2 : 1
			ti = found + 1
		}
		return score
	}

	function parseImageMeta(preview) {
		const m = preview.match(/([\d.]+\s*[KMG]i?B)\s+(\S+\/\S+)/i)
		if (m) return { size: m[1], mime: m[2] }
		return { size: "", mime: "binary" }
	}

	function refreshHistory() {
		listProc.running = true
	}

	Process {
		id: listProc
		command: ["cliphist", "list"]
		stdout: StdioCollector {
			onStreamFinished: root.parseList(this.text)
		}
	}

	function parseList(text) {
		const lines = text.split("\n").filter(l => l.length > 0)
		let entries = []

		for (const line of lines) {
			const tabIdx = line.indexOf("\t")
			if (tabIdx === -1) continue

			const id = line.slice(0, tabIdx)
			const preview = line.slice(tabIdx + 1)
			const isImage = /binary\s*data/i.test(preview)
			const meta = isImage ? root.parseImageMeta(preview) : null

			entries.push({
				id: id,
				rawLine: line,
				preview: preview,
				isImage: isImage,
				mime: isImage ? meta.mime : "",
				size: isImage ? meta.size : "",
				searchable: isImage ? ("image " + meta.mime) : preview
			})
		}

		root.allEntries = entries
		root.applyFilter(root.query)
	}

	function applyFilter(q) {
		root.query = q
		const query = q.trim()
		let results

		if (query === "") {
			results = root.allEntries.slice()
		} else {
			results = []
			for (let i = 0; i < root.allEntries.length; i++) {
				const entry = root.allEntries[i]
				const score = root.fuzzyScore(query, entry.searchable)
				if (score < 0) continue
				results.push(Object.assign({}, entry, { matchScore: score }))
			}
			results.sort((a, b) => b.matchScore - a.matchScore)
		}

		root.searchResults = results
		root.currentIndex = results.length > 0 ? 0 : -1
	}

	// ------------------------------------------------------------- thumbnails

	function ensureThumbnail(id, rawLine) {
		if (root.thumbCache[id] !== undefined) return

		const updated = Object.assign({}, root.thumbCache)
		updated[id] = "pending"
		root.thumbCache = updated

		root.pendingQueue.push({ id: id, rawLine: rawLine, path: root.thumbDir + "/" + id + ".png" })

		if (!root.thumbWorkerRunning) root.processNextThumbnail()
	}

	function processNextThumbnail() {
		if (root.pendingQueue.length === 0) {
			root.thumbWorkerRunning = false
			return
		}

		root.thumbWorkerRunning = true
		const task = root.pendingQueue.shift()

		thumbWorker.currentId = task.id
		thumbWorker.currentPath = task.path
		thumbWorker.command = [
			"sh", "-c",
			"printf '%s\\n' \"$1\" | cliphist decode > \"$2.raw\" || exit 1; " +
			"if command -v magick >/dev/null 2>&1; then " +
			"magick \"$2.raw\" -thumbnail '560x320>' -strip -quality 82 \"$2\" || mv \"$2.raw\" \"$2\"; " +
			"else mv \"$2.raw\" \"$2\"; fi; rm -f \"$2.raw\"",
			"--", task.rawLine, task.path
		]
		thumbWorker.running = true
	}

	Process {
		id: thumbWorker
		property string currentId: ""
		property string currentPath: ""

		onExited: (code, status) => {
			const updated = Object.assign({}, root.thumbCache)
			updated[thumbWorker.currentId] = (code === 0) ? thumbWorker.currentPath : "error"
			root.thumbCache = updated
			root.processNextThumbnail()
		}
	}

	// ---------------------------------------------------------------- actions

	function copyEntry(entry) {
		Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist decode | wl-copy", "--", entry.rawLine])
	}

	function deleteEntry(entry) {
		root.deletingId = parseInt(entry.id)
		deleteProc.command = ["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "--", entry.rawLine]
		deleteProc.running = true
	}

	Process {
		id: deleteProc
		onExited: {
			root.deletingId = -1
			root.refreshHistory()
		}
	}

	function clearAll() {
		if (!root.clearArmed) {
			root.clearArmed = true
			clearTimer.restart()
			return
		}
		root.clearArmed = false
		clearTimer.stop()
		wipeProc.running = true
	}

	Process {
		id: wipeProc
		command: ["cliphist", "wipe"]
		onExited: {
			root.thumbCache = ({})
			root.refreshHistory()
		}
	}

	function activateCurrent() {
		if (root.currentIndex < 0 || root.currentIndex >= root.searchResults.length) return
		const entry = root.searchResults[root.currentIndex]
		root.copyEntry(entry)
		root.clipOpen = false
	}

	// ------------------------------------------------------------------ panel

	Variants {
		model: Quickshell.screens

		PanelWindow {
			id: clipWindow
			required property var modelData
			screen: modelData

			readonly property var monitor: Hyprland.monitorFor(modelData)
			readonly property bool isFocusedMonitor: monitor?.name === Hyprland.focusedMonitor?.name

			visible: root.clipOpen && isFocusedMonitor
			implicitWidth: 640
			implicitHeight: 640
			color: "transparent"
			exclusionMode: ExclusionMode.Ignore

			WlrLayershell.layer: WlrLayer.Overlay
			WlrLayershell.namespace: "clipboard"
			WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

			onVisibleChanged: {
				if (visible) {
					searchInput.text = ""
					root.applyFilter("")
					root.refreshHistory()
					searchInput.forceActiveFocus()
				}
			}

			Rectangle {
				id: card
				anchors.fill: parent
				radius: Config.radius.xlarge
				color: Config.colors.base
				border.width: 1
				border.color: Config.colors.border
				opacity: clipWindow.visible ? 1 : 0
				scale: clipWindow.visible ? 1 : 0.97
				transformOrigin: Item.Center

				Behavior on opacity { NumberAnimation { duration: Config.motion.normal } }
				Behavior on scale { NumberAnimation { duration: Config.motion.normal; easing.type: Easing.OutCubic } }

				ColumnLayout {
					anchors.fill: parent
					anchors.margins: 20
					spacing: 14

					// -------------------------------------------------- header

					RowLayout {
						Layout.fillWidth: true
						spacing: 8

						Text {
							Layout.fillWidth: true
							text: "Clipboard"
							color: Config.colors.text
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize + 1
							font.weight: 700
						}

						Text {
							visible: root.searchResults.length > 0
							text: root.searchResults.length
							color: Config.colors.textDim
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 2
						}

						IconButton {
							icon: "\uf021"
							iconSize: Config.bar.fontSize - 1
							implicitHeight: 26
							iconColor: Config.colors.textDim
							onClicked: root.refreshHistory()
						}

						Text {
							text: root.clearArmed ? "clear?" : "clear all"
							color: root.clearArmed
								? Config.colors.bad
								: clearMouse.containsMouse
									? Config.colors.text
									: Config.colors.textDim
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 3
							font.weight: root.clearArmed ? 700 : 500
							Behavior on color { ColorAnimation { duration: Config.motion.fast } }

							MouseArea {
								id: clearMouse
								anchors.fill: parent
								anchors.margins: -8
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: root.clearAll()
							}
						}
					}

					// -------------------------------------------------- search

					Rectangle {
						Layout.fillWidth: true
						Layout.preferredHeight: 44
						radius: Config.radius.medium
						color: searchInput.activeFocus ? Config.colors.surface : Config.colors.elevated
						border.width: 1
						border.color: searchInput.activeFocus ? Config.colors.accentDim : Config.colors.borderMuted

						Behavior on color { ColorAnimation { duration: Config.motion.fast } }
						Behavior on border.color { ColorAnimation { duration: Config.motion.fast } }

						RowLayout {
							anchors.fill: parent
							anchors.leftMargin: 14
							anchors.rightMargin: 12
							spacing: 10

							Text {
								text: "\uf002"
								color: Config.colors.textDim
								font.family: Config.bar.iconFontFamily
								font.pixelSize: Config.bar.fontSize + 1
							}

							Item {
								Layout.fillWidth: true
								Layout.preferredHeight: 30

								Text {
									anchors.verticalCenter: parent.verticalCenter
									visible: searchInput.text.length === 0
									text: "Search clipboard history"
									color: Config.colors.textDim
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize
									elide: Text.ElideRight
									width: parent.width
								}

								TextInput {
									id: searchInput
									anchors.fill: parent
									verticalAlignment: TextInput.AlignVCenter
									color: Config.colors.text
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize
									selectByMouse: true
									selectionColor: Config.colors.accent
									selectedTextColor: Config.colors.onAccent
									clip: true

									onTextChanged: root.applyFilter(text)
									onAccepted: root.activateCurrent()

									Keys.onEscapePressed: root.clipOpen = false

									Keys.onDownPressed: {
										if (root.searchResults.length > 0)
											root.currentIndex = (root.currentIndex + 1) % root.searchResults.length
									}
									Keys.onUpPressed: {
										if (root.searchResults.length > 0)
											root.currentIndex = (root.currentIndex - 1 + root.searchResults.length) % root.searchResults.length
									}
									Keys.onTabPressed: {
										if (root.searchResults.length > 0)
											root.currentIndex = (root.currentIndex + 1) % root.searchResults.length
									}
									Keys.onDeletePressed: {
										if (root.currentIndex >= 0 && root.currentIndex < root.searchResults.length)
											root.deleteEntry(root.searchResults[root.currentIndex])
									}
								}
							}

							Text {
								visible: searchInput.text.length > 0
								text: "\uf00d"
								color: searchClear.containsMouse ? Config.colors.text : Config.colors.textDim
								font.family: Config.bar.iconFontFamily
								font.pixelSize: Config.bar.fontSize - 1

								MouseArea {
									id: searchClear
									anchors.fill: parent
									anchors.margins: -6
									hoverEnabled: true
									cursorShape: Qt.PointingHandCursor
									onClicked: {
										searchInput.text = ""
										searchInput.forceActiveFocus()
									}
								}
							}
						}
					}

					// --------------------------------------------------- list

					ListView {
						id: clipList
						Layout.fillWidth: true
						Layout.fillHeight: true
						visible: root.searchResults.length > 0
						model: root.searchResults
						currentIndex: root.currentIndex
						clip: true
						spacing: 3
						boundsBehavior: Flickable.StopAtBounds
						highlightMoveDuration: 80

						onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

						delegate: Item {
							id: delegateRoot
							width: ListView.view.width
							height: delegateRoot.modelData.isImage ? Config.panel.thumbHeight : Config.panel.listItemHeight

							required property var modelData
							required property int index

							property bool isCurrent: ListView.isCurrentItem
							property bool deleting: root.deletingId === parseInt(modelData.id)

							Component.onCompleted: {
								if (modelData.isImage) root.ensureThumbnail(modelData.id, modelData.rawLine)
							}

							Rectangle {
								anchors.fill: parent
								radius: Config.radius.medium
								color: delegateRoot.isCurrent
									? Config.colors.surfaceAlt
									: rowHover.containsMouse
										? Config.colors.surface
										: "transparent"
								border.width: delegateRoot.isCurrent ? 1 : 0
								border.color: Config.colors.hoverBorder
								opacity: delegateRoot.deleting ? 0.35 : 1
								Behavior on color { ColorAnimation { duration: Config.motion.fast } }
								Behavior on opacity { NumberAnimation { duration: Config.motion.fast } }
							}

							ColumnLayout {
								anchors.fill: parent
								anchors.leftMargin: 12
								anchors.rightMargin: 12
								anchors.topMargin: 8
								anchors.bottomMargin: 8
								spacing: 6

								RowLayout {
									Layout.fillWidth: true
									Layout.preferredHeight: 28
									spacing: 10

									Text {
										Layout.alignment: Qt.AlignVCenter
										text: delegateRoot.modelData.isImage ? "\uf03e" : "\uf0c5"
										color: delegateRoot.modelData.isImage ? Config.colors.accent2 : Config.colors.accent
										font.family: Config.bar.iconFontFamily
										font.pixelSize: Config.bar.fontSize
									}

									ColumnLayout {
										Layout.fillWidth: true
										spacing: 1

										Text {
											Layout.fillWidth: true
											text: delegateRoot.modelData.isImage
												? "Image"
												: delegateRoot.modelData.preview
											color: delegateRoot.isCurrent ? Config.colors.text : Config.colors.textMuted
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize
											font.weight: delegateRoot.isCurrent ? 500 : 400
											elide: Text.ElideRight
											maximumLineCount: 1
										}

										Text {
											Layout.fillWidth: true
											text: delegateRoot.modelData.isImage
												? (delegateRoot.modelData.size !== ""
													? delegateRoot.modelData.size + "  ·  " + delegateRoot.modelData.mime
													: delegateRoot.modelData.mime)
												: "text entry"
											color: Config.colors.textDim
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize - 4
											elide: Text.ElideRight
										}
									}

									Text {
										Layout.alignment: Qt.AlignVCenter
										visible: delegateRoot.isCurrent
										text: "\u23ce copy"
										color: Config.colors.textDim
										font.family: Config.bar.fontFamily
										font.pixelSize: Config.bar.fontSize - 4
									}

									Text {
										Layout.alignment: Qt.AlignVCenter
										text: "\uf00d"
										color: delMouse.containsMouse ? Config.colors.bad : Config.colors.textDim
										font.family: Config.bar.iconFontFamily
										font.pixelSize: Config.bar.fontSize - 2
										Behavior on color { ColorAnimation { duration: Config.motion.fast } }

										MouseArea {
											id: delMouse
											anchors.fill: parent
											anchors.margins: -7
											hoverEnabled: true
											cursorShape: Qt.PointingHandCursor
											onClicked: root.deleteEntry(delegateRoot.modelData)
										}
									}
								}

								Item {
									visible: delegateRoot.modelData.isImage
									Layout.fillWidth: true
									Layout.fillHeight: true

									Rectangle {
										anchors.fill: parent
										radius: Config.radius.small
										color: Config.colors.elevated
										border.width: 1
										border.color: Config.colors.borderMuted
										clip: true

										Image {
											id: thumb
											anchors.fill: parent
											anchors.margins: 5
											fillMode: Image.PreserveAspectFit
											asynchronous: true
											cache: false
											source: {
												const path = root.thumbCache[delegateRoot.modelData.id]
												return (path && path !== "pending" && path !== "error")
													? ("file://" + path)
													: ""
											}
										}

										Text {
											anchors.centerIn: parent
											visible: {
												const path = root.thumbCache[delegateRoot.modelData.id]
												return path === "pending" || path === undefined
											}
											text: "\uf03e"
											color: Config.colors.textDim
											font.family: Config.bar.iconFontFamily
											font.pixelSize: 26
										}

										Text {
											anchors.centerIn: parent
											visible: root.thumbCache[delegateRoot.modelData.id] === "error"
											text: "Preview unavailable"
											color: Config.colors.textDim
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize - 2
										}
									}
								}
							}

							MouseArea {
								id: rowHover
								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								z: -1
								onEntered: root.currentIndex = delegateRoot.index
								onClicked: {
									root.currentIndex = delegateRoot.index
									root.activateCurrent()
								}
							}
						}
					}

					Item {
						Layout.fillWidth: true
						Layout.fillHeight: true
						visible: root.searchResults.length === 0

						ColumnLayout {
							anchors.centerIn: parent
							spacing: 8

							Text {
								Layout.alignment: Qt.AlignHCenter
								text: "\uf0ea"
								color: Config.colors.textDim
								font.family: Config.bar.iconFontFamily
								font.pixelSize: 30
							}

							Text {
								Layout.alignment: Qt.AlignHCenter
								text: root.allEntries.length === 0
									? "No clipboard history yet"
									: "No matching entries"
								color: Config.colors.textDim
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 1
							}
						}
					}

					// -------------------------------------------------- footer

					Rectangle {
						Layout.fillWidth: true
						Layout.preferredHeight: 1
						color: Config.colors.borderMuted
					}

					RowLayout {
						Layout.fillWidth: true
						spacing: 14

						Text {
							Layout.fillWidth: true
							text: "\u2191\u2193 navigate   \u23ce copy   \u232b delete   \u238b close"
							color: Config.colors.textDim
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 3
							elide: Text.ElideRight
						}

						Text {
							text: root.allEntries.length + " entries"
							color: Config.colors.textDim
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 3
						}
					}
				}
			}
		}
	}
}
