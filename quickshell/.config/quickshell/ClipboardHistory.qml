import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import "config.js" as Config

Scope {
	id: root
	property bool clipOpen: false

	property var allEntries: []
	property var searchResults: []
	property int currentIndex: -1
	property string query: ""

	property var thumbCache: ({})
	property var pendingQueue: []
	property bool thumbWorkerRunning: false

	readonly property string thumbDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-clip-thumbs"

	Component.onCompleted: mkdirProc.running = true

	Process {
		id: mkdirProc
		command: ["mkdir", "-p", root.thumbDir]
	}

	IpcHandler {
		target: "clipboard"

		function toggle() : void {
			root.clipOpen = !root.clipOpen
		}

		function show() : void {
			root.clipOpen = true
		}

		function hide() : void {
			root.clipOpen = false
		}
	}

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
			onStreamFinished: {
				console.log("[clipboard] cliphist list returned " + this.text.split("\n").filter(l => l.length > 0).length + " lines")
				root.parseList(this.text)
			}
		}
		stderr: StdioCollector {
			onStreamFinished: {
				if (this.text.length > 0) console.log("[clipboard] cliphist list stderr: " + this.text)
			}
		}
		onExited: (code, status) => {
			if (code !== 0) console.log("[clipboard] cliphist list exited with code " + code)
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

		console.log("[clipboard] parsed " + entries.length + " entries, " + entries.filter(e => e.isImage).length + " detected as images")
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
				const e = root.allEntries[i]
				const score = root.fuzzyScore(query, e.searchable)
				if (score < 0) continue
				results.push(Object.assign({}, e, { matchScore: score }))
			}
			results.sort((a, b) => b.matchScore - a.matchScore)
		}

		root.searchResults = results
		root.currentIndex = results.length > 0 ? 0 : -1
	}

	function ensureThumbnail(id, rawLine) {
		if (root.thumbCache[id] !== undefined) return

		const updated = Object.assign({}, root.thumbCache)
		updated[id] = "pending"
		root.thumbCache = updated

		root.pendingQueue.push({
			id: id,
			rawLine: rawLine,
			path: root.thumbDir + "/" + id + ".png"
		})

		if (!root.thumbWorkerRunning) {
			root.processNextThumbnail()
		}
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
		thumbWorker.command = ["sh", "-c", "printf '%s\\n' \"$1\" | cliphist decode > \"$2\"", "--", task.rawLine, task.path]
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

	function copyEntry(entry) {
		Quickshell.execDetached(["sh", "-c", "printf '%s\\n' \"$1\" | cliphist decode | wl-copy", "--", entry.rawLine])
	}

	function deleteEntry(entry) {
		deleteProc.command = ["sh", "-c", "printf '%s\\n' \"$1\" | cliphist delete", "--", entry.rawLine]
		deleteProc.running = true
	}

	Process {
		id: deleteProc
		onExited: root.refreshHistory()
	}

	function activateCurrent() {
		if (root.currentIndex < 0 || root.currentIndex >= root.searchResults.length) return
		const entry = root.searchResults[root.currentIndex]
		root.copyEntry(entry)
		root.clipOpen = false
	}

	Variants {
		model: Quickshell.screens

		PanelWindow {
			required property var modelData
			screen: modelData

			readonly property var monitor: Hyprland.monitorFor(modelData)
			readonly property bool isFocusedMonitor: monitor?.name === Hyprland.focusedMonitor?.name

			visible: root.clipOpen && isFocusedMonitor
			implicitWidth: 520
			implicitHeight: 620
			color: "transparent"
			exclusionMode: ExclusionMode.Ignore

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
				anchors.fill: parent
				radius: Config.radius.large
				color: Config.colors.base
				border.width: 1
				border.color: Config.colors.border

				ColumnLayout {
					anchors.fill: parent
					anchors.margins: Config.panel.padding
					spacing: 10

					RowLayout {
						Layout.fillWidth: true

						Text {
							Layout.fillWidth: true
							text: "clipboard"
							color: Config.colors.textMuted
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize
						}

						Text {
							visible: root.searchResults.length > 0
							text: root.searchResults.length
							color: Config.colors.textDim
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 2
						}
					}

					ColumnLayout {
						Layout.fillWidth: true
						spacing: 6

						RowLayout {
							Layout.fillWidth: true
							spacing: 8

							Item {
								Layout.fillWidth: true
								Layout.preferredHeight: 30

								Text {
									anchors.verticalCenter: parent.verticalCenter
									visible: searchInput.text.length === 0
									text: "search clipboard history"
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
						}

						Rectangle {
							Layout.fillWidth: true
							Layout.preferredHeight: 1
							color: searchInput.activeFocus ? Config.colors.accent : Config.colors.border
						}
					}

					ListView {
						id: clipList
						Layout.fillWidth: true
						Layout.fillHeight: true
						visible: root.searchResults.length > 0
						model: root.searchResults
						currentIndex: root.currentIndex
						clip: true
						spacing: 2
						boundsBehavior: Flickable.StopAtBounds
						highlightMoveDuration: 100

						onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

						delegate: Item {
							id: delegateRoot
							width: ListView.view.width
							height: modelData.isImage ? Config.panel.thumbHeight : Config.panel.listItemHeight

							required property var modelData
							required property int index

							property bool isCurrent: ListView.isCurrentItem

							Component.onCompleted: {
								if (modelData.isImage) root.ensureThumbnail(modelData.id, modelData.rawLine)
							}

							Rectangle {
								anchors.fill: parent
								radius: Config.radius.small
								color: delegateRoot.isCurrent
									? Config.colors.surfaceAlt
									: (mouseArea.containsMouse ? Config.colors.surface : "transparent")
								Behavior on color { ColorAnimation { duration: 100 } }
							}

							Rectangle {
								visible: delegateRoot.isCurrent
								width: 2
								height: parent.height - 12
								anchors.verticalCenter: parent.verticalCenter
								anchors.left: parent.left
								color: Config.colors.accent
							}

							ColumnLayout {
								anchors.fill: parent
								anchors.leftMargin: 14
								anchors.rightMargin: 10
								anchors.topMargin: 6
								anchors.bottomMargin: 6
								spacing: 6

								RowLayout {
									Layout.fillWidth: true
									Layout.preferredHeight: 30
									spacing: 10

									Text {
										text: "\u25a4"
										color: Config.colors.textDim
										font.family: Config.bar.iconFontFamily
										font.pixelSize: Config.bar.fontSize
									}

									ColumnLayout {
										Layout.fillWidth: true
										spacing: 1

										Text {
											Layout.fillWidth: true
											text: modelData.isImage ? "Image" : modelData.preview
											color: delegateRoot.isCurrent ? Config.colors.text : Config.colors.textMuted
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize
											elide: Text.ElideRight
											maximumLineCount: 1
										}

										Text {
											visible: modelData.isImage && modelData.size !== ""
											text: modelData.size
											color: Config.colors.textDim
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize - 3
										}
									}

									Text {
										text: "\u2715"
										color: delBtn.containsMouse ? Config.colors.bad : Config.colors.textDim
										font.pixelSize: Config.bar.fontSize - 1
										Behavior on color { ColorAnimation { duration: 120 } }

										MouseArea {
											id: delBtn
											anchors.fill: parent
											anchors.margins: -6
											hoverEnabled: true
											onClicked: root.deleteEntry(modelData)
										}
									}
								}

								Item {
									visible: modelData.isImage
									Layout.fillWidth: true
									Layout.fillHeight: true

									Rectangle {
										anchors.fill: parent
										radius: Config.radius.small
										color: Config.colors.base
										visible: modelData.isImage

										Image {
											visible: modelData.isImage && root.thumbCache[modelData.id] && root.thumbCache[modelData.id] !== "pending" && root.thumbCache[modelData.id] !== "error"
											anchors.fill: parent
											anchors.margins: 4
											fillMode: Image.PreserveAspectFit
											source: visible ? ("file://" + root.thumbCache[modelData.id]) : ""
											cache: false
										}

										Text {
											visible: modelData.isImage && (root.thumbCache[modelData.id] === "pending" || root.thumbCache[modelData.id] === undefined)
											anchors.centerIn: parent
											text: "..."
											color: Config.colors.textDim
											font.pixelSize: Config.bar.fontSize + 4
										}

										Text {
											visible: modelData.isImage && root.thumbCache[modelData.id] === "error"
											anchors.centerIn: parent
											text: "\u2715"
											color: Config.colors.bad
											font.bold: true
											font.pixelSize: Config.bar.fontSize + 4
										}
									}
								}
							}

							MouseArea {
								id: mouseArea
								anchors.fill: parent
								hoverEnabled: true
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

						Text {
							anchors.centerIn: parent
							text: root.allEntries.length === 0
								? "no clipboard history yet"
								: "no matching entries"
							color: Config.colors.textDim
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 1
							horizontalAlignment: Text.AlignHCenter
						}
					}
				}
			}
		}
	}
}
