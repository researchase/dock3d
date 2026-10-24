#!/bin/sh
# WM_CLASS of every open window, so the dock can light up apps that are running.
for w in $(xprop -root _NET_CLIENT_LIST | grep -o '0x[0-9a-f]*'); do
  xprop -id "$w" WM_CLASS
done
