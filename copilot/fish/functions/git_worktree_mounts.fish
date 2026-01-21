function git_worktree_mounts --description 'Print bwrap mount args for git worktrees'
    set -l worktree_mounts
    if git rev-parse --is-inside-work-tree &>/dev/null
        set -l git_common_dir (git rev-parse --git-common-dir 2>/dev/null)
        set -l git_dir (git rev-parse --git-dir 2>/dev/null)
        if test "$git_common_dir" != "$git_dir"
            set -l main_repo (dirname (realpath $git_common_dir))
            if test -d "$main_repo"
                set worktree_mounts --bind $main_repo $main_repo
            end
        end
    end

    if test (count $worktree_mounts) -gt 0
        printf "%s\n" $worktree_mounts
    end
end
