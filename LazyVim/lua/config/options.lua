-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local function is_dotter_template(buf)
	if vim.bo[buf].buftype ~= "" then
		return false
	end
	local handlebars_open = "{" .. "{"

	-- Dotter templates are identified by the repository marker and raw
	-- Handlebars syntax. Keep this in the trusted editor config so opening a
	-- project does not require executing a project-local config file.
	if not vim.fs.root(buf, ".dotter") then
		return false
	end

	for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		if line:find(handlebars_open, 1, true) then
			return true
		end
	end
	return false
end

local dotter_template_group = vim.api.nvim_create_augroup("dotter_template_noformat", { clear = true })
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWritePre" }, {
	group = dotter_template_group,
	callback = function(args)
		if is_dotter_template(args.buf) then
			vim.b[args.buf].autoformat = false
		end
	end,
})
