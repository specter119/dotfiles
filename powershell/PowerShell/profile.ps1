Remove-Item -Path Alias:ls
Remove-Item -Path Alias:cat

# psfzf
Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
$env:FZF_DEFAULT_COMMAND = '$env:SCOOP\apps\fd\current\fd --type file --color=always'
$env:FZF_DEFAULT_OPTS = '--ansi'
$env:FZF_CTRL_T_OPTS = @"
    --walker-skip .git,node_modules,target
    --preview 'bat -n --color=always {}'
    --bind 'ctrl-/:change-preview-window(down|hidden|)'
"@

$env:FZF_CTRL_R_OPTS = @"
    --bind 'ctrl-y:execute-silent(echo -n {2..} | clip)+abort'
    --color header:italic
    --header 'Press CTRL-Y to copy command into clipboard'
"@
Import-Module PSFzf
Set-PSReadLineKeyHandler -Key Tab -ScriptBlock { Invoke-FzfTabCompletion }
Set-PSFzfOption -EnableFd -EnableAliasFuzzyKillProcess -EnableAliasFuzzyEdit -EnableAliasFuzzyScoop

# zoxide
Invoke-Expression (& { (zoxide init powershell | Out-String) })

# shovel
Import-Module "$env:SCOOP\apps\scoop\current\supporting\completion\Scoop-Completion.psd1" -ErrorAction SilentlyContinue

#region mamba initialize
# !! Contents within this block are managed by 'mamba shell init' !!
# $env:MAMBA_ROOT_PREFIX = "$env:UserProfile\.local\share\mamba"
# $env:MAMBA_EXE = "$env:SCOOP\apps\micromamba\current\micromamba.exe"
(& $env:MAMBA_EXE 'shell' 'hook' --shell 'powershell' --root-prefix $env:MAMBA_ROOT_PREFIX) | Out-String | Invoke-Expression
#endregion
New-Alias umamba Invoke-Mamba
New-Alias conda Invoke-Mamba

# alias
New-Alias open explorer
New-Alias cat bat
function ls { eza --group-directories-first @args }
function l { ls --icons @args }
function ll { l --long --time-style=long-iso @args }
function la { ll --all @args }
function tree { ls --tree @args }
