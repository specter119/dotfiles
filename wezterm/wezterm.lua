local wezterm = require 'wezterm'
local config = wezterm.config_builder()
local launch_menu = {}

-- Enable Kitty Keyboard Protocol for better key handling (required for zellij Ctrl+Shift bindings)
-- config.enable_kitty_keyboard = true

if wezterm.target_triple == 'x86_64-pc-windows-msvc' then
  table.insert(launch_menu, {
    label = 'PowerShell Core',
    args = { os.getenv 'SCOOP' .. '\\apps\\pwsh\\current\\pwsh.exe', '-NoLogo' },
  })

  table.insert(launch_menu, {
    label = 'Command Prompt',
    args = { 'cmd.exe' },
  })

  table.insert(launch_menu, {
    label = 'Arch Linux (WSL)',
    args = { 'wsl.exe', '--cd', '~', '--distribution', 'archlinux', '--', 'fish', '--login' },
  })

  table.insert(launch_menu, {
    label = 'Arch Linux with zellij (WSL)',
    args = { 'wsl.exe', '--cd', '~', '--distribution', 'archlinux', '--', 'zellij', 'attach', '--create', 'main' },
  })

  config.default_prog =
    { 'wsl.exe', '--cd', '~', '--distribution', 'archlinux', '--', 'zellij', 'attach', '--create', 'main' }

  config.keys = {
    { key = 'v', mods = 'CTRL', action = wezterm.action.Nop },
    { key = 'Enter', mods = 'SHIFT', action = wezterm.action.SendString '\x1b\r' },
  }
elseif wezterm.target_triple == 'x86_64-unknown-linux-gnu' then
  table.insert(launch_menu, {
    label = 'Default Shell',
  })

  table.insert(launch_menu, {
    label = 'Bash',
    args = { 'bash', '-l' },
  })

  table.insert(launch_menu, {
    label = 'zellij',
    args = { 'zellij', 'attach', '--create', 'main' },
  })
end

config.launch_menu = launch_menu

config.font = wezterm.font('Sarasa Term SC Nerd', { weight = 'DemiBold' })
config.font_size = 13.0
config.window_background_opacity = 0.86
config.window_decorations = 'RESIZE'

return config
