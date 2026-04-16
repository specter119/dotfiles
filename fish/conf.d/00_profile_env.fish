# Import /etc/profile environment once for login shells and the first zellij layer.
if status is-login; or set -q ZELLIJ
    if not set -q __profile_sourced
        set -gx __profile_sourced 1

        bash -c 'test -e /etc/profile && source /etc/profile; env -0' | while read --null env_line
            set -l parts (string split --max 1 = -- $env_line)
            set -l name $parts[1]
            set -l value $parts[2]

            switch $name
                case "" PWD OLDPWD SHLVL _ __profile_sourced
                    continue
            end

            if string match --quiet --regex '^[A-Za-z_][A-Za-z0-9_]*$' -- $name
                set -gx $name $value
            end
        end
    end
end
