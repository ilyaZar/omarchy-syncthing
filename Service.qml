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

  property string _apiKey: ""
  property int _generation: 0
  property int _pendingRequests: 0
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

  function countConnectedDevices() {
    var count = 0
    var values = connections && connections.connections
      ? connections.connections : {}
    var ids = Object.keys(values)
    for (var i = 0; i < ids.length; i++) {
      if (values[ids[i]].connected === true) count++
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

    fetch("getSystemStatus", {}, function() {})
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
    _apiKey = ""
    connections = ({})
    devices = []
    folders = []
    folderStatuses = ({})
    phase = nextPhase
    lastError = ""
  }

  function fetchFolder(folderId) {
    fetch("getFolderStatus", { query: { folder: folderId } }, function(data) {
      root.setFolderStatus(folderId, data || ({}))
    }, function(error) {
      root.setFolderStatus(folderId, {
        state: "error",
        error: error.message
      })
    })
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

  function fetch(name, options, onSuccess, onError) {
    var generation = _generation
    _pendingRequests++
    refreshing = true
    var xhr = Api.request(baseUrl, _apiKey, name, options, function(data) {
      if (generation !== root._generation) return
      if (onSuccess) onSuccess(data)
      root.finishRequest(generation)
    }, function(error) {
      if (generation !== root._generation) return
      if (onError) onError(error)
      else root.fail(error)
      root.finishRequest(generation)
    })
    var next = _requests.slice()
    next.push(xhr)
    _requests = next
  }

  function finishRequest(generation) {
    if (generation !== _generation) return
    _pendingRequests = Math.max(0, _pendingRequests - 1)
    refreshing = _pendingRequests > 0
    if (!refreshing && phase === "loading") phase = "ready"
  }

  function fail(error) {
    if (error && error.status === 403) _apiKey = ""
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
    refreshing = false
  }

  function discoverApiKey() {
    if (apiKeyProcess.running || !executablePath) return
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
        root.refreshApi()
      } else if (root.serviceActive) {
        root.phase = "error"
        root.lastError = "Could not discover the local API key"
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
    _apiKey = ""
  }
}
