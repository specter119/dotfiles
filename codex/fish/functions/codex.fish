function codex --description 'Run codex with bwrap sandboxing'
    # Purpose: Add security isolation using bwrap sandboxing
    # Simple setup: just mount ~/.codex directory

    set -q CODEX_CONFIG; or set CODEX_CONFIG $HOME/.config/codex
    set CODEX_CONFIG (string replace '~' $HOME $CODEX_CONFIG)

    # Create codex home directory
    mkdir -p $CODEX_CONFIG

    # Detect git worktree and prepare extra mounts
    set -l worktree_mounts
    if git rev-parse --is-inside-work-tree &>/dev/null
        set -l git_common_dir (git rev-parse --git-common-dir 2>/dev/null)
        set -l git_dir (git rev-parse --git-dir 2>/dev/null)
        # If git-common-dir differs from git-dir, we're in a worktree
        if test "$git_common_dir" != "$git_dir"
            set -l main_repo (dirname (realpath $git_common_dir))
            if test -d "$main_repo"
                set worktree_mounts --bind $main_repo $main_repo
            end
        end
    end

    # Bwrap sandboxing
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
        --tmpfs $HOME \
        --dir $HOME/.config \
        --bind-try $HOME/.config $HOME/.config \
        --dir $HOME/.local \
        --bind-try $HOME/.local $HOME/.local \
        --bind-try $HOME/.cache $HOME/.cache \
        --bind $CODEX_CONFIG $HOME/.codex \
        --bind (pwd) (pwd) \
        $worktree_mounts \
        --setenv HOME $HOME \
        --setenv PATH $HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
        --unshare-all \
        --share-net \
        (command -v codex) $argv
end
