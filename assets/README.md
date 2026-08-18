# Syncthing status icons

The four SVG files in `brand/` are formatting adaptations of Syncthing's
official 16-by-16 status icons. Their appearance and view boxes are preserved:

- `status-default.svg`
- `status-notify.svg`
- `status-pause.svg`
- `status-sync.svg`

They were retrieved from the Syncthing repository at commit
`058bcd7334839663cf569501d3ac539034d45cb5`:

<https://github.com/syncthing/syncthing/tree/main/assets/statusicons>

`mono/` holds monochrome redraws of the same four icons, tinted to the theme
at runtime by `MonoIcon.qml`. They must stay pure white on transparent: the
tint multiplies the source's value channel, so anything darker comes out
darker still.

Copyright belongs to the Syncthing contributors. These adapted files remain
licensed under the Mozilla Public License 2.0:

<https://github.com/syncthing/syncthing/blob/main/LICENSE>
