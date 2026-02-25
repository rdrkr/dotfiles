-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
--
vim.opt.wrap = false
vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.undofile = true
vim.opt.undodir = vim.fn.expand("~/.undodir")
vim.g.codeium_os = "Darwin"
vim.g.codeium_arch = "arm64"
vim.o.sessionoptions = "blank,buffers,curdir,folds,help,tabpages,winsize,winpos,terminal,localoptions"
