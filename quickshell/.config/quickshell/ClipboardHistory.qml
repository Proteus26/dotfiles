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
			implicitWidth: 480
			implicitHeight: 560
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
				radius: 10
				color: Config.colors.base
				border.width: 2
				border.color: Config.colors.mauve

				ColumnLayout {
					anchors.fill: parent
					anchors.margins: 16
					spacing: 12

					RowLayout {
						Layout.fillWidth: true

						Text {
							Layout.fillWidth: true
							text: "Clipboard History"
							color: Config.colors.sky
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize + 1
							font.bold: true
						}

						Text {
							visible: root.searchResults.length > 0
							text: root.searchResults.length + " item" + (root.searchResults.length === 1 ? "" : "s")
							color: Config.colors.subtext0
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 3
						}
					}

					Rectangle {
						Layout.fillWidth: true
						Layout.preferredHeight: 45
						radius: 8
						color: Config.colors.mantle
						border.width: 1
						border.color: searchInput.activeFocus ? Config.colors.sky : Config.colors.overlay2

						RowLayout {
							anchors.fill: parent
							anchors.margins: 12
							spacing: 8

							Text {
								text: ""
								color: Config.colors.subtext0
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize + 2
							}

							Item {
								Layout.fillWidth: true
								Layout.fillHeight: true

								Text {
									anchors.verticalCenter: parent.verticalCenter
									visible: searchInput.text.length === 0
									text: "Search clipboard history..."
									color: Config.colors.subtext0
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
									font.pixelSize: Config.bar.fontSize + 2
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
					}

					ListView {
						id: clipList
						Layout.fillWidth: true
						Layout.fillHeight: true
						visible: root.searchResults.length > 0
						model: root.searchResults
						currentIndex: root.currentIndex
						clip: true
						spacing: 4
						boundsBehavior: Flickable.StopAtBounds
						highlightMoveDuration: 100

						onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

						delegate: Rectangle {
							id: delegateRoot
							width: ListView.view.width
							height: modelData.isImage ? 160 : 56 
							radius: 8

							required property var modelData
							required property int index

							property bool isCurrent: ListView.isCurrentItem
							color: isCurrent
								? Config.colors.surface0
								: (mouseArea.containsMouse ? Config.colors.surface0 : "transparent")
							border.width: isCurrent ? 1 : 0
							border.color: Config.colors.sky

							Component.onCompleted: {
								if (modelData.isImage) root.ensureThumbnail(modelData.id, modelData.rawLine)
							}

							ColumnLayout {
								anchors.fill: parent
								anchors.margins: 10
								spacing: 8

								RowLayout {
									Layout.fillWidth: true
									Layout.preferredHeight: 36
									spacing: 12

									Item {
										Layout.preferredWidth: 36
										Layout.preferredHeight: 36

										Text {
											anchors.centerIn: parent
											text: "󰅍"
											color: Config.colors.subtext0
											font.pixelSize: Config.bar.fontSize + 4
										}
									}

									ColumnLayout {
										Layout.fillWidth: true
										spacing: 2

										Text {
											Layout.fillWidth: true
											text: modelData.isImage ? "Image" : modelData.preview
											color: Config.colors.text
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize
											elide: Text.ElideRight
											maximumLineCount: 1
										}

										Text {
											visible: modelData.isImage && modelData.size !== ""
											text: modelData.size
											color: Config.colors.subtext0
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize - 3
										}
									}

									Rectangle {
										Layout.preferredWidth: 28
										Layout.preferredHeight: 28
										radius: 6
										color: delBtn.containsMouse ? Config.colors.red : "transparent"

										Text {
											anchors.centerIn: parent
											text: "󰆴"
											color: delBtn.containsMouse ? Config.colors.base : Config.colors.subtext0
											font.pixelSize: Config.bar.fontSize
										}

										MouseArea {
											id: delBtn
											anchors.fill: parent
											hoverEnabled: true
											onClicked: root.deleteEntry(modelData)
										}
									}
								}

								Item {
									visible: modelData.isImage
									Layout.fillWidth: true
									Layout.fillHeight: true

									Image {
										id: thumbImg
										visible: modelData.isImage && root.thumbCache[modelData.id] && root.thumbCache[modelData.id] !== "pending" && root.thumbCache[modelData.id] !== "error"
										anchors.fill: parent
										fillMode: Image.PreserveAspectFit
										source: visible ? ("file://" + root.thumbCache[modelData.id]) : ""
										cache: false
									}

									Text {
										visible: modelData.isImage && (root.thumbCache[modelData.id] === "pending" || root.thumbCache[modelData.id] === undefined)
										anchors.centerIn: parent
										text: "󰔟"
										color: Config.colors.subtext0
										font.pixelSize: Config.bar.fontSize + 4
									}

									Text {
										visible: modelData.isImage && root.thumbCache[modelData.id] === "error"
										anchors.centerIn: parent
										text: "󰅖"
										color: Config.colors.red
										font.bold: true
										font.pixelSize: Config.bar.fontSize + 4
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
								? "No clipboard history yet"
								: "No matching entries"
							color: Config.colors.subtext0
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
