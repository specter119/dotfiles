if status is-interactive && not set -q ZELLIJ_SESSION_NAME
    # Only initialize atuin outside of zellij to avoid defunct processes
    ATUIN_NOBIND='true' atuin init fish | source
end
