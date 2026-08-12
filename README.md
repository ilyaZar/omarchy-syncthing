# Syncthing for Omarchy

See what Syncthing is doing without leaving the Omarchy bar. The plugin shows
live sync health, opens configured folders, starts or stops the user service,
and launches Syncthing's local Web UI.

![Syncthing status and installation controls](preview.png)

## Install

```bash
omarchy plugin add \
  https://github.com/ilyaZar/omarchy-syncthing.git \
  --enable \
  --yes
```

The widget starts on the right side of the bar and can be moved with Omarchy's
bar customization controls.

## Install Syncthing

Open the widget, select **More**, then select **Install Syncthing**. The plugin
installs the official Arch package through `omarchy pkg add syncthing`, so it
follows normal system updates. A terminal shows every step and waits for Enter
when it finishes.

The square **?** beside **Installation** explains what the plugin manages and
what it preserves.

After the first start, select **Open Web UI** to add devices and folders.

## Use

- Use the switch beside **Syncthing** to start or stop syncing.
- Select any folder row to open that folder in the file manager.
- Select **Refresh** for an immediate health update.
- Select **Open Web UI** to open the local Syncthing interface.

The status beneath **Syncthing** changes as folders synchronize, scan, pause,
or need attention. Long folder paths are shortened from the left while keeping
the final directory visible.

| Key | Action                |
| --- | --------------------- |
| `R` | refresh status        |
| `W` | open the Web UI       |
| `P` | start or stop syncing |
| `M` | show or hide More     |

## Uninstall

Open **More**, select **Uninstall Syncthing**, and confirm. The package is
removed through Omarchy. Syncthing configuration, shared folders, and their
files are never removed.

Remove the plugin separately:

```bash
omarchy plugin remove io.github.ilyazar.syncthing --yes
```

The plugin refuses to adopt or remove an existing unrecorded Syncthing
installation. Remove that installation first, then use the installer in the
widget.

## Security and license

The plugin talks only to Syncthing's local API at `127.0.0.1:8384`. It reads
the API key into memory and never writes or logs it.

Plugin code is MIT licensed. Adapted Syncthing status icons are MPL-2.0; their
source and attribution are documented in `assets/README.md`.
