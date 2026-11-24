# See scoop.fish: the extensionless shim is a `#!/bin/sh` script that fish 4 cannot
# resolve through the wsl.exe-appended Windows $PATH.
function shovel --description 'Shovel (Windows) shim'
    $WSL_SCOOP_PATH/shims/shovel $argv
end
