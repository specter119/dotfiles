function qodercli --description 'Run qodercli with bwrap sandboxing and adapted home directory'
    # XDG Base Directory Specification:
    #   - $QODER_CONFIG_DIR (`~/.config/qoder`): config (settings, etc.)
    #   - $QODER_SHARE (`~/.local/share/qoder`): state (.qoder.json, projects, etc.)
    #
    # Inside bwrap, $QODER_SHARE is mounted as ~/.qoder (qodercli's default),
    # with config files from the host's $QODER_CONFIG_DIR overlaid on top.

    set -q QODER_CONFIG_DIR; or set QODER_CONFIG_DIR $HOME/.config/qoder
    set QODER_CONFIG_DIR (string replace '~' $HOME $QODER_CONFIG_DIR)
    set -l QODER_SHARE $HOME/.local/share/qoder

    # Ensure state directory and .qoder.json exist
    mkdir -p $QODER_SHARE
    test -f ~/.qoder.json; and mv ~/.qoder.json $QODER_SHARE/
    test -f $QODER_SHARE/.qoder.json; or echo '{}' >$QODER_SHARE/.qoder.json

    # Claude config for reading
    set -q CLAUDE_CONFIG_DIR; or set CLAUDE_CONFIG_DIR $HOME/.config/claude
    set CLAUDE_CONFIG_DIR (string replace '~' $HOME $CLAUDE_CONFIG_DIR)
    set -l CLAUDE_SHARE $HOME/.local/share/claude

    _bwrap_agentic_cli \
        --bind $QODER_SHARE/.qoder.json $HOME/.qoder.json \
        --bind $QODER_SHARE $HOME/.qoder \
        --bind $QODER_CONFIG_DIR/settings.json $HOME/.qoder/settings.json \
        --bind-try $QODER_CONFIG_DIR/AGENTS.md $HOME/.qoder/AGENTS.md \
        --bind-try $QODER_CONFIG_DIR/commands $HOME/.qoder/commands \
        --bind-try $QODER_CONFIG_DIR/agents $HOME/.qoder/agents \
        --bind-try $QODER_CONFIG_DIR/skills $HOME/.qoder/skills \
        --ro-bind-try $CLAUDE_SHARE $HOME/.claude \
        --ro-bind-try $CLAUDE_CONFIG_DIR/settings.json $HOME/.claude/settings.json \
        --ro-bind-try $CLAUDE_CONFIG_DIR/CLAUDE.md $HOME/.claude/CLAUDE.md \
        --ro-bind-try $CLAUDE_CONFIG_DIR/commands $HOME/.claude/commands \
        --ro-bind-try $CLAUDE_CONFIG_DIR/agents $HOME/.claude/agents \
        --ro-bind-try $CLAUDE_CONFIG_DIR/skills $HOME/.claude/skills \
        -- qodercli $argv
end
