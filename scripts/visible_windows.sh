#!/bin/sh
# Visible normal windows on the current workspace, one per line: id x y width height.
# Used by the launcher to auto-hide the dock when a window covers it.
cur=$(xprop -root _NET_CURRENT_DESKTOP | grep -o '[0-9]*$')
for w in $(xprop -root _NET_CLIENT_LIST | grep -o '0x[0-9a-f]*'); do
  p=$(xprop -id $w _NET_WM_STATE _NET_WM_WINDOW_TYPE _NET_WM_DESKTOP 2>/dev/null | tr '\n' ' ')
  case "$p" in *HIDDEN*|*TYPE_DOCK*|*TYPE_DESKTOP*) continue;; esac
  d=$(echo "$p" | grep -o 'DESKTOP(CARDINAL) = [0-9]*' | grep -o '[0-9]*$')
  if [ -n "$d" ] && [ "$d" != "$cur" ] && [ "$d" != "4294967295" ]; then continue; fi
  xwininfo -id $w 2>/dev/null | awk -v id="$w" '/Absolute upper-left X/{x=$4}/Absolute upper-left Y/{y=$4}/^  Width/{w=$2}/^  Height/{h=$2}/Map State/{m=$3}END{if(m=="IsViewable")print id,x,y,w,h}'
done
