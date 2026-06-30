-- Project-local nvim config for the dotfiles repo.
--
-- Disable LazyVim autoformat for buffers that are NOT valid JSON/JSONC/TOML.
-- Dotter/Handlebars templates break structural syntax ({{ }} in keys, array
-- positions, etc.), so a formatter would corrupt them. Valid files — including
-- templates whose {{ }} live inside string literals — stay formatted.
--
-- `vim.b.autoformat = false` is the LazyVim buffer-local format switch.
-- Loaded via exrc; requires `vim.o.exrc = true` (set in lua/config/options.lua).

local function buf_text(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

-- Strip // line and /* block */ comments that are outside strings, so JSONC
-- can be validated by nvim's strict json decoder.
local function strip_jsonc_comments(text)
  local out, i, n = {}, 1, #text
  local in_str, in_line, in_block = false, false, false
  while i <= n do
    local c = text:sub(i, i)
    local nxt = text:sub(i + 1, i + 1)
    if in_block then
      if c == "*" and nxt == "/" then i = i + 2; in_block = false else i = i + 1 end
    elseif in_line then
      if c == "\n" then in_line = false; out[#out + 1] = c end
      i = i + 1
    elseif in_str then
      out[#out + 1] = c
      if c == "\\" and nxt ~= "" then out[#out + 1] = nxt; i = i + 2
      elseif c == "\"" then in_str = false; i = i + 1
      else i = i + 1 end
    else
      if c == "\"" then in_str = true; out[#out + 1] = c; i = i + 1
      elseif c == "/" and nxt == "/" then i = i + 2; in_line = true
      elseif c == "/" and nxt == "*" then i = i + 2; in_block = true
      else out[#out + 1] = c; i = i + 1 end
    end
  end
  return table.concat(out)
end

local validators = {
  json = function(text)
    return pcall(vim.json.decode, text)
  end,
  jsonc = function(text)
    return pcall(vim.json.decode, strip_jsonc_comments(text))
  end,
  toml = function(text)
    if not vim.fn.executable("python3") then
      return true -- can't validate; assume valid so we don't disable
    end
    vim.fn.system(
      { "python3", "-c", "import tomllib,sys; tomllib.loads(sys.stdin.read())" },
      text
    )
    return vim.v.shell_error == 0
  end,
}

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("dotfiles_invalid_noformat", { clear = true }),
  pattern = { "json", "jsonc", "toml" },
  callback = function(args)
    local text = buf_text(args.buf)
    -- empty/new buffer: leave autoformat on
    if text == "" or not text:find("%S") then
      return
    end
    local validate = validators[vim.bo[args.buf].filetype]
    if validate and not validate(text) then
      vim.b[args.buf].autoformat = false
    end
  end,
})
