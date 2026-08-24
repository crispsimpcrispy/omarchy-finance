import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.crispsimpcrispy.finance"

  readonly property string backendPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/io.github.crispsimpcrispy.finance/backend.sh"
  property var quotes: []
  property int quoteIndex: 0

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open(payloadJson) { if (panelLoader.item) panelLoader.item.open(payloadJson || "{}") }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle(payloadJson) { if (panelLoader.item) panelLoader.item.toggle(payloadJson || "{}") }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  function acceptQuotes(newQuotes) {
    root.quotes = newQuotes || []
    if (root.quoteIndex >= root.quotes.length) root.quoteIndex = 0
  }

  function refreshQuotes(force) {
    if (quoteProc.running) return
    quoteProc.command = force ? [root.backendPath, "quotes", "--force"] : [root.backendPath, "quotes"]
    quoteProc.running = true
  }

  function formatPct(value) {
    var n = Number(value)
    if (isNaN(n)) return ""
    return (n >= 0 ? "+" : "") + n.toFixed(1) + "%"
  }

  function displaySymbol(quote) {
    if (!quote) return "$"
    var s = String(quote.symbol || "$")
    if (quote.type === "crypto" && s.endsWith("-USD")) s = s.substring(0, s.length - 4)
    return s
  }

  function currentQuote() {
    if (!root.quotes || root.quotes.length === 0) return null
    return root.quotes[root.quoteIndex % root.quotes.length]
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Process {
    id: quoteProc
    stdout: StdioCollector { id: quoteOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      try {
        var data = JSON.parse(String(quoteOut.text || "{}"))
        root.acceptQuotes(data.quotes || [])
      } catch (e) {}
    }
  }

  Timer {
    interval: 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshQuotes(false)
  }

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: {
      if (root.quotes && root.quotes.length > 1)
        root.quoteIndex = (root.quoteIndex + 1) % root.quotes.length
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    horizontalMargin: 7.5
    readonly property var quote: root.currentQuote()

    text: {
      if (root.bar && root.bar.vertical) return "◆"
      if (!quote) return "◆ Markets"
      if (quote.error) return root.displaySymbol(quote) + " —"
      return root.displaySymbol(quote) + " " + root.formatPct(quote.changePercent)
    }

    tooltipText: {
      if (!quote) return "Finance"
      if (quote.error) return (quote.name || quote.symbol) + " · quote unavailable"
      return (quote.name || quote.symbol) + " · " + quote.priceFormatted + " · " + root.formatPct(quote.changePercent) + " · " + (quote.provider || "Market")
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle("{}")
      else if (buttonCode === Qt.MiddleButton) root.refreshQuotes(true)
    }
  }
}
