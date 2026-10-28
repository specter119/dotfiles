local wezterm = require 'wezterm'
local config = wezterm.config_builder()
local launch_menu = {}

-- Kitty Keyboard Protocol: good for key handling, but bad for display
-- config.enable_kitty_keyboard = true

if wezterm.target_triple == 'x86_64-pc-windows-msvc' then
  config.default_domain = 'WSL:DebianWSL'
  -- zellij/herdr come from the Nix profile, which is not on the PATH of a bare WSL
  -- command, so launch them (and everything they spawn) via a login fish shell
  -- TODO: add login shell support to wezterm
  config.default_gui_startup_args = { 'start', '--', 'fish', '-lc', 'exec zellij attach --create main' }
  config.wsl_domains = {
    { name = 'WSL:DebianWSL', distribution = 'DebianWSL', default_prog = { 'fish', '-lc', 'exec zellij' } },
  }
  table.insert(launch_menu, { label = 'Zellij', args = { 'fish', '-lc', 'exec zellij' } })
  table.insert(launch_menu, { label = 'Herdr', args = { 'fish', '-lc', 'exec herdr' } })
  table.insert(launch_menu, {
    label = 'PowerShell Core',
    domain = { DomainName = 'local' },
    args = { os.getenv 'SCOOP' .. '\\apps\\pwsh\\current\\pwsh.exe', '-NoLogo' },
  })
  table.insert(launch_menu, {
    label = 'Command Prompt',
    domain = { DomainName = 'local' },
    args = { 'cmd.exe' },
  })
  config.keys = {
    -- Nop would swallow Ctrl+V; agent TUIs read the clipboard image themselves on ^V
    { key = 'v', mods = 'CTRL', action = wezterm.action.DisableDefaultAssignment },
    { key = 'Enter', mods = 'SHIFT', action = wezterm.action.SendString '\x1b\r' },
  }
elseif wezterm.target_triple == 'x86_64-unknown-linux-gnu' then
  config.default_prog = { 'zellij' }
  table.insert(launch_menu, { label = 'Bash', args = { 'bash', '-l' } })
  table.insert(launch_menu, { label = 'Zellij', args = { 'zellij' } })
end

config.launch_menu = launch_menu

config.term = 'wezterm'
-- TODO: term = 'wezterm' breaks ssh to hosts without wezterm terminfo, solve it later.
config.font = wezterm.font('Sarasa Term SC Nerd', { weight = 'DemiBold' })
config.font_size = 13.0
config.window_background_opacity = 0.86
config.window_decorations = 'RESIZE'

return config
