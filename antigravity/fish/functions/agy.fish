function agy --description 'Run agy with bwrap sandboxing'
    set -q ANTIGRAVITY_CLI_HOME; or set ANTIGRAVITY_CLI_HOME $HOME/.config/antigravity
    set ANTIGRAVITY_CLI_HOME (string replace -r '^~/' "$HOME/" $ANTIGRAVITY_CLI_HOME)
    set ANTIGRAVITY_CLI_HOME (string replace -r '^~$' $HOME $ANTIGRAVITY_CLI_HOME)

    mkdir -p $ANTIGRAVITY_CLI_HOME

    _bwrap_agentic_cli \
        --bind $ANTIGRAVITY_CLI_HOME $HOME/.gemini/antigravity-cli \
        -- agy $argv
end
