# rclone

Operational notes for the machine-local Zotero sync job. The job lives in the
`rclone` Dotter package: `config/` maps to `~/.config/rclone`, `bin/` maps to
`~/.local/bin`, and `systemd/user/` maps to `~/.config/systemd/user`. The remote
path lives in `local.toml`.

## Zotero storage

`rclone-zotero-sync` runs `rclone bisync` between
`~/Documents/Zotero/storage` and `dropbox:<zotero_remote>`. The remote path is
read from `[variables.rclone.dropbox].zotero_remote` in `local.toml` and passed
by the unit, so it is never tracked.

- `rclone-bisync-zotero.timer` runs the sync daily as a backstop.
- `rclone-watch-zotero.service` watches the local tree with `inotifywait`,
  debounces for 15 seconds, and triggers the same script. It restarts every 30
  minutes so newly created Zotero storage directories are picked up.
- Both paths share `$XDG_RUNTIME_DIR/rclone-bisync-zotero.lock`, so only one
  bisync runs at a time.

Enable both units on a machine that should sync:

```sh
systemctl --user enable --now rclone-bisync-zotero.timer rclone-watch-zotero.service
```

## Cold start

The first sync must be a single-threaded full copy, not `bisync --resync`.
Dropbox throttles concurrent downloads; one stream both runs faster and resumes
cleanly. Seed the local tree first, then let bisync record the baseline:

```sh
rclone copy "dropbox:$REMOTE" ~/Documents/Zotero/storage \
  --transfers 1 --checkers 4 --create-empty-src-dirs \
  --retries 100000 --retries-sleep 30s --low-level-retries 50 \
  --stats 60s -v

rclone bisync ~/Documents/Zotero/storage "dropbox:$REMOTE" --resync --resilient
```

Interrupting the copy is safe: rerunning it skips files that already exist.
`--resync` only records the baseline once both sides match.

## Dependencies

- `rclone` on `PATH`
- `inotifywait` from `inotify-tools` on `PATH`
- `flock` from util-linux on `PATH`
