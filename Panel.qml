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

  property string mode: "watchlist" // watchlist | detail | add
  property var configData: ({ watchlist: [], refreshSeconds: 60, defaultRange: "1M" })
  property var quotes: []
  property var assets: []
  property int updatedAt: 0
  property bool busy: false
  property string statusMessage: ""
  property bool statusError: false

  property string selectedSymbol: ""
  property string selectedName: ""
  property string selectedType: "stock"
  property string selectedRange: "1M"
  property var historyData: ({ points: [] })

  property var catalogAssets: []
  property string catalogQuery: ""
  property string catalogFilter: "all"
  property string customType: "stock"

  readonly property color foreground: root.bar ? root.bar.foreground : Color.foreground
  readonly property color background: Color.popups.background
  readonly property color borderColor: Color.popups.border
  readonly property color accent: Color.menu.selectedBackground
  readonly property color mutedText: Util.alpha(root.foreground, 0.58)
  readonly property color subtleText: Util.alpha(root.foreground, 0.42)
  readonly property color surface: Util.alpha(root.foreground, 0.045)
  readonly property color surfaceHover: Util.alpha(root.foreground, 0.075)
  readonly property color subtleBorder: Util.alpha(root.foreground, 0.11)
  readonly property color positiveColor: "#7fd48b"
  readonly property color negativeColor: root.bar ? root.bar.urgent : "#e06c75"
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  function parseJson(text, fallback) {
    try { return JSON.parse(String(text || "")) } catch (e) { return fallback }
  }

  function open(payloadJson) {
    root.mode = "watchlist"
    root.statusMessage = ""
    root.controller.show()
    root.refreshDashboard(false)
  }

  function close() { root.controller.hide() }
  function toggle(payloadJson) { if (root.opened) root.close(); else root.open(payloadJson || "{}") }
  function closeForPopoutSwitch() { root.controller.hide() }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function refreshDashboard(force) {
    if (dashboardProc.running) return
    root.busy = true
    dashboardProc.command = force ? [root.backendPath, "dashboard", "--force"] : [root.backendPath, "dashboard"]
    dashboardProc.running = true
  }

  function quoteBySymbol(symbol) {
    for (var i = 0; i < root.quotes.length; ++i)
      if (String(root.quotes[i].symbol).toUpperCase() === String(symbol).toUpperCase()) return root.quotes[i]
    return null
  }

  function assetBySymbol(symbol) {
    for (var i = 0; i < root.assets.length; ++i)
      if (String(root.assets[i].symbol).toUpperCase() === String(symbol).toUpperCase()) return root.assets[i]
    return null
  }

  function isWatched(symbol) {
    var rows = root.configData.watchlist || []
    for (var i = 0; i < rows.length; ++i)
      if (String(rows[i].symbol).toUpperCase() === String(symbol).toUpperCase()) return true
    return false
  }

  function displaySymbol(symbol, type) {
    var s = String(symbol || "")
    if (type === "crypto" && s.endsWith("-USD")) return s.substring(0, s.length - 4)
    return s
  }

  function formatPct(value, digits) {
    var n = Number(value)
    if (isNaN(n)) return "—"
    return (n >= 0 ? "+" : "") + n.toFixed(digits === undefined ? 2 : digits) + "%"
  }

  function formatNumber(value, currency) {
    var n = Number(value)
    if (isNaN(n)) return "—"
    var sign = currency === "GBP" ? "£" : (currency === "EUR" ? "€" : (currency === "USD" ? "$" : ""))
    var digits = Math.abs(n) < 1 ? 4 : 2
    try { return sign + n.toLocaleString(Qt.locale(), "f", digits) }
    catch (e) { return sign + n.toFixed(digits) }
  }

  function changeColor(value) { return Number(value) < 0 ? root.negativeColor : root.positiveColor }

  function updatedLabel() {
    if (!root.updatedAt) return "Waiting for market data"
    var d = new Date(root.updatedAt * 1000)
    return "Updated " + d.toLocaleTimeString()
  }

  function openDetail(symbol, name, type) {
    root.selectedSymbol = symbol
    root.selectedName = name
    root.selectedType = type
    root.selectedRange = String(root.configData.defaultRange || "1M")
    root.historyData = ({ points: [] })
    root.mode = "detail"
    root.loadHistory(false)
  }

  function loadHistory(force) {
    if (!root.selectedSymbol || historyProc.running) return
    historyProc.command = force
      ? [root.backendPath, "history", root.selectedSymbol, root.selectedType, root.selectedRange, "--force"]
      : [root.backendPath, "history", root.selectedSymbol, root.selectedType, root.selectedRange]
    historyProc.running = true
  }

  function chooseRange(range) {
    root.selectedRange = range
    root.historyData = ({ points: [] })
    root.loadHistory(false)
  }

  function openAdd() {
    root.mode = "add"
    root.catalogQuery = ""
    catalogSearch.text = ""
    if (root.catalogAssets.length === 0 && !catalogProc.running) {
      catalogProc.command = [root.backendPath, "catalog"]
      catalogProc.running = true
    }
    root.rebuildCatalogModel()
    Qt.callLater(function() { catalogSearch.forceActiveFocus() })
  }

  function rebuildCatalogModel() {
    catalogModel.clear()
    var q = root.catalogQuery.trim().toLowerCase()
    for (var i = 0; i < root.catalogAssets.length; ++i) {
      var a = root.catalogAssets[i]
      if (root.catalogFilter !== "all" && a.type !== root.catalogFilter) continue
      var hay = [a.symbol, a.name, a.market, a.type].join(" ").toLowerCase()
      var terms = q ? q.split(/\s+/) : []
      var ok = true
      for (var j = 0; j < terms.length; ++j)
        if (terms[j] && hay.indexOf(terms[j]) < 0) { ok = false; break }
      if (!ok) continue
      catalogModel.append({
        symbol: String(a.symbol || ""),
        name: String(a.name || a.symbol || ""),
        assetType: String(a.type || "stock"),
        assetClass: String(a.assetClass || "stocks"),
        coinId: String(a.coinId || ""),
        market: String(a.market || "")
      })
    }
  }

  function addCatalogAsset(symbol, name, type, coinId, assetClass) {
    if (root.isWatched(symbol)) return
    root.runAction(["add", symbol, name, type, coinId || "", assetClass || ""], "Adding " + symbol + "…")
  }

  function addCustomAsset() {
    var symbol = customSymbol.text.trim().toUpperCase()
    var name = customName.text.trim()
    if (!symbol) {
      root.statusError = true
      root.statusMessage = "Enter a ticker or crypto symbol."
      return
    }
    if (root.customType === "crypto" && symbol.indexOf("-") < 0) symbol += "-USD"
    if (!name) name = root.displaySymbol(symbol, root.customType)
    root.runAction(["add", symbol, name, root.customType], "Adding " + symbol + "…")
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

  ListModel { id: catalogModel }

  Process {
    id: dashboardProc
    stdout: StdioCollector { id: dashboardOut; waitForEnd: true }
    stderr: StdioCollector { id: dashboardErr; waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode !== 0) {
        root.statusError = true
        root.statusMessage = String(dashboardErr.text || "Could not load market data.").trim()
        return
      }
      var data = root.parseJson(dashboardOut.text, {})
      root.configData = data.config || root.configData
      root.quotes = data.quotes || []
      root.assets = data.assets || []
      root.updatedAt = Number(data.updatedAt || 0)
      root.statusError = false
      root.statusMessage = ""
      if (root.hostWidget && typeof root.hostWidget.acceptQuotes === "function")
        root.hostWidget.acceptQuotes(root.quotes)
    }
  }

  Process {
    id: historyProc
    stdout: StdioCollector { id: historyOut; waitForEnd: true }
    stderr: StdioCollector { id: historyErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.historyData = ({ points: [], error: String(historyErr.text || "Chart data unavailable").trim() })
        return
      }
      root.historyData = root.parseJson(historyOut.text, { points: [], error: "Chart data unavailable" })
    }
  }

  Process {
    id: catalogProc
    stdout: StdioCollector { id: catalogOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var data = root.parseJson(catalogOut.text, { assets: [] })
      root.catalogAssets = data.assets || []
      root.rebuildCatalogModel()
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
      root.statusMessage = String(actionOut.text || "Done.").trim()
      customSymbol.text = ""
      customName.text = ""
      root.mode = "watchlist"
      root.refreshDashboard(true)
    }
  }

  Timer {
    interval: Math.max(30000, Number(root.configData.refreshSeconds || 60) * 1000)
    running: root.opened
    repeat: true
    onTriggered: root.refreshDashboard(false)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher

    contentWidth: panel.fittedContentWidth(Style.space(830))
    contentHeight: panel.fittedContentHeight(Style.space(650))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.mode === "watchlist") root.close()
        else root.mode = "watchlist"
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: watchPage
        anchors.fill: parent
        spacing: Style.space(11)
        visible: root.mode === "watchlist"

        Row {
          width: parent.width
          spacing: Style.space(8)
          Column {
            width: parent.width - refreshButton.width - addButton.width - Style.space(16)
            spacing: Style.space(2)
            Text { text: "Finance"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true }
            Text { text: root.updatedLabel() + " · " + (root.configData.watchlist || []).length + " assets"; color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
          }
          Rectangle {
            id: refreshButton
            width: Style.space(82); height: Style.space(34); radius: Style.space(8)
            color: refreshMouse.containsMouse ? Util.alpha(root.foreground, 0.16) : root.surface
            border.width: 1; border.color: root.subtleBorder
            Text { anchors.centerIn: parent; text: root.busy ? "Loading…" : "Refresh"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            MouseArea { id: refreshMouse; anchors.fill: parent; hoverEnabled: true; enabled: !root.busy; onClicked: root.refreshDashboard(true) }
          }
          Rectangle {
            id: addButton
            width: Style.space(74); height: Style.space(34); radius: Style.space(8)
            color: addMouse.containsMouse ? Util.alpha(root.accent, 0.25) : Util.alpha(root.accent, 0.13)
            border.width: 1; border.color: Util.alpha(root.accent, 0.48)
            Text { anchors.centerIn: parent; text: "+ Add"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
            MouseArea { id: addMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.openAdd() }
          }
        }

        Rectangle { width: parent.width; height: 1; color: root.subtleBorder }

        ListView {
          id: watchList
          width: parent.width
          height: Style.space(520)
          clip: true
          spacing: Style.space(8)
          model: root.assets

          delegate: Rectangle {
            id: assetCard
            required property var modelData
            readonly property var quote: root.quoteBySymbol(modelData.symbol)
            readonly property bool available: quote && !quote.error
            readonly property color trendColor: available ? root.changeColor(quote.changePercent) : root.mutedText

            width: watchList.width
            height: Style.space(96)
            radius: Style.space(10)
            color: cardMouse.containsMouse ? root.surfaceHover : root.surface
            border.width: 1
            border.color: cardMouse.containsMouse ? Util.alpha(root.foreground, 0.18) : root.subtleBorder

            Row {
              z: 2
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(10)

              Rectangle {
                width: Style.space(78); height: Style.space(46); radius: Style.space(9)
                anchors.verticalCenter: parent.verticalCenter
                color: modelData.type === "crypto" ? Util.alpha(root.accent, 0.13) : Util.alpha(root.foreground, 0.065)
                border.width: 1
                border.color: modelData.type === "crypto" ? Util.alpha(root.accent, 0.38) : root.subtleBorder
                Text {
                  anchors.centerIn: parent
                  text: root.displaySymbol(modelData.symbol, modelData.type)
                  color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true
                }
              }

              Column {
                width: Style.space(190)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)
                Text { width: parent.width; text: modelData.name; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight }
                Text {
                  width: parent.width
                  text: (modelData.type === "crypto" ? "CRYPTO" : "STOCK") + (available && quote.provider ? " · " + quote.provider : "")
                  color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight
                }
              }

              Item {
                width: parent.width - Style.space(78) - Style.space(190) - priceColumn.width - removeButton.width - Style.space(50)
                height: Style.space(58)
                anchors.verticalCenter: parent.verticalCenter
                Sparkline {
                  anchors.fill: parent
                  points: modelData.sparkline || []
                  lineColor: assetCard.trendColor
                  fillColor: Util.alpha(assetCard.trendColor, 0.06)
                  lineWidth: 1.7
                }
                Text {
                  anchors.centerIn: parent
                  visible: !modelData.sparkline || modelData.sparkline.length < 2
                  text: available ? "No chart" : "Quote unavailable"
                  color: root.subtleText; font.family: root.fontFamily; font.pixelSize: Style.font.caption
                }
              }

              Column {
                id: priceColumn
                width: Style.space(146)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(5)
                Text {
                  width: parent.width; horizontalAlignment: Text.AlignRight
                  text: available ? quote.priceFormatted : "Unavailable"
                  color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true
                }
                Rectangle {
                  anchors.right: parent.right
                  width: pctText.implicitWidth + Style.space(14); height: pctText.implicitHeight + Style.space(8); radius: Style.space(6)
                  color: available ? Util.alpha(assetCard.trendColor, 0.12) : "transparent"
                  Text { id: pctText; anchors.centerIn: parent; text: available ? root.formatPct(quote.changePercent) : "Try refresh"; color: assetCard.trendColor; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: available }
                }
              }

              Rectangle {
                id: removeButton
                z: 2
                width: Style.space(28); height: Style.space(28); radius: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                color: removeMouse.containsMouse ? Util.alpha(root.negativeColor, 0.18) : "transparent"
                Text { anchors.centerIn: parent; text: "×"; color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.body }
                MouseArea {
                  id: removeMouse; anchors.fill: parent; hoverEnabled: true
                  onClicked: function(mouse) { mouse.accepted = true; root.removeAsset(modelData.symbol) }
                }
              }
            }

            MouseArea {
              id: cardMouse
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton
              z: 1
              onClicked: root.openDetail(modelData.symbol, modelData.name, modelData.type)
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.assets.length === 0
            text: root.busy ? "Loading markets…" : "Your watchlist is empty. Add a stock or cryptocurrency."
            color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall
          }
        }

        Rectangle {
          width: parent.width; radius: Style.space(8)
          color: root.surface; border.width: 1; border.color: root.subtleBorder
          implicitHeight: watchStatus.implicitHeight + Style.space(16)
          Text {
            id: watchStatus
            anchors.fill: parent; anchors.margins: Style.space(8)
            text: root.statusMessage || "Click an asset for its chart and market details. Prices are for monitoring only."
            color: root.statusError ? root.negativeColor : root.mutedText
            font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap
          }
        }
      }

      Column {
        id: detailPage
        anchors.fill: parent
        spacing: Style.space(11)
        visible: root.mode === "detail"
        readonly property var quote: root.quoteBySymbol(root.selectedSymbol)
        readonly property bool available: quote && !quote.error
        readonly property bool historyAvailable: root.historyData && root.historyData.points && root.historyData.points.length >= 2
        readonly property color chartColor: historyAvailable ? root.changeColor(root.historyData.changePercent) : (available ? root.changeColor(quote.changePercent) : root.mutedText)

        Row {
          width: parent.width; spacing: Style.space(8)
          Rectangle {
            width: Style.space(64); height: Style.space(34); radius: Style.space(8)
            color: detailBackMouse.containsMouse ? Util.alpha(root.foreground, 0.14) : root.surface
            border.width: 1; border.color: root.subtleBorder
            Text { anchors.centerIn: parent; text: "← Back"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            MouseArea { id: detailBackMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.mode = "watchlist" }
          }
          Column {
            width: parent.width - Style.space(64) - detailRefresh.width - Style.space(16)
            spacing: Style.space(1)
            Text { text: root.selectedName; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true }
            Text { text: root.displaySymbol(root.selectedSymbol, root.selectedType) + " · " + (root.selectedType === "crypto" ? "Cryptocurrency" : "Stock"); color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
          }
          Rectangle {
            id: detailRefresh
            width: Style.space(82); height: Style.space(34); radius: Style.space(8)
            color: detailRefreshMouse.containsMouse ? Util.alpha(root.foreground, 0.14) : root.surface
            border.width: 1; border.color: root.subtleBorder
            Text { anchors.centerIn: parent; text: historyProc.running ? "Loading…" : "Refresh"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            MouseArea { id: detailRefreshMouse; anchors.fill: parent; hoverEnabled: true; enabled: !historyProc.running; onClicked: { root.refreshDashboard(true); root.loadHistory(true) } }
          }
        }

        Row {
          width: parent.width; spacing: Style.space(14)
          Column {
            width: Style.space(260); spacing: Style.space(5)
            Text { text: detailPage.available ? detailPage.quote.priceFormatted : "Unavailable"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.title; font.bold: true }
            Text {
              text: detailPage.available ? (root.formatNumber(detailPage.quote.change, detailPage.quote.currency) + "  " + root.formatPct(detailPage.quote.changePercent)) : "Current quote unavailable"
              color: detailPage.available ? root.changeColor(detailPage.quote.changePercent) : root.mutedText
              font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: detailPage.available
            }
          }
          Item { width: parent.width - Style.space(274); height: Style.space(50) }
        }

        Rectangle {
          width: parent.width; height: Style.space(276); radius: Style.space(11)
          color: root.surface; border.width: 1; border.color: root.subtleBorder

          Column {
            anchors.fill: parent; anchors.margins: Style.space(12); spacing: Style.space(8)
            Row {
              width: parent.width
              Text { width: parent.width - rangeChange.width; text: root.selectedRange + " price history"; color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              Text {
                id: rangeChange
                text: detailPage.historyAvailable ? root.formatPct(root.historyData.changePercent) : ""
                color: detailPage.chartColor; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true
              }
            }
            Sparkline {
              width: parent.width; height: Style.space(196)
              points: root.historyData.points || []
              lineColor: detailPage.chartColor
              fillColor: Util.alpha(detailPage.chartColor, 0.055)
              gridColor: Util.alpha(root.foreground, 0.07)
              showGrid: true
              lineWidth: 2.1
              horizontalPadding: 6; verticalPadding: 8
            }
            Text {
              width: parent.width
              visible: !detailPage.historyAvailable
              text: historyProc.running ? "Loading chart…" : (root.historyData.error || "Chart data unavailable")
              color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; horizontalAlignment: Text.AlignHCenter
            }
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter; spacing: Style.space(7)
          Repeater {
            model: ["1D", "5D", "1M", "3M", "1Y"]
            delegate: Rectangle {
              required property var modelData
              width: Style.space(66); height: Style.space(32); radius: Style.space(7)
              color: root.selectedRange === modelData ? Util.alpha(root.accent, 0.20) : root.surface
              border.width: 1
              border.color: root.selectedRange === modelData ? Util.alpha(root.accent, 0.55) : root.subtleBorder
              Text { anchors.centerIn: parent; text: modelData; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: root.selectedRange === modelData }
              MouseArea { anchors.fill: parent; onClicked: root.chooseRange(modelData) }
            }
          }
        }

        Row {
          width: parent.width; spacing: Style.space(8)
          Repeater {
            model: [
              { label: "Range high", value: detailPage.historyAvailable ? root.formatNumber(root.historyData.high, detailPage.available ? detailPage.quote.currency : "USD") : "—" },
              { label: "Range low", value: detailPage.historyAvailable ? root.formatNumber(root.historyData.low, detailPage.available ? detailPage.quote.currency : "USD") : "—" },
              { label: "Prev close", value: detailPage.available ? root.formatNumber(detailPage.quote.previousClose, detailPage.quote.currency) : "—" },
              { label: "Provider", value: root.historyData.provider || (detailPage.available ? detailPage.quote.provider : "—") }
            ]
            delegate: Rectangle {
              required property var modelData
              width: (parent.width - Style.space(24)) / 4; height: Style.space(68); radius: Style.space(8)
              color: root.surface; border.width: 1; border.color: root.subtleBorder
              Column {
                anchors.fill: parent; anchors.margins: Style.space(8); spacing: Style.space(4)
                Text { text: modelData.label; color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
                Text { width: parent.width; text: modelData.value; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideRight }
              }
            }
          }
        }

        Row {
          width: parent.width
          Text { width: parent.width - removeDetail.width; anchors.verticalCenter: parent.verticalCenter; text: "Charts are cached locally to reduce requests. Market data may be delayed."; color: root.subtleText; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          Rectangle {
            id: removeDetail
            width: Style.space(150); height: Style.space(34); radius: Style.space(8)
            color: removeDetailMouse.containsMouse ? Util.alpha(root.negativeColor, 0.19) : Util.alpha(root.negativeColor, 0.08)
            border.width: 1; border.color: Util.alpha(root.negativeColor, 0.34)
            Text { anchors.centerIn: parent; text: "Remove from watchlist"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
            MouseArea { id: removeDetailMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.removeAsset(root.selectedSymbol) }
          }
        }
      }

      Column {
        id: addPage
        anchors.fill: parent
        spacing: Style.space(10)
        visible: root.mode === "add"

        Row {
          width: parent.width; spacing: Style.space(8)
          Rectangle {
            width: Style.space(64); height: Style.space(34); radius: Style.space(8)
            color: addBackMouse.containsMouse ? Util.alpha(root.foreground, 0.14) : root.surface
            border.width: 1; border.color: root.subtleBorder
            Text { anchors.centerIn: parent; text: "← Back"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
            MouseArea { id: addBackMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.mode = "watchlist" }
          }
          Column {
            anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(1)
            Text { text: "Add to watchlist"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.subtitle; font.bold: true }
            Text { text: "Search popular assets or enter any ticker manually."; color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
          }
        }

        Rectangle {
          width: parent.width; height: Style.space(40); radius: Style.space(8)
          color: root.surface; border.width: 1; border.color: root.subtleBorder
          TextInput {
            id: catalogSearch
            anchors.fill: parent; anchors.margins: Style.space(8)
            color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; verticalAlignment: TextInput.AlignVCenter; selectByMouse: true
            onTextChanged: { root.catalogQuery = text; root.rebuildCatalogModel() }
          }
          Text { anchors.left: parent.left; anchors.leftMargin: Style.space(9); anchors.verticalCenter: parent.verticalCenter; visible: !catalogSearch.text; text: "Search Apple, Tesla, Bitcoin, Rolls-Royce…"; color: root.subtleText; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall }
        }

        Row {
          spacing: Style.space(7)
          Repeater {
            model: [ {v:"all",l:"All"}, {v:"stock",l:"Stocks"}, {v:"crypto",l:"Crypto"} ]
            delegate: Rectangle {
              required property var modelData
              width: Style.space(82); height: Style.space(30); radius: Style.space(7)
              color: root.catalogFilter === modelData.v ? Util.alpha(root.accent, 0.19) : root.surface
              border.width: 1; border.color: root.catalogFilter === modelData.v ? Util.alpha(root.accent, 0.48) : root.subtleBorder
              Text { anchors.centerIn: parent; text: modelData.l; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: root.catalogFilter === modelData.v }
              MouseArea { anchors.fill: parent; onClicked: { root.catalogFilter = modelData.v; root.rebuildCatalogModel() } }
            }
          }
        }

        ListView {
          width: parent.width; height: Style.space(340); clip: true; spacing: Style.space(6); model: catalogModel
          delegate: Rectangle {
            id: catalogRow
            required property string symbol
            required property string name
            required property string assetType
            required property string assetClass
            required property string coinId
            required property string market
            readonly property bool watched: root.isWatched(symbol)
            width: ListView.view.width; height: Style.space(62); radius: Style.space(8)
            color: catalogMouse.containsMouse ? root.surfaceHover : root.surface
            border.width: 1; border.color: root.subtleBorder
            Row {
              anchors.fill: parent; anchors.margins: Style.space(8); spacing: Style.space(10)
              Rectangle {
                width: Style.space(78); height: Style.space(38); radius: Style.space(8); anchors.verticalCenter: parent.verticalCenter
                color: assetType === "crypto" ? Util.alpha(root.accent, 0.13) : Util.alpha(root.foreground, 0.06)
                border.width: 1; border.color: assetType === "crypto" ? Util.alpha(root.accent, 0.34) : root.subtleBorder
                Text { anchors.centerIn: parent; text: root.displaySymbol(symbol, assetType); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.bodySmall; font.bold: true }
              }
              Column {
                width: parent.width - Style.space(78) - addCatalogButton.width - Style.space(28); anchors.verticalCenter: parent.verticalCenter; spacing: Style.space(2)
                Text { width: parent.width; text: name; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight }
                Text { width: parent.width; text: market + " · " + (assetType === "crypto" ? "Crypto" : "Stock"); color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
              }
              Rectangle {
                id: addCatalogButton
                width: Style.space(76); height: Style.space(32); radius: Style.space(7); anchors.verticalCenter: parent.verticalCenter
                color: watched ? root.surface : (catalogAddMouse.containsMouse ? Util.alpha(root.accent, 0.24) : Util.alpha(root.accent, 0.12))
                border.width: 1; border.color: watched ? root.subtleBorder : Util.alpha(root.accent, 0.42)
                Text { anchors.centerIn: parent; text: watched ? "Added" : "+ Add"; color: watched ? root.mutedText : root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: !watched }
                MouseArea { id: catalogAddMouse; anchors.fill: parent; hoverEnabled: true; enabled: !watched; onClicked: root.addCatalogAsset(symbol, name, assetType, coinId, assetClass) }
              }
            }
            MouseArea { id: catalogMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
          }
        }

        Rectangle { width: parent.width; height: 1; color: root.subtleBorder }

        Text { text: "Custom asset"; color: root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
        Row {
          width: parent.width; spacing: Style.space(7)
          Rectangle {
            width: Style.space(170); height: Style.space(36); radius: Style.space(7); color: root.surface; border.width: 1; border.color: root.subtleBorder
            TextInput { id: customSymbol; anchors.fill: parent; anchors.margins: Style.space(7); color: root.foreground; font.family: root.fontFamily; verticalAlignment: TextInput.AlignVCenter; selectByMouse: true; capitalization: Font.AllUppercase }
            Text { anchors.left: parent.left; anchors.leftMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter; visible: !customSymbol.text; text: "Ticker / BTC"; color: root.subtleText; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          }
          Rectangle {
            width: Style.space(230); height: Style.space(36); radius: Style.space(7); color: root.surface; border.width: 1; border.color: root.subtleBorder
            TextInput { id: customName; anchors.fill: parent; anchors.margins: Style.space(7); color: root.foreground; font.family: root.fontFamily; verticalAlignment: TextInput.AlignVCenter; selectByMouse: true }
            Text { anchors.left: parent.left; anchors.leftMargin: Style.space(8); anchors.verticalCenter: parent.verticalCenter; visible: !customName.text; text: "Display name (optional)"; color: root.subtleText; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          }
          Repeater {
            model: [ {v:"stock",l:"Stock"}, {v:"crypto",l:"Crypto"} ]
            delegate: Rectangle {
              required property var modelData
              width: Style.space(72); height: Style.space(36); radius: Style.space(7)
              color: root.customType === modelData.v ? Util.alpha(root.accent, 0.19) : root.surface
              border.width: 1; border.color: root.customType === modelData.v ? Util.alpha(root.accent, 0.45) : root.subtleBorder
              Text { anchors.centerIn: parent; text: modelData.l; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
              MouseArea { anchors.fill: parent; onClicked: root.customType = modelData.v }
            }
          }
          Rectangle {
            width: Style.space(92); height: Style.space(36); radius: Style.space(7)
            color: customAddMouse.containsMouse ? Util.alpha(root.accent, 0.25) : Util.alpha(root.accent, 0.12)
            border.width: 1; border.color: Util.alpha(root.accent, 0.44)
            Text { anchors.centerIn: parent; text: "Add custom"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
            MouseArea { id: customAddMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.addCustomAsset() }
          }
        }

        Text {
          width: parent.width
          text: root.statusMessage || "US stocks use Nasdaq first; crypto uses CoinGecko. Other tickers fall back to Yahoo/Stooq where available."
          color: root.statusError ? root.negativeColor : root.mutedText; font.family: root.fontFamily; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap
        }
      }
    }
  }
}
