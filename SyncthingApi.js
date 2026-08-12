.pragma library

// Keep the plugin's API surface read-only and limited to displayed status.
var Endpoints = {
  getDevices: "/rest/config/devices",
  getFolders: "/rest/config/folders",
  getFolderStatus: "/rest/db/status",
  getConnections: "/rest/system/connections",
  getSystemStatus: "/rest/system/status"
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
  var path = Endpoints[name]
  if (!path) throw new Error("Unknown Syncthing endpoint: " + name)

  var settings = options || {}
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

  xhr.open("GET", url, true)
  xhr.setRequestHeader("Accept", "application/json")
  if (apiKey) xhr.setRequestHeader("X-API-Key", apiKey)
  xhr.onreadystatechange = function() {
    if (xhr.readyState !== 4 || completed) return
    if (xhr.status >= 200 && xhr.status < 300) {
      completed = true
      if (onSuccess) onSuccess(parseResponse(xhr), xhr)
    } else {
      fail("HTTP " + (xhr.status || 0))
    }
  }
  xhr.onerror = function() { fail("Connection failed") }

  xhr.send()
  return xhr
}
