#!/usr/bin/env fish
function cat --description 'Display file contents with modern bat if available'
    if type -q bat
        command bat $argv
    else
        command cat $argv
    end
end
