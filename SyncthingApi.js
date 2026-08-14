.pragma library

var Endpoints = {
  addFolder: "/rest/config/folders",
  deleteFolder: "/rest/config/folders/{id}",
  getDefaultFolder: "/rest/config/defaults/folder",
  getDevices: "/rest/config/devices",
  getFolder: "/rest/config/folders/{id}",
  getFolders: "/rest/config/folders",
  getFileInfo: "/rest/db/file",
  getFolderStatus: "/rest/db/status",
  getConnections: "/rest/system/connections",
  getPendingFolders: "/rest/cluster/pending/folders",
  getRandomString: "/rest/svc/random/string",
  getRestartRequired: "/rest/config/restart-required",
  getSystemStatus: "/rest/system/status",
  getEvents: "/rest/events",
  patchFolder: "/rest/config/folders/{id}",
  scanFolder: "/rest/db/scan"
}

function endpointPath(name, settings) {
  var path = Endpoints[name]
  if (!path) throw new Error("Unknown Syncthing endpoint: " + name)
  var values = (settings || {}).path || {}
  return path.replace(/\{([^}]+)\}/g, function(match, key) {
    if (values[key] === undefined || values[key] === null) {
      throw new Error("Missing Syncthing endpoint value: " + key)
    }
    return encodeURIComponent(String(values[key]))
  })
}

function queryString(values) {
  var parts = []
  var query = values || {}
  var keys = Object.keys(query)
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i]
    var value = query[key]
    if (value === undefined || value === null) continue
    var list = value instanceof Array ? value : [value]
    for (var j = 0; j < list.length; j++) {
      parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(list[j])))
    }
  }
  return parts.length ? "?" + parts.join("&") : ""
}

function parseResponse(xhr) {
  var text = String(xhr.responseText || "")
  if (!text) return null
  var first = text.charAt(0)
  if (first === "{" || first === "[") {
    try {
      return JSON.parse(text)
    } catch (error) {
      return text
    }
  }
  return text
}

function request(baseUrl, apiKey, name, options, onSuccess, onError) {
  var settings = options || {}
  var path = endpointPath(name, settings)
  var url = String(baseUrl || "").replace(/\/$/, "") + path
    + queryString(settings.query)
  var xhr = new XMLHttpRequest()
  var completed = false

  function fail(message) {
    if (completed) return
    completed = true
    if (onError) {
      onError({
        endpoint: name,
        status: xhr.status || 0,
        message: message,
        body: parseResponse(xhr)
      })
    }
  }

  xhr.open(String(settings.method || "GET"), url, true)
  xhr.setRequestHeader("Accept", "application/json")
  if (settings.json !== undefined) {
    xhr.setRequestHeader("Content-Type", "application/json")
  }
  if (apiKey) xhr.setRequestHeader("X-API-Key", apiKey)
  xhr.onreadystatechange = function() {
    if (xhr.readyState !== 4 || completed) return
    var accepted = settings.acceptStatuses || []
    if ((xhr.status >= 200 && xhr.status < 300)
        || accepted.indexOf(xhr.status) >= 0) {
      completed = true
      if (onSuccess) onSuccess(parseResponse(xhr), xhr)
    } else {
      fail("HTTP " + (xhr.status || 0))
    }
  }
  xhr.onerror = function() { fail("Connection failed") }

  var body = settings.json !== undefined
    ? JSON.stringify(settings.json) : (settings.body || null)
  xhr.send(body)
  return xhr
}
