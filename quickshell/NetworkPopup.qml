import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

import "config.js" as Config

PopupWindow {
	id: root

	property var parentPanel
	property Item anchorItem
	property string activeSsid: ""
	property string networkType: "offline"
	property int activeSignal: 0

	property bool wifiEnabled: true
	property bool busy: false
	property var collected: []
	property var networks: []
	property string pendingSsid: ""
	property string pendingPassword: ""
	property string statusMessage: ""

	implicitWidth: 340
	implicitHeight: Math.min(520, 210 + Math.min(Math.max(root.networks.length, 1), 6) * 45
		+ (root.pendingSsid !== "" ? 130 : 0)
		+ (root.statusMessage !== "" ? 18 : 0))
	color: "transparent"

	anchor {
		window: root.parentPanel
		adjustment: PopupAdjustment.None
		gravity: Edges.Bottom | Edges.Right

		onAnchoring: {
			const pos = root.anchorItem.QsWindow.contentItem.mapFromItem(
				root.anchorItem,
				root.anchorItem.width / 2 - root.width / 2,
				root.anchorItem.height + 5
			)
			anchor.rect.x = pos.x
			anchor.rect.y = pos.y
		}
	}

	onVisibleChanged: {
		if (visible) {
			root.pendingSsid = ""
			root.pendingPassword = ""
			root.statusMessage = ""
			root.refresh()
		}
	}

	function splitEscaped(line) {
		const parts = []
		let current = ""
		let escaped = false
		for (let i = 0; i < line.length; i++) {
			const ch = line[i]
			if (escaped) {
				current += ch
				escaped = false
			} else if (ch === "\\") {
				escaped = true
			} else if (ch === ":") {
				parts.push(current)
				current = ""
			} else {
				current += ch
			}
		}
		parts.push(current)
		return parts
	}

	function addNetwork(line) {
		if (!line) return
		const parts = root.splitEscaped(line)
		if (parts.length < 4) return
		const ssid = parts[1].trim()
		if (ssid === "") return
		const active = parts[0].trim() === "*" || parts[0].trim().toLowerCase() === "yes"
		const signal = parseInt(parts[2]) || 0
		const security = parts[3].trim()

		for (let i = 0; i < root.collected.length; i++) {
			if (root.collected[i].ssid === ssid) {
				root.collected[i].signal = Math.max(root.collected[i].signal, signal)
				root.collected[i].active = root.collected[i].active || active
				if (root.collected[i].security === "") root.collected[i].security = security
				return
			}
		}

		root.collected.push({
			ssid: ssid,
			signal: signal,
			security: security,
			active: active
		})
	}

	function commitNetworks() {
		const list = root.collected.slice()
		list.sort((a, b) => {
			if (a.active !== b.active) return a.active ? -1 : 1
			return b.signal - a.signal
		})
		root.networks = list
	}

	function refresh() {
		if (!root.visible) return
		wifiListProc.running = false
		wifiRadioProc.running = false
		wifiListProc.running = true
		wifiRadioProc.running = true
	}

	function toggleWifi() {
		const next = !root.wifiEnabled
		root.wifiEnabled = next
		root.pendingSsid = ""
		root.pendingPassword = ""
		root.statusMessage = ""
		wifiToggleProc.command = ["nmcli", "radio", "wifi", next ? "on" : "off"]
		wifiToggleProc.running = true
	}

	function connectTo(ssid, password) {
		root.busy = true
		root.statusMessage = "Connecting to " + ssid + "..."
		connectProc.command = password.length > 0
			? ["nmcli", "device", "wifi", "connect", ssid, "password", password]
			: ["nmcli", "device", "wifi", "connect", ssid]
		connectProc.running = true
	}

	function selectNetwork(network) {
		if (!network || network.active || !root.wifiEnabled || root.busy) return
		root.statusMessage = ""
		if (network.security === "" || network.security === "--") {
			root.pendingSsid = ""
			root.pendingPassword = ""
			root.connectTo(network.ssid, "")
		} else {
			root.pendingSsid = network.ssid
			root.pendingPassword = ""
			passwordInput.text = ""
			Qt.callLater(() => passwordInput.forceActiveFocus())
		}
	}

	function connectPending() {
		if (root.pendingSsid === "") return
		if (root.pendingPassword.length === 0) {
			root.statusMessage = "Enter the Wi-Fi password"
			return
		}
		const ssid = root.pendingSsid
		const password = root.pendingPassword
		root.pendingSsid = ""
		root.pendingPassword = ""
		passwordInput.text = ""
		root.connectTo(ssid, password)
	}

	function signalIcon(signal) {
		if (signal >= 75) return "\udb82\udd28"
		if (signal >= 50) return "\udb82\udd25"
		if (signal >= 25) return "\udb82\udd22"
		return "\udb82\udd1f"
	}

	function activeLabel() {
		if (!root.wifiEnabled) return "Wi-Fi is off"
		if (root.networkType === "ethernet") return root.activeSsid || "Wired"
		if (root.networkType === "wifi" && root.activeSsid !== "" && root.activeSsid !== "Offline")
			return root.activeSsid
		return "Not connected"
	}

	function activeIcon() {
		if (!root.wifiEnabled) return "\uf05aa"
		if (root.networkType === "ethernet") return "\uef09"
		if (root.networkType === "wifi") return root.signalIcon(root.activeSignal)
		return "\uf05aa"
	}

	Process {
		id: wifiRadioProc
		command: ["nmcli", "radio", "wifi"]
		stdout: SplitParser {
			onRead: data => root.wifiEnabled = data.trim() === "enabled"
		}
	}

	Process {
		id: wifiListProc
		command: ["sh", "-c", "nmcli device wifi rescan >/dev/null 2>&1; nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list"]

		onStarted: root.collected = []

		stdout: SplitParser {
			onRead: data => root.addNetwork(data)
		}

		onExited: root.commitNetworks()
	}

	Process {
		id: wifiToggleProc
		onExited: root.refresh()
	}

	Process {
		id: connectProc
		onExited: (exitCode, exitStatus) => {
			root.busy = false
			root.statusMessage = exitCode === 0 ? "Connected" : "Could not connect"
			root.refresh()
		}
	}

	Timer {
		interval: 15000
		running: root.visible
		repeat: true
		onTriggered: root.refresh()
	}

	Rectangle {
		anchors.fill: parent
		radius: Config.radius.large
		color: Config.colors.base
		border.width: 1
		border.color: Config.colors.border

		ColumnLayout {
			anchors.fill: parent
			anchors.margins: 14
			spacing: 8

			RowLayout {
				Layout.fillWidth: true
				spacing: 6

				Text {
					text: "\uf1eb"
					color: root.wifiEnabled ? Config.colors.accent2 : Config.colors.textDim
					font.family: Config.bar.iconFontFamily
					font.pixelSize: Config.bar.fontSize
				}

				Text {
					Layout.fillWidth: true
					text: "Network"
					color: Config.colors.text
					font.family: Config.bar.fontFamily
					font.pixelSize: Config.bar.fontSize
					font.weight: 700
				}

				IconButton {
					icon: "\uf021"
					iconSize: Config.bar.fontSize - 2
					iconColor: Config.colors.textMuted
					onClicked: root.refresh()
				}

				IconButton {
					icon: "\uf011"
					iconSize: Config.bar.fontSize - 1
					active: root.wifiEnabled
					activeColor: Config.colors.accent
					iconColor: Config.colors.textDim
					onClicked: root.toggleWifi()
				}
			}

			RowLayout {
				Layout.fillWidth: true
				spacing: 8

				Text {
					text: root.activeIcon()
					color: root.wifiEnabled ? Config.colors.accent2 : Config.colors.textDim
					font.family: Config.bar.iconFontFamily
					font.pixelSize: Config.bar.fontSize
				}

				Text {
					Layout.fillWidth: true
					text: root.activeLabel()
					color: Config.colors.textMuted
					font.family: Config.bar.fontFamily
					font.pixelSize: Config.bar.fontSize - 2
					elide: Text.ElideRight
				}

				Text {
					visible: root.busy
					text: "Connecting..."
					color: Config.colors.warn
					font.family: Config.bar.fontFamily
					font.pixelSize: Config.bar.fontSize - 3
				}
			}

			Rectangle {
				Layout.fillWidth: true
				Layout.preferredHeight: 1
				color: Config.colors.borderMuted
			}

			Text {
				text: "Available networks"
				color: Config.colors.textDim
				font.family: Config.bar.fontFamily
				font.pixelSize: Config.bar.fontSize - 4
				font.weight: 600
			}

			Item {
				Layout.fillWidth: true
				Layout.fillHeight: true
				Layout.minimumHeight: 40

				ListView {
					id: networkList
					anchors.fill: parent
					clip: true
					spacing: 3
					model: root.networks
					visible: root.networks.length > 0

					delegate: Rectangle {
						id: networkRow
						required property var modelData
						width: ListView.view.width
						height: 42
						radius: Config.radius.small
						color: modelData.active
							? Config.colors.accentFaint
							: rowHover.containsMouse
								? Config.colors.surface
								: "transparent"
						border.width: modelData.active ? 1 : 0
						border.color: Config.colors.accentDim

						RowLayout {
							anchors.fill: parent
							anchors.leftMargin: 8
							anchors.rightMargin: 8
							spacing: 8

							Text {
								text: root.signalIcon(networkRow.modelData.signal)
								color: networkRow.modelData.active ? Config.colors.accent : Config.colors.textMuted
								font.family: Config.bar.iconFontFamily
								font.pixelSize: Config.bar.fontSize
							}

							ColumnLayout {
								Layout.fillWidth: true
								spacing: 0

								Text {
									Layout.fillWidth: true
									text: networkRow.modelData.ssid
									color: Config.colors.text
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize - 2
									font.weight: networkRow.modelData.active ? 600 : 400
									elide: Text.ElideRight
								}

								Text {
									text: networkRow.modelData.active
										? "Connected"
										: networkRow.modelData.security !== "" && networkRow.modelData.security !== "--"
											? networkRow.modelData.security
											: "Open"
									color: networkRow.modelData.active ? Config.colors.accent : Config.colors.textDim
									font.family: Config.bar.fontFamily
									font.pixelSize: Config.bar.fontSize - 6
								}
							}

							Text {
								visible: networkRow.modelData.security !== ""
									&& networkRow.modelData.security !== "--"
								text: "\uf023"
								color: Config.colors.textDim
								font.family: Config.bar.iconFontFamily
								font.pixelSize: Config.bar.fontSize - 4
							}

							Text {
								text: networkRow.modelData.signal + "%"
								color: Config.colors.textDim
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 5
							}
						}

						MouseArea {
							id: rowHover
							anchors.fill: parent
							hoverEnabled: true
							cursorShape: Qt.PointingHandCursor
							onClicked: root.selectNetwork(networkRow.modelData)
						}
					}
				}

				Text {
					anchors.centerIn: parent
					visible: root.networks.length === 0
					text: root.wifiEnabled ? "No networks found" : "Wi-Fi is off"
					color: Config.colors.textDim
					font.family: Config.bar.fontFamily
					font.pixelSize: Config.bar.fontSize - 2
				}
			}

			Rectangle {
				Layout.fillWidth: true
				Layout.preferredHeight: visible ? passwordColumn.implicitHeight + 20 : 0
				visible: root.pendingSsid !== ""
				radius: Config.radius.small
				color: Config.colors.surface
				border.width: 1
				border.color: Config.colors.borderMuted

				ColumnLayout {
					id: passwordColumn
					anchors.fill: parent
					anchors.margins: 10
					spacing: 7

					Text {
						Layout.fillWidth: true
						text: "Connect to " + root.pendingSsid
						color: Config.colors.text
						font.family: Config.bar.fontFamily
						font.pixelSize: Config.bar.fontSize - 2
						font.weight: 600
						elide: Text.ElideRight
					}

					Rectangle {
						Layout.fillWidth: true
						Layout.preferredHeight: 32
						radius: Config.radius.small
						color: Config.colors.base
						border.width: 1
						border.color: Config.colors.borderMuted

						TextInput {
							id: passwordInput
							anchors.fill: parent
							anchors.leftMargin: 9
							anchors.rightMargin: 9
							verticalAlignment: TextInput.AlignVCenter
							echoMode: TextInput.Password
							color: Config.colors.text
							font.family: Config.bar.fontFamily
							font.pixelSize: Config.bar.fontSize - 2
							selectByMouse: true
							selectionColor: Config.colors.accent
							selectedTextColor: Config.colors.onAccent
							clip: true
							onTextChanged: root.pendingPassword = text
							onAccepted: root.connectPending()

							Text {
								anchors.verticalCenter: parent.verticalCenter
								visible: passwordInput.text.length === 0
								text: "Password"
								color: Config.colors.textDim
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 2
							}
						}
					}

					RowLayout {
						Layout.fillWidth: true
						spacing: 6

						Item { Layout.fillWidth: true }

						Rectangle {
							Layout.preferredWidth: 64
							Layout.preferredHeight: 28
							radius: Config.radius.small
							color: cancelHover.containsMouse ? Config.colors.surfaceAlt : "transparent"

							Text {
								anchors.centerIn: parent
								text: "Cancel"
								color: Config.colors.textMuted
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 3
							}

							MouseArea {
								id: cancelHover
								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: {
									root.pendingSsid = ""
									root.pendingPassword = ""
									passwordInput.text = ""
									root.statusMessage = ""
								}
							}
						}

						Rectangle {
							Layout.preferredWidth: 78
							Layout.preferredHeight: 28
							radius: Config.radius.small
							color: connectHover.containsMouse ? Config.colors.accentDim : Config.colors.accent

							Text {
								anchors.centerIn: parent
								text: "Connect"
								color: Config.colors.onAccent
								font.family: Config.bar.fontFamily
								font.pixelSize: Config.bar.fontSize - 3
								font.weight: 600
							}

							MouseArea {
								id: connectHover
								anchors.fill: parent
								hoverEnabled: true
								cursorShape: Qt.PointingHandCursor
								onClicked: root.connectPending()
							}
						}
					}
				}
			}

			Text {
				Layout.fillWidth: true
				visible: root.statusMessage !== ""
				text: root.statusMessage
				color: root.statusMessage === "Connected" ? Config.colors.accent : Config.colors.textDim
				font.family: Config.bar.fontFamily
				font.pixelSize: Config.bar.fontSize - 4
				elide: Text.ElideRight
			}
		}
	}
}
