function claude --description 'Run claude code with bwrap sandboxing and adapted home directory'
    # XDG Base Directory Specification:
    #   - $CLAUDE_CONFIG_DIR (`~/.config/claude`): config (settings, CLAUDE.md, commands, agents, skills)
    #   - $CLAUDE_SHARE (`~/.local/share/claude`): state (.claude.json, projects, etc.)
    #
    # Inside bwrap, $CLAUDE_SHARE is mounted as ~/.claude (Claude Code's default),
    # with config files from the host's $CLAUDE_CONFIG_DIR overlaid on top.

    set -q CLAUDE_CONFIG_DIR; or set CLAUDE_CONFIG_DIR $HOME/.config/claude
    set CLAUDE_CONFIG_DIR (string replace '~' $HOME $CLAUDE_CONFIG_DIR)
    set -l CLAUDE_SHARE $HOME/.local/share/claude

    # Ensure state directory and .claude.json files exist
    mkdir -p $CLAUDE_SHARE
    for config_file in .claude.json .claude.json.backup
        test -f ~/$config_file; and mv ~/$config_file $CLAUDE_SHARE/
        test -f $CLAUDE_SHARE/$config_file; or echo '{}' >$CLAUDE_SHARE/$config_file
    end

    _bwrap_agentic_cli \
        --bind $CLAUDE_SHARE/.claude.json $HOME/.claude.json \
        --bind $CLAUDE_SHARE/.claude.json.backup $HOME/.claude.json.backup \
        --bind $CLAUDE_SHARE $HOME/.claude \
        --bind $CLAUDE_CONFIG_DIR/settings.json $HOME/.claude/settings.json \
        --bind-try $CLAUDE_CONFIG_DIR/CLAUDE.md $HOME/.claude/CLAUDE.md \
        --bind-try $CLAUDE_CONFIG_DIR/commands $HOME/.claude/commands \
        --bind-try $CLAUDE_CONFIG_DIR/agents $HOME/.claude/agents \
        --bind-try $CLAUDE_CONFIG_DIR/skills $HOME/.claude/skills \
        --bind-try $HOME/.config/gemini $HOME/.gemini \
        -- claude $argv
end
