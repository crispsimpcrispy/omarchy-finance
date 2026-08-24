import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.crispsimpcrispy.finance"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property string backendPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.crispsimpcrispy.finance/backend.sh"

  property var configData: ({ watchlist: [], refreshSeconds: 60 })
  property var quoteData: ({ quotes: [], updatedAt: 0 })
  property bool addOpen: false
  property string addType: "stock"
  property string statusMessage: ""
  property bool statusError: false
  property bool busy: false

  readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
  readonly property color background: Color.popups.background
  readonly property color borderColor: Color.popups.border
  readonly property color accent: Color.accent
  readonly property color mutedText: Util.alpha(root.foreground, 0.62)
  readonly property color subtleSurface: Util.alpha(root.foreground, 0.045)
  readonly property color subtleBorder: Util.alpha(root.foreground, 0.11)
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  function open(payloadJson) {
    root.addOpen = false
    root.statusMessage = ""
    root.controller.show()
    root.refreshAll(false)
  }

  function close() { root.controller.hide() }

  function toggle(payloadJson) {
    if (root.opened) root.close()
    else root.open(payloadJson || "{}")
  }

  function closeForPopoutSwitch() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function parseJson(text, fallback) {
    try { return JSON.parse(String(text || "")) } catch (e) { return fallback }
  }

  function refreshAll(force) {
    root.loadConfig()
    root.loadQuotes(force)
  }

  function loadConfig() {
    if (configProc.running) return
    configProc.command = [root.backendPath, "config"]
    configProc.running = true
  }

  function loadQuotes(force) {
    if (quoteProc.running) return
    root.busy = true
    quoteProc.command = force
      ? [root.backendPath, "quotes", "--force"]
      : [root.backendPath, "quotes"]
    quoteProc.running = true
  }

  function quoteBySymbol(symbol) {
    var rows = root.quoteData.quotes || []
    for (var i = 0; i < rows.length; ++i)
      if (String(rows[i].symbol).toUpperCase() === String(symbol).toUpperCase()) return rows[i]
    return null
  }

  function formatPct(value) {
    var n = Number(value)
    if (isNaN(n)) return "—"
    return (n >= 0 ? "+" : "") + n.toFixed(2) + "%"
  }

  function formatChange(value, currency) {
    var n = Number(value)
    if (isNaN(n)) return "—"
    var prefix = n >= 0 ? "+" : ""
    return prefix + n.toFixed(Math.abs(n) < 1 ? 4 : 2) + (currency ? " " + currency : "")
  }

  function changeColor(value) {
    var n = Number(value)
    if (isNaN(n) || n === 0) return root.mutedText
    if (n < 0) return root.bar ? root.bar.urgent : "#d46a6a"
    return root.accent
  }

  function updatedText() {
    var ts = Number(root.quoteData.updatedAt || 0)
    if (!ts) return "Not refreshed yet"
    try { return "Updated " + new Date(ts * 1000).toLocaleTimeString() }
    catch (e) { return "Updated" }
  }

  function addAsset() {
    var symbol = symbolInput.text.trim().toUpperCase()
    var name = nameInput.text.trim()
    if (!symbol) {
      root.statusError = true
      root.statusMessage = "Enter a ticker or crypto symbol."
      return
    }
    root.runAction(["add", symbol, name, root.addType], "Adding " + symbol + "…")
  }

  function removeAsset(symbol) {
    root.runAction(["remove", symbol], "Removing " + symbol + "…")
  }

  function runAction(args, message) {
    if (actionProc.running) return
    root.busy = true
    root.statusError = false
    root.statusMessage = message || "Working…"
    actionProc.command = [root.backendPath].concat(args)
    actionProc.running = true
  }

  Process {
    id: configProc
    stdout: StdioCollector { id: configOut; waitForEnd: true }
    stderr: StdioCollector { id: configErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.configData = root.parseJson(configOut.text, { watchlist: [], refreshSeconds: 60 })
        watchModel.clear()
        var rows = root.configData.watchlist || []
        for (var i = 0; i < rows.length; ++i) {
          watchModel.append({
            symbol: String(rows[i].symbol || ""),
            name: String(rows[i].name || rows[i].symbol || "Asset"),
            assetType: String(rows[i].type || "stock")
          })
        }
      } else {
        root.statusError = true
        root.statusMessage = String(configErr.text || "Could not read watchlist.").trim()
      }
    }
  }

  Process {
    id: quoteProc
    stdout: StdioCollector { id: quoteOut; waitForEnd: true }
    stderr: StdioCollector { id: quoteErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode === 0) {
        root.quoteData = root.parseJson(quoteOut.text, { quotes: [], updatedAt: 0 })
        root.statusError = false
        root.statusMessage = ""
        if (root.hostWidget) root.hostWidget.refreshQuotes(false)
      } else {
        root.statusError = true
        root.statusMessage = String(quoteErr.text || "Could not refresh prices.").trim()
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode !== 0) {
        root.statusError = true
        root.statusMessage = String(actionErr.text || "Action failed.").trim()
        return
      }
      root.statusError = false
      root.statusMessage = String(actionOut.text || "Saved.").trim()
      symbolInput.text = ""
      nameInput.text = ""
      root.addOpen = false
      root.refreshAll(true)
    }
  }

  ListModel { id: watchModel }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher

    contentWidth: panel.fittedContentWidth(Style.space(620))
    contentHeight: panel.fittedContentHeight(Style.space(610))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        anchors.fill: parent
        spacing: Style.space(10)

        Row {
          width: parent.width
          spacing: Style.space(8)

          Column {
            width: parent.width - refreshButton.width - addButton.width - Style.space(16)
            spacing: Style.space(2)
            Text {
              text: "Finance Watchlist"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              text: root.updatedText()
              color: root.mutedText
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Rectangle {
            id: refreshButton
            width: Style.space(82); height: Style.space(34); radius: Style.space(8)
            color: refreshMouse.containsMouse ? Util.alpha(root.foreground, 0.18) : root.subtleSurface
            border.width: 1; border.color: root.subtleBorder
            Text { anchors.centerIn: parent; text: root.busy ? "Loading…" : "Refresh"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            MouseArea { id: refreshMouse; anchors.fill: parent; hoverEnabled: true; enabled: !root.busy; onClicked: root.loadQuotes(true) }
          }

          Rectangle {
            id: addButton
            width: Style.space(70); height: Style.space(34); radius: Style.space(8)
            color: addMouse.containsMouse ? Util.alpha(root.accent, 0.22) : Util.alpha(root.accent, 0.10)
            border.width: 1; border.color: Util.alpha(root.accent, 0.42)
            Text { anchors.centerIn: parent; text: root.addOpen ? "Cancel" : "+ Add"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
            MouseArea { id: addMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.addOpen = !root.addOpen }
          }
        }

        Rectangle {
          width: parent.width
          height: root.addOpen ? Style.space(122) : 0
          visible: root.addOpen
          radius: Style.space(9)
          color: root.subtleSurface
          border.width: 1
          border.color: root.subtleBorder

          Column {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(8)

            Row {
              width: parent.width
              spacing: Style.space(8)

              Rectangle {
                width: Style.space(128); height: Style.space(34); radius: Style.space(6); color: Util.alpha(root.foreground, 0.06); border.width: 1; border.color: root.subtleBorder
                TextInput { id: symbolInput; anchors.fill: parent; anchors.margins: Style.space(7); color: root.foreground; font.family: root.fontFamily; verticalAlignment: TextInput.AlignVCenter; selectByMouse: true }
                Text { anchors.left: parent.left; anchors.leftMargin: Style.space(7); anchors.verticalCenter: parent.verticalCenter; visible: !symbolInput.text; text: "AAPL / BTC-USD"; color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
              }

              Rectangle {
                width: parent.width - Style.space(128) - typeStock.width - typeCrypto.width - Style.space(24); height: Style.space(34); radius: Style.space(6); color: Util.alpha(root.foreground, 0.06); border.width: 1; border.color: root.subtleBorder
                TextInput { id: nameInput; anchors.fill: parent; anchors.margins: Style.space(7); color: root.foreground; font.family: root.fontFamily; verticalAlignment: TextInput.AlignVCenter; selectByMouse: true }
                Text { anchors.left: parent.left; anchors.leftMargin: Style.space(7); anchors.verticalCenter: parent.verticalCenter; visible: !nameInput.text; text: "Display name (optional)"; color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
              }

              Rectangle {
                id: typeStock
                width: Style.space(64); height: Style.space(34); radius: Style.space(6)
                color: root.addType === "stock" ? Util.alpha(root.accent, 0.18) : Util.alpha(root.foreground, 0.05)
                border.width: 1; border.color: root.addType === "stock" ? Util.alpha(root.accent, 0.50) : root.subtleBorder
                Text { anchors.centerIn: parent; text: "Stock"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                MouseArea { anchors.fill: parent; onClicked: root.addType = "stock" }
              }

              Rectangle {
                id: typeCrypto
                width: Style.space(64); height: Style.space(34); radius: Style.space(6)
                color: root.addType === "crypto" ? Util.alpha(root.accent, 0.18) : Util.alpha(root.foreground, 0.05)
                border.width: 1; border.color: root.addType === "crypto" ? Util.alpha(root.accent, 0.50) : root.subtleBorder
                Text { anchors.centerIn: parent; text: "Crypto"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                MouseArea { anchors.fill: parent; onClicked: root.addType = "crypto" }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)
              Text {
                width: parent.width - saveAssetButton.width - Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: root.addType === "crypto" ? "Crypto symbols use pairs such as BTC-USD or ETH-USD." : "Use market ticker symbols such as AAPL, TSLA or RR.L."
                color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap
              }
              Rectangle {
                id: saveAssetButton
                width: Style.space(86); height: Style.space(32); radius: Style.space(6)
                color: saveAssetMouse.containsMouse ? Util.alpha(root.accent, 0.24) : Util.alpha(root.accent, 0.12)
                border.width: 1; border.color: Util.alpha(root.accent, 0.45)
                Text { anchors.centerIn: parent; text: "Add asset"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
                MouseArea { id: saveAssetMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.addAsset() }
              }
            }
          }
        }

        Rectangle { width: parent.width; height: 1; color: root.subtleBorder }

        ListView {
          id: assetList
          width: parent.width
          height: root.addOpen ? Style.space(330) : Style.space(415)
          clip: true
          spacing: Style.space(7)
          model: watchModel

          delegate: Rectangle {
            id: assetRow
            required property int index
            required property string symbol
            required property string name
            required property string assetType
            readonly property var quote: root.quoteBySymbol(assetRow.symbol)

            width: assetList.width
            height: Style.space(78)
            radius: Style.space(9)
            color: assetMouse.containsMouse ? Util.alpha(root.foreground, 0.065) : root.subtleSurface
            border.width: 1
            border.color: root.subtleBorder

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(9)
              spacing: Style.space(10)

              Rectangle {
                width: Style.space(76); height: Style.space(42); radius: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                color: assetRow.assetType === "crypto" ? Util.alpha(root.accent, 0.14) : Util.alpha(root.foreground, 0.07)
                border.width: 1
                border.color: assetRow.assetType === "crypto" ? Util.alpha(root.accent, 0.38) : root.subtleBorder
                Text { anchors.centerIn: parent; text: assetRow.symbol; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
              }

              Column {
                width: parent.width - Style.space(76) - priceColumn.width - removeButton.width - Style.space(35)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)
                Text { width: parent.width; text: assetRow.name; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight }
                Text {
                  width: parent.width
                  text: assetRow.quote && !assetRow.quote.error
                    ? ((assetRow.quote.instrumentType || assetRow.assetType).toUpperCase() + " · " + (assetRow.quote.provider || assetRow.quote.exchange || "Market") + " · " + (assetRow.quote.currency || ""))
                    : ((assetRow.assetType === "crypto" ? "Crypto" : "Stock") + (assetRow.quote && assetRow.quote.error ? " · " + assetRow.quote.error : ""))
                  color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight
                }
              }

              Column {
                id: priceColumn
                width: Style.space(150)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignRight
                  text: assetRow.quote ? (assetRow.quote.error ? "Unavailable" : assetRow.quote.priceFormatted) : "Loading…"
                  color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true
                }
                Text {
                  width: parent.width
                  horizontalAlignment: Text.AlignRight
                  text: assetRow.quote && !assetRow.quote.error
                    ? (root.formatChange(assetRow.quote.change, assetRow.quote.currency) + "  " + root.formatPct(assetRow.quote.changePercent))
                    : (assetRow.quote && assetRow.quote.error ? "Try Refresh" : "")
                  color: assetRow.quote ? root.changeColor(assetRow.quote.changePercent) : root.mutedText
                  font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true
                }
              }

              Rectangle {
                id: removeButton
                width: Style.space(30); height: Style.space(30); radius: Style.space(6); anchors.verticalCenter: parent.verticalCenter
                color: removeMouse.containsMouse ? Util.alpha(root.bar.urgent, 0.20) : "transparent"
                Text { anchors.centerIn: parent; text: "×"; color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.body }
                MouseArea { id: removeMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.removeAsset(assetRow.symbol) }
              }
            }

            MouseArea { id: assetMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
          }

          Text {
            anchors.centerIn: parent
            visible: watchModel.count === 0
            text: "Your watchlist is empty."
            color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
          }
        }

        Rectangle {
          width: parent.width
          radius: Style.space(8)
          color: root.subtleSurface
          border.width: 1
          border.color: root.subtleBorder
          implicitHeight: footerText.implicitHeight + Style.space(16)
          Text {
            id: footerText
            anchors.fill: parent
            anchors.margins: Style.space(8)
            text: root.statusMessage || "Prices are for monitoring only. Stocks use Yahoo Finance with a Stooq fallback; crypto uses CoinGecko with Yahoo fallback. Availability or delay can vary."
            color: root.statusError ? root.bar.urgent : root.mutedText
            font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
