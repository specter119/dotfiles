function codex --description 'Run codex with bwrap sandboxing'
    # Purpose: Add security isolation using bwrap sandboxing
    # Simple setup: just mount ~/.codex directory

    set -q CODEX_CONFIG; or set CODEX_CONFIG $HOME/.config/codex
    set CODEX_CONFIG (string replace '~' $HOME $CODEX_CONFIG)

    # Create codex home directory
    mkdir -p $CODEX_CONFIG

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
        --setenv HOME $HOME \
        --setenv PATH $HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
        --unshare-all \
        --share-net \
        (command -v codex) $argv
end
