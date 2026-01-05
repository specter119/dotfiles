if status is-interactive
	string match -q "$TERM_PROGRAM" "vscode"; and . (/opt/visual-studio-code-insiders/bin/code-insiders --locate-shell-integration-path fish)
end
