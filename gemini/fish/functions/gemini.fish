function gemini --description 'Run gemini with bwrap sandboxing'
    set -q GEMINI_CLI_HOME; or set GEMINI_CLI_HOME $HOME/.config/gemini
    set GEMINI_CLI_HOME (string replace '~' $HOME $GEMINI_CLI_HOME)

    mkdir -p $GEMINI_CLI_HOME

    _bwrap_agentic_cli \
        --bind $GEMINI_CLI_HOME $HOME/.gemini \
        -- gemini $argv
end
