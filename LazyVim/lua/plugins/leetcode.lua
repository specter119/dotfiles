local leet_arg = "leetcode.nvim"

local copilot_state = {
  global_enabled = nil,
  was_disabled = nil,
}

local function load_copilot()
  local ok, lazy = pcall(require, "lazy")
  if ok then
    pcall(lazy.load, { plugins = { "copilot.lua" } })
  end
end

local function disable_copilot_for_leetcode()
  copilot_state.global_enabled = vim.g.copilot_enabled

  load_copilot()
  local client = package.loaded["copilot.client"]
  copilot_state.was_disabled = client and client.is_disabled() or vim.g.copilot_enabled == 0

  vim.g.copilot_enabled = 0
  vim.cmd("silent! Copilot disable")
end

local function restore_copilot_after_leetcode()
  vim.g.copilot_enabled = copilot_state.global_enabled

  if copilot_state.was_disabled == false then
    load_copilot()
    vim.cmd("silent! Copilot enable")
  end
end

return {
  {
    "kawre/leetcode.nvim",
    cmd = "Leet",
    lazy = leet_arg ~= vim.fn.argv(0, -1),
    build = function()
      pcall(vim.cmd, "TSUpdateSync html")
    end,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
    },
    keys = {
      { "<leader>L", "<cmd>Leet<cr>", desc = "LeetCode" },
      { "<leader>Ll", "<cmd>Leet list<cr>", desc = "List Problems" },
      { "<leader>Ld", "<cmd>Leet daily<cr>", desc = "Daily Problem" },
      { "<leader>Lr", "<cmd>Leet random<cr>", desc = "Random Problem" },
      { "<leader>Lt", "<cmd>Leet test<cr>", desc = "Run Tests" },
      { "<leader>Ls", "<cmd>Leet submit<cr>", desc = "Submit" },
      { "<leader>Li", "<cmd>Leet info<cr>", desc = "Problem Info" },
      { "<leader>Lc", "<cmd>Leet console<cr>", desc = "Console" },
      { "<leader>Lo", "<cmd>Leet open<cr>", desc = "Open in Browser" },
      { "<leader>Ly", "<cmd>Leet yank<cr>", desc = "Yank Code" },
      { "<leader>La", "<cmd>Leet lang<cr>", desc = "Change Language" },
      { "<leader>LR", "<cmd>Leet reset<cr>", desc = "Reset Code" },
      { "<leader>Lq", "<cmd>Leet exit<cr>", desc = "Exit LeetCode" },
    },
    opts = {
      arg = leet_arg,
      lang = "python3",
      cn = {
        enabled = true,
        translator = true,
        translate_problems = true,
      },
      picker = { provider = "snacks-picker" },
      plugins = {
        non_standalone = true,
      },
      hooks = {
        enter = { disable_copilot_for_leetcode },
        leave = { restore_copilot_after_leetcode },
      },
    },
  },
}
