#!/usr/bin/env fish
function code --wraps=code-insiders --description 'alias code-insiders as code'
    if type -q code-insiders
        code-insiders $argv
    else
        command code $argv
    end
end
