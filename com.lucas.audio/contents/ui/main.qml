import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasma5support as Plasma5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground

    // Umbrales bajos para que el escritorio muestre la vista completa
    switchWidth: Kirigami.Units.gridUnit * 4
    switchHeight: Kirigami.Units.gridUnit * 4

    property var sinks: []
    property var sources: []
    property string defaultSink: ""
    property string defaultSource: ""
    property bool dragging: false
    readonly property real scrX: Screen.virtualX
    readonly property real scrY: Screen.virtualY
    readonly property real scrW: Screen.width
    readonly property real scrH: Screen.height
    property int seq: 0

    readonly property int maxVolume: Plasmoid.configuration.maxVolume
    readonly property var curSink: findDev(sinks, defaultSink)
    readonly property var curSource: findDev(sources, defaultSource)

    readonly property string speakerIcon: {
        var d = curSink
        if (!d || d.mute || d.vol === 0) return "audio-volume-muted"
        return d.vol < 34 ? "audio-volume-low" : d.vol < 67 ? "audio-volume-medium" : "audio-volume-high"
    }
    readonly property string micIcon: (curSource && !curSource.mute && curSource.vol > 0)
        ? "microphone-sensitivity-high" : "microphone-sensitivity-muted"

    Plasmoid.icon: speakerIcon
    toolTipMainText: "Audio"
    toolTipSubText: (curSink ? "🔊 " + curSink.desc + " — " + (curSink.mute ? "silenciado" : curSink.vol + "%") : "sin salida") +
                    "\n" + (curSource ? "🎤 " + curSource.desc + " — " + (curSource.mute ? "silenciado" : curSource.vol + "%") : "sin micrófono")

    function findDev(list, name) {
        for (var i = 0; i < list.length; i++) if (list[i].name === name) return list[i]
        return null
    }

    function localPath(url) {
        var s = url.toString()
        if (s.indexOf("file://") === 0) s = s.substring(7)
        return s
    }

    readonly property string scriptPath: localPath(Qt.resolvedUrl("../code/audio.sh"))

    function convert(json, keepMonitors, isSink) {
        var arr = []
        try { arr = JSON.parse(json) } catch (e) { return [] }
        var out = []
        arr.forEach(function (d) {
            if (d.name.slice(-8) === ".monitor") return
            var first = d.volume ? d.volume[Object.keys(d.volume)[0]] : null
            out.push({
                name: d.name,
                desc: d.description,
                mute: d.mute,
                vol: first ? Math.round(first.value / 655.36) : 0
            })
        })
        return out
    }

    function parse(text) {
        var map = {}
        text.split("\n").forEach(function (line) {
            var i = line.indexOf("=")
            if (i > 0) map[line.substring(0, i)] = line.substring(i + 1).trim()
        })
        if (dragging) return
        root.defaultSink = map.DSINK || ""
        root.defaultSource = map.DSOURCE || ""
        root.sinks = convert(map.SINKS || "[]")
        root.sources = convert(map.SOURCES || "[]")
        autoSwitch(true, root.sinks, knownSinks)
        autoSwitch(false, root.sources, knownSources)
        knownSinks = root.sinks.map(function (d) { return d.name })
        knownSources = root.sources.map(function (d) { return d.name })
        seenOnce = true
    }

    // Dispositivos nuevos (auriculares, USB, Bluetooth) pasan a ser el predeterminado
    property var knownSinks: []
    property var knownSources: []
    property bool seenOnce: false

    function autoSwitch(isSink, list, known) {
        if (!seenOnce || !Plasmoid.configuration.autoSwitch) return
        for (var i = 0; i < list.length; i++) {
            var d = list[i]
            if (known.indexOf(d.name) >= 0 || d.name.indexOf("HDMI") >= 0) continue
            setDefault(isSink, d.name)
        }
    }

    function visibleSinks() {
        return sinks.filter(function (d) {
            return Plasmoid.configuration.showHdmi || d.name === defaultSink || d.name.indexOf("HDMI") < 0
        })
    }

    Plasma5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            if (sourceName.indexOf("audio.sh") >= 0) {
                var out = data["stdout"] ? data["stdout"].toString() : ""
                if (out.length) root.parse(out)
            } else {
                root.refresh()
            }
        }
    }

    function refresh() {
        exec.connectSource("sh " + JSON.stringify(scriptPath) + " #" + (++seq))
    }

    function act(cmd) {
        exec.connectSource(cmd + " #" + (++seq))
    }

    function kind(isSink) { return isSink ? "sink" : "source" }

    function setVolume(isSink, name, pct) {
        pct = Math.max(0, Math.min(maxVolume, Math.round(pct)))
        act("pactl set-" + kind(isSink) + "-volume " + JSON.stringify(name) + " " + pct + "%")
    }
    function toggleMute(isSink, name) {
        act("pactl set-" + kind(isSink) + "-mute " + JSON.stringify(name) + " toggle")
    }
    function setDefault(isSink, name) {
        act("pactl set-default-" + kind(isSink) + " " + JSON.stringify(name))
    }

    Timer {
        interval: Math.max(500, Plasmoid.configuration.updateInterval)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Aviso gris semitransparente: qué salida y qué entrada se están usando
    property bool loaded: false
    function showNotice() { if (loaded && Plasmoid.configuration.showNotice) { notice.visible = true; noticeTimer.restart() } }
    onDefaultSinkChanged: showNotice()
    onDefaultSourceChanged: showNotice()
    Timer { id: firstLoad; interval: 3000; running: true; onTriggered: root.loaded = true }
    Timer { id: noticeTimer; interval: Plasmoid.configuration.noticeSeconds * 1000; onTriggered: notice.visible = false }

    PlasmaCore.Dialog {
        id: notice
        visible: false
        location: PlasmaCore.Types.Floating
        type: PlasmaCore.Dialog.OnScreenDisplay
        backgroundHints: PlasmaCore.Types.NoBackground
        flags: Qt.WindowDoesNotAcceptFocus | Qt.WindowStaysOnTopHint
        x: root.scrX + (root.scrW - width) / 2
        y: root.scrY + root.scrH * 0.78

        mainItem: Rectangle {
            implicitWidth: noticeCol.implicitWidth + Kirigami.Units.gridUnit * 2
            implicitHeight: noticeCol.implicitHeight + Kirigami.Units.gridUnit * 1.5
            radius: 14
            color: "#b3323236"
            border.color: "#33ffffff"
            border.width: 1

            ColumnLayout {
                id: noticeCol
                anchors.centerIn: parent
                spacing: Kirigami.Units.smallSpacing
                Shadowed {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Se está usando"
                    opacity: 0.7
                    font.pixelSize: Kirigami.Units.gridUnit * 0.7
                }
                RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Icon { source: root.speakerIcon; color: "#7dd3fc"; implicitWidth: Kirigami.Units.iconSizes.smallMedium; implicitHeight: implicitWidth }
                    Shadowed {
                        text: root.curSink ? root.curSink.desc : "sin salida"
                        font.bold: true
                    }
                }
                RowLayout {
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Icon { source: root.micIcon; color: "#f9a8d4"; implicitWidth: Kirigami.Units.iconSizes.smallMedium; implicitHeight: implicitWidth }
                    Shadowed {
                        text: root.curSource ? root.curSource.desc : "sin micrófono"
                        font.bold: true
                    }
                }
            }
        }
    }

    component Shadowed: Text {
        color: "white"
        layer.enabled: true
        layer.effect: DropShadow {
            horizontalOffset: 0
            verticalOffset: 1
            radius: 6
            samples: 13
            color: "#cc000000"
        }
    }

    component Slider: Item {
        id: sl
        property int value: 0
        property int maximum: 100
        property color accent: "#7dd3fc"
        property bool muted: false
        signal moved(int v)
        implicitHeight: Kirigami.Units.gridUnit * 1.5

        readonly property real shown: drag.pressed ? dragValue : value
        property real dragValue: value

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 6
            radius: 3
            color: "#40ffffff"

            Rectangle {
                width: parent.width * Math.min(1, sl.shown / sl.maximum)
                height: parent.height
                radius: 3
                color: sl.muted ? "#80ffffff" : sl.accent
            }
            // marca del 100 %
            Rectangle {
                visible: sl.maximum > 100
                x: parent.width * 100 / sl.maximum - 1
                y: -3
                width: 2
                height: 12
                color: "#a0ffffff"
            }
        }
        Rectangle {
            x: track.width * Math.min(1, sl.shown / sl.maximum) - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: 14
            height: 14
            radius: 7
            color: "white"
        }
        MouseArea {
            id: drag
            anchors.fill: parent
            function update(mx) {
                var v = Math.round(Math.max(0, Math.min(1, mx / width)) * sl.maximum)
                sl.dragValue = v
                sl.moved(v)
            }
            onPressed: (m) => { root.dragging = true; update(m.x) }
            onPositionChanged: (m) => { if (pressed) update(m.x) }
            onReleased: { root.dragging = false; root.refresh() }
            onWheel: (w) => sl.moved(Math.max(0, Math.min(sl.maximum, sl.value + (w.angleDelta.y > 0 ? 5 : -5))))
        }
    }

    component Section: ColumnLayout {
        id: sec
        property string title
        property bool isSink: true
        property var devices: []
        property string current
        property var cur
        property string icon
        property color accent

        spacing: Kirigami.Units.smallSpacing

        Shadowed {
            text: sec.title
            font.bold: true
            opacity: 0.75
            font.pixelSize: Kirigami.Units.gridUnit * 0.7
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1.2
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                source: sec.icon
                color: "white"
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: implicitWidth
                MouseArea {
                    anchors.fill: parent
                    enabled: sec.cur !== null
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleMute(sec.isSink, sec.current)
                }
            }
            Slider {
                Layout.fillWidth: true
                enabled: sec.cur !== null
                value: sec.cur ? sec.cur.vol : 0
                maximum: root.maxVolume
                accent: sec.accent
                muted: sec.cur ? sec.cur.mute : false
                onMoved: (v) => root.setVolume(sec.isSink, sec.current, v)
            }
            Shadowed {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5
                horizontalAlignment: Text.AlignRight
                font.bold: true
                text: !sec.cur ? "—" : sec.cur.mute ? "mute" : sec.cur.vol + "%"
            }
        }

        Repeater {
            model: sec.devices
            delegate: Rectangle {
                required property var modelData
                readonly property bool active: modelData.name === sec.current
                Layout.fillWidth: true
                implicitHeight: Kirigami.Units.gridUnit * 1.8
                radius: 8
                color: active ? "#33ffffff" : hover.hovered ? "#1affffff" : "transparent"
                border.color: active ? sec.accent : "transparent"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.rightMargin: Kirigami.Units.largeSpacing
                    Rectangle {
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: 4
                        color: active ? sec.accent : "#60ffffff"
                    }
                    Shadowed {
                        Layout.fillWidth: true
                        text: modelData.desc
                        elide: Text.ElideRight
                        font.pixelSize: Kirigami.Units.gridUnit * 0.75
                        font.bold: active
                    }
                }
                HoverHandler { id: hover }
                TapHandler { onTapped: root.setDefault(sec.isSink, modelData.name) }
            }
        }
    }

    compactRepresentation: Item {
        id: compact
        Layout.minimumWidth: Kirigami.Units.gridUnit * 2
        Layout.minimumHeight: Kirigami.Units.gridUnit * 2
        Layout.preferredWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                source: root.speakerIcon
                implicitWidth: Math.min(compact.height * 0.6, Kirigami.Units.iconSizes.medium)
                implicitHeight: implicitWidth
            }
            Kirigami.Icon {
                source: root.micIcon
                implicitWidth: Math.min(compact.height * 0.6, Kirigami.Units.iconSizes.medium)
                implicitHeight: implicitWidth
                opacity: root.curSource && !root.curSource.mute ? 1 : 0.6
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            onClicked: (m) => {
                if (m.button === Qt.MiddleButton) { if (root.curSink) root.toggleMute(true, root.defaultSink) }
                else { root.loaded = true; root.showNotice(); Plasmoid.expanded = !Plasmoid.expanded }
            }
            onWheel: (w) => {
                if (root.curSink)
                    root.setVolume(true, root.defaultSink, root.curSink.vol + (w.angleDelta.y > 0 ? 5 : -5))
            }
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 14
        Layout.minimumHeight: Kirigami.Units.gridUnit * 10
        Layout.preferredWidth: Kirigami.Units.gridUnit * 20
        Layout.preferredHeight: Kirigami.Units.gridUnit * 14

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: "#b3323236"
            border.color: "#33ffffff"
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            Section {
                Layout.fillWidth: true
                title: "Parlantes"
                isSink: true
                devices: root.visibleSinks()
                current: root.defaultSink
                cur: root.curSink
                icon: root.speakerIcon
                accent: "#7dd3fc"
            }
            Section {
                Layout.fillWidth: true
                title: "Micrófonos"
                isSink: false
                devices: root.sources
                current: root.defaultSource
                cur: root.curSource
                icon: root.micIcon
                accent: "#f9a8d4"
            }
            Item { Layout.fillHeight: true }
        }
    }
}
