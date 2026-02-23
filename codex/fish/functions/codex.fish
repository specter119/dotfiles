function codex --description 'Run codex with bwrap sandboxing'
    set -q CODEX_CONFIG; or set CODEX_CONFIG $HOME/.config/codex
    set CODEX_CONFIG (string replace '~' $HOME $CODEX_CONFIG)

    mkdir -p $CODEX_CONFIG

    _bwrap_agentic_cli \
        --bind $CODEX_CONFIG $HOME/.codex \
        -- codex $argv
end
