# Syncthing for Omarchy

See what Syncthing is doing without leaving the Omarchy bar. The plugin shows
live sync health, manages configured folders, opens their directories, starts or
stops the user service, and launches Syncthing's local Web UI.

![Syncthing status and installation controls](preview.png)

## Install

```bash
omarchy plugin add \
  https://github.com/ilyaZar/omarchy-syncthing.git \
  --enable \
  --yes
```

## Install Syncthing

Open the widget, select **More**, then select **Install Syncthing**. The plugin
installs the official Arch package through `omarchy pkg add syncthing`, then
enables and immediately starts `syncthing.service`.

After installation, the plugin treats Syncthing like any other existing
installation. It does not retain package ownership or offer package removal.

After the first start, select **Open Web UI** to add devices and configure
advanced folder options. Syncthing ships with the Web UI built in, so no
separate installation is required. Basic folder management is also available
directly from the plugin.

> [!IMPORTANT]
> Syncthing is powerful, but its initial setup can be cumbersome. The plugin
> makes folder management easier, while the full setup remains in the Web UI.
> Carefully read [Details on setup](#details-on-setup), and use **Open Web UI**
> for easy access to the Syncthing web interface.

## Use

### General

- Use the switch beside **Syncthing** to start or stop the user service. This
  does not change whether the service starts automatically at login.
- Select any folder row to open that folder in the file manager.
- Under **More**, use the folder selector below **FOLDERS** to choose the target
  for **LINK** or **UNLINK**.
- Select **+** to add an existing local directory.
- Select **Refresh** for an immediate health update.
- Select **Open Web UI** to open the local Syncthing interface.

### Keyboard

| Key   | Action                    |
| ----- | ------------------------- |
| `R`   | refresh status            |
| `W`   | open the Web UI           |
| `P`   | start or stop the service |
| `M`   | show or hide More         |
| `Q`   | close the panel           |
| `Esc` | close the panel           |

## Demo

> [!WARNING]
> The Hyprland window to the left of the plugin is **not** part of the plugin. It
> live-tracks changes in the `test-source` directory to make the demo easier to
> follow.

See a folder added, follow uploads, downloads, updates, and removals, open
Syncthing's local Web UI, then unlink and forget the folder without deleting its
files.

<https://github.com/user-attachments/assets/445066ac-68db-4abb-9e2e-68943c348f9b>

## Manage folders

**UNLINK** pauses a folder; **LINK** resumes it. Both map directly to
Syncthing's reversible `paused` setting. Neither action creates a filesystem
link or changes device sharing. Unlinking preserves the Folder ID, path,
settings, device associations, directory, and data. Linking can resume
synchronization immediately.

Adding a folder requires an existing local directory and a unique Folder ID. It
creates an active (`paused=false`) configuration from Syncthing's current folder
defaults. The plugin asks Syncthing to generate a new ID, but the ID can be
replaced when rejoining an existing remote folder. Folder IDs are case sensitive
and must match exactly on every device that shares the folder.

Relative paths and `~/` paths are resolved under `$HOME` and canonicalized.
Paths already configured by Syncthing, nested inside a configured folder, or
parents of another configured folder are rejected. The selected directory may
already contain data, so review advanced behavior in the Web UI and maintain
appropriate backups before synchronizing it.

When creating a new folder identity, no remote devices are selected by default.
Select named devices explicitly to share the folder with them. Selected devices
receive a folder offer and may still need to accept it before synchronization
begins. The plugin never silently shares a new directory with every configured
device.

Pending unencrypted folder offers appear under **More** and in the add form.
**ACCEPT** pre-fills the form with the existing Folder ID, label, and named
offering device. Choose an existing local path, then select **ADD FOLDER** to
complete acceptance. Folder IDs with encrypted offers and sharing with untrusted
devices must be handled in the Syncthing Web UI.

An unlinked row has a **FORGET** action. After confirmation, this removes only
that folder from Syncthing configuration and the plugin view. It does not delete
the directory or its data files. For the default marker, Syncthing also attempts
to remove its internal `.stfolder` directory and normally recreates it if the
folder is added again. Forgetting discards the local folder settings and device
list; no hidden plugin metadata is retained. To rejoin the same remote folder
later, accept its pending offer or enter its exact Folder ID and select the
intended devices. Reusing an ID restores only the folder identity, not the
previous settings or device selections. Select **NEW ID** only when creating a
different folder identity.

Folder management requires Syncthing 1.12.0 or later.

**BROWSE** opens a folder chooser. A path can be entered manually if the chooser
is unavailable.

## Details on setup

Syncthing requires two separate relationships before files can synchronize:

1. The devices must trust each other.
2. A specific folder must be shared between those devices.

A successful device connection alone does not synchronize any folders.

### Add the remote device

On one machine, open the Web UI and select **Actions**, then **Show ID**. Copy
the Device ID. On the other machine, select **Add Remote Device** and enter:

- **Device ID:** the exact ID shown by the other machine
- **Device name:** a descriptive local name, such as `workstation`
- **Device group:** optional local organization, such as `Personal devices`

For example, a fictional Device ID looks like this:

```text
A7B3CDE-F4G5HJK-L6M7NPQ-R2STUVW-X3Y4ZAB-C5D6EFG-H7J2KLM-N3P4QRS
```

The device name and group are descriptive. A device group only organizes the Web
UI locally; it does not grant folder access or enable synchronization.

Save the device and accept the resulting device request on the other machine.
Alternatively, add each machine's Device ID manually on the other machine. The
devices should then show **Connected**.

See Syncthing's
[Getting Started guide](https://docs.syncthing.net/intro/getting-started.html)
and
[device configuration reference](https://docs.syncthing.net/users/config.html#device-element)
for more detail.

### Share the folder

On the machine that already owns the folder:

1. Select the folder in the Syncthing Web UI.
2. Select **Edit**.
3. Open the **Sharing** tab.
4. Select the new remote device.
5. Save.

The receiving machine should display a notification that a folder has been
offered:

1. Select **Add** or **Accept**.
2. Choose the local destination path.
3. Save.

Accept the offered folder instead of independently creating another folder with
the same label and path. Accepting the offer preserves the shared Folder ID.

### Folder label, path, and ID

A Syncthing folder has three distinct values:

- **Folder label:** a human-readable display name
- **Folder path:** the directory used on this particular machine
- **Folder ID:** the identity used to match the folder across devices

Paths and labels may differ between machines. The Folder ID must be identical.
The safest setup is to create the folder on one machine, share it, and accept
the offer on every other machine.

For example, these are the same shared folder even though their paths differ:

```text
workstation  ID: project-files  Path: /home/alex/Documents/project
laptop       ID: project-files  Path: /home/sam/Sync/project
```

These are unrelated folders despite using the same path and label:

```text
workstation  ID: project-files  Path: /home/alex/Sync  Label: Syncthing
laptop       ID: q7r2m-p5x4k    Path: /home/alex/Sync  Label: Syncthing
```

See Syncthing's
[Web UI folder guide](https://docs.syncthing.net/intro/gui.html#creating-a-new-synced-folder)
for the official explanation of Folder IDs, labels, paths, and device sharing.

### Recover from independently created folders

If both machines already created separate folder identities for the intended
directory, choose one Folder ID as the canonical identity. Usually this is the
folder on the machine that already contains the complete data.

On the receiving machine:

1. Remove the unrelated folder from Syncthing configuration.
2. Do not delete the directory or its files.

On the machine with the canonical folder:

1. Edit the folder.
2. Open **Sharing**.
3. Select the receiving device.
4. Save.

On the receiving machine:

1. Accept the offered canonical folder.
2. Select the existing local directory as its path.
3. Confirm that the offered Folder ID is preserved.
4. Save.

Review both directories and maintain an appropriate backup before merging
existing data. Once both devices show the same Folder ID and include each other
under **Sharing**, synchronization can begin.

## Remove Syncthing

Remove Syncthing manually with the method that installed it. For the official
package installed by this plugin:

```bash
systemctl --user disable --now syncthing.service
omarchy pkg drop syncthing
```

These commands do not remove Syncthing configuration, shared folders, or their
files.

Remove the plugin separately:

```bash
omarchy plugin remove io.github.ilyazar.syncthing --yes
```

Removing the plugin never removes Syncthing. The plugin monitors any Syncthing
installation found on the command path, shows its resolved executable, and can
control an existing `syncthing.service`. Installation is offered only when no
Syncthing executable or conflicting installation files are found.

Removing the plugin does not reverse changes made through it. Added folders,
device associations, and linked or unlinked states remain in Syncthing
configuration. The plugin stores no separate folder-restoration metadata.

## Security and license

The plugin talks only to Syncthing's local API at `127.0.0.1:8384`. It keeps the
API key in memory and does not persist or log it. Like other Omarchy shell
plugins, it runs unsandboxed; the API key permits Syncthing configuration
changes.

Plugin code is MIT licensed. Adapted Syncthing status icons are MPL-2.0; their
source and attribution are documented in `assets/README.md`.
