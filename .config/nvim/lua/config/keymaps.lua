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

-- package-info.nvim keymaps
vim.keymap.set({ "n" }, "<LEADER>ns", require("package-info").show, { silent = true, noremap = true })
vim.keymap.set({ "n" }, "<LEADER>nc", require("package-info").hide, { silent = true, noremap = true })
vim.keymap.set({ "n" }, "<LEADER>nt", require("package-info").toggle, { silent = true, noremap = true })
vim.keymap.set({ "n" }, "<LEADER>nu", require("package-info").update, { silent = true, noremap = true })
vim.keymap.set({ "n" }, "<LEADER>nd", require("package-info").delete, { silent = true, noremap = true })
vim.keymap.set({ "n" }, "<LEADER>ni", require("package-info").install, { silent = true, noremap = true })
vim.keymap.set({ "n" }, "<LEADER>np", require("package-info").change_version, { silent = true, noremap = true })

-- py-requirements.nvim keymaps
vim.keymap.set("n", "<leader>ns", require("py-requirements").show_description, {})
vim.keymap.set("n", "<leader>nu", require("py-requirements").upgrade, {})
vim.keymap.set("n", "<leader>nU", require("py-requirements").upgrade_all, {})
