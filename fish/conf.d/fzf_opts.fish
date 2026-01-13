if status is-interactive
    set -gx FZF_DEFAULT_COMMAND 'fd --type file --color=always --hidden --exclude .git'
    set -gx FZF_DEFAULT_OPTS '--ansi --height 40% --reverse'

    set -gx FZF_CTRL_T_COMMAND 'fd --type file --hidden --exclude .git'
    set -gx FZF_CTRL_T_OPTS "--preview 'bat -n --color=always {}' --bind 'ctrl-/:toggle-preview'"

    set -gx FZF_ALT_C_COMMAND 'fd --type directory --hidden --exclude .git'
    set -gx FZF_ALT_C_OPTS "--preview 'eza --tree --level=2 --color=always {}'"
end
