function opencode-cn --description 'Run opencode with Chinese AI engines (volcengine)'
    set -lx OPENCODE_CONFIG_DIR ~/.config/opencode-cn
    command opencode $argv
end
