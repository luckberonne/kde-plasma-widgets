/*
 * Miniatura en vivo de una ventana.
 * En Wayland el contenido llega por PipeWire; si el stream no está listo
 * (o en X11 sin soporte), cae al icono de la aplicación.
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

    PipeWire.PipeWireSourceItem {
        id: stream
        anchors.centerIn: parent
        nodeId: request.nodeId
        visible: ready && nodeId > 0

        // Encaja la ventana dentro del recuadro sin deformarla.
        readonly property real ratio: streamSize.height > 0 ? streamSize.width / streamSize.height : 1.6
        width: Math.min(parent.width, parent.height * ratio)
        height: ratio > 0 ? width / ratio : parent.height
    }

    Kirigami.Icon {
        anchors.centerIn: parent
        visible: !stream.visible
        source: preview.fallbackIcon
        width: Math.min(parent.width, parent.height) * 0.6
        height: width
    }
}
