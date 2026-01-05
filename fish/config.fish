# source /etc/profile with bash - handle both login and zellij first layer
if status is-login; or set -q ZELLIJ
    if not set -q __profile_sourced
        set -gx __profile_sourced 1
        exec bash -c "\
            test -e /etc/profile && source /etc/profile
            test -e $HOME/.bash_profile && source $HOME/.bash_profile
            exec fish --login
        "
    end
end

# Main fish configuration file
if status is-interactive
end
