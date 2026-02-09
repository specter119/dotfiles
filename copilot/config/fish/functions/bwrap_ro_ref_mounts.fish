#!/usr/bin/env fish
function bwrap_ro_ref_mounts --description 'Print bwrap ro-bind args for reference directories, excluding pwd conflicts'
    # Usage: set ro_mounts (bwrap_ro_ref_mounts)
    # Environment: BWRAP_AGENTIC_RO_DIRS - colon-separated list of directories to mount read-only
    #
    # Conflict resolution (ro_ref_mounts should be placed BEFORE pwd's rw mount):
    #   - If pwd == ro_dir: skip (pwd's rw mount will take effect)
    #   - If pwd is under ro_dir: add ro mount (pwd's rw mount will override the pwd portion)
    #   - If ro_dir is under pwd: skip (pwd is rw, so ro_dir should also be rw)

    set -q BWRAP_AGENTIC_RO_DIRS; or return

    set -l pwd_real (realpath (pwd) 2>/dev/null); or set pwd_real (pwd)
    set -l ro_mounts

    for ro_dir in (string split ':' -- $BWRAP_AGENTIC_RO_DIRS)
        # Skip empty entries
        test -z "$ro_dir"; and continue

        # Expand ~ and resolve to absolute path
        set ro_dir (string replace '~' $HOME -- $ro_dir)
        test -d "$ro_dir"; or continue
        set -l ro_real (realpath $ro_dir 2>/dev/null); or continue

        # Skip if pwd == ro_dir (pwd's rw mount will take effect)
        if test "$pwd_real" = "$ro_real"
            continue
        end

        # Skip if ro_dir is under pwd (pwd is rw, so ro_dir should also be rw)
        if string match -q "$pwd_real/*" "$ro_real"
            continue
        end

        # Add ro-bind mount (including when pwd is under ro_dir)
        set -a ro_mounts --ro-bind $ro_real $ro_real
    end

    if test (count $ro_mounts) -gt 0
        printf "%s\n" $ro_mounts
    end
end
