import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root

  ipcTarget: moduleName

  readonly property var syncthing: bar && bar.shell && moduleName
    ? bar.shell.serviceFor(moduleName) : null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string tooltip: syncthing
    ? "Syncthing: " + syncthing.summaryText : "Syncthing unavailable"

  function configureService() {
    if (!syncthing) return
    syncthing.setRefreshInterval(setting("refreshIntervalSec", 15))
  }

  onSyncthingChanged: configureService()
  onSettingsChanged: configureService()
  onOpenedChanged: if (opened && syncthing) syncthing.refresh()
  Component.onCompleted: configureService()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "S"
    foreground: root.syncthing && root.syncthing.online ? root.barForeground : root.dim
    active: root.syncthing ? root.syncthing.folderProblemCount > 0 : false
    tooltipText: root.tooltip
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(300))
    contentHeight: popup.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text.toLowerCase() === "r" && root.syncthing) root.syncthing.refresh()
      }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        Text {
          text: "SYNCTHING"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: 1.2
        }

        Text {
          width: parent.width
          text: root.syncthing ? root.syncthing.summaryText : "Service unavailable"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Text {
          width: parent.width
          text: root.syncthing
            ? root.syncthing.folderCount + " folders | "
              + root.syncthing.connectedDeviceCount + "/"
              + root.syncthing.deviceCount + " devices connected"
            : ""
          visible: root.syncthing !== null
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          text: root.syncthing ? root.syncthing.lastError : ""
          visible: text !== ""
          color: bar ? bar.urgent : Color.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "Refresh"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: root.syncthing && !root.syncthing.refreshing
            onClicked: root.syncthing.refresh()
          }

          Button {
            text: "Open Web UI"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: root.syncthing !== null
            onClicked: Qt.openUrlExternally(root.syncthing.baseUrl)
          }
        }
      }
    }
  }
}
