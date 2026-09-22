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

    // Umbrales bajos: en el escritorio siempre se ve completo; en un panel, icono con desplegable.
    switchWidth: Kirigami.Units.gridUnit * 4
    switchHeight: Kirigami.Units.gridUnit * 4

    // En un panel se muestra dentro del desplegable de Plasma (con su tema);
    // en el escritorio, con el estilo glass propio.
    readonly property bool inPopup: Plasmoid.location !== PlasmaCore.Types.Floating
    readonly property color fg: inPopup ? Kirigami.Theme.textColor : "white"
    readonly property color cardColor: inPopup ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.08) : "#26ffffff"

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

    readonly property real avgChange: {
        var vals = []
        for (var k in root.quotes) if (!root.quotes[k].error) vals.push(root.quotes[k].changePct)
        if (!vals.length) return 0
        var sum = 0
        for (var i = 0; i < vals.length; i++) sum += vals[i]
        return sum / vals.length
    }

    readonly property int attentionCount: root.symbols.length

    component GlassText: Text {
        color: root.fg
        elide: Text.ElideRight
        layer.enabled: !root.inPopup
        layer.effect: DropShadow {
            verticalOffset: 1
            radius: 5
            samples: 11
            color: "#aa000000"
        }
    }

    compactRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
        Layout.preferredHeight: Kirigami.Units.iconSizes.medium

        Kirigami.Icon {
            anchors.fill: parent
            source: "view-financial-account"
        }

        Rectangle {
            visible: root.symbols.length > 0
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.max(height, badge.implicitWidth + 6)
            height: Math.max(12, parent.height * 0.42)
            radius: height / 2
            color: root.avgChange >= 0 ? root.upColor : root.downColor
            Text {
                id: badge
                anchors.centerIn: parent
                text: (root.avgChange >= 0 ? "▲" : "▼") + Math.abs(root.avgChange).toFixed(1) + "%"
                color: "#1a1a1a"
                font.bold: true
                font.pixelSize: parent.height * 0.6
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: Plasmoid.expanded = !Plasmoid.expanded
        }
    }

    fullRepresentation: Item {
        id: view

        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 16

        Rectangle {
            visible: !root.inPopup
            anchors.fill: parent
            radius: Kirigami.Units.largeSpacing
            color: "#66000000"
            border.color: "#33ffffff"
        }

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

                delegate: Rectangle {
                    width: listView.width
                    height: row.implicitHeight + Kirigami.Units.smallSpacing * 2
                    radius: Kirigami.Units.mediumSpacing
                    color: root.cardColor
                    property string sym: modelData
                    property var q: root.quotes[sym]

                    RowLayout {
                    id: row
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.smallSpacing

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
