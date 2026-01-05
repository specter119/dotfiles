if test -x /usr/bin/wsl2-ssh-agent
    /usr/bin/wsl2-ssh-agent | source
    systemctl --user import-environment SSH_AUTH_SOCK
end
