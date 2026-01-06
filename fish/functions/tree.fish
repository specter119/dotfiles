#!/usr/bin/env fish
function tree --description 'Display directories as trees with modern eza'
    if type -q eza
        eza -T $argv
    else
        command tree $argv
    end
end
