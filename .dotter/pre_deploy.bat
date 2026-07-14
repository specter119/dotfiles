@echo off

REM Sync runtime-managed Windows config into local.toml before templates render.
call uv run .dotter\scripts\live_config_reverse_sync.py
exit /b %errorlevel%
