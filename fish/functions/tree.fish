#!/usr/bin/env fish
function tree --description 'Display directories as trees with morden exa'
    if type -q exa
        exa -T $argv
    else
        command tree $argv
    end
end
