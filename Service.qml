import QtQuick
import Quickshell
import Quickshell.Io
import "SyncthingApi.js" as Api

QtObject {
  id: root

  readonly property string baseUrl: "http://127.0.0.1:8384"
  readonly property string helperPath: localPath(
    Qt.resolvedUrl("scripts/syncthing-install.sh"))
  property string phase: "discovering"
  property string lastError: ""
  property bool refreshing: false
  property int refreshIntervalSec: 60
  property var connections: ({})
  property var devices: []
  property var folders: []
  property var folderStatuses: ({})
  property string localDeviceId: ""
  property var syncingFiles: []
  property var syncActions: ({})

  property string installationState: "checking"
  property string installationLabel: "Checking"
  property string executablePath: ""
  property bool serviceAvailable: false
  property bool serviceRunning: false
  property bool operationRunning: false
  property bool packageRefreshing: false
  property bool packageActionRunning: false
  property string packageStatus: ""
  property string packageError: ""
  property string controlError: ""
  readonly property string recoveryWarning: _recoveryActive
    ? (_apiKey ? "Refreshing Syncthing state" : "Trying to find local API key")
      + [".", "..", "..."][_recoveryDotCount] : ""
  readonly property string syncActivityDots: syncingFiles.length > 0
    ? [".", "..", "..."][_syncDotCount] : ""
  readonly property string syncActivityPath: syncingFiles.length > 0
    ? syncingFiles[_syncFileIndex % syncingFiles.length] : ""
  readonly property string syncActivityFileName: syncingFiles.length > 0
    ? displayFileName(syncActivityPath) : ""
  readonly property string syncActivityAction: syncingFiles.length > 0
    ? String(syncActions["p|" + syncActivityPath] || "syncing") : ""
  readonly property string syncActivityDetail: {
    if (!syncActivityFileName) return ""
    if (syncActivityAction === "removing") {
      return "Removing " + syncActivityFileName
    }
    if (syncActivityAction === "upload") {
      return "Upload " + syncActivityFileName
    }
    return syncActivityFileName
  }
  readonly property string syncActivity: syncingFiles.length > 0
    ? "File syncing" + syncActivityDots + " " + syncActivityDetail : ""

  property string _apiKey: ""
  property bool _recoveryActive: false
  property bool _apiKeyFailureLatched: false
  property int _apiKeyAttempts: 0
  property int _recoveryDotCount: 0
  property int _recoveryTicks: 0
  property bool _finishRecoveryAfterRefresh: false
  property int _generation: 0
  property int _pendingRequests: 0
  property bool _connectionRefreshing: false
  property var _localSyncFiles: []
  property var _remoteSyncFiles: ({})
  property var _changeSyncFiles: []
  property var _changeSyncActions: ({})
  property var _pendingSyncDeletes: []
  property int _syncDotCount: 0
  property int _syncFileIndex: 0
  property int _syncEventSince: 0
  property bool _syncEventsInitialized: false
  property bool _syncEventPolling: false
  property int _syncEventGeneration: 0
  property var _syncEventRequest: null
  property var _requests: []
  property string _keyOutput: ""
  property string _packageOutput: ""
  property string _packageErrorOutput: ""
  property string _controlErrorOutput: ""
  property int _desiredServiceState: -1
  property bool _operationSeen: false

  readonly property bool online: phase === "ready"
  readonly property bool serviceActive: _desiredServiceState === -1
    ? serviceRunning : _desiredServiceState === 1
  readonly property bool serviceActionRunning: controlProcess.running
  readonly property bool canUseRuntime: installationState === "existing"
    && executablePath !== ""
  readonly property bool canControlService: canUseRuntime && serviceAvailable
  readonly property bool lifecycleBusy: packageRefreshing || packageActionRunning
    || serviceActionRunning
  readonly property bool canInstall: installationState === "missing"
    && !lifecycleBusy
  readonly property int folderCount: folders.length
  readonly property int deviceCount: devices.length
  readonly property int connectedDeviceCount: countConnectedDevices()
  readonly property int folderProblemCount: countFolderProblems()
  readonly property int syncingFolderCount: countSyncingFolders()
  readonly property string summaryText: summary()

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.slice(7)
    return decodeURIComponent(value)
  }

  function displayFileName(path) {
    var parts = String(path || "").split(/[\\/]/)
    return parts.length ? parts[parts.length - 1] : ""
  }

  function countConnectedDevices() {
    var count = 0
    var values = connections && connections.connections
      ? connections.connections : {}
    for (var i = 0; i < devices.length; i++) {
      var id = String((devices[i] || {}).deviceID || "")
      if (id && id === localDeviceId) count++
      else if (id && values[id] && values[id].connected === true) count++
    }
    return count
  }

  function countFolderProblems() {
    var count = 0
    var ids = Object.keys(folderStatuses)
    for (var i = 0; i < ids.length; i++) {
      var status = folderStatuses[ids[i]] || {}
      if (status.state === "error" || status.error
          || Number(status.errors || 0) > 0
          || Number(status.pullErrors || 0) > 0) count++
    }
    return count
  }

  function countSyncingFolders() {
    var count = 0
    var ids = Object.keys(folderStatuses)
    for (var i = 0; i < ids.length; i++) {
      if (Number((folderStatuses[ids[i]] || {}).needTotalItems || 0) > 0) {
        count++
      }
    }
    return count
  }

  function summary() {
    if (installationState === "missing") return "Syncthing is not installed"
    if (installationState === "incomplete") {
      return "Installation needs cleanup"
    }
    if (serviceAvailable && !serviceActive) return "Syncing stopped"
    if (phase === "discovering") return "Finding Syncthing"
    if (phase === "loading") return "Reading status"
    if (phase === "error") return "Syncthing unavailable"
    if (folderProblemCount > 0) return folderProblemCount + " folder problem"
      + (folderProblemCount === 1 ? "" : "s")
    if (syncingFolderCount > 0) return syncingFolderCount + " folder"
      + (syncingFolderCount === 1 ? "" : "s") + " syncing"
    return "Up to date"
  }

  function setRefreshInterval(seconds) {
    var value = parseInt(String(seconds), 10)
    if (!isFinite(value)) value = 60
    refreshIntervalSec = Math.max(60, Math.min(3600, value))
  }

  function refresh() {
    _apiKeyFailureLatched = false
    if (phase === "error") lastError = ""
    updateInstallationStatus()
    refreshApi()
  }

  function refreshApi() {
    if (installationState === "checking") return
    if (!canUseRuntime) {
      stopApi(installationState)
      return
    }
    if (serviceAvailable && !serviceActive) {
      stopApi("stopped")
      return
    }
    if (!_apiKey) {
      discoverApiKey()
      return
    }

    _generation++
    abortRequests()
    phase = "loading"
    lastError = ""

    fetch("getSystemStatus", {}, function(data) {
      root.localDeviceId = String((data || {}).myID || "")
    })
    fetch("getConnections", {}, function(data) {
      root.connections = data || ({})
    })
    fetch("getDevices", {}, function(data) {
      root.devices = data instanceof Array ? data : []
    })
    fetch("getFolders", {}, function(data) {
      root.folders = data instanceof Array ? data : []
      root.folderStatuses = ({})
      for (var i = 0; i < root.folders.length; i++) {
        root.fetchFolder(root.folders[i].id)
      }
    })
  }

  function stopApi(nextPhase) {
    _generation++
    abortRequests()
    stopRecovery()
    _apiKeyFailureLatched = false
    _apiKey = ""
    connections = ({})
    devices = []
    folders = []
    folderStatuses = ({})
    localDeviceId = ""
    stopSyncEvents()
    phase = nextPhase
    lastError = ""
  }

  function fetchFolder(folderId, showProgress) {
    fetch("getFolderStatus", { query: { folder: folderId } }, function(data) {
      root.setFolderStatus(folderId, data || ({}))
    }, function(error) {
      root.setFolderStatus(folderId, {
        state: "error",
        error: error.message
      })
    }, showProgress)
  }

  function refreshFolderStatuses(showProgress) {
    if (!_apiKey || !canUseRuntime
        || (serviceAvailable && !serviceActive)) return
    for (var i = 0; i < folders.length; i++) {
      fetchFolder(folders[i].id, showProgress)
    }
  }

  function setFolderStatus(folderId, status) {
    var next = ({})
    var ids = Object.keys(folderStatuses)
    for (var i = 0; i < ids.length; i++) {
      next[ids[i]] = folderStatuses[ids[i]]
    }
    next[String(folderId)] = status
    folderStatuses = next
  }

  function fetch(name, options, onSuccess, onError, showProgress) {
    var generation = _generation
    var visible = showProgress !== false
    if (visible) {
      _pendingRequests++
      refreshing = true
    }
    var xhr = Api.request(baseUrl, _apiKey, name, options, function(data) {
      if (generation !== root._generation) return
      if (onSuccess) onSuccess(data)
      root.finishRequest(generation, visible)
    }, function(error) {
      if (generation !== root._generation) return
      if (onError) onError(error)
      else root.fail(error)
      root.finishRequest(generation, visible)
    })
    var next = _requests.slice()
    next.push(xhr)
    _requests = next
  }

  function finishRequest(generation, visible) {
    if (generation !== _generation) return
    if (visible) {
      _pendingRequests = Math.max(0, _pendingRequests - 1)
      refreshing = _pendingRequests > 0
    }
    if (!refreshing && phase === "loading") phase = "ready"
    if (!refreshing && _finishRecoveryAfterRefresh && phase === "ready") {
      stopRecovery()
    }
  }

  function fail(error) {
    if (error && error.status === 403) _apiKey = ""
    stopRecovery()
    phase = "error"
    lastError = error ? error.message : "Connection failed"
  }

  function abortRequests() {
    for (var i = 0; i < _requests.length; i++) {
      try {
        _requests[i].abort()
      } catch (error) {
      }
    }
    _requests = []
    _pendingRequests = 0
    _connectionRefreshing = false
    refreshing = false
  }

  function discoverApiKey() {
    if (apiKeyProcess.running || !executablePath || _apiKeyFailureLatched) {
      return
    }
    apiKeyRetryTimer.stop()
    if (!_recoveryActive) {
      _recoveryActive = true
      _apiKeyAttempts = 0
      _recoveryDotCount = 0
      _recoveryTicks = 0
      _finishRecoveryAfterRefresh = false
    }
    _apiKeyAttempts++
    _generation++
    abortRequests()
    phase = "discovering"
    lastError = ""
    _keyOutput = ""
    apiKeyProcess.command = [
      executablePath,
      "cli",
      "config",
      "gui",
      "apikey",
      "get"
    ]
    apiKeyProcess.running = true
  }

  function stopRecovery() {
    _recoveryActive = false
    _apiKeyAttempts = 0
    _recoveryDotCount = 0
    _recoveryTicks = 0
    _finishRecoveryAfterRefresh = false
    apiKeyRetryTimer.stop()
  }

  function failApiKeyRecovery() {
    stopRecovery()
    _apiKeyFailureLatched = true
    phase = "error"
    lastError = "Could not discover the local API key"
  }

  function updateInstallationStatus() {
    if (packageStatusProcess.running) return
    packageRefreshing = true
    packageError = ""
    _packageOutput = ""
    _packageErrorOutput = ""
    packageStatusProcess.running = true
  }

  function applyInstallationStatus(text) {
    var data
    try {
      data = JSON.parse(String(text || ""))
    } catch (error) {
      packageError = "Could not read Syncthing installation status"
      return false
    }

    var state = String(data.state || "")
    if (["existing", "incomplete", "missing"].indexOf(state) < 0) {
      packageError = "Syncthing installation status is invalid"
      return false
    }

    installationState = state
    installationLabel = String(data.label || "Unavailable")
    executablePath = String(data.executable || "")
    serviceAvailable = data.serviceAvailable === true
    serviceRunning = data.serviceRunning === true
    operationRunning = data.operationRunning === true

    if (_desiredServiceState !== -1) {
      var expectedRunning = _desiredServiceState === 1
      if (serviceRunning === expectedRunning) {
        _desiredServiceState = -1
      } else if (!controlProcess.running) {
        _desiredServiceState = -1
        controlError = expectedRunning
          ? "Syncthing did not start" : "Syncthing did not stop"
      }
    }

    if (packageActionRunning && operationRunning) _operationSeen = true
    if (packageActionRunning && _operationSeen && !operationRunning) {
      packageActionRunning = false
      packageStatus = "Installation terminal closed"
      _operationSeen = false
      operationPollTimer.stop()
      packageMessageTimer.restart()
    }

    var canUseRuntime = state === "existing" && executablePath !== ""
    if (!canUseRuntime) stopApi(state)
    else if (serviceAvailable && !serviceActive) stopApi("stopped")
    else if (!_apiKey && !apiKeyProcess.running) refreshApi()
    return true
  }

  function installSyncthing() {
    if (!canInstall) return

    packageActionRunning = true
    packageError = ""
    packageStatus = "Complete installation in the Omarchy terminal"
    operationPollTimer.ticks = 0
    _operationSeen = false
    operationPollTimer.start()
    var command = ["bash", helperPath, "install"]
    Quickshell.execDetached(command)
  }

  function toggleService() {
    if (!canControlService || controlProcess.running) return
    var start = !serviceActive
    _desiredServiceState = start ? 1 : 0
    controlError = ""
    _apiKeyFailureLatched = false
    _controlErrorOutput = ""
    controlProcess.command = [
      "systemctl",
      "--user",
      start ? "start" : "stop",
      "syncthing.service"
    ]
    if (!start) stopApi("stopped")
    else phase = "discovering"
    controlProcess.running = true
  }

  function refreshConnections() {
    if (!_apiKey || !canUseRuntime || refreshing || _connectionRefreshing
        || (serviceAvailable && !serviceActive)) return
    _connectionRefreshing = true
    fetch("getConnections", {}, function(data) {
      root.connections = data || ({})
      root._connectionRefreshing = false
    }, function(error) {
      root._connectionRefreshing = false
      root.fail(error)
    }, false)
  }

  function rebuildSyncingFiles() {
    var wasSyncing = syncingFiles.length > 0
    var result = []
    var seen = ({})
    var actions = ({})

    function append(names, action, actionMap) {
      for (var i = 0; i < names.length; i++) {
        var name = String(names[i] || "")
        var nextAction = actionMap
          ? String(actionMap["p|" + name] || action) : action
        if (name && !seen[name]) {
          seen[name] = true
          result.push(name)
        }
        var key = "p|" + name
        if (name && root.syncActionPriority(nextAction)
            > root.syncActionPriority(actions[key])) actions[key] = nextAction
      }
    }

    append(_localSyncFiles, "syncing")
    var keys = Object.keys(_remoteSyncFiles)
    for (var i = 0; i < keys.length; i++) {
      append(_remoteSyncFiles[keys[i]], "upload")
    }
    append(_changeSyncFiles, "syncing", _changeSyncActions)
    syncingFiles = result
    syncActions = actions
    if (_syncFileIndex >= result.length) _syncFileIndex = 0
    if (wasSyncing && result.length === 0) refreshFolderStatuses(false)
  }

  function syncActionPriority(action) {
    if (action === "removing") return 3
    if (action === "upload") return 2
    if (action === "syncing") return 1
    return 0
  }

  function noteSyncChange(path, action) {
    var name = String(path || "")
    if (!name) return

    var next = _changeSyncFiles.slice()
    var nextActions = ({})
    var actionKeys = Object.keys(_changeSyncActions)
    for (var i = 0; i < actionKeys.length; i++) {
      nextActions[actionKeys[i]] = _changeSyncActions[actionKeys[i]]
    }
    var existing = next.indexOf(name)
    if (existing >= 0) next.splice(existing, 1)
    next.push(name)
    nextActions["p|" + name] = action || "syncing"
    while (next.length > 12) {
      var removed = next.shift()
      delete nextActions["p|" + removed]
    }
    _changeSyncFiles = next
    _changeSyncActions = nextActions
    syncChangeHoldTimer.restart()
  }

  function forgetSyncChange(path) {
    var name = String(path || "")
    var next = _changeSyncFiles.slice()
    var existing = next.indexOf(name)
    if (existing >= 0) next.splice(existing, 1)

    var nextActions = ({})
    var actionKeys = Object.keys(_changeSyncActions)
    for (var i = 0; i < actionKeys.length; i++) {
      if (actionKeys[i] !== "p|" + name) {
        nextActions[actionKeys[i]] = _changeSyncActions[actionKeys[i]]
      }
    }
    _changeSyncFiles = next
    _changeSyncActions = nextActions
    rebuildSyncingFiles()
  }

  function hasVisibleMoveTarget(path) {
    var name = displayFileName(path)
    if (!name) return false
    for (var i = 0; i < _changeSyncFiles.length; i++) {
      var candidate = String(_changeSyncFiles[i] || "")
      if (candidate !== path && displayFileName(candidate) === name) return true
    }
    return false
  }

  function processOrDelaySyncChange(event) {
    var data = (event || {}).data || ({})
    if (String(data.action || "") === "deleted") {
      var next = _pendingSyncDeletes.slice()
      next.push(event)
      _pendingSyncDeletes = next
      syncDeleteDelayTimer.restart()
    } else {
      processSyncEvent(event)
    }
  }

  function processPendingSyncDeletes() {
    var events = _pendingSyncDeletes
    _pendingSyncDeletes = []
    for (var i = 0; i < events.length; i++) {
      processSyncEvent(events[i])
    }
  }

  function inspectIndexedFile(folder, path, onFinished) {
    fetch("getFileInfo", {
      query: { folder: folder, file: path }
    }, function(data) {
      var local = (data || {}).local || ({})
      var type = String(local.type || "")
      if (type === "FILE_INFO_TYPE_DIRECTORY" && local.deleted !== true) {
        onFinished({ directoryPath: path })
        return
      }
      if (type !== "FILE_INFO_TYPE_FILE") {
        onFinished(null)
        return
      }
      onFinished({
        type: "LocalChangeDetected",
        data: {
          action: local.deleted === true ? "deleted" : "modified",
          folder: folder,
          path: path,
          type: "file"
        }
      })
    }, function() {
      onFinished(null)
    }, false)
  }

  function scanIndexedDirectory(folder, path) {
    fetch("scanFolder", {
      method: "POST",
      query: { folder: folder, sub: path }
    }, function() {}, function() {}, false)
  }

  function processLocalIndexUpdate(event) {
    var data = (event || {}).data || ({})
    var folder = String(data.folder || "")
    var filenames = data.filenames instanceof Array ? data.filenames : []
    var names = []
    for (var i = Math.max(0, filenames.length - 12);
        i < filenames.length; i++) {
      var name = String(filenames[i] || "")
      if (name) names.push(name)
    }
    if (!folder || names.length === 0) return

    var remaining = names.length
    var changes = []
    var directories = []
    function finish(change) {
      if (change && change.directoryPath) {
        directories.push(change.directoryPath)
      } else if (change) {
        changes.push(change)
      }
      remaining--
      if (remaining > 0) return
      if (changes.length === 0) {
        for (var j = 0; j < directories.length; j++) {
          root.scanIndexedDirectory(folder, directories[j])
        }
      }
      for (var k = 0; k < changes.length; k++) {
        root.processOrDelaySyncChange(changes[k])
      }
    }
    for (var m = 0; m < names.length; m++) {
      inspectIndexedFile(folder, names[m], finish)
    }
  }

  function processSyncEvents(events) {
    for (var i = 0; i < events.length; i++) {
      var type = String((events[i] || {}).type || "")
      if (type === "LocalChangeDetected" || type === "RemoteChangeDetected") {
        processOrDelaySyncChange(events[i])
      } else if (type === "LocalIndexUpdated") {
        processLocalIndexUpdate(events[i])
      } else {
        processSyncEvent(events[i])
      }
    }
  }

  function processSyncEvent(event) {
    var type = String((event || {}).type || "")
    var data = (event || {}).data || ({})

    if (type === "DownloadProgress") {
      var local = []
      var folders = Object.keys(data)
      for (var i = 0; i < folders.length; i++) {
        local = local.concat(Object.keys(data[folders[i]] || ({})))
      }
      _localSyncFiles = local
    } else if (type === "RemoteDownloadProgress") {
      var next = ({})
      var keys = Object.keys(_remoteSyncFiles)
      for (var j = 0; j < keys.length; j++) next[keys[j]] = _remoteSyncFiles[keys[j]]
      var key = String(data.device || "") + "|" + String(data.folder || "")
      var names = Object.keys(data.state || ({}))
      if (names.length > 0) next[key] = names
      else delete next[key]
      _remoteSyncFiles = next
    } else if (type === "DeviceDisconnected") {
      var device = String(data.id || data.device || "")
      var remaining = ({})
      var remoteKeys = Object.keys(_remoteSyncFiles)
      for (var k = 0; k < remoteKeys.length; k++) {
        if (remoteKeys[k].indexOf(device + "|") !== 0) {
          remaining[remoteKeys[k]] = _remoteSyncFiles[remoteKeys[k]]
        }
      }
      _remoteSyncFiles = remaining
    } else if (type === "LocalChangeDetected"
        || type === "RemoteChangeDetected") {
      if (!data.type || data.type === "file") {
        var path = String(data.path || "")
        var isDeleted = String(data.action || "") === "deleted"
        if (isDeleted && hasVisibleMoveTarget(path)) {
          forgetSyncChange(data.path)
          return
        }
        var action = isDeleted ? "removing" : "syncing"
        noteSyncChange(data.path, action)
      }
    } else if (type === "ItemStarted" || type === "ItemFinished") {
      if (!data.type || data.type === "file") {
        noteSyncChange(data.item,
          String(data.action || "") === "delete" ? "removing" : "syncing")
      }
    }
    rebuildSyncingFiles()
  }

  function pollSyncEvents() {
    if (_syncEventPolling || !_apiKey || !canUseRuntime
        || (serviceAvailable && !serviceActive)) return

    var generation = _syncEventGeneration
    var query = {
      events: "DownloadProgress,RemoteDownloadProgress,DeviceDisconnected,"
        + "LocalChangeDetected,RemoteChangeDetected,LocalIndexUpdated,"
        + "ItemStarted,ItemFinished",
      timeout: _syncEventsInitialized ? 5 : 0
    }
    if (_syncEventsInitialized) query.since = _syncEventSince
    else query.limit = 1

    _syncEventPolling = true
    _syncEventRequest = Api.request(baseUrl, _apiKey, "getEvents", {
      query: query
    }, function(data) {
      if (generation !== root._syncEventGeneration) return
      root._syncEventPolling = false
      root._syncEventRequest = null
      var events = data instanceof Array ? data : []
      if (!root._syncEventsInitialized) {
        root._syncEventsInitialized = true
      } else {
        root.processSyncEvents(events)
      }
      if (events.length > 0) {
        root._syncEventSince = Number(events[events.length - 1].id || 0)
      }
    }, function() {
      if (generation !== root._syncEventGeneration) return
      root._syncEventPolling = false
      root._syncEventRequest = null
    })
  }

  function stopSyncEvents() {
    _syncEventGeneration++
    if (_syncEventRequest) {
      try {
        _syncEventRequest.abort()
      } catch (error) {
      }
    }
    _syncEventRequest = null
    _syncEventPolling = false
    _syncEventsInitialized = false
    _syncEventSince = 0
    _localSyncFiles = []
    _remoteSyncFiles = ({})
    _changeSyncFiles = []
    _changeSyncActions = ({})
    _pendingSyncDeletes = []
    syncDeleteDelayTimer.stop()
    syncChangeHoldTimer.stop()
    syncingFiles = []
    syncActions = ({})
    _syncDotCount = 0
    _syncFileIndex = 0
  }

  property Timer refreshTimer: Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    onTriggered: root.refreshApi()
  }

  property Timer installationTimer: Timer {
    interval: 15000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.updateInstallationStatus()
  }

  property Timer operationPollTimer: Timer {
    property int ticks: 0
    interval: 1500
    repeat: true
    onTriggered: {
      ticks++
      root.updateInstallationStatus()
      if (ticks >= 10 && !root._operationSeen) {
        stop()
        root.packageActionRunning = false
        root.packageStatus = ""
        root.packageError = "The installation terminal did not start"
      }
    }
  }

  property Timer packageMessageTimer: Timer {
    interval: 3000
    repeat: false
    onTriggered: root.packageStatus = ""
  }

  property Timer recoveryDotTimer: Timer {
    interval: 500
    repeat: true
    running: root._recoveryActive
    onTriggered: root._recoveryDotCount = (root._recoveryDotCount + 1) % 3
  }

  property Timer apiKeyRetryTimer: Timer {
    interval: 1000
    repeat: false
    onTriggered: root.discoverApiKey()
  }

  property Timer recoveryRefreshTimer: Timer {
    interval: 1000
    repeat: true
    running: root._recoveryActive && root._apiKey !== ""
    onTriggered: {
      if (!root.refreshing) {
        root._recoveryTicks++
        if (root._recoveryTicks >= 10) {
          root._finishRecoveryAfterRefresh = true
          root.refreshApi()
        } else {
          root.refreshConnections()
        }
      }
    }
  }

  property Timer connectionRefreshTimer: Timer {
    interval: 10000
    repeat: true
    running: true
    onTriggered: if (!root._recoveryActive) root.refreshConnections()
  }

  property Timer syncEventTimer: Timer {
    interval: 500
    repeat: true
    running: true
    onTriggered: root.pollSyncEvents()
  }

  property Timer syncAnimationTimer: Timer {
    interval: 400
    repeat: true
    running: root.syncingFiles.length > 0
    onTriggered: root._syncDotCount = (root._syncDotCount + 1) % 3
  }

  property Timer syncFileTimer: Timer {
    interval: 2500
    repeat: true
    running: root.syncingFiles.length > 1
    onTriggered: root._syncFileIndex = (root._syncFileIndex + 1)
      % root.syncingFiles.length
  }

  property Timer syncChangeHoldTimer: Timer {
    interval: 7000
    repeat: false
    onTriggered: {
      root._changeSyncFiles = []
      root._changeSyncActions = ({})
      root.rebuildSyncingFiles()
    }
  }

  property Timer syncDeleteDelayTimer: Timer {
    interval: 1500
    repeat: false
    onTriggered: root.processPendingSyncDeletes()
  }

  property Process apiKeyProcess: Process {
    id: apiKeyProcess
    command: []
    stdout: StdioCollector {
      id: apiKeyStdout
      waitForEnd: true
      onStreamFinished: root._keyOutput = text
    }
    onExited: function(exitCode) {
      var key = String(root._keyOutput || apiKeyStdout.text || "").trim()
      if (exitCode === 0 && key) {
        root._apiKey = key
        root.apiKeyRetryTimer.stop()
        root._recoveryTicks = 0
        root._finishRecoveryAfterRefresh = false
        root._apiKeyFailureLatched = false
        root.refreshApi()
      } else if (root.canUseRuntime
          && (!root.serviceAvailable || root.serviceActive)) {
        if (root._apiKeyAttempts < 15) root.apiKeyRetryTimer.restart()
        else root.failApiKeyRecovery()
      }
    }
  }

  property Process packageStatusProcess: Process {
    id: packageStatusProcess
    command: ["bash", root.helperPath, "status"]
    stdout: StdioCollector {
      id: packageStdout
      waitForEnd: true
      onStreamFinished: root._packageOutput = text
    }
    stderr: StdioCollector {
      id: packageStderr
      waitForEnd: true
      onStreamFinished: root._packageErrorOutput = text
    }
    onExited: function(exitCode) {
      root.packageRefreshing = false
      var output = String(root._packageOutput || packageStdout.text || "")
      var error = String(
        root._packageErrorOutput || packageStderr.text || "").trim()
      if (exitCode === 0) root.applyInstallationStatus(output)
      else root.packageError = error || "Could not check Syncthing installation"
    }
  }

  property Process controlProcess: Process {
    id: controlProcess
    command: []
    stderr: StdioCollector {
      id: controlStderr
      waitForEnd: true
      onStreamFinished: root._controlErrorOutput = text
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.controlError = String(
        root._controlErrorOutput || controlStderr.text
          || "Could not change Syncthing service state").trim()
        root._desiredServiceState = -1
      }
      root.updateInstallationStatus()
      if (exitCode === 0 && root.serviceActive) root._apiKey = ""
    }
  }

  Component.onDestruction: {
    _generation++
    abortRequests()
    stopRecovery()
    stopSyncEvents()
    _apiKey = ""
  }
}
