set TTY1 (tty)
[ "$TTY1" = "/dev/tty1" ] && exec sway -D legacy-wl-drm
