import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

import "config.js" as Config

Scope {
	id: root

	property bool launcherOpen: false
	property string mode: "apps"
	property string calcExpression: ""
	property string calcResult: ""
	property bool calcValid: false
	property var searchResults: []
	property int currentIndex: -1
	property string query: ""

	IpcHandler {
		target: "launcher"

		function toggle(): void {
			if (!root.launcherOpen) root.closeOtherPanels()
			root.launcherOpen = !root.launcherOpen
		}

		function show(): void {
			root.closeOtherPanels()
			root.launcherOpen = true
		}

		function hide(): void {
			root.launcherOpen = false
		}
	}

	function ipcCall(target, fn) {
		Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", target, fn])
	}

	function closeOtherPanels() {
		root.ipcCall("clipboard", "hide")
		root.ipcCall("notifications", "hide")
		root.ipcCall("controlcenter", "hide")
		root.ipcCall("powermenu", "hide")
	}

	readonly property var systemCommands: [
		{ title: "Lock screen", detail: "Lock the current session", icon: "\uf023", action: "lock" },
		{ title: "Clipboard history", detail: "Browse and restore copied items", icon: "\uf0ea", action: "clipboard" },
		{ title: "Notifications", detail: "Open the notification center", icon: "\uf0f3", action: "notifications" },
		{ title: "Control center", detail: "Volume, brightness and system controls", icon: "\uf1de", action: "controlcenter" },
		{ title: "Power menu", detail: "Lock, suspend, reboot or shut down", icon: "\uf011", action: "powermenu" },
		{ title: "Suspend", detail: "Put the computer to sleep", icon: "\uf186", action: "suspend" },
		{ title: "Reboot", detail: "Restart the computer", icon: "\uf021", action: "reboot" },
		{ title: "Shut down", detail: "Power the computer off", icon: "\uf011", action: "shutdown" }
	]

	// ---------------------------------------------------------------- search

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

	function safeCalculate(expr) {
		if (!/^[0-9+\-*/().%\s]+$/.test(expr)) return null
		try {
			const result = Function('"use strict"; return (' + expr + ')')()
			return (typeof result === "number" && isFinite(result)) ? result : null
		} catch (e) {
			return null
		}
	}

	function updateModel(text) {
		root.query = text
		const trimmed = text.trim()

		if (text.startsWith("=")) {
			root.mode = "calc"
			const expr = text.slice(1).trim()
			root.calcExpression = expr
			if (expr.length === 0) {
				root.calcValid = false
				root.calcResult = ""
			} else {
				const result = root.safeCalculate(expr)
				root.calcValid = result !== null
				root.calcResult = result !== null ? String(result) : ""
			}
			root.searchResults = []
			root.currentIndex = root.calcValid ? 0 : -1
			return
		}

		if (text.startsWith(">")) {
			root.mode = "commands"
			const q = text.slice(1).trim()
			let results = []

			for (let i = 0; i < root.systemCommands.length; i++) {
				const command = root.systemCommands[i]
				const score = q === ""
					? 1
					: Math.max(
						root.fuzzyScore(q, command.title),
						root.fuzzyScore(q, command.detail) * 0.5
					)
				if (score < 0) continue
				results.push({
					title: command.title,
					subtitle: command.detail,
					icon: command.icon,
					iconFont: true,
					action: command.action,
					matchScore: score
				})
			}

			results.sort((a, b) => {
				if (b.matchScore !== a.matchScore) return b.matchScore - a.matchScore
				return a.title.localeCompare(b.title)
			})

			root.searchResults = results
			root.currentIndex = results.length > 0 ? 0 : -1
			return
		}

		root.mode = "apps"
		const allApps = DesktopEntries.applications.values
		let results = []

		for (let i = 0; i < allApps.length; i++) {
			const app = allApps[i]
			if (!app || app.noDisplay || !app.name) continue

			let score = 0
			if (trimmed !== "") {
				const nameScore = root.fuzzyScore(trimmed, app.name)
				const genericScore = app.genericName ? root.fuzzyScore(trimmed, app.genericName) : -1
				const commentScore = app.comment ? root.fuzzyScore(trimmed, app.comment) * 0.4 : -1
				let keywordScore = -1

				if (app.keywords) {
					for (let k = 0; k < app.keywords.length; k++)
						keywordScore = Math.max(keywordScore, root.fuzzyScore(trimmed, app.keywords[k]))
				}

				score = Math.max(nameScore, genericScore * 0.7, commentScore, keywordScore * 0.5)
				if (score < 0) continue
			} else {
				score = 1
			}

			results.push({
				title: app.name,
				subtitle: app.comment || app.genericName || "",
				icon: app.icon || "",
				iconFont: false,
				appObj: app,
				action: "",
				matchScore: score
			})
		}

		results.sort((a, b) => {
			if (b.matchScore !== a.matchScore) return b.matchScore - a.matchScore
			return a.title.localeCompare(b.title)
		})

		root.searchResults = results
		root.currentIndex = results.length > 0 ? 0 : -1
	}

	// -------------------------------------------------------------- activate

	function activateCurrent() {
		if (root.mode === "calc") {
			if (root.calcValid) {
				Quickshell.execDetached(["wl-copy", root.calcResult])
				Qt.callLater(() => root.launcherOpen = false)
			}
			return
		}

		if (root.currentIndex < 0 || root.currentIndex >= root.searchResults.length) return
		const entry = root.searchResults[root.currentIndex]

		if (entry.action !== "") {
			root.launcherOpen = false
			root.runAction(entry.action)
			return
		}

		if (entry.appObj) entry.appObj.execute()
		root.launcherOpen = false
	}

	function runAction(action) {
		if (action === "lock") {
			Quickshell.execDetached(["loginctl", "lock-session"])
		} else if (action === "suspend") {
			Quickshell.execDetached(["systemctl", "suspend"])
		} else if (action === "reboot") {
			Quickshell.execDetached(["systemctl", "reboot"])
		} else if (action === "shutdown") {
			Quickshell.execDetached(["systemctl", "poweroff"])
		} else {
			root.ipcCall(action, "toggle")
		}
	}

	// ---------------------------------------------------------------- panel

	Variants {
		model: Quickshell.screens

		PanelWindow {
			id: launcherWindow
			required property var modelData
			screen: modelData

			readonly property var monitor: Hyprland.monitorFor(modelData)
			readonly property bool isFocusedMonitor: monitor?.name === Hyprland.focusedMonitor?.name

			visible: root.launcherOpen && isFocusedMonitor
			implicitWidth: 620
			implicitHeight: 600
			color: "transparent"
			exclusionMode: ExclusionMode.Ignore

			WlrLayershell.layer: WlrLayer.Overlay
			WlrLayershell.namespace: "launcher"
			WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

			onVisibleChanged: {
				if (visible) {
					searchInput.text = ""
					root.updateModel("")
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
				opacity: launcherWindow.visible ? 1 : 0
				scale: launcherWindow.visible ? 1 : 0.97
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
							text: "Launcher"
							color: Config.colors.text
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize + 1
							font.weight: 700
						}

						Text {
							text: Qt.formatDateTime(new Date(), "HH:mm")
							color: Config.colors.textDim
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 2
						}
					}

					// -------------------------------------------------- search

					Rectangle {
						Layout.fillWidth: true
						Layout.preferredHeight: 46
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
								text: root.mode === "calc" ? "=" : root.mode === "commands" ? ">" : "\uf002"
								color: root.mode === "calc" ? Config.colors.accent : Config.colors.textDim
								font.family: root.mode === "apps" ? Config.bar.iconFontFamily : Config.bar.fontFamily
								font.pixelSize: root.mode === "apps" ? Config.bar.fontSize + 1 : Config.bar.fontSize + 1
								font.weight: 700
							}

							Item {
								Layout.fillWidth: true
								Layout.preferredHeight: 30

								Text {
									anchors.verticalCenter: parent.verticalCenter
									visible: searchInput.text.length === 0
									text: "Search applications, or use = or >"
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

									onTextChanged: root.updateModel(text)
									onAccepted: root.activateCurrent()

									Keys.onEscapePressed: root.launcherOpen = false

									Keys.onDownPressed: {
										if (root.mode === "calc") return
										if (root.searchResults.length > 0)
											root.currentIndex = (root.currentIndex + 1) % root.searchResults.length
									}
									Keys.onUpPressed: {
										if (root.mode === "calc") return
										if (root.searchResults.length > 0)
											root.currentIndex = (root.currentIndex - 1 + root.searchResults.length) % root.searchResults.length
									}
									Keys.onTabPressed: {
										if (root.mode === "calc") return
										if (root.searchResults.length > 0)
											root.currentIndex = (root.currentIndex + 1) % root.searchResults.length
									}
								}
							}

							Text {
								visible: searchInput.text.length > 0
								text: "\uf00d"
								color: clearMouse.containsMouse ? Config.colors.text : Config.colors.textDim
								font.family: Config.bar.iconFontFamily
								font.pixelSize: Config.bar.fontSize - 1

								MouseArea {
									id: clearMouse
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

					// --------------------------------------------------- calc

					Rectangle {
						visible: root.mode === "calc"
						Layout.fillWidth: true
						Layout.fillHeight: true
						radius: Config.radius.medium
						color: Config.colors.elevated
						border.width: 1
						border.color: root.calcValid ? Config.colors.accentDim : Config.colors.borderMuted

						ColumnLayout {
							anchors.centerIn: parent
							spacing: 10

							Text {
								Layout.alignment: Qt.AlignHCenter
								text: root.calcExpression !== "" ? root.calcExpression : "type an expression"
								color: Config.colors.textMuted
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize + 1
							}

							Text {
								Layout.alignment: Qt.AlignHCenter
								text: root.calcExpression === ""
									? "="
									: root.calcValid ? "= " + root.calcResult : "invalid expression"
								color: root.calcValid ? Config.colors.accent : Config.colors.bad
								font.family: Config.bar.displayFontFamily
								font.pixelSize: root.calcValid ? 34 : Config.bar.fontSize + 2
								font.weight: root.calcValid ? 700 : 500
								elide: Text.ElideRight
								Layout.maximumWidth: 520
							}

							Text {
								Layout.alignment: Qt.AlignHCenter
								visible: root.calcValid
								text: "Press Enter to copy the result"
								color: Config.colors.textDim
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 2
							}
						}

						MouseArea {
							anchors.fill: parent
							cursorShape: root.calcValid ? Qt.PointingHandCursor : Qt.ArrowCursor
							onClicked: root.activateCurrent()
						}
					}

					// ------------------------------------------------- results

					ColumnLayout {
						visible: root.mode !== "calc"
						Layout.fillWidth: true
						Layout.fillHeight: true
						spacing: 8

						RowLayout {
							Layout.fillWidth: true
							spacing: 6

							Text {
								Layout.fillWidth: true
								text: root.mode === "commands" ? "System commands" : "Applications"
								color: Config.colors.textDim
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 3
								font.weight: 600
								font.letterSpacing: 0.6
							}

							Text {
								text: root.searchResults.length
								color: Config.colors.textDim
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 3
							}
						}

						ListView {
							id: appList
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
								height: 58

								required property var modelData
								required property int index
								property bool isCurrent: ListView.isCurrentItem

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
									Behavior on color { ColorAnimation { duration: Config.motion.fast } }
								}

								RowLayout {
									anchors.fill: parent
									anchors.leftMargin: 12
									anchors.rightMargin: 12
									spacing: 12

									Rectangle {
										Layout.preferredWidth: 36
										Layout.preferredHeight: 36
										Layout.alignment: Qt.AlignVCenter
										radius: Config.radius.small
										color: Config.colors.elevated
										border.width: 1
										border.color: Config.colors.borderMuted

										Text {
											anchors.centerIn: parent
											text: delegateRoot.modelData.title.charAt(0).toUpperCase()
											color: Config.colors.textDim
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize + 1
											font.weight: 700
										}

										Text {
											visible: delegateRoot.modelData.iconFont
											anchors.centerIn: parent
											text: delegateRoot.modelData.icon
											color: Config.colors.accent
											font.family: Config.bar.iconFontFamily
											font.pixelSize: Config.bar.fontSize + 3
										}

										Image {
											visible: !delegateRoot.modelData.iconFont && source.toString() !== ""
											anchors.fill: parent
											anchors.margins: 5
											source: delegateRoot.modelData.iconFont
												? ""
												: (Quickshell.iconPath(delegateRoot.modelData.icon, true) || "")
											fillMode: Image.PreserveAspectFit
											smooth: true
											asynchronous: true
										}
									}

									ColumnLayout {
										Layout.fillWidth: true
										Layout.alignment: Qt.AlignVCenter
										spacing: 1

										Text {
											Layout.fillWidth: true
											text: delegateRoot.modelData.title
											color: delegateRoot.isCurrent ? Config.colors.text : Config.colors.textMuted
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize
											font.weight: delegateRoot.isCurrent ? 600 : 500
											elide: Text.ElideRight
										}

										Text {
											Layout.fillWidth: true
											visible: text !== ""
											text: delegateRoot.modelData.subtitle
											color: Config.colors.textDim
											font.family: Config.bar.fontFamily
											font.pixelSize: Config.bar.fontSize - 3
											elide: Text.ElideRight
										}
									}

									Text {
										Layout.alignment: Qt.AlignVCenter
										visible: delegateRoot.isCurrent
										text: "\u23ce"
										color: Config.colors.accent
										font.family: Config.bar.fontFamily
										font.pixelSize: Config.bar.fontSize
									}
								}

								MouseArea {
									id: rowHover
									anchors.fill: parent
									hoverEnabled: true
									cursorShape: Qt.PointingHandCursor
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
									text: root.mode === "commands" ? "\uf120" : "\uf002"
									color: Config.colors.textDim
									font.family: Config.bar.iconFontFamily
									font.pixelSize: 28
								}

								Text {
									Layout.alignment: Qt.AlignHCenter
									text: root.mode === "commands"
										? "No matching commands"
										: "No matching applications"
									color: Config.colors.textDim
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize - 1
								}
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
							text: "\u2191\u2193 navigate   \u23ce open   \u238b close"
							color: Config.colors.textDim
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 3
							elide: Text.ElideRight
						}

						Text {
							text: "= calculate   > commands"
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
