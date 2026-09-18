/*
 * Panel Transparente — botón que alterna la transparencia total del panel
 * SPDX-License-Identifier: MIT
 */
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    Plasmoid.icon: Plasmoid.configuration.transparente ? "view-visible" : "view-hidden"
    toolTipMainText: i18n("Panel Transparente")
    toolTipSubText: Plasmoid.configuration.transparente
        ? i18n("Click para restaurar el fondo del panel")
        : i18n("Click para hacer el panel completamente transparente")

    // Si el contenedor del panel declara NoBackground, la vista del panel no
    // dibuja el fondo (ni pide desenfoque a KWin). Al desactivar la opción se
    // restaura el valor que tenía antes.
    Binding {
        target: Plasmoid.containment
        property: "backgroundHints"
        value: PlasmaCore.Types.NoBackground
        when: Plasmoid.configuration.transparente && Plasmoid.containment !== null
        restoreMode: Binding.RestoreBindingOrValue
    }

    compactRepresentation: PlasmaComponents3.ToolButton {
        icon.name: Plasmoid.icon
        display: PlasmaComponents3.AbstractButton.IconOnly

        onClicked: Plasmoid.configuration.transparente = !Plasmoid.configuration.transparente
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 12
        Layout.minimumHeight: Kirigami.Units.gridUnit * 3

        PlasmaComponents3.CheckBox {
            anchors.centerIn: parent
            text: i18n("Panel transparente")
            checked: Plasmoid.configuration.transparente
            onToggled: Plasmoid.configuration.transparente = checked
        }
    }
}
