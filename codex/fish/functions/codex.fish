function codex --description 'Run codex with bwrap sandboxing'
    set -q CODEX_HOME; or set CODEX_HOME $HOME/.config/codex
    set CODEX_HOME (string replace '~' $HOME $CODEX_HOME)

    mkdir -p $CODEX_HOME

    _bwrap_agentic_cli \
        --bind $CODEX_HOME $HOME/.codex \
        -- codex $argv
end
