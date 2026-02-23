#!/usr/bin/env fish
function _bwrap_agentic_cli --description 'Run a CLI tool inside a bwrap sandbox'
    # Usage: _bwrap_agentic_cli [extra-bwrap-args...] -- command [args...]
    #
    # Common bwrap sandbox for agentic CLI tools (claude, codex, etc.).
    # Handles worktree detection, read-only reference mounts, and /mnt symlink resolution.
    # Extra bwrap args (e.g. --bind) go before `--`; the CLI command and its args go after.

    # Split argv on `--`: extra bwrap args before, command+args after
    set -l bwrap_extra
    set -l cmd_args
    set -l sep (contains -i -- -- $argv)
    if test -n "$sep"
        set bwrap_extra $argv[1..(math $sep - 1)]
        set cmd_args $argv[(math $sep + 1)..]
    else
        set cmd_args $argv
    end

    # Detect git worktree and prepare extra mounts
    set -l worktree_mounts
    if functions -q git_worktree_mounts
        set worktree_mounts (git_worktree_mounts)
    end

    # Prepare read-only reference mounts
    set -l ro_ref_mounts
    if functions -q bwrap_ro_ref_mounts
        set ro_ref_mounts (bwrap_ro_ref_mounts)
    end

    # Resolve symlink to real path for /mnt directories
    set -l work_dir (pwd)
    set -l real_dir (realpath $work_dir)
    if test "$work_dir" != "$real_dir"; and string match -q '/mnt*' $real_dir
        set work_dir $real_dir
    end

    bwrap \
        --dev /dev \
        --dev-bind-try /dev/dri /dev/dri \
        --proc /proc \
        --ro-bind /etc /etc \
        --ro-bind /usr/share /usr/share \
        --ro-bind /usr/lib /usr/lib \
        --ro-bind /usr/lib64 /usr/lib64 \
        --ro-bind /usr/bin /usr/bin \
        --ro-bind /usr/sbin /usr/sbin \
        --ro-bind /usr/include /usr/include \
        --bind /tmp /tmp \
        --bind /run /run \
        --bind /var /var \
        --ro-bind-try /opt /opt \
        --symlink /usr/lib /lib \
        --symlink /usr/lib /lib64 \
        --symlink /usr/bin /bin \
        --symlink /usr/bin /sbin \
        --ro-bind-try /mnt/wslg /mnt/wslg \
        --ro-bind-try /mnt/c/Windows/Fonts /mnt/c/Windows/Fonts \
        --ro-bind-try $WSL_WIN_HOME/scoop/apps/mingit $WSL_WIN_HOME/scoop/apps/mingit \
        --tmpfs $HOME \
        --dir $HOME/.config \
        --bind-try $HOME/.config $HOME/.config \
        --dir $HOME/.local \
        --bind-try $HOME/.local $HOME/.local \
        --dir $HOME/.cache \
        --bind-try $HOME/.cache $HOME/.cache \
        $bwrap_extra \
        $ro_ref_mounts \
        --bind $work_dir $work_dir \
        --chdir $work_dir \
        $worktree_mounts \
        --setenv HOME $HOME \
        --setenv PATH $HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
        (command -v $cmd_args[1]) $cmd_args[2..]
end
