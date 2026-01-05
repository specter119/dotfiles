#!/usr/bin/env fish
function rm --description 'alias rm as trash'
    if type -q trash
        command trash $argv
    else
        command rm $argv
    end
end
