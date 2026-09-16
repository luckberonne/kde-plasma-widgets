import QtQuick

Item {
    id: gauge

    property real value: 0
    property color trackColor: "#33ffffff"
    property color valueColor: "#ffffff"
    property real ringWidth: 8

    Canvas {
        id: canvas
        anchors.fill: parent

        Component.onCompleted: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            var cx = width / 2
            var cy = height / 2
            var r = Math.min(width, height) / 2 - gauge.ringWidth / 2
            var start = -Math.PI / 2
            var pct = Math.max(0, Math.min(100, gauge.value))

            ctx.lineWidth = gauge.ringWidth
            ctx.lineCap = "round"

            ctx.strokeStyle = gauge.trackColor
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.stroke()

            if (pct > 0) {
                var end = start + (Math.PI * 2) * (pct / 100)
                ctx.strokeStyle = gauge.valueColor
                ctx.beginPath()
                ctx.arc(cx, cy, r, start, end)
                ctx.stroke()
            }
        }
    }

    onValueChanged: canvas.requestPaint()
    onValueColorChanged: canvas.requestPaint()
    onTrackColorChanged: canvas.requestPaint()
}
