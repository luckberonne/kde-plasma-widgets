import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import Qt5Compat.GraphicalEffects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    switchWidth: Kirigami.Units.gridUnit * 14
    switchHeight: Kirigami.Units.gridUnit * 6

    readonly property color upColor: "#4ade80"
    readonly property color downColor: "#f87171"
    readonly property color neutralColor: "#e5e7eb"

    property var symbols: []
    property var quotes: ({})
    property real cclRate: 0
    property bool loading: false

    toolTipMainText: "Acciones y CEDEARs"
    toolTipSubText: root.symbols.length ? root.symbols.join(", ") : "sin símbolos"

    function loadSymbols() {
        try {
            var arr = JSON.parse(Plasmoid.configuration.symbols || "[]")
            root.symbols = Array.isArray(arr) ? arr : []
        } catch (e) {
            root.symbols = []
        }
    }

    function saveSymbols() {
        Plasmoid.configuration.symbols = JSON.stringify(root.symbols)
    }

    function addSymbol(text) {
        var sym = (text || "").trim().toUpperCase()
        if (!sym.length) return
        if (root.symbols.indexOf(sym) !== -1) return
        var arr = root.symbols.slice()
        arr.push(sym)
        root.symbols = arr
        saveSymbols()
        fetchQuote(sym)
    }

    function removeSymbol(sym) {
        var arr = root.symbols.filter(function (s) { return s !== sym })
        root.symbols = arr
        saveSymbols()
        var q = {}
        for (var k in root.quotes) if (k !== sym) q[k] = root.quotes[k]
        root.quotes = q
    }

    function fetchRate() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) return
            try {
                var data = JSON.parse(xhr.responseText)
                if (data && data.venta) root.cclRate = parseFloat(data.venta)
            } catch (e) {}
        }
        xhr.open("GET", "https://dolarapi.com/v1/dolares/contadoconliqui")
        xhr.send()
    }

    function fetchQuote(sym) {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status !== 200) {
                var q = Object.assign({}, root.quotes)
                q[sym] = Object.assign({}, q[sym] || {}, { error: true })
                root.quotes = q
                return
            }
            try {
                var data = JSON.parse(xhr.responseText)
                var meta = data.chart.result[0].meta
                var price = meta.regularMarketPrice
                var prevClose = meta.previousClose ?? meta.chartPreviousClose
                var currency = meta.currency || "USD"
                var q = Object.assign({}, root.quotes)
                q[sym] = {
                    price: price,
                    prevClose: prevClose,
                    currency: currency,
                    changePct: prevClose ? (price - prevClose) / prevClose * 100 : 0,
                    error: false
                }
                root.quotes = q
            } catch (e) {
                var q2 = Object.assign({}, root.quotes)
                q2[sym] = Object.assign({}, q2[sym] || {}, { error: true })
                root.quotes = q2
            }
        }
        xhr.open("GET", "https://query1.finance.yahoo.com/v8/finance/chart/" + encodeURIComponent(sym) + "?interval=1d&range=1d")
        xhr.setRequestHeader("User-Agent", "Mozilla/5.0")
        xhr.send()
    }

    function refreshAll() {
        root.loading = true
        fetchRate()
        for (var i = 0; i < root.symbols.length; i++) fetchQuote(root.symbols[i])
        root.loading = false
    }

    function fmtARS(v) {
        if (v === undefined || v === null || isNaN(v)) return "—"
        return "$ " + v.toLocaleString(Qt.locale("es_AR"), "f", 2)
    }

    function fmtUSD(v) {
        if (v === undefined || v === null || isNaN(v)) return "—"
        return "US$ " + v.toLocaleString(Qt.locale("en_US"), "f", 2)
    }

    function priceARS(sym) {
        var q = root.quotes[sym]
        if (!q || q.error) return undefined
        return q.currency === "ARS" ? q.price : (root.cclRate > 0 ? q.price * root.cclRate : undefined)
    }

    function priceUSD(sym) {
        var q = root.quotes[sym]
        if (!q || q.error) return undefined
        return q.currency === "ARS" ? (root.cclRate > 0 ? q.price / root.cclRate : undefined) : q.price
    }

    Component.onCompleted: {
        loadSymbols()
        refreshAll()
    }

    Timer {
        interval: Math.max(15000, Plasmoid.configuration.updateInterval)
        running: true
        repeat: true
        onTriggered: root.refreshAll()
    }

    component GlassText: Text {
        color: "white"
        font.bold: true
        layer.enabled: true
        layer.effect: DropShadow {
            horizontalOffset: 0
            verticalOffset: 1
            radius: 6
            samples: 13
            color: "#cc000000"
        }
    }

    compactRepresentation: Item {
        id: compact
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        readonly property real avgChange: {
            var vals = []
            for (var k in root.quotes) if (!root.quotes[k].error) vals.push(root.quotes[k].changePct)
            if (!vals.length) return 0
            var sum = 0
            for (var i = 0; i < vals.length; i++) sum += vals[i]
            return sum / vals.length
        }

        Layout.minimumWidth: vertical ? Kirigami.Units.gridUnit * 3 : label.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumHeight: Kirigami.Units.gridUnit * 2
        Layout.preferredWidth: Layout.minimumWidth
        Layout.preferredHeight: Layout.minimumHeight

        MouseArea {
            anchors.fill: parent
            onClicked: Plasmoid.expanded = !Plasmoid.expanded
        }

        GlassText {
            id: label
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Math.max(9, Math.min(compact.height * 0.36, 14))
            textFormat: Text.RichText
            text: {
                var color = compact.avgChange >= 0 ? root.upColor : root.downColor
                var arrow = compact.avgChange >= 0 ? "▲" : "▼"
                return root.symbols.length
                    ? "<span style='color:" + color + "'>" + arrow + " " + Math.abs(compact.avgChange).toFixed(1) + "%</span>"
                    : "Acciones"
            }
        }
    }

    fullRepresentation: Item {
        id: view

        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 16

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                Layout.fillWidth: true
                GlassText {
                    Layout.fillWidth: true
                    text: "ACCIONES Y CEDEARS"
                    font.pixelSize: Kirigami.Units.gridUnit * 0.7
                    opacity: 0.7
                }
                QQC2.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: root.refreshAll()
                }
            }

            ListView {
                id: listView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: root.symbols
                spacing: Kirigami.Units.smallSpacing

                delegate: RowLayout {
                    width: listView.width
                    property string sym: modelData
                    property var q: root.quotes[sym]

                    GlassText {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 4.5
                        text: sym
                        font.pixelSize: Kirigami.Units.gridUnit * 0.8
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        GlassText {
                            font.bold: false
                            font.pixelSize: Kirigami.Units.gridUnit * 0.75
                            text: q && !q.error ? root.fmtARS(root.priceARS(sym)) : (q && q.error ? "error" : "cargando…")
                            opacity: 0.95
                        }
                        GlassText {
                            font.bold: false
                            font.pixelSize: Kirigami.Units.gridUnit * 0.65
                            text: q && !q.error ? root.fmtUSD(root.priceUSD(sym)) : ""
                            opacity: 0.7
                        }
                    }

                    GlassText {
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                        horizontalAlignment: Text.AlignRight
                        font.pixelSize: Kirigami.Units.gridUnit * 0.75
                        visible: q && !q.error
                        color: q && q.changePct >= 0 ? root.upColor : root.downColor
                        text: q ? (q.changePct >= 0 ? "▲" : "▼") + Math.abs(q.changePct).toFixed(1) + "%" : ""
                    }

                    QQC2.ToolButton {
                        icon.name: "list-remove"
                        Layout.preferredWidth: Kirigami.Units.gridUnit * 1.6
                        onClicked: root.removeSymbol(sym)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    id: addField
                    Layout.fillWidth: true
                    placeholderText: i18n("Agregar ticker (ej: GGAL.BA, AAPL)")
                    onAccepted: {
                        root.addSymbol(text)
                        text = ""
                    }
                }

                QQC2.ToolButton {
                    icon.name: "list-add"
                    onClicked: {
                        root.addSymbol(addField.text)
                        addField.text = ""
                    }
                }
            }
        }
    }
}
