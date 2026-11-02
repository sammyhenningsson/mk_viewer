# mk_viewer

A small GTK4 desktop app, written in Ruby, that shows your keyboard's current
layer and lights up the keys you press. It recognises each keyboard by its
Bluetooth name or USB IDs and shows that keyboard's own keymap. With several
connected, it shows whichever you used last. The **Highlight keys** switch in the
title bar turns the highlighting on and off.
Light and dark mode follow your system setting.

## Run

    bundle install
    bin/mk_viewer          # the app
    bin/mk_viewer --list   # the HID devices it sees, and how each one matches
    bundle exec rake test

Needs Ruby, GTK 4.20 or newer (for the system light/dark setting) and read/write access to `/dev/hidraw*`. A permission error
appears in the window; fix it with a udev rule (see `/etc/udev/rules.d/`).

## Supported protocols

| `protocol` | Firmware needed | Layer | Key highlight |
|---|---|---|---|
| `oryx` | ZSA Oryx firmware, nothing extra | yes | exact matrix position |
| `zmk_layer_status` | ZMK with `CONFIG_ZMK_LAYER_STATUS_BLE_HID=y` | yes | inferred from the keycodes sent |

### Limits of `zmk_layer_status`

ZMK's report carries keycodes rather than physical keys, so positions are worked
out from the keymap. As a result:

- Keys that send nothing while held never light, such as a layer-tap held for its layer.
- Tap-hold keys light when they resolve, not when pressed.
- Adaptive keys and macros light the key for what they typed, not the key you pressed.
- If a keycode is on the layer twice, both keys light.
- The layer shows as the first layer until the first report after the app starts.

Exact highlighting would need firmware that also reports positions.

## Adding a keyboard

Add an entry to `config/keyboards.yml`, or copy that file to
`~/.config/mk_viewer/keyboards.yml` (it then replaces the bundled one, and its
`layout:` paths resolve relative to it):

    - id: corne
      name: Corne
      match:
        name: corne          # substring of the Bluetooth name or USB product
      protocol: zmk_layer_status
      layout: layouts/corne.yml
      keymap:
        type: zmk
        path: ~/Development/corne/config/corne_choc_pro.keymap
        labels: ~/path/to/keymap-drawer.yaml   # optional legends

A layout lists `x`/`y` for each key in keymap order, in key-width units. Oryx
boards also need `matrix: [row, col]` and `oryx:` (the key's index in Oryx's data).

A new firmware protocol is a class in `lib/mk_viewer/protocols/` with
`interface?(device)`, `handshake(io)` and `receive(bytes)`, registered in
`Session::PROTOCOLS`.

## Privacy and network

The app reads raw keyboard reports, so it sees what you type. It keeps only the
currently pressed positions, in memory, and doesn't log or store them. The only
network request fetches an Oryx keymap (layout ID and revision) from
`oryx.zsa.io`, once per revision, cached in `~/.cache/mk_viewer/`.
