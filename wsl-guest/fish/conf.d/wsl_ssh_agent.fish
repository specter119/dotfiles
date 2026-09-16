if type -q wsl2-ssh-agent
    wsl2-ssh-agent | source
    systemctl --user import-environment SSH_AUTH_SOCK
end
