# WSL login shells bypass pam_systemd, so import the session environment once for
# login shells and the first zellij layer. Child shells inherit the result;
# rerunning would prepend environment.d entries to PATH again on every layer.
if status is-login; or set -q ZELLIJ
    if not set -q __session_env_sourced
        set -gx __session_env_sourced 1

        bash -c 'test -e /etc/profile && source /etc/profile; env -0' | while read --null env_line
            set -l parts (string split --max 1 = -- $env_line)
            set -l name $parts[1]
            set -l value $parts[2]

            switch $name
                case "" PWD OLDPWD SHLVL _ __session_env_sourced
                    continue
            end

            if string match --quiet --regex '^[A-Za-z_][A-Za-z0-9_]*$' -- $name
                set -gx $name $value
            end
        end

        export ( /usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator )
    end
end
