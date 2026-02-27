function claude --description 'Run claude code with bwrap sandboxing and adapted home directory'
    # All Claude Code data (config + state) lives under $CLAUDE_CONFIG_DIR,
    # mounted as ~/.claude (Claude Code's default) inside bwrap.

    set -q CLAUDE_CONFIG_DIR; or set CLAUDE_CONFIG_DIR $HOME/.config/claude
    set CLAUDE_CONFIG_DIR (string replace '~' $HOME $CLAUDE_CONFIG_DIR)

    # Ensure directory and .claude.json files exist
    mkdir -p $CLAUDE_CONFIG_DIR
    for config_file in .claude.json .claude.json.backup
        test -f ~/$config_file; and mv ~/$config_file $CLAUDE_CONFIG_DIR/
        test -f $CLAUDE_CONFIG_DIR/$config_file; or echo '{}' >$CLAUDE_CONFIG_DIR/$config_file
    end

    _bwrap_agentic_cli \
        --bind $CLAUDE_CONFIG_DIR/.claude.json $HOME/.claude.json \
        --bind $CLAUDE_CONFIG_DIR/.claude.json.backup $HOME/.claude.json.backup \
        --bind $CLAUDE_CONFIG_DIR $HOME/.claude \
        --bind-try $HOME/.config/gemini $HOME/.gemini \
        -- claude $argv
end
