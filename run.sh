#!/bin/sh
# Start Dock3D. Uses $GODOT if set, else godot4/godot on PATH, else ~/apps/Godot_v4.7.2-stable_linux.x86_64.
cd "$(dirname "$0")" || exit 1
G="${GODOT:-$(command -v godot4 || command -v godot || echo "$HOME/apps/Godot_v4.7.2-stable_linux.x86_64")}"
exec "$G" --path . "$@"
