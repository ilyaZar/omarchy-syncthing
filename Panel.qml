import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root

  ipcTarget: moduleName

  readonly property var syncthing: bar && bar.shell && moduleName
    ? bar.shell.serviceFor(moduleName) : null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color warning: "#ebcb8b"
  readonly property color success: "#a3be8c"
  readonly property color syncthingBlue: "#26B6DB"
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string homePath: Quickshell.env("HOME")
  property bool moreOpen: false
  readonly property var folderRows: buildFolderRows()
  readonly property double trackedBytes: folderTotal("globalBytes")
  readonly property int trackedFiles: folderTotal("globalFiles")
  readonly property int scanningFolderCount: folderStateCount("scanning")
  readonly property int pausedFolderCount: folderStateCount("paused")
  readonly property bool busy: syncthing
    ? syncthing.refreshing || syncthing.syncingFolderCount > 0
      || scanningFolderCount > 0 || syncthing.syncingFiles.length > 0
    : false
  readonly property bool hasProblems: syncthing
    ? syncthing.folderProblemCount > 0 : false
  readonly property string iconVariant: {
    if (!syncthing || !syncthing.canUseRuntime) return "notify"
    if (syncthing.serviceAvailable && !syncthing.serviceActive) return "pause"
    if (syncthing.phase === "error" || hasProblems) return "notify"
    if (busy) return "sync"
    if (pausedFolderCount > 0) return "pause"
    return "default"
  }
  readonly property url syncthingIconSource: Qt.resolvedUrl(
    "assets/status-" + iconVariant + ".svg")
  readonly property string tooltip: syncthing
    ? "Syncthing: " + syncthing.summaryText : "Syncthing unavailable"
  readonly property string toggleHint: syncthing && syncthing.serviceActive
    ? "Stop syncing" : "Start syncing"
  readonly property string visibleError: {
    if (!syncthing) return ""
    return syncthing.controlError || syncthing.packageError
      || syncthing.lastError || ""
  }
  readonly property string visibleWarning: syncthing
    ? syncthing.recoveryWarning : ""
  readonly property string visibleSyncActivity: syncthing
    ? syncthing.syncActivity : ""
  readonly property string visibleSyncDots: syncthing
    ? syncthing.syncActivityDots : ""
  readonly property string visibleSyncAction: syncthing
    ? syncthing.syncActivityAction : ""
  readonly property string visibleSyncDetail: syncthing
    ? syncthing.syncActivityDetail : ""
  readonly property string heroMeta: {
    if (!syncthing) return "Service unavailable"
    if (syncthing.installationState === "missing") {
      return "Syncthing is not installed"
    }
    if (syncthing.installationState === "incomplete") {
      return "Installation needs cleanup"
    }
    if (syncthing.serviceAvailable && !syncthing.serviceActive) {
      return "Syncing stopped"
    }
    if (syncthing.phase === "discovering") return "Finding local service"
    if (syncthing.phase === "loading") return "Reading folder health"
    if (syncthing.phase === "error") return "Local service unavailable"
    if (hasProblems) return syncthing.folderProblemCount + " folder"
      + (syncthing.folderProblemCount === 1 ? " needs" : "s need")
      + " attention"
    if (root.visibleSyncActivity !== "") return "Synchronizing"
    if (syncthing.syncingFolderCount > 0) return syncthing.syncingFolderCount
      + " folder" + (syncthing.syncingFolderCount === 1 ? " is" : "s are")
      + " syncing"
    if (scanningFolderCount > 0) return scanningFolderCount + " folder"
      + (scanningFolderCount === 1 ? " is" : "s are") + " scanning"
    if (pausedFolderCount > 0) return pausedFolderCount + " folder"
      + (pausedFolderCount === 1 ? " is" : "s are") + " paused"
    return "Everything synchronized"
  }

  function configureService() {
    if (!syncthing) return
    syncthing.setRefreshInterval(setting("refreshIntervalSec", 60))
  }

  function syncActivityColor(action) {
    if (action === "removing") return urgent
    if (action === "upload") return success
    return syncthingBlue
  }

  function buildFolderRows() {
    var rows = []
    var source = syncthing && syncthing.folders ? syncthing.folders : []
    var statuses = syncthing && syncthing.folderStatuses
      ? syncthing.folderStatuses : ({})

    for (var i = 0; i < source.length; i++) {
      var folder = source[i] || ({})
      var id = String(folder.id || "")
      var status = statuses[id] || ({})
      var state = String(status.state || "unknown")
      var errors = Number(status.errors || 0) + Number(status.pullErrors || 0)
      var problem = state === "error" || !!status.error || errors > 0
      var needItems = Number(status.needTotalItems || 0)
      var syncing = needItems > 0 || state.indexOf("sync") === 0
      var scanning = state.indexOf("scan") === 0

      rows.push({
        id: id,
        label: String(folder.label || id || "Unnamed folder"),
        path: String(folder.path || ""),
        state: state,
        error: String(status.error || ""),
        problem: problem,
        syncing: syncing,
        scanning: scanning,
        paused: !!folder.paused,
        needItems: needItems,
        needBytes: Number(status.needBytes || 0),
        globalFiles: Number(status.globalFiles || 0),
        globalBytes: Number(status.globalBytes || 0)
      })
    }
    return rows
  }

  function folderTotal(key) {
    var total = 0
    for (var i = 0; i < folderRows.length; i++) {
      total += Number(folderRows[i][key] || 0)
    }
    return total
  }

  function folderStateCount(key) {
    var count = 0
    for (var i = 0; i < folderRows.length; i++) {
      if (folderRows[i][key]) count++
    }
    return count
  }

  function formatCount(value) {
    var count = Math.max(0, Number(value || 0))
    if (count >= 1000000) return (count / 1000000).toFixed(1) + "m"
    if (count >= 1000) return (count / 1000).toFixed(count >= 10000 ? 0 : 1) + "k"
    return String(Math.round(count))
  }

  function formatBytes(value) {
    var bytes = Math.max(0, Number(value || 0))
    var units = ["B", "KiB", "MiB", "GiB", "TiB"]
    var unit = 0
    while (bytes >= 1024 && unit < units.length - 1) {
      bytes /= 1024
      unit++
    }
    return (unit === 0 ? String(Math.round(bytes)) : bytes.toFixed(bytes >= 10 ? 0 : 1))
      + " " + units[unit]
  }

  function folderMeta(folder) {
    if (folder.problem) return folder.error || "Folder needs attention"
    if (folder.paused) return "Syncing paused"
    if (folder.scanning) return "Scanning local changes"
    if (folder.syncing) {
      var remaining = formatCount(folder.needItems) + " item"
        + (folder.needItems === 1 ? "" : "s") + " remaining"
      return folder.needBytes > 0
        ? remaining + " · " + formatBytes(folder.needBytes) : remaining
    }
    return formatCount(folder.globalFiles) + " files · "
      + formatBytes(folder.globalBytes)
  }

  function folderStatus(folder) {
    if (folder.problem) return "ISSUE"
    if (folder.paused) return "PAUSED"
    if (folder.scanning) return "SCANNING"
    if (folder.syncing) return "SYNCING"
    if (folder.state === "unknown") return "UNKNOWN"
    return "CURRENT"
  }

  function openWebUi() {
    if (syncthing && syncthing.online) Qt.openUrlExternally(syncthing.baseUrl)
  }

  function openFolder(folder) {
    var path = resolveFolderPath(folder ? folder.path : "")
    if (!path) return
    Quickshell.execDetached(["uwsm-app", "--", "xdg-open", path])
  }

  function resolveFolderPath(value) {
    var path = String(value || "")
    if (path === "~") return homePath
    if (path.indexOf("~/") === 0) return homePath + path.slice(1)
    if (path.charAt(0) === "/" || !homePath) return path
    return homePath + "/" + path
  }

  function toggleSyncing() {
    if (syncthing && syncthing.canControlService
        && !syncthing.serviceActionRunning) syncthing.toggleService()
  }

  function installationAction() {
    if (syncthing && syncthing.installationState === "missing") {
      syncthing.installSyncthing()
    }
  }

  onSyncthingChanged: configureService()
  onSettingsChanged: configureService()
  onOpenedChanged: if (opened) {
    if (syncthing) syncthing.refresh()
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  Component.onCompleted: configureService()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        Image {
          anchors.centerIn: parent
          width: Style.space(12)
          height: width
          source: root.syncthingIconSource
          sourceSize.width: 32
          sourceSize.height: 32
          fillMode: Image.PreserveAspectFit
          smooth: true
          opacity: root.syncthing && root.syncthing.online ? 1.0 : 0.55
        }
      }
    }
    active: root.hasProblems
    tooltipText: root.tooltip
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton && root.syncthing) root.syncthing.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(380))
    contentHeight: popup.fittedContentHeight(content.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = text.toLowerCase()
        if (key === "r" && root.syncthing) root.syncthing.refresh()
        else if (key === "w") root.openWebUi()
        else if (key === "p") root.toggleSyncing()
        else if (key === "m") root.moreOpen = !root.moreOpen
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool serviceAvailable: root.syncthing
              ? root.syncthing.canControlService : false
            readonly property bool serviceActive: root.syncthing
              ? root.syncthing.serviceActive : false
            readonly property bool serviceBusy: root.syncthing
              ? root.syncthing.serviceActionRunning : false
            readonly property string toggleHint: root.toggleHint
            function toggleService() { root.toggleSyncing() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Syncthing"
              meta: root.heroMeta
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.syncthing && root.syncthing.serviceActive
                && root.syncthing.online ? 1.0 : 0.5
              iconComponent: Component {
                Image {
                  width: hero.iconSize
                  height: width
                  source: root.syncthingIconSource
                  sourceSize.width: 64
                  sourceSize.height: 64
                  fillMode: Image.PreserveAspectFit
                  smooth: true
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: header.serviceAvailable
                  checked: header.serviceActive
                  busy: header.serviceBusy
                  foreground: hero.foreground
                  onToggled: header.toggleService()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: header.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            visible: root.visibleWarning !== ""
            width: parent.width
            text: root.visibleWarning
            color: root.warning
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Row {
            visible: root.visibleWarning === "" && root.visibleSyncActivity !== ""
            width: parent.width
            spacing: 0

            Text {
              id: syncActivityLabel
              text: "File syncing"
              color: root.syncthingBlue
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Item {
              id: syncDotsSlot
              width: syncDotsProbe.implicitWidth
              height: syncDotsProbe.implicitHeight

              Text {
                text: root.visibleSyncDots
                color: root.syncthingBlue
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                id: syncDotsProbe
                visible: false
                text: "..."
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
            }

            Text {
              width: Math.max(0, parent.width - syncActivityLabel.implicitWidth
                - syncDotsSlot.width)
              text: " " + root.visibleSyncDetail
              color: root.syncActivityColor(root.visibleSyncAction)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              wrapMode: Text.NoWrap
            }
          }

          Text {
            visible: root.visibleError !== ""
            width: parent.width
            text: root.visibleError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Column {
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair {
              label: "Folders"
              value: root.syncthing ? String(root.syncthing.folderCount) : "—"
            }
            InfoPair {
              label: "Devices"
              value: root.syncthing
                ? root.syncthing.connectedDeviceCount + " of "
                  + root.syncthing.deviceCount + " connected"
                : "—"
            }
            InfoPair {
              label: "Tracked"
              value: root.formatCount(root.trackedFiles) + " files · "
                + root.formatBytes(root.trackedBytes)
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "FOLDERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.folderRows.length === 0
              width: parent.width
              text: root.syncthing && root.syncthing.online
                ? "No folders configured." : "Folder status is unavailable."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.folderRows

                FolderRow {
                  required property var modelData
                  width: parent.width
                  folder: modelData
                }
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }

          Row {
            spacing: Style.space(8)

            Button {
              text: root.syncthing && root.syncthing.refreshing
                ? "Refreshing…" : "Refresh"
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
              enabled: root.syncthing !== null && root.syncthing.online
              onClicked: root.openWebUi()
            }
          }

          Button {
            width: parent.width
            text: root.moreOpen ? "Less" : "More"
            iconText: root.moreOpen ? "\uf077" : "\uf078"
            leftAlign: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: {
              root.moreOpen = !root.moreOpen
            }
          }

          Column {
            visible: root.moreOpen
            width: parent.width
            spacing: Style.space(8)

            Row {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                width: parent.width - installationHelp.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: "INSTALLATION"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Button {
                id: installationHelp
                implicitWidth: implicitHeight
                text: "?"
                tooltipText: "Installs the official package through Omarchy "
                  + "when Syncthing is absent. Removal is manual."
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: 0
                bordered: true
                focusable: true
              }
            }

            InfoPair {
              label: "Installation"
              value: root.syncthing
                ? root.syncthing.installationLabel : "Unavailable"
            }

            InfoPair {
              visible: root.syncthing
                && root.syncthing.executablePath !== ""
              label: "Executable"
              value: root.syncthing
                ? root.syncthing.executablePath : ""
              elideMode: Text.ElideLeft
            }

            Text {
              width: parent.width
              text: {
                if (!root.syncthing) return "Installation status unavailable."
                if (root.syncthing.installationState === "existing") {
                  return "Monitoring this installation. Removal is manual."
                }
                if (root.syncthing.installationState === "incomplete") {
                  return "Repair or remove the incomplete installation manually."
                }
                if (root.syncthing.installationState === "missing") {
                  return "Installs through Omarchy. Removal is manual."
                }
                return "Checking installation."
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              wrapMode: Text.NoWrap
            }

            Text {
              visible: root.syncthing
                && root.syncthing.packageStatus !== ""
              width: parent.width
              text: root.syncthing ? root.syncthing.packageStatus : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
              wrapMode: Text.NoWrap
            }

            Button {
              visible: root.syncthing && root.syncthing.canInstall
              text: "Install Syncthing"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: root.syncthing && root.syncthing.canInstall
              onClicked: root.installationAction()
            }
          }

          Text {
            text: "REFRESH (R)  WEB UI (W)  START/STOP (P)  MORE (M)"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 0.8
          }
        }
      }
    }
  }

  component FolderRow: BorderSurface {
    id: folderRow

    property var folder: ({})
    readonly property bool problem: folder && folder.problem
    readonly property bool syncing: folder && folder.syncing
    readonly property bool canOpen: folder && String(folder.path || "") !== ""
    readonly property color stateColor: problem
      ? root.urgent : (syncing ? root.foreground : root.dim)

    implicitHeight: row.implicitHeight + Style.space(14)
    color: rowMouse.containsMouse
      ? Style.hoverFillFor(stateColor, Color.accent) : "transparent"
    borderSpec: Border.controlSpec("normal", stateColor, Color.accent)
    radius: Style.cornerRadius

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      enabled: folderRow.canOpen
      hoverEnabled: true
      cursorShape: folderRow.canOpen
        ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.openFolder(folderRow.folder)
    }

    RowLayout {
      id: row
      anchors.fill: parent
      anchors.margins: Style.space(8)
      spacing: Style.space(8)

      Text {
        text: folderRow.problem ? "\uf071"
          : (folderRow.folder.paused ? "\uf04c"
            : (folderRow.syncing ? "\uf021" : "\uf00c"))
        color: folderRow.stateColor
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          Layout.fillWidth: true
          text: String(folderRow.folder.label || "Unnamed folder")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }

        Text {
          Layout.fillWidth: true
          text: root.folderMeta(folderRow.folder)
          color: folderRow.problem ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          visible: folderRow.canOpen
          Layout.fillWidth: true
          text: String(folderRow.folder.path || "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideLeft
        }
      }

      ColumnLayout {
        spacing: Style.space(4)
        Layout.alignment: Qt.AlignVCenter

        BorderSurface {
          implicitWidth: statusLabel.implicitWidth + Style.space(10)
          implicitHeight: statusLabel.implicitHeight + Style.space(4)
          color: "transparent"
          borderSpec: Border.controlSpec(
            "normal", folderRow.stateColor, Color.accent)
          radius: Style.cornerRadius
          Layout.alignment: Qt.AlignRight

          Text {
            id: statusLabel
            anchors.centerIn: parent
            text: root.folderStatus(folderRow.folder)
            color: folderRow.stateColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

      }
    }
  }

  component InfoPair: RowLayout {
    property string label: ""
    property string value: ""
    property int elideMode: Text.ElideRight

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(8)

    Text {
      text: parent.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      Layout.fillWidth: true
      text: parent.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: parent.elideMode
      horizontalAlignment: Text.AlignRight
    }
  }
}
