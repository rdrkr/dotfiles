-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.api.nvim_set_keymap("i", "jj", "<Esc>", { noremap = false })
vim.api.nvim_set_keymap("i", "jk", "<Esc>", { noremap = false })

-- Switch buffers with Alt+Tab and Alt+Shift+Tab
vim.keymap.set("n", "<M-Tab>", "<cmd>BufferLineCycleNext<cr>", { desc = "Next Buffer" })
vim.keymap.set("n", "<M-S-Tab>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Previous Buffer" })
vim.keymap.set("n", "<A-S-Tab>", "<cmd>BufferLineCyclePrev<cr>", { desc = "Previous Buffer" })

-- Override Alt+f and Alt-Right to jump word forward in both normal and insert modes
vim.keymap.set({ "n", "i" }, "<M-f>", function()
    if vim.fn.mode() == "i" then
        return "<C-o>w"
    else
        return "w"
    end
end, { expr = true, desc = "Jump word forward" })

-- Close current buffer with Alt+w
vim.keymap.set({ "n", "i", "v" }, "<M-w>", function()
    Snacks.bufdelete()
end, { desc = "Close Buffer" })
