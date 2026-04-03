# OpenRGB CPU temperature script (`rgb.sh`)

`rgb.sh` reads CPU temperature (AMD `Tctl` via `sensors`), maps it to a color, and drives OpenRGB in **direct** mode. On start it tries to bring up the **OpenRGB SDK server** (default `0.0.0.0:6742`) if nothing is already listening on that port.

## Dependencies

Install these on the machine (Debian/Ubuntu-style names):

```bash
sudo apt update
sudo apt install -y openrgb lm-sensors bc iproute2 bash
```

- **openrgb** — RGB control (CLI + server used by the script).
- **lm-sensors** — provides the `sensors` command.
- **bc** — floating-point math in the script.
- **iproute2** — provides `ss` (used to detect if port 6742 is listening).

Enable kernel modules / sensor detection if you have not already:

```bash
sudo sensors-detect   # answer the prompts; then load suggested modules if needed
sensors               # confirm you see a Tctl line for the CPU
```

### Device access (recommended)

RGB and SMBus access often need **udev rules** and group membership. You can use the helper in this repo or install rules manually:

```bash
cd /path/to/OpenRGB
chmod +x rules.sh
./rules.sh    # downloads OpenRGB udev rules; requires sudo
```

Then add your user to the groups OpenRGB documents (commonly `i2c`, `plugdev`, or similar on your distro), **log out and back in**, and verify `openrgb` can see devices.

---

## Make the script executable

```bash
chmod +x /path/to/OpenRGB/rgb.sh
```

Replace `/path/to/OpenRGB` with the real directory (example: `/home/yourname/Programs/OpenRGB`).

---

## Run as a systemd service (start at boot)

You can install either a **system** service (runs as a specific user at boot) or a **user** service (runs in your login session; can run at boot if **lingering** is enabled).

### Option A — System service (typical for “at boot”)

1. **Note the full path to `openrgb`** (systemd uses a minimal `PATH`):

   ```bash
   command -v openrgb
   ```

   Example output: `/usr/bin/openrgb`. The script calls `openrgb` by name; the unit below sets a normal `PATH` so this usually works.

2. **Create a unit file** (edit `User=`, paths, and `ExecStart=` for your account):

   ```bash
   sudo nano /etc/systemd/system/openrgb-temp-rgb.service
   ```

   Paste (adjust **`User`**, **`Group`**, and **`ExecStart`**):

   ```ini
   [Unit]
   Description=OpenRGB CPU temperature RGB (rgb.sh)
   After=network-online.target
   Wants=network-online.target

   [Service]
   Type=simple
   User=chamd
   Group=chamd
   ExecStart=/bin/bash /home/chamd/Programs/OpenRGB/rgb.sh
   Restart=on-failure
   RestartSec=5
   Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin
   # Optional: listen only on localhost instead of 0.0.0.0
   # Environment=SDK_HOST=127.0.0.1
   # Optional: peak R/G/B for temp colors (0–255; default in script is 40)
   # Environment=MAX_CH=200

   [Install]
   WantedBy=multi-user.target
   ```

   To pass brightness as an **argument** instead (overrides `MAX_CH` if both are set):

   ```ini
   ExecStart=/bin/bash /home/chamd/Programs/OpenRGB/rgb.sh 200
   ```

3. **Reload systemd, enable, and start:**

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable openrgb-temp-rgb.service
   sudo systemctl start openrgb-temp-rgb.service
   ```

4. **Check status and logs:**

   ```bash
   systemctl status openrgb-temp-rgb.service
   journalctl -u openrgb-temp-rgb.service -f
   ```

5. **Stop / disable if needed:**

   ```bash
   sudo systemctl stop openrgb-temp-rgb.service
   sudo systemctl disable openrgb-temp-rgb.service
   ```

6. **Change `MAX_CH`, `ExecStart`, or other unit options later:** edit the unit file, then reload and restart so systemd picks up the changes:

   ```bash
   sudo nano /etc/systemd/system/openrgb-temp-rgb.service
   sudo systemctl daemon-reload
   sudo systemctl restart openrgb-temp-rgb.service
   ```

**Graphical / OpenRGB note:** At boot, OpenRGB may still need a **display** or working Qt platform for your install. If the service fails only before you log in graphically, try **Option B** (user service after graphical session) or start the service **after** `graphical.target` (advanced; depends on your desktop).

---

### Option B — User service (per login) + optional boot without login GUI

1. **Create the user systemd directory and unit:**

   ```bash
   mkdir -p ~/.config/systemd/user
   nano ~/.config/systemd/user/openrgb-temp-rgb.service
   ```

   Paste (adjust **`ExecStart`** if your clone is not under `~/Programs/OpenRGB`):

   ```ini
   [Unit]
   Description=OpenRGB CPU temperature RGB (rgb.sh)
   After=graphical-session.target

   [Service]
   Type=simple
   ExecStart=%h/Programs/OpenRGB/rgb.sh
   Restart=on-failure
   RestartSec=5
   Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin
   # Environment=SDK_HOST=127.0.0.1
   # Environment=MAX_CH=200

   [Install]
   WantedBy=default.target
   ```

   Or pass brightness as the first argument (wins over `MAX_CH`):

   ```ini
   ExecStart=%h/Programs/OpenRGB/rgb.sh 200
   ```

2. **Reload, enable, and start for your user session:**

   ```bash
   systemctl --user daemon-reload
   systemctl --user enable openrgb-temp-rgb.service
   systemctl --user start openrgb-temp-rgb.service
   systemctl --user status openrgb-temp-rgb.service
   ```

3. **Logs:**

   ```bash
   journalctl --user -u openrgb-temp-rgb.service -f
   ```

4. **Run user services at boot even before interactive login** (optional):

   ```bash
   loginctl enable-linger "$USER"
   ```

   Reboot and confirm with `systemctl --user status` (may still require a graphical session for OpenRGB depending on your setup).

5. **After editing the user unit** (e.g. `MAX_CH` or `ExecStart`):

   ```bash
   nano ~/.config/systemd/user/openrgb-temp-rgb.service
   systemctl --user daemon-reload
   systemctl --user restart openrgb-temp-rgb.service
   ```

---

## Brightness (`MAX_CH`) and systemd

`rgb.sh` maps CPU temperature to RGB using a **peak channel value** (default **40**). You can set it to **0–255** in either of these ways:

| Method | Example |
|--------|---------|
| **Environment** (no positional arg) | `Environment=MAX_CH=200` in the unit’s `[Service]` section |
| **First argument** to the script | `ExecStart=.../rgb.sh 200` |

If you use **both**, the **positional argument overrides** `MAX_CH`.

You can combine variables on one line:

```ini
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin" "MAX_CH=200"
```

**Apply any unit-file change:** `daemon-reload` then `restart` (see step 6 under Option A, or step 5 under Option B).

---

## Manual test (foreground)

```bash
/path/to/OpenRGB/rgb.sh
/path/to/OpenRGB/rgb.sh 200          # peak channel 200 (0–255)
MAX_CH=128 /path/to/OpenRGB/rgb.sh   # same via env
```

Stop with `Ctrl+C`. If port 6742 was free, stopping the script stops the OpenRGB server process **this script started**; an already-running OpenRGB is left alone.

---

## Environment variables (optional)

| Variable   | Default     | Meaning                          |
|-----------|-------------|----------------------------------|
| `SDK_HOST` | `0.0.0.0` | SDK bind address                 |
| `SDK_PORT` | `6742`    | SDK TCP port                     |
| `MAX_CH`   | `40`      | Peak R/G/B for temp mapping (0–255); ignored if you pass a numeric first argument to `rgb.sh` |

Example:

```bash
SDK_HOST=127.0.0.1 /path/to/OpenRGB/rgb.sh
MAX_CH=200 /path/to/OpenRGB/rgb.sh
```

---

## Security note

Binding the SDK to **`0.0.0.0`** exposes the OpenRGB SDK to **all network interfaces**. For a single PC, **`SDK_HOST=127.0.0.1`** in the unit file is often safer.
