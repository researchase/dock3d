# Dock3D

A 3D, see-through dock for Linux (X11), built with Godot 4.7, with two built-in views:

- **Drawers**: a 3D file browser. Folders are little drawer cabinets and files are paper cards,
  wrapped round an invisible cylinder. Click a folder and the current drum glides back into the
  blurred background while its contents fly out to take its place. Hover a file for a preview;
  pictures and videos preview on the right.
- **Apps**: every installed app on a rolling drum. Click one to start it.

The dock magnifies under the mouse, shows which apps are running, auto-hides when a window covers
it, and accepts `.desktop` files dropped onto it.

## Requirements

Linux with X11 and a compositor (tested on Ubuntu GNOME), Godot 4.7, and `xprop`, `xwininfo`,
`gtk-launch`, `ffmpeg` (video thumbnails/previews) and `pdftoppm` (PDF thumbnails).

## Run

```sh
./run.sh            # or: GODOT=/path/to/godot ./run.sh
```

Edit `apps.cfg` to choose the dock's apps. To start at login, add `run.sh` to Startup Applications.

## License

Apache License 2.0 — see `LICENSE`. Please keep the `NOTICE` file (credits) when sharing.
