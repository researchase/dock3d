#!/usr/bin/env python3
"""Bring a window to the front, the way a taskbar asks the window manager to (_NET_ACTIVE_WINDOW).
Usage: raise_window.py 0x3a00007"""
import ctypes
import ctypes.util
import sys

CLIENT_MESSAGE = 33
SUBSTRUCTURE_NOTIFY = 1 << 19
SUBSTRUCTURE_REDIRECT = 1 << 20


class XClientMessageEvent(ctypes.Structure):
    _fields_ = [("type", ctypes.c_int), ("serial", ctypes.c_ulong), ("send_event", ctypes.c_int),
                ("display", ctypes.c_void_p), ("window", ctypes.c_ulong), ("message_type", ctypes.c_ulong),
                ("format", ctypes.c_int), ("l", ctypes.c_long * 5)]


class XEvent(ctypes.Union):
    _fields_ = [("xclient", XClientMessageEvent), ("pad", ctypes.c_long * 24)]


def main():
    wid = int(sys.argv[1], 0)
    x = ctypes.cdll.LoadLibrary(ctypes.util.find_library("X11"))
    x.XOpenDisplay.restype = ctypes.c_void_p
    x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    x.XDefaultRootWindow.restype = ctypes.c_ulong
    x.XInternAtom.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int]
    x.XInternAtom.restype = ctypes.c_ulong
    x.XSendEvent.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.c_int, ctypes.c_long, ctypes.c_void_p]
    x.XFlush.argtypes = [ctypes.c_void_p]
    x.XCloseDisplay.argtypes = [ctypes.c_void_p]
    d = x.XOpenDisplay(None)
    if not d:
        sys.exit(1)
    ev = XEvent()
    ev.xclient.type = CLIENT_MESSAGE
    ev.xclient.send_event = 1
    ev.xclient.display = d
    ev.xclient.window = wid
    ev.xclient.message_type = x.XInternAtom(d, b"_NET_ACTIVE_WINDOW", 0)
    ev.xclient.format = 32
    ev.xclient.l[0] = 2   # source: a pager/taskbar, which the window manager always honours
    x.XSendEvent(d, x.XDefaultRootWindow(d), 0, SUBSTRUCTURE_REDIRECT | SUBSTRUCTURE_NOTIFY, ctypes.byref(ev))
    x.XFlush(d)
    x.XCloseDisplay(d)


if __name__ == "__main__":
    main()
