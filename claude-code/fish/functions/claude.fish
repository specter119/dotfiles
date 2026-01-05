function claude --description 'Run claude code with bwrap sandboxing and adapted home directory'
    # Purpose:
    #   1. Make claude-code follow XDG Base Directory Specification, by setting
    #     $CLAUDE_CONFIG as `~/.config/claude`
    #     $CLAUDE_SHARE as `~/.local/share/claude`
    #   2. Add security isolation using bwrap sandboxing
    #

    # Prerequisites:
    #   - $CLAUDE_CONFIG/settings.json must exist (required configuration)
    #
    # Auto-generated files:
    #   - ~/.claude.json (user settings, auto-created as empty JSON if needed)
    #   - ~/.claude.json.backup (backup file, auto-created as empty JSON if needed)
    #
    # Binary priority: $CLAUDE_SHARE/local/claude > global claude from PATH

    set -q CLAUDE_SHARE; or set CLAUDE_SHARE $HOME/.local/share/claude
    set CLAUDE_SHARE (string replace '~' $HOME $CLAUDE_SHARE)
    set -q CLAUDE_CONFIG; or set CLAUDE_CONFIG $HOME/.config/claude
    set CLAUDE_CONFIG (string replace '~' $HOME $CLAUDE_CONFIG)

    # Determine which claude binary to use
    if test -f $CLAUDE_SHARE/local/claude
        set claude_cmd $HOME/.claude/local/claude
    else
        set claude_cmd (command -v claude)
    end

    # Handle config files localted at `~` by default.
    mkdir -p $CLAUDE_SHARE
    for config_file in .claude.json .claude.json.backup
        test -f ~/$config_file; and mv ~/$config_file $CLAUDE_SHARE/
        test -f $CLAUDE_SHARE/$config_file; or echo '{}' >$CLAUDE_SHARE/$config_file
    end

    # Bwrap
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
        --bind $CLAUDE_SHARE/.claude.json $HOME/.claude.json \
        --bind $CLAUDE_SHARE/.claude.json.backup $HOME/.claude.json.backup \
        --bind $CLAUDE_SHARE $HOME/.claude \
        --bind $CLAUDE_CONFIG/settings.json $HOME/.claude/settings.json \
        --bind-try $CLAUDE_CONFIG/CLAUDE.md $HOME/.claude/CLAUDE.md \
        --bind-try $CLAUDE_CONFIG/commands $HOME/.claude/commands \
        --bind-try $CLAUDE_CONFIG/agents $HOME/.claude/agents \
        --bind-try $CLAUDE_CONFIG/skills $HOME/.claude/skills \
        --bind-try $HOME/.gemini $HOME/.gemini \
        --bind (pwd) (pwd) \
        --setenv HOME $HOME \
        --setenv PATH $HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
        --unshare-all \
        --share-net \
        $claude_cmd $argv
end
