# Camera framing for Omarchy

Zoom and reframe your webcam the way macOS lets you frame the camera on an Apple
display, for any USB webcam on [Omarchy](https://omarchy.org).

`camframe` publishes a virtual camera, **"Framed Camera"**, that crops and zooms
the real one. A bar widget shows the whole camera image with the framed area
outlined: drag the frame to move it, scroll or use the slider to zoom.

- **Works with locked cameras.** Many webcams, including the Apple Studio Display
  camera, don't let Linux control zoom or pan. The crop happens in software, so
  it works with any camera.
- **The camera is only on when it's used.** The real camera opens when an app
  starts streaming from "Framed Camera" (or the widget preview is open) and
  closes a few seconds after, so the camera light behaves as usual.
- **Live changes, no OBS.** Zoom and position change smoothly while you're on a
  call.

## Install

```bash
omarchy plugin add https://github.com/<you>/omarchy-camframe.git --enable
~/.config/omarchy/plugins/vk.camframe/camframe setup
```

`camframe setup` lists what it will do and asks before using `sudo`:

- installs `v4l2loopback-dkms`, `python-pyzmq`, `v4l-utils` and `ffmpeg` if missing
  (v4l2loopback is built for your kernel with DKMS, which takes a minute);
- creates the "Framed Camera" virtual camera now and at every boot
  (`/etc/modprobe.d/camframe-v4l2loopback.conf`, `/etc/modules-load.d/camframe-v4l2loopback.conf`);
- installs and starts a systemd user service, and links `camframe` into `~/.local/bin`.

Then pick **"Framed Camera"** as the camera in Teams, Meet, Zoom or your browser.

Check the result any time with:

```bash
camframe doctor
```

## Use

| Where | Action |
|---|---|
| Bar widget | Click the camera icon. Drag the frame to move it, scroll to zoom, double-click to reset. Middle-click the icon to reset. |
| Terminal | `camframe zoom in`, `camframe zoom out`, `camframe pan left`, `camframe reset`, `camframe set 1.5 0.5 0.4` |

The icon turns red while the camera is live. The widget preview is mirrored like
a self-view (turn off **Mirror preview** in the widget settings); people on the
call see the normal, unmirrored image.

### Keybindings (optional)

Add to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + ALT + C", "Toggle framed camera", "camframe toggle")
o.bind("SUPER + CTRL + ALT + EQUAL", "Camera zoom in", "camframe zoom in")
o.bind("SUPER + CTRL + ALT + MINUS", "Camera zoom out", "camframe zoom out")
o.bind("SUPER + CTRL + ALT + 0", "Camera framing reset", "camframe reset")
o.bind("SUPER + CTRL + ALT + LEFT", "Camera pan left", "camframe pan left")
o.bind("SUPER + CTRL + ALT + RIGHT", "Camera pan right", "camframe pan right")
o.bind("SUPER + CTRL + ALT + UP", "Camera pan up", "camframe pan up")
o.bind("SUPER + CTRL + ALT + DOWN", "Camera pan down", "camframe pan down")
```

Left and right follow the mirrored self-view.

## Configuration

Everything is detected automatically. To override, create
`~/.config/camframe/config.json`:

```json
{
  "camera": "/dev/v4l/by-id/usb-Logitech_BRIO_1234-video-index0",
  "mode": "1920x1080",
  "output": "1280x720",
  "label": "Framed Camera"
}
```

| Key | Default | Meaning |
|---|---|---|
| `camera` | first camera in `/dev/v4l/by-id` | Which real camera to crop |
| `mode` | largest 16:9 MJPEG mode up to 1920×1080 | Capture size from the real camera |
| `output` | `1280x720` | Size of the virtual camera |
| `label` | `Framed Camera` | Name of the virtual camera to use |
| `loopback` | found by `label` | Virtual camera device, e.g. `/dev/video10` |

Restart the service after changes: `systemctl --user restart camframe`.

## Good to know

- **USB bandwidth.** A webcam reserves a fixed share of its USB link. If a USB
  audio interface sits behind the same hub as the camera (a monitor's built-in
  hub or a dock), heavy camera modes can cut its audio. `camframe doctor` warns
  about this. Plugging the audio interface directly into the computer fixes it.
  camframe caps the capture mode at 1920×1080 for the same reason.
- **Apple Studio Display.** Center Stage runs in the display's firmware and
  can't be controlled from Linux; the camera's zoom and pan controls refuse
  every request. camframe gives you manual framing instead.
- **Other apps using v4l2loopback** (OBS virtual camera, etc.): if the module is
  already loaded with other options, `camframe setup` can't add its device.
  Load one module with several devices, or set `loopback` to the device camframe
  should use.
- **Updating the plugin.** After `omarchy plugin update vk.camframe`, run
  `omarchy restart shell` so the bar loads the new widget, and
  `systemctl --user restart camframe` for the service.

## Uninstall

```bash
systemctl --user disable --now camframe
rm ~/.config/systemd/user/camframe.service ~/.local/bin/camframe
omarchy plugin remove vk.camframe
sudo rm /etc/modprobe.d/camframe-v4l2loopback.conf /etc/modules-load.d/camframe-v4l2loopback.conf
sudo modprobe -r v4l2loopback   # optional
```

## How it works

`camframe run` (the systemd service) opens the v4l2loopback device as its
writer and subscribes to v4l2loopback's client-usage events. While nobody
reads, it writes a cheap placeholder frame so apps still list the camera. When
an app starts streaming, it starts ffmpeg on the real camera: one branch crops
and scales into the virtual camera, the other writes a small preview JPEG for
the widget. ffmpeg's crop filter is driven over ZeroMQ on `127.0.0.1:5561`, so
zoom and pan change without restarting the stream. A few seconds after the last
reader stops, ffmpeg and the real camera close.

## License

MIT
