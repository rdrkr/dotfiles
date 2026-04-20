-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
--
vim.opt.wrap = false
vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.undofile = true
vim.opt.undodir = vim.fn.expand("~/.undodir")
local uname = vim.loop.os_uname()
vim.g.codeium_os = uname.sysname   -- "Darwin", "Linux", or "Windows_NT"
vim.g.codeium_arch = uname.machine  -- "arm64", "x86_64", etc.
vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"

vim.opt.spell = true
vim.opt.spelllang = "en"
vim.opt.spellfile = vim.fn.expand("~/.config/nvim/spell/en.utf-8.add")
