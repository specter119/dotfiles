# Set WIN_HOME and WSL_WIN_HOME for WSL environment and import to systemd
# WIN_HOME: Windows native path (e.g., C:\Users\xxx)
# WSL_WIN_HOME: Linux path via wslpath (e.g., /mnt/c/Users/xxx)

if test -f /proc/sys/fs/binfmt_misc/WSLInterop
    set -l win_home (/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -NonInteractive -c 'echo $env:userprofile' 2>/dev/null | string trim)

    if test -n "$win_home"
        set -gx WIN_HOME $win_home
        set -gx WSL_WIN_HOME (wslpath $win_home)
        # Import to systemd user session (non-blocking, ignore if systemd not running)
        systemctl --user import-environment WIN_HOME WSL_WIN_HOME &>/dev/null &
        disown
    end
end
