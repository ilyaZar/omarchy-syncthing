.pragma library

function resolvePath(value, homePath) {
  var path = String(value || "")
  if (path === "~") return homePath
  if (path.indexOf("~/") === 0) return homePath + path.slice(1)
  if (path.charAt(0) === "/" || !homePath) return path
  return homePath + "/" + path
}

function errorMessage(error, fallback) {
  var message = ""
  var body = error ? error.body : null
  if (typeof body === "string") message = body.trim()
  else if (body && body.error) message = String(body.error)
  else if (body && body.message) message = String(body.message)
  if (!message && error && error.message) message = String(error.message)
  if (!message) message = fallback || "Syncthing rejected the operation"
  return message.replace(/(?:[A-Z2-7]{7}-){7}[A-Z2-7]{7}/g,
    function(value) { return value.slice(0, 7) + "-REDACTED" })
}

function validateAddInput(id, rawPath, requestedPath, alreadyConfigured) {
  if (!id.trim()) return "Folder ID is required"
  if (id !== id.trim()) return "Folder ID cannot start or end with whitespace"
  if (alreadyConfigured) return "Folder ID already exists"
  if (!rawPath.trim()) return "Folder path is required"
  if (requestedPath.indexOf("\n") >= 0 || requestedPath.indexOf("\r") >= 0) {
    return "Folder paths containing line breaks are not supported"
  }
  return ""
}

function buildConfig(defaults, pending, localDeviceId, displayFileName) {
  var config = JSON.parse(JSON.stringify(defaults || ({})))
  config.id = pending.id
  config.label = pending.label || displayFileName(pending.path) || pending.id
  config.path = pending.path
  config.paused = false
  config.devices = [{
    deviceID: localDeviceId, introducedBy: "", encryptionPassword: ""
  }]
  for (var i = 0; i < pending.selectedDeviceIds.length; i++) {
    config.devices.push({
      deviceID: pending.selectedDeviceIds[i],
      introducedBy: "",
      encryptionPassword: ""
    })
  }
  return config
}

function folderSnapshotMatches(pending, current) {
  if (current.length !== pending.configuredFolders.length) return false
  for (var i = 0; i < pending.configuredFolders.length; i++) {
    var expected = pending.configuredFolders[i]
    var matched = false
    for (var j = 0; j < current.length; j++) {
      var folder = current[j] || ({})
      if (String(folder.id || "") === expected.id
          && String(folder.path || "") === expected.path) matched = true
    }
    if (!matched) return false
  }
  return true
}

function deviceSnapshotError(pending, current) {
  for (var i = 0; i < pending.selectedDeviceIds.length; i++) {
    var selectedId = pending.selectedDeviceIds[i]
    var device = null
    for (var j = 0; j < current.length; j++) {
      if (String((current[j] || {}).deviceID || "") === selectedId) {
        device = current[j]
      }
    }
    if (!device) return "A selected device is no longer configured"
    if (device.untrusted === true) {
      return "Encrypted sharing with untrusted devices must be configured "
        + "in the Syncthing Web UI"
    }
  }
  return ""
}

function offerSnapshotError(pending, currentPending) {
  var offeredBy = ((currentPending[pending.id] || {}).offeredBy || ({}))
  var devices = Object.keys(offeredBy)
  for (var i = 0; i < devices.length; i++) {
    var offer = offeredBy[devices[i]] || ({})
    if (offer.receiveEncrypted === true || offer.remoteEncrypted === true) {
      return "Encrypted folder offers must be accepted in the Syncthing Web UI"
    }
  }
  if (pending.pendingDeviceId && !offeredBy[pending.pendingDeviceId]) {
    return "The selected remote folder offer is no longer available"
  }
  return ""
}

function resolvedPathError(lines, pending, folders) {
  if (lines.length !== pending.configuredPaths.length + 1 || !lines[0]) {
    return "Could not resolve the folder path"
  }
  for (var i = 1; i < lines.length; i++) {
    var folder = folders[i - 1] || ({})
    if (lines[i] === lines[0]) {
      return "Folder path is already configured as "
        + String(folder.label || folder.id || "another folder")
    }
    var existingPrefix = lines[i] === "/" ? "/" : lines[i] + "/"
    var newPrefix = lines[0] === "/" ? "/" : lines[0] + "/"
    if (lines[0].indexOf(existingPrefix) === 0
        || lines[i].indexOf(newPrefix) === 0) {
      return "Nested Syncthing folders are unsupported; choose a path outside "
        + String(folder.label || folder.id || "the configured folder")
    }
  }
  return ""
}
