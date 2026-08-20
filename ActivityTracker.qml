import QtQuick

QtObject {
  id: root

  property bool enabled: false
  property var requestApi
  property var syncingFiles: []
  property var syncActions: ({})
  property var _localFiles: []
  property var _remoteFiles: ({})
  property var _indexedFiles: []
  property var _indexedActions: ({})
  property int _dotIndex: 0
  property int _fileIndex: 0
  property int _eventSince: 0
  property bool _eventsInitialized: false
  property bool _eventPolling: false
  property int _eventGeneration: 0
  property var _eventRequest: null

  readonly property string dots: syncingFiles.length > 0
    ? [".  ", ".. ", "..."][_dotIndex] : ""
  readonly property string path: syncingFiles.length > 0
    ? tokenParts(syncingFiles[_fileIndex % syncingFiles.length])[1] : ""
  readonly property string folderId: syncingFiles.length > 0
    ? tokenParts(syncingFiles[_fileIndex % syncingFiles.length])[0] : ""
  readonly property string fileName: syncingFiles.length > 0
    ? displayFileName(path) : ""
  readonly property string action: syncingFiles.length > 0
    ? String(syncActions[
      syncingFiles[_fileIndex % syncingFiles.length]] || "syncing") : ""
  readonly property string detail: {
    if (!fileName) return ""
    if (action === "removing") return "Removing " + fileName
    if (action === "upload") return "Upload " + fileName
    return fileName
  }
  readonly property string label: syncingFiles.length > 0
    ? "File syncing" + dots + " " + detail : ""

  signal becameIdle
  signal pendingFoldersUpdated(var pending)

  function displayFileName(filePath) {
    var parts = String(filePath || "").split(/[\\/]/)
    return parts.length ? parts[parts.length - 1] : ""
  }

  function token(folder, filePath) {
    return JSON.stringify([String(folder || ""), String(filePath || "")])
  }

  function tokenParts(value) {
    try {
      var parts = JSON.parse(String(value || ""))
      if (parts instanceof Array && parts.length === 2) {
        return [String(parts[0] || ""), String(parts[1] || "")]
      }
    } catch (error) {
    }
    return ["", String(value || "")]
  }

  function actionPriority(value) {
    if (value === "removing") return 3
    if (value === "upload") return 2
    if (value === "syncing") return 1
    return 0
  }

  function rebuild() {
    var wasActive = syncingFiles.length > 0
    var result = []
    var seen = ({})
    var actions = ({})

    function append(names, defaultAction, actionMap) {
      for (var i = 0; i < names.length; i++) {
        var name = String(names[i] || "")
        var nextAction = actionMap
          ? String(actionMap[name] || defaultAction) : defaultAction
        if (name && !seen[name]) {
          seen[name] = true
          result.push(name)
        }
        if (name && root.actionPriority(nextAction)
            > root.actionPriority(actions[name])) actions[name] = nextAction
      }
    }

    append(_localFiles, "syncing")
    var keys = Object.keys(_remoteFiles)
    for (var i = 0; i < keys.length; i++) append(_remoteFiles[keys[i]], "upload")
    append(_indexedFiles, "syncing", _indexedActions)
    syncingFiles = result
    syncActions = actions
    if (_fileIndex >= result.length) _fileIndex = 0
    if (wasActive && result.length === 0) becameIdle()
  }

  function noteIndexedChange(folder, filePath, nextAction) {
    if (!String(filePath || "")) return
    var value = token(folder, filePath)
    var next = _indexedFiles.slice()
    var actions = ({})
    var keys = Object.keys(_indexedActions)
    for (var i = 0; i < keys.length; i++) actions[keys[i]] = _indexedActions[keys[i]]
    var existing = next.indexOf(value)
    if (existing >= 0) next.splice(existing, 1)
    next.push(value)
    actions[value] = nextAction || "syncing"
    while (next.length > 12) delete actions[next.shift()]
    _indexedFiles = next
    _indexedActions = actions
    changeHoldTimer.restart()
  }

  function processIndexedChanges(folder, changes) {
    for (var i = 0; i < changes.length; i++) {
      noteIndexedChange(folder, changes[i].path,
        changes[i].deleted ? "removing" : "syncing")
    }
    rebuild()
  }

  function inspectIndexedFile(folder, filePath, onFinished) {
    requestApi("getFileInfo", {
      query: { folder: folder, file: filePath }
    }, function(data) {
      var local = (data || {}).local || ({})
      var type = String(local.type || "")
      if (type === "FILE_INFO_TYPE_DIRECTORY" && local.deleted !== true) {
        onFinished({ directoryPath: filePath })
      } else if (type === "FILE_INFO_TYPE_FILE") {
        onFinished({
          path: String(local.name || filePath),
          deleted: local.deleted === true
        })
      } else {
        onFinished(null)
      }
    }, function() { onFinished(null) })
  }

  function scanIndexedDirectory(folder, filePath) {
    requestApi("scanFolder", {
      method: "POST",
      query: { folder: folder, sub: filePath }
    }, function() {}, function() {})
  }

  function processLocalIndexUpdate(event) {
    var data = (event || {}).data || ({})
    var folder = String(data.folder || "")
    var filenames = data.filenames instanceof Array ? data.filenames : []
    var names = []
    for (var i = Math.max(0, filenames.length - 12); i < filenames.length; i++) {
      var name = String(filenames[i] || "")
      if (name) names.push(name)
    }
    if (!folder || names.length === 0) return

    var remaining = names.length
    var changes = []
    var directories = []
    function finish(change) {
      if (change && change.directoryPath) directories.push(change.directoryPath)
      else if (change) changes.push(change)
      remaining--
      if (remaining > 0) return
      for (var j = 0; j < directories.length; j++) {
        root.scanIndexedDirectory(folder, directories[j])
      }
      root.processIndexedChanges(folder, changes)
    }
    for (var fileIndex = 0; fileIndex < names.length; fileIndex++) {
      inspectIndexedFile(folder, names[fileIndex], finish)
    }
  }

  function processEvent(event) {
    var type = String((event || {}).type || "")
    var data = (event || {}).data || ({})
    if (type === "DownloadProgress") {
      var local = []
      var folders = Object.keys(data)
      for (var i = 0; i < folders.length; i++) {
        var names = Object.keys(data[folders[i]] || ({}))
        for (var nameIndex = 0; nameIndex < names.length; nameIndex++) {
          local.push(token(folders[i], names[nameIndex]))
        }
      }
      _localFiles = local
    } else if (type === "RemoteDownloadProgress") {
      var remote = ({})
      var keys = Object.keys(_remoteFiles)
      for (var j = 0; j < keys.length; j++) remote[keys[j]] = _remoteFiles[keys[j]]
      var key = String(data.device || "") + "|" + String(data.folder || "")
      var remoteNames = Object.keys(data.state || ({}))
      var tokens = []
      for (var remoteIndex = 0; remoteIndex < remoteNames.length; remoteIndex++) {
        tokens.push(token(data.folder, remoteNames[remoteIndex]))
      }
      if (tokens.length > 0) remote[key] = tokens
      else delete remote[key]
      _remoteFiles = remote
    } else if (type === "DeviceDisconnected") {
      var device = String(data.id || data.device || "")
      var connected = ({})
      var remoteKeys = Object.keys(_remoteFiles)
      for (var remoteKey = 0; remoteKey < remoteKeys.length; remoteKey++) {
        if (remoteKeys[remoteKey].indexOf(device + "|") !== 0) {
          connected[remoteKeys[remoteKey]] = _remoteFiles[remoteKeys[remoteKey]]
        }
      }
      _remoteFiles = connected
    } else if (type === "PendingFoldersChanged") {
      requestApi("getPendingFolders", {}, function(pending) {
        root.pendingFoldersUpdated(pending || ({}))
      }, function() {})
    }
    rebuild()
  }

  function processEvents(events) {
    for (var i = 0; i < events.length; i++) {
      if (String((events[i] || {}).type || "") === "LocalIndexUpdated") {
        processLocalIndexUpdate(events[i])
      } else {
        processEvent(events[i])
      }
    }
  }

  function poll() {
    if (!enabled || _eventPolling || !requestApi) return
    var generation = _eventGeneration
    var query = {
      events: "DownloadProgress,RemoteDownloadProgress,DeviceDisconnected,"
        + "PendingFoldersChanged,LocalIndexUpdated",
      timeout: _eventsInitialized ? 5 : 0
    }
    if (_eventsInitialized) query.since = _eventSince
    else query.limit = 1
    _eventPolling = true
    _eventRequest = requestApi("getEvents", { query: query }, function(data) {
      if (generation !== root._eventGeneration) return
      root._eventPolling = false
      root._eventRequest = null
      var events = data instanceof Array ? data : []
      if (root._eventsInitialized) root.processEvents(events)
      else root._eventsInitialized = true
      if (events.length > 0) {
        root._eventSince = Number(events[events.length - 1].id || 0)
      }
    }, function() {
      if (generation !== root._eventGeneration) return
      root._eventPolling = false
      root._eventRequest = null
    })
  }

  function stop() {
    _eventGeneration++
    if (_eventRequest) {
      try {
        _eventRequest.abort()
      } catch (error) {
      }
    }
    _eventRequest = null
    _eventPolling = false
    _eventsInitialized = false
    _eventSince = 0
    _localFiles = []
    _remoteFiles = ({})
    _indexedFiles = []
    _indexedActions = ({})
    changeHoldTimer.stop()
    syncingFiles = []
    syncActions = ({})
    _dotIndex = 0
    _fileIndex = 0
  }

  onEnabledChanged: if (!enabled) stop()

  property Timer eventTimer: Timer {
    interval: 500
    repeat: true
    running: root.enabled
    onTriggered: root.poll()
  }

  property Timer animationTimer: Timer {
    interval: 400
    repeat: true
    running: root.syncingFiles.length > 0
    onTriggered: root._dotIndex = (root._dotIndex + 1) % 3
  }

  property Timer fileTimer: Timer {
    interval: 2500
    repeat: true
    running: root.syncingFiles.length > 1
    onTriggered: root._fileIndex = (root._fileIndex + 1)
      % root.syncingFiles.length
  }

  property Timer changeHoldTimer: Timer {
    interval: 7000
    repeat: false
    onTriggered: {
      root._indexedFiles = []
      root._indexedActions = ({})
      root.rebuild()
    }
  }
}
