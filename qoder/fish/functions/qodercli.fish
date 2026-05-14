function qodercli --description 'Run qodercli with bwrap sandboxing and adapted home directory'
    # Keep qoder data in an XDG-style host directory and mount it as ~/.qoder
    # inside bwrap (qodercli's built-in home path).
    set -l qoder_config_dir
    if set -q QODER_CONFIG_DIR
        set qoder_config_dir $QODER_CONFIG_DIR
    else
        set qoder_config_dir $HOME/.config/qoder
    end
    set qoder_config_dir (string replace -r '^~/' "$HOME/" $qoder_config_dir)
    set qoder_config_dir (string replace -r '^~$' $HOME $qoder_config_dir)

    # Backward compatibility: if old state dir exists and new dir does not,
    # continue using the old path to avoid losing history/sessions.
    set -l qoder_legacy_home $HOME/.local/share/qoder
    if test -d $qoder_legacy_home; and not test -d $qoder_config_dir
        set qoder_config_dir $qoder_legacy_home
    end

    mkdir -p $qoder_config_dir

    # Claude config for optional qoder --with-claude-config usage.
    set -q CLAUDE_CONFIG_DIR; or set CLAUDE_CONFIG_DIR $HOME/.config/claude
    set CLAUDE_CONFIG_DIR (string replace -r '^~/' "$HOME/" $CLAUDE_CONFIG_DIR)

    _bwrap_agentic_cli \
        --bind $qoder_config_dir $HOME/.qoder \
        --ro-bind-try $CLAUDE_CONFIG_DIR $HOME/.claude \
        -- qodercli $argv
end
