/*
 * Miniatura en vivo de una ventana.
 * En Wayland el contenido llega por PipeWire; mientras el stream no entrega
 * frames se muestra el icono de la aplicación.
 * SPDX-License-Identifier: MIT
 */
import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager
import org.kde.pipewire as PipeWire

Item {
    id: preview

    required property var windowId
    property var fallbackIcon: null

    TaskManager.ScreencastingRequest {
        id: request
        uuid: String(preview.windowId)
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        visible: !stream.ready
        source: preview.fallbackIcon
        width: Math.min(parent.width, parent.height) * 0.6
        height: width
    }


    PipeWire.PipeWireSourceItem {
        id: stream
        anchors.fill: parent
        nodeId: request.nodeId

        // Ojo: NO condicionar `visible` a `ready`. PipeWireSourceItem pausa el
        // stream mientras el item está oculto, así que `visible: ready` se queda
        // trabado (nunca corre, nunca está listo). Se mantiene visible y se
        // revela con opacity cuando llegan los primeros frames.
        opacity: ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }
}
