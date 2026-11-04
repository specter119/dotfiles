# fish 4 skips the Windows $PATH that wsl.exe appends when resolving Linux
# executables, and Scoop's extensionless shim is a `#!/bin/sh` script.
function scoop --description 'Scoop (Windows) shim'
    $WSL_WIN_HOME/scoop/shims/scoop $argv
end
