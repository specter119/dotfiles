function gemini --description 'Run gemini with bwrap sandboxing'
    set -q GEMINI_CONFIG_DIR; or set GEMINI_CONFIG_DIR $HOME/.config/gemini
    set GEMINI_CONFIG_DIR (string replace '~' $HOME $GEMINI_CONFIG_DIR)

    mkdir -p $GEMINI_CONFIG_DIR

    _bwrap_agentic_cli \
        --bind $GEMINI_CONFIG_DIR $HOME/.gemini \
        -- gemini $argv
end
