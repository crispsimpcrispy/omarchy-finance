import QtQuick

Item {
  id: root
  property var points: []
  property color lineColor: "#d8dee9"
  property color fillColor: "transparent"
  property color gridColor: "transparent"
  property bool showGrid: false
  property real lineWidth: 1.8
  property real horizontalPadding: 4
  property real verticalPadding: 5

  function requestRepaint() { chart.requestPaint() }
  onPointsChanged: requestRepaint()
  onLineColorChanged: requestRepaint()
  onFillColorChanged: requestRepaint()
  onGridColorChanged: requestRepaint()
  onShowGridChanged: requestRepaint()
  onWidthChanged: requestRepaint()
  onHeightChanged: requestRepaint()

  Canvas {
    id: chart
    anchors.fill: parent
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)

      if (root.showGrid) {
        ctx.strokeStyle = root.gridColor
        ctx.lineWidth = 1
        for (var g = 1; g < 4; ++g) {
          var gy = Math.round((height / 4) * g) + 0.5
          ctx.beginPath()
          ctx.moveTo(0, gy)
          ctx.lineTo(width, gy)
          ctx.stroke()
        }
      }

      var raw = root.points || []
      var vals = []
      for (var i = 0; i < raw.length; ++i) {
        var value = Number(raw[i] && raw[i].v !== undefined ? raw[i].v : raw[i])
        if (!isNaN(value) && isFinite(value)) vals.push(value)
      }
      if (vals.length < 2) return

      var min = vals[0]
      var max = vals[0]
      for (var j = 1; j < vals.length; ++j) {
        if (vals[j] < min) min = vals[j]
        if (vals[j] > max) max = vals[j]
      }
      if (max === min) { max += 1; min -= 1 }

      var left = root.horizontalPadding
      var right = Math.max(left + 1, width - root.horizontalPadding)
      var top = root.verticalPadding
      var bottom = Math.max(top + 1, height - root.verticalPadding)
      var drawWidth = right - left
      var drawHeight = bottom - top

      function px(idx) { return left + (idx / (vals.length - 1)) * drawWidth }
      function py(value) { return bottom - ((value - min) / (max - min)) * drawHeight }

      if (root.fillColor !== "transparent") {
        ctx.fillStyle = root.fillColor
        ctx.beginPath()
        ctx.moveTo(px(0), bottom)
        ctx.lineTo(px(0), py(vals[0]))
        for (var f = 1; f < vals.length; ++f) ctx.lineTo(px(f), py(vals[f]))
        ctx.lineTo(px(vals.length - 1), bottom)
        ctx.closePath()
        ctx.fill()
      }

      ctx.strokeStyle = root.lineColor
      ctx.lineWidth = root.lineWidth
      ctx.lineJoin = "round"
      ctx.lineCap = "round"
      ctx.beginPath()
      ctx.moveTo(px(0), py(vals[0]))
      for (var k = 1; k < vals.length; ++k) ctx.lineTo(px(k), py(vals[k]))
      ctx.stroke()
    }
  }
}
