import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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
  readonly property string folderPickerScript: localPathFromUrl(
    Qt.resolvedUrl("scripts/syncthing-folder-picker.sh"))
  property bool moreOpen: false
  property bool addOpen: false
  property bool addIdEdited: false
  property bool addLabelFromOffer: false
  property bool addSubmissionPending: false
  property bool preserveStateForFolderPicker: false
  property string selectedFolderId: ""
  property string selectedPendingOffer: ""
  property string forgetFolderId: ""
  property bool forgetConfirmOpen: false
  property string folderPickerOutput: ""
  property string folderPickerError: ""
  property string displayedNotice: ""
  property bool noticeShown: false
  readonly property var folderRows: buildFolderRows()
  readonly property var pendingOfferRows: pendingOfferOptions()
  readonly property double trackedBytes: folderTotal("globalBytes")
  readonly property int trackedFiles: folderTotal("globalFiles")
  readonly property int scanningFolderCount: folderStateCount("scanning")
  readonly property int pausedFolderCount: folderStateCount("paused")
  readonly property bool syncInProgress: syncthing
    ? syncthing.syncingFolderCount > 0 || scanningFolderCount > 0
      || syncthing.syncingFiles.length > 0
    : false
  readonly property bool busy: syncthing
    ? syncthing.refreshing || syncInProgress
    : false
  readonly property bool hasProblems: syncthing
    ? syncthing.folderProblemCount > 0 : false
  readonly property string iconVariant: {
    if (!syncthing || !syncthing.canUseRuntime) return "notify"
    if (syncthing.serviceAvailable && !syncthing.serviceActive) return "pause"
    if (syncthing.phase === "error" || hasProblems) return "notify"
    if (busy) return "sync"
    return "default"
  }
  // Bar icon: Brand keeps Syncthing's artwork, Auto tints a monochrome master
  // with the bar foreground. Brand is the default, so nothing changes unless
  // asked. See "Icon color" in the widget settings, or BAR ICON under More.
  readonly property string iconStyle: setting("iconStyle", "Brand")
  readonly property bool brandIcon: iconStyle === "Brand"
  readonly property url syncthingIconSource: Qt.resolvedUrl(
    "assets/" + (brandIcon ? "brand" : "mono")
      + "/status-" + iconVariant + ".svg")
  readonly property string tooltip: {
    if (!syncthing) return "Syncthing unavailable"
    if (iconVariant === "sync" && syncInProgress) {
      return "Syncthing: Sync in progress..."
    }
    return "Syncthing: " + syncthing.summaryText
  }
  readonly property string toggleHint: syncthing && syncthing.serviceActive
    ? "Stop syncing" : "Start syncing"
  readonly property string visibleError: {
    if (folderPickerError) return folderPickerError
    if (!syncthing) return ""
    return syncthing.folderMutationError || syncthing.controlError
      || syncthing.packageError
      || syncthing.lastError || ""
  }
  readonly property string visibleNotice: syncthing
    ? syncthing.folderMutationNotice : ""
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

  // A widget setting is a plain key on this module's shell.json entry, so
  // writing one means finding that entry in the bar layout. Guarded so a shell
  // without the mutator leaves the control disabled instead of throwing.
  readonly property bool canPersistSettings: bar && bar.shell
    && typeof bar.shell.mutateShellConfig === "function"

  readonly property var iconStyleOptions: [
    { value: "Brand", label: "Syncthing blue" },
    { value: "Auto", label: "Theme color" }
  ]

  function persistSetting(key, value) {
    if (!canPersistSettings || moduleName === "") return false
    var written = false
    bar.shell.mutateShellConfig(function(config) {
      var layout = (config && config.bar && config.bar.layout) || {}
      for (var region in layout) {
        var entries = layout[region] || []
        for (var i = 0; i < entries.length; i++) {
          var entry = entries[i]
          // A bare string entry has nowhere to keep a setting; promote it.
          if (typeof entry === "string" && entry === root.moduleName)
            entry = entries[i] = { id: entry }
          else if (!entry || String(entry.id) !== root.moduleName) continue
          entry[key] = value
          written = true
        }
      }
    })
    return written
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
      var configuredLabel = String(folder.label || "")
      var displayName = pathLabel(resolveFolderPath(folder.path))
        || configuredLabel || id || "Unnamed folder"
      var sharedDeviceCount = 0
      var folderDevices = folder.devices || []
      for (var j = 0; j < folderDevices.length; j++) {
        var deviceId = String((folderDevices[j] || {}).deviceID || "")
        if (deviceId && (!syncthing || deviceId !== syncthing.localDeviceId)) {
          sharedDeviceCount++
        }
      }

      rows.push({
        id: id,
        label: displayName,
        configuredLabel: configuredLabel,
        markerName: String(folder.markerName || ".stfolder"),
        path: String(folder.path || ""),
        state: state,
        error: String(status.error || ""),
        problem: problem,
        syncing: syncing,
        scanning: scanning,
        paused: !!folder.paused,
        sharedDeviceCount: sharedDeviceCount,
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
    var labelSuffix = folder.configuredLabel
      && folder.configuredLabel !== folder.label
      ? " · " + folder.configuredLabel : ""
    if (folder.problem) {
      return (folder.error || "Folder needs attention") + labelSuffix
    }
    if (folder.paused) return "Syncing paused" + labelSuffix
    if (folder.scanning) return "Scanning local changes" + labelSuffix
    if (folder.syncing) {
      var remaining = formatCount(folder.needItems) + " item"
        + (folder.needItems === 1 ? "" : "s") + " remaining"
      return folder.needBytes > 0
        ? remaining + " · " + formatBytes(folder.needBytes) + labelSuffix
        : remaining + labelSuffix
    }
    if (folder.sharedDeviceCount === 0) {
      return formatCount(folder.globalFiles) + " files · local only" + labelSuffix
    }
    return formatCount(folder.globalFiles) + " files · "
      + formatBytes(folder.globalBytes) + labelSuffix
  }

  function folderLinkState(folder) {
    return folder && folder.paused ? "UNLINKED" : "LINKED"
  }

  function selectedFolder() {
    for (var i = 0; i < folderRows.length; i++) {
      if (folderRows[i].id === selectedFolderId) return folderRows[i]
    }
    return null
  }

  function ensureFolderSelection() {
    if (selectedFolder()) return
    selectedFolderId = folderRows.length > 0 ? folderRows[0].id : ""
  }

  function selectFolderOffset(offset) {
    if (folderRows.length < 2 || offset === 0) return
    var index = 0
    for (var i = 0; i < folderRows.length; i++) {
      if (folderRows[i].id === selectedFolderId) {
        index = i
        break
      }
    }
    index = (index + (offset > 0 ? 1 : -1) + folderRows.length)
      % folderRows.length
    selectedFolderId = folderRows[index].id
  }

  function folderOptions() {
    var options = []
    for (var i = 0; i < folderRows.length; i++) {
      var duplicate = false
      for (var j = 0; j < folderRows.length; j++) {
        if (i !== j && folderRows[j].label === folderRows[i].label) {
          duplicate = true
        }
      }
      var label = folderRows[i].label
      if (duplicate) label += " (" + pathParentName(folderRows[i].path) + ")"
      options.push({ value: folderRows[i].id, label: label })
    }
    return options
  }

  function deviceName(deviceId) {
    var source = syncthing && syncthing.devices ? syncthing.devices : []
    for (var i = 0; i < source.length; i++) {
      var device = source[i] || ({})
      if (String(device.deviceID || "") === String(deviceId || "")) {
        return String(device.name || "Device "
          + String(device.deviceID || "").slice(0, 7))
      }
    }
    return "Unknown device"
  }

  function deviceOptions() {
    var options = []
    var source = syncthing && syncthing.devices ? syncthing.devices : []
    for (var i = 0; i < source.length; i++) {
      var device = source[i] || ({})
      var id = String(device.deviceID || "")
      if (!id || id === syncthing.localDeviceId) continue
      options.push({
        value: id,
        label: String(device.name || "Device " + id.slice(0, 7)),
        description: device.untrusted
          ? "Encrypted sharing requires the Web UI"
          : "Will receive a folder share offer"
      })
    }
    return options
  }

  function pendingOfferOptions() {
    var options = []
    var pending = syncthing && syncthing.pendingFolders
      ? syncthing.pendingFolders : ({})
    var ids = Object.keys(pending)
    for (var i = 0; i < ids.length; i++) {
      var offeredBy = (pending[ids[i]] || {}).offeredBy || ({})
      var deviceIds = Object.keys(offeredBy)
      var encrypted = false
      for (var encryptedIndex = 0;
          encryptedIndex < deviceIds.length; encryptedIndex++) {
        var candidate = offeredBy[deviceIds[encryptedIndex]] || ({})
        if (candidate.receiveEncrypted === true
            || candidate.remoteEncrypted === true) encrypted = true
      }
      if (encrypted) continue
      for (var j = 0; j < deviceIds.length; j++) {
        var offer = offeredBy[deviceIds[j]] || ({})
        var label = String(offer.label || ids[i])
        options.push({
          value: JSON.stringify([ids[i], deviceIds[j]]),
          label: label + " from " + deviceName(deviceIds[j])
        })
      }
    }
    return options
  }

  function pendingFolderOptions() {
    var options = [{ value: "", label: "Create a new folder identity" }]
    for (var i = 0; i < pendingOfferRows.length; i++) {
      options.push({
        value: pendingOfferRows[i].value,
        label: "Accept " + pendingOfferRows[i].label
      })
    }
    return options
  }

  function ensurePendingOfferSelection() {
    for (var i = 0; i < pendingOfferRows.length; i++) {
      if (pendingOfferRows[i].value === selectedPendingOffer) return
    }
    selectedPendingOffer = pendingOfferRows.length > 0
      ? pendingOfferRows[0].value : ""
  }

  function encryptedPendingOfferCount() {
    var count = 0
    var pending = syncthing && syncthing.pendingFolders
      ? syncthing.pendingFolders : ({})
    var ids = Object.keys(pending)
    for (var i = 0; i < ids.length; i++) {
      var offeredBy = (pending[ids[i]] || {}).offeredBy || ({})
      var deviceIds = Object.keys(offeredBy)
      var encrypted = false
      for (var j = 0; j < deviceIds.length; j++) {
        var offer = offeredBy[deviceIds[j]] || ({})
        if (offer.receiveEncrypted === true || offer.remoteEncrypted === true) {
          encrypted = true
        }
      }
      if (encrypted) count++
    }
    return count
  }

  function pathLabel(path) {
    var value = String(path || "").replace(/\/+$/, "")
    if (String(path || "").charAt(0) === "/" && value === "") return "/"
    var parts = value.split("/")
    return parts.length > 0 && parts[parts.length - 1]
      ? parts[parts.length - 1] : "Folder"
  }

  function pathParentName(path) {
    var value = resolveFolderPath(path).replace(/\/+$/, "")
    if (!value || value === "/") return "/"
    var parts = value.split("/")
    parts.pop()
    return parts.length > 0 && parts[parts.length - 1]
      ? parts[parts.length - 1] : "/"
  }

  function localPathFromUrl(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    return decodeURIComponent(value)
  }

  function openAddFolder() {
    if (!syncthing || !syncthing.online || syncthing.folderMutationBusy) return
    syncthing.clearFolderMutationMessage()
    addOpen = true
    addIdEdited = false
    addLabelFromOffer = false
    addSubmissionPending = false
    addPathField.text = ""
    addLabelField.text = ""
    addIdField.text = ""
    pendingFolderPicker.value = ""
    devicePicker.values = []
    syncthing.requestFolderIdSuggestion()
    Qt.callLater(function() { addPathField.forceActiveFocus() })
  }

  function closeAddFolder() {
    if (syncthing && syncthing.folderMutationBusy
        && syncthing.folderMutationAction === "add") return
    addOpen = false
    addSubmissionPending = false
    keyCatcher.forceActiveFocus()
  }

  function resetTransientState() {
    moreOpen = false
    addOpen = false
    addIdEdited = false
    addLabelFromOffer = false
    addSubmissionPending = false
    forgetFolderId = ""
    forgetConfirmOpen = false
    folderPickerError = ""
    if (folderSelector.popupOpen) folderSelector.close()
    if (pendingOfferSelector.popupOpen) pendingOfferSelector.close()
    if (devicePicker.popupOpen) devicePicker.close()
    if (iconStyleSelector.popupOpen) iconStyleSelector.close()
  }

  function applyPendingFolder(value) {
    var selected = String(value || "")
    devicePicker.values = []
    if (!selected) {
      addIdEdited = false
      addIdField.text = ""
      if (addLabelFromOffer) addLabelField.text = ""
      addLabelFromOffer = false
      if (syncthing) syncthing.requestFolderIdSuggestion()
      return
    }
    var choice
    try {
      choice = JSON.parse(selected)
    } catch (error) {
      return
    }
    if (!(choice instanceof Array) || choice.length !== 2) return
    var id = String(choice[0] || "")
    var deviceId = String(choice[1] || "")
    var pending = syncthing && syncthing.pendingFolders
      ? syncthing.pendingFolders[id] || ({}) : ({})
    var offeredBy = pending.offeredBy || ({})
    var offer = offeredBy[deviceId] || ({})
    addIdEdited = true
    addIdField.text = id
    addLabelField.text = String(offer.label || id)
    addLabelFromOffer = true
    devicePicker.values = deviceId ? [deviceId] : []
  }

  function acceptPendingFolderOffer(value) {
    var selected = String(value || "")
    if (!selected) return
    openAddFolder()
    if (!addOpen) return
    pendingFolderPicker.value = selected
    applyPendingFolder(selected)
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { addPathField.forceActiveFocus() })
  }

  function selectedPendingDeviceId() {
    var value = String(pendingFolderPicker.value || "")
    if (!value) return ""
    try {
      var choice = JSON.parse(value)
      if (!(choice instanceof Array) || choice.length !== 2) return ""
      var deviceId = String(choice[1] || "")
      return devicePicker.values.indexOf(deviceId) >= 0 ? deviceId : ""
    } catch (error) {
      return ""
    }
  }

  function submitAddFolder() {
    if (!syncthing || syncthing.folderMutationBusy) return
    var label = String(addLabelField.text || "").trim()
    if (!label) label = pathLabel(addPathField.text)
    selectedFolderId = String(addIdField.text || "").trim()
    addSubmissionPending = syncthing.addFolder(
      addPathField.text,
      label,
      addIdField.text,
      devicePicker.values,
      selectedPendingDeviceId())
  }

  function requestForget(folder) {
    if (!folder || !folder.paused || !syncthing
        || syncthing.folderMutationBusy) return
    selectedFolderId = folder.id
    forgetFolderId = folder.id
    forgetConfirmOpen = true
  }

  function confirmForget() {
    forgetConfirmOpen = false
    if (syncthing) syncthing.forgetFolder(forgetFolderId)
    forgetFolderId = ""
  }

  function openWebUi() {
    if (syncthing && syncthing.online) Qt.openUrlExternally(syncthing.baseUrl)
  }

  function openFolder(folder) {
    var path = resolveFolderPath(folder ? folder.path : "")
    if (!path) return
    Quickshell.execDetached(["uwsm-app", "--", "xdg-open", path])
  }

  function browseForFolder() {
    if (folderPickerProcess.running) return
    folderPickerOutput = ""
    folderPickerError = ""
    folderPickerProcess.command = ["bash", folderPickerScript]
    preserveStateForFolderPicker = true
    close()
    folderPickerProcess.running = true
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
  onFolderRowsChanged: ensureFolderSelection()
  onPendingOfferRowsChanged: ensurePendingOfferSelection()
  onVisibleNoticeChanged: {
    if (visibleNotice !== "") {
      displayedNotice = visibleNotice
      noticeShown = true
      noticeFadeTimer.stop()
      noticeDisplayTimer.restart()
    } else if (displayedNotice !== "") {
      noticeDisplayTimer.stop()
      noticeShown = false
      noticeFadeTimer.restart()
    }
  }
  onOpenedChanged: {
    if (opened) {
      if (syncthing) syncthing.refresh()
      ensureFolderSelection()
      if (panelFlick) panelFlick.contentY = 0
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else if (!preserveStateForFolderPicker) {
      resetTransientState()
    }
  }
  Component.onCompleted: configureService()

  Timer {
    id: noticeDisplayTimer
    interval: 10000
    repeat: false
    onTriggered: {
      root.noticeShown = false
      noticeFadeTimer.restart()
    }
  }

  Timer {
    id: noticeFadeTimer
    interval: 350
    repeat: false
    onTriggered: {
      if (root.noticeShown) return
      var expired = root.displayedNotice
      root.displayedNotice = ""
      if (root.syncthing
          && root.syncthing.folderMutationNotice === expired) {
        root.syncthing.clearFolderMutationNotice()
      }
    }
  }

  Connections {
    target: root.syncthing

    function onFolderIdSuggestionChanged() {
      if (root.addOpen && !root.addIdEdited
          && pendingFolderPicker.value === "") {
        addIdField.text = root.syncthing.folderIdSuggestion
      }
    }

    function onFolderMutationNoticeChanged() {
      if (root.addSubmissionPending
          && root.syncthing.folderMutationNotice !== "") {
        root.addOpen = false
        root.addSubmissionPending = false
        keyCatcher.forceActiveFocus()
      }
    }

    function onFolderMutationErrorChanged() {
      if (root.syncthing.folderMutationError !== "") {
        root.addSubmissionPending = false
      }
    }
  }

  Process {
    id: folderPickerProcess
    command: []

    stdout: StdioCollector {
      id: folderPickerStdout
      waitForEnd: true
      onStreamFinished: root.folderPickerOutput = text
    }

    onExited: function(exitCode) {
      var selected = String(root.folderPickerOutput
        || folderPickerStdout.text || "").trim()
      if (exitCode === 0 && selected) {
        var path = root.localPathFromUrl(selected)
        addPathField.text = path
        if (!addLabelField.text) addLabelField.text = root.pathLabel(path)
      } else if (exitCode !== 0) {
        root.folderPickerError = "Folder chooser failed; enter the path manually."
      }
      Qt.callLater(function() {
        root.preserveStateForFolderPicker = false
        root.open()
        if (root.addOpen) {
          Qt.callLater(function() { addPathField.forceActiveFocus() })
        }
      })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        MonoIcon {
          anchors.centerIn: parent
          width: Style.space(12)
          height: width
          source: root.syncthingIconSource
          tint: root.foreground
          colorize: !root.brandIcon
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
    // 620, not 560: the BAR ICON row pushed the shortcut hints past the old cap.
    contentHeight: popup.fittedContentHeight(content.implicitHeight, Style.space(620))

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        blocked: root.addOpen || folderSelector.popupOpen
          || pendingOfferSelector.popupOpen || iconStyleSelector.popupOpen
        onCloseRequested: {
          if (root.forgetConfirmOpen) {
            root.forgetConfirmOpen = false
            root.forgetFolderId = ""
          } else if (root.addOpen) root.closeAddFolder()
          else root.close()
        }
        onTabRequested: function(direction) { root.switchPanel(direction) }
        onMoveRequested: function(dx, dy) {
          if (root.forgetConfirmOpen && (dx !== 0 || dy !== 0)) {
            forgetDialog.selectedIndex = forgetDialog.selectedIndex === 0 ? 1 : 0
          } else if (!root.addOpen && dx !== 0) {
            root.selectFolderOffset(dx)
          }
        }
        onReturnRequested: {
          if (root.forgetConfirmOpen) {
            if (forgetDialog.selectedIndex === 0) {
              root.forgetConfirmOpen = false
              root.forgetFolderId = ""
            } else root.confirmForget()
          }
        }
        onTextKey: function(text) {
          if (root.forgetConfirmOpen) return
          var key = text.toLowerCase()
          if (key === "r" && root.syncthing) root.syncthing.refresh()
          else if (key === "w") root.openWebUi()
          else if (key === "p") root.toggleSyncing()
          else if (key === "m") root.moreOpen = !root.moreOpen
          else if (key === "q") root.close()
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
              ? root.syncthing.serviceActionRunning
                || root.syncthing.folderMutationBusy : false
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
                MonoIcon {
                  width: hero.iconSize
                  height: width
                  source: root.syncthingIconSource
                  tint: root.foreground
                  colorize: !root.brandIcon
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

          Text {
            visible: root.displayedNotice !== ""
            width: parent.width
            text: root.displayedNotice
            opacity: root.noticeShown ? 1 : 0
            color: root.success
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap

            Behavior on opacity {
              NumberAnimation {
                duration: root.noticeShown ? 0 : 350
                easing.type: Easing.OutCubic
              }
            }
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

            BorderSurface {
              id: addForm
              visible: root.addOpen
              width: parent.width
              implicitHeight: addColumn.implicitHeight + Style.space(16)
              color: "transparent"
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              radius: Style.cornerRadius
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  root.closeAddFolder()
                  event.accepted = true
                }
              }

              Column {
                id: addColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(8)
                spacing: Style.space(6)

                RowLayout {
                  width: parent.width

                  PanelSectionHeader {
                    Layout.fillWidth: true
                    text: "ADD FOLDER"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                  }

                  Button {
                    text: "CANCEL"
                    bordered: true
                    foreground: root.urgent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    horizontalPadding: Style.space(6)
                    verticalPadding: Style.space(4)
                    enabled: !root.syncthing || !root.syncthing.folderMutationBusy
                    onClicked: root.closeAddFolder()
                  }
                }

                Dropdown {
                  id: pendingFolderPicker
                  visible: options.length > 1
                  width: parent.width
                  showLabel: false
                  value: ""
                  options: root.pendingFolderOptions()
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onChanged: function(value) { root.applyPendingFolder(value) }
                }

                Text {
                  visible: root.encryptedPendingOfferCount() > 0
                  width: parent.width
                  text: root.encryptedPendingOfferCount()
                    + " encrypted folder offer"
                    + (root.encryptedPendingOfferCount() === 1 ? " requires" : "s require")
                    + " the Syncthing Web UI."
                  color: root.warning
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Text {
                  text: "Existing directory"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                RowLayout {
                  width: parent.width
                  spacing: Style.space(6)

                  TextField {
                    id: addPathField
                    Layout.fillWidth: true
                    enabled: !root.syncthing || !root.syncthing.folderMutationBusy
                    placeholderText: "/path/to/existing/folder"
                    foreground: root.foreground
                  }

                  Button {
                    text: "BROWSE"
                    tooltipText: "Choose an existing local directory"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    enabled: (!root.syncthing
                      || !root.syncthing.folderMutationBusy)
                      && !folderPickerProcess.running
                    onClicked: root.browseForFolder()
                  }
                }

                Text {
                  text: "Label"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                TextField {
                  id: addLabelField
                  width: parent.width
                  enabled: !root.syncthing || !root.syncthing.folderMutationBusy
                  placeholderText: "Derived from the directory name when empty"
                  foreground: root.foreground
                  onTextEdited: root.addLabelFromOffer = false
                }

                Text {
                  text: "Folder ID"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                RowLayout {
                  width: parent.width
                  spacing: Style.space(6)

                  TextField {
                    id: addIdField
                    Layout.fillWidth: true
                    enabled: !root.syncthing || !root.syncthing.folderMutationBusy
                    placeholderText: root.syncthing
                      && root.syncthing.folderPreparationBusy
                      ? "Generating..." : "Required folder identity"
                    foreground: root.foreground
                    onTextEdited: root.addIdEdited = true
                    onAccepted: root.submitAddFolder()
                  }

                  Button {
                    text: "NEW ID"
                    tooltipText: "Generate a new Syncthing folder ID"
                    bordered: true
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    enabled: root.syncthing
                      && !root.syncthing.folderPreparationBusy
                      && !root.syncthing.folderMutationBusy
                    onClicked: {
                      root.addIdEdited = false
                      addIdField.text = ""
                      pendingFolderPicker.value = ""
                      root.syncthing.requestFolderIdSuggestion()
                    }
                  }
                }

                Text {
                  width: parent.width
                  text: "Reuse the exact ID to rejoin an existing remote folder. "
                    + "A new ID creates a different folder identity."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                MultiSelect {
                  id: devicePicker
                  property double lastClosedAt: 0
                  width: parent.width
                  label: "Share with devices"
                  values: []
                  options: root.deviceOptions()
                  noSelectionText: "Local only"
                  placeholderText: "Find a device..."
                  foreground: root.foreground
                  fontFamily: root.fontFamily

                  onPopupOpenChanged: if (!popupOpen) lastClosedAt = Date.now()

                  MouseArea {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.rowHeight
                    z: 10
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    onEntered: parent.hasCursor = true
                    onExited: parent.hasCursor = false
                    onPressed: function(mouse) {
                      if (parent.popupOpen) parent.close()
                      mouse.accepted = true
                    }
                    onClicked: function(mouse) {
                      if (parent.popupOpen) parent.close()
                      else if (Date.now() - parent.lastClosedAt > 150) {
                        parent.open()
                      }
                      mouse.accepted = true
                    }
                  }

                  Button {
                    id: devicePickerOk
                    parent: devicePicker.Overlay.overlay || devicePicker
                    readonly property real buttonSize:
                      devicePicker.popupRowHeight
                      + Style.spacing.controlPaddingX - Style.spacing.md * 2
                    readonly property point popupOrigin: parent
                      ? devicePicker.mapToItem(
                        parent, 0, devicePicker.height + Style.spacing.xxs)
                      : Qt.point(0, 0)
                    visible: devicePicker.popupOpen
                    x: popupOrigin.x + devicePicker.width - width
                      - Border.right(devicePicker.popupBorderSpec)
                      - Style.spacing.hairline - Style.spacing.md
                    y: popupOrigin.y + Border.top(devicePicker.popupBorderSpec)
                      + Style.spacing.hairline + Style.spacing.md
                    width: buttonSize
                    height: buttonSize
                    z: 10000
                    text: "OK"
                    bordered: true
                    foreground: root.success
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    horizontalPadding: 0
                    verticalPadding: 0
                    onClicked: devicePicker.close()
                  }
                }

                Text {
                  width: parent.width
                  text: devicePicker.values.length === 0
                    ? "Local only: this folder will not synchronize with another device."
                    : "Selected devices receive a share offer and may need to accept it."
                  color: devicePicker.values.length === 0 ? root.warning : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Text {
                  visible: root.syncthing
                    && root.syncthing.folderPreparationError !== ""
                  width: parent.width
                  text: root.syncthing
                    ? root.syncthing.folderPreparationError : ""
                  color: root.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }

                Button {
                  width: parent.width
                  text: root.syncthing && root.syncthing.folderMutationBusy
                    && root.syncthing.folderMutationAction === "add"
                    ? "ADDING..." : "ADD FOLDER"
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: root.syncthing && root.syncthing.online
                    && !root.syncthing.folderMutationBusy
                    && String(addPathField.text || "").trim() !== ""
                    && String(addIdField.text || "").trim() !== ""
                  onClicked: root.submitAddFolder()
                }
              }
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
                && !root.syncthing.folderMutationBusy
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

            PanelSectionHeader {
              text: "FOLDERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              ToggleDropdown {
                id: folderSelector
                visible: root.folderRows.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(28)
                showLabel: false
                rowHeight: Style.space(28)
                value: root.selectedFolderId
                options: root.folderOptions()
                foreground: root.foreground
                fontFamily: root.fontFamily
                onChanged: function(value) { root.selectedFolderId = value }
              }

              Button {
                text: "+"
                Layout.preferredHeight: Style.space(28)
                tooltipText: root.addOpen ? "Close add folder form" : "Add folder"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.body
                horizontalPadding: Style.space(7)
                verticalPadding: Style.space(3)
                enabled: root.syncthing && root.syncthing.online
                  && !root.syncthing.folderMutationBusy
                onClicked: root.addOpen
                  ? root.closeAddFolder() : root.openAddFolder()
              }

              Button {
                id: folderLinkButton
                readonly property var targetFolder: root.selectedFolder()
                readonly property bool targetBusy: root.syncthing
                  && root.syncthing.folderMutationBusy
                  && root.syncthing.folderMutationId === root.selectedFolderId
                visible: root.folderRows.length > 0
                Layout.preferredHeight: Style.space(28)
                text: targetBusy ? "WAIT"
                  : (targetFolder && targetFolder.paused ? "LINK" : "UNLINK")
                tooltipText: targetFolder
                  ? (targetFolder.paused
                    ? "Resume synchronization for " + targetFolder.label
                    : "Pause synchronization for " + targetFolder.label)
                    + "\n" + targetFolder.path
                  : "Select a folder"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(4)
                enabled: targetFolder && root.syncthing
                  && root.syncthing.online && !root.syncthing.folderMutationBusy
                onClicked: root.syncthing.setFolderLinked(
                  targetFolder.id, targetFolder.paused)
              }
            }

            RowLayout {
              visible: root.pendingOfferRows.length > 0
              width: parent.width
              spacing: Style.space(6)

              ToggleDropdown {
                id: pendingOfferSelector
                Layout.fillWidth: true
                Layout.preferredHeight: Style.space(28)
                showLabel: false
                rowHeight: Style.space(28)
                value: root.selectedPendingOffer
                options: root.pendingOfferRows
                foreground: root.foreground
                fontFamily: root.fontFamily
                onChanged: function(value) {
                  root.selectedPendingOffer = value
                }
              }

              Button {
                text: "ACCEPT"
                Layout.preferredHeight: Style.space(28)
                tooltipText: "Prepare this offered folder for local acceptance"
                bordered: true
                foreground: root.success
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                horizontalPadding: Style.space(6)
                verticalPadding: Style.space(4)
                enabled: root.syncthing && root.syncthing.online
                  && !root.syncthing.folderMutationBusy
                  && root.selectedPendingOffer !== ""
                onClicked: root.acceptPendingFolderOffer(
                  root.selectedPendingOffer)
              }
            }

            PanelSeparator {
              foreground: root.foreground
            }

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
              value: {
                if (!root.syncthing) return "Unavailable"
                if (root.syncthing.installationState === "existing") {
                  return "Existing installation found: <font color=\""
                    + root.success + "\">working</font>"
                }
                if (root.syncthing.installationState === "incomplete") {
                  return "Incomplete installation: <font color=\""
                    + root.urgent + "\">non-working</font>"
                }
                return root.syncthing.installationLabel
              }
              valueTextFormat: Text.StyledText
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
              visible: text !== ""
              width: parent.width
              text: {
                if (!root.syncthing) return "Installation status unavailable."
                if (root.syncthing.installationState === "existing") {
                  return ""
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

            PanelSeparator {
              foreground: root.foreground
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                Layout.fillWidth: true
                text: "BAR ICON"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              ToggleDropdown {
                id: iconStyleSelector
                Layout.preferredWidth: Style.space(132)
                Layout.preferredHeight: Style.space(28)
                showLabel: false
                rowHeight: Style.space(28)
                value: root.iconStyle
                options: root.iconStyleOptions
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: root.canPersistSettings
                onChanged: function(value) {
                  root.persistSetting("iconStyle", value)
                }
              }
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

        CompactConfirmDialog {
          id: forgetDialog
          anchors.fill: parent
          opened: root.forgetConfirmOpen
          z: 10
          message: {
            var folder = root.selectedFolder()
            return folder
              ? "Forget " + folder.label + " (" + folder.id + ")?\n\n"
                + "This removes only its Syncthing configuration. The "
                + "directory and data files will not be deleted. "
                + (folder.markerName === ".stfolder"
                  ? "Syncthing will also attempt to remove its internal "
                    + ".stfolder marker. " : "")
                + "Rejoining the "
                + "same remote folder requires this exact Folder ID."
              : "Forget this unlinked folder?"
          }
          confirmText: "Forget"
          background: Color.background
          foreground: root.foreground
          selectedText: root.urgent
          fontFamily: root.fontFamily
          onCanceled: {
            root.forgetConfirmOpen = false
            root.forgetFolderId = ""
          }
          onConfirmed: root.confirmForget()
        }
    }
  }

  component FolderRow: BorderSurface {
    id: folderRow

    property var folder: ({})
    readonly property bool problem: folder && folder.problem
    readonly property bool syncing: folder && folder.syncing
    readonly property bool canOpen: folder && String(folder.path || "") !== ""
    readonly property bool selected: folder
      && String(folder.id || "") === root.selectedFolderId
    readonly property color stateColor: problem
      ? root.urgent : (syncing ? root.foreground : root.dim)
    readonly property color linkColor: folder && folder.paused
      ? root.warning : root.success

    implicitHeight: row.implicitHeight + Style.space(14)
    color: rowMouse.containsMouse
      ? Style.hoverFillFor(stateColor, Color.accent) : "transparent"
    borderSpec: Border.controlSpec(
      selected ? "focus" : "normal", stateColor, Color.accent)
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
      z: 1
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
        Layout.alignment: Qt.AlignTop | Qt.AlignRight

        BorderSurface {
          implicitWidth: statusLabel.implicitWidth + Style.space(10)
          implicitHeight: statusLabel.implicitHeight + Style.space(4)
          color: "transparent"
          borderSpec: Border.controlSpec(
            "normal", folderRow.linkColor, Color.accent)
          radius: Style.cornerRadius
          Layout.alignment: Qt.AlignRight

          Text {
            id: statusLabel
            anchors.centerIn: parent
            text: root.folderLinkState(folderRow.folder)
            color: folderRow.linkColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
          }
        }

        Button {
          visible: folderRow.folder && folderRow.folder.paused
          text: "FORGET"
          tooltipText: "Remove only this unlinked Syncthing configuration"
          bordered: true
          foreground: root.urgent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          horizontalPadding: Style.space(5)
          verticalPadding: Style.space(2)
          enabled: root.syncthing && !root.syncthing.folderMutationBusy
          Layout.alignment: Qt.AlignRight
          onClicked: root.requestForget(folderRow.folder)
        }
      }
    }
  }

  component InfoPair: RowLayout {
    property string label: ""
    property string value: ""
    property int elideMode: Text.ElideRight
    property int valueTextFormat: Text.PlainText

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
      textFormat: parent.valueTextFormat
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: parent.elideMode
      horizontalAlignment: Text.AlignRight
    }
  }
}
