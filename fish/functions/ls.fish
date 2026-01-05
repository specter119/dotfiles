#!/usr/bin/env fish
function ls --description 'List contents of directory by mordern command if exists'
    if type -q eza
        eza --time-style=long-iso $argv
    else if type -q lsd
        lsd $argv
    else
        command ls --color=auto $argv
    end
end
