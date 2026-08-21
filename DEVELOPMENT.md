# Development

Runtime code is grouped by responsibility:

- Root `Panel.qml` and `Service.qml` are the runtime entry points.
- `core/` contains stateful controllers and local API orchestration.
- `ui/` contains panel views and dialogs.
- `models/` contains pure JavaScript transformations.
- `config/` and `webui/` contain shipped settings and theme templates.
- `scripts/` contains bounded helpers for lifecycle and system integration.
- `tests/` covers pure models plus helper behavior.

Split a file when it owns unrelated behavior, not to meet an arbitrary line
count.

## Checks

Run the complete local suite from the repository root:

```bash
git diff --check
jq empty manifest.json
omarchy plugin validate .
qmllint Panel.qml Service.qml core/*.qml models/*.js ui/*.qml \
  tests/run.qml scripts/folder-picker.qml
for script in scripts/*.sh; do bash -n "$script"; done
shellcheck scripts/*.sh
qml6 --apptype core -f tests/run.qml
bash tests/scripts.test.sh
```

## Syncthing state contract

Display only state reported by Syncthing:

- Classify an indexed file with `/rest/db/file` and `local.deleted`.
- Treat `RemoteDownloadProgress` as an upload from the local device.
- Rescan an indexed directory so files newly placed inside it are classified.
- Do not infer a rename or move from hashes, timing, or adjacent events.

Tests should cover these user-visible contracts or a concrete model invariant.
Avoid assertions that only mirror implementation details.
