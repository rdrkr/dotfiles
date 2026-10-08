-- Plugin: mikavilpas/yazi.nvim
-- Installed via store.nvim

return {
    "mikavilpas/yazi.nvim",
    version = "*", -- use the latest stable version
    event = "VeryLazy",
    dependencies = {
        {
            "nvim-lua/plenary.nvim",
            lazy = true
        }
    },
    keys = {
        -- 👇 in this section, choose your own keymappings!
        {
            "<leader>-",
            mode = {"n", "v"},
            "<cmd>Yazi<cr>",
            desc = "Open yazi at the current file"
        },
        {
            -- Open in the current working directory
            "<leader>cw",
            "<cmd>Yazi cwd<cr>",
            desc = "Open the file manager in nvim's working directory"
        },
        {
            "<c-up>",
            "<cmd>Yazi toggle<cr>",
            desc = "Resume the last yazi session"
        }
    },
    ---@type YaziConfig | {}
    opts = {
        -- if you want to open yazi instead of netrw, see below for more info
        open_for_directories = false,
        keymaps = {
            show_help = "<f1>"
        }
    },
    ---Runs at startup, before the plugin loads: disables netrw and, inside
    ---psmux on Windows, hides WT_SESSION from the yazi this plugin spawns.
    init = function()
        -- 👇 if you use `open_for_directories=true`, this is recommended
        -- mark netrw as loaded so it's not loaded at all.
        --
        -- More details: https://github.com/mikavilpas/yazi.nvim/issues/802
        vim.g.loaded_netrwPlugin =
            1

        -- yazi reads WT_SESSION as "Windows Terminal" and sends sixel, but a
        -- psmux pane is hosted by the inbox conhost, which strips sixel
        -- (psmux#431), so image previews come out blank. Without it yazi falls
        -- back to chafa block art. yazi.nvim's jobstart can only add variables,
        -- not remove them, so it is cleared for nvim as a whole: nothing nvim
        -- starts inside a psmux pane talks to Windows Terminal directly anyway.
        -- The PowerShell twin of this is the `yazi` function in profile.ps1.
        if vim.fn.has("win32") == 1 and vim.env.TMUX then
            vim.env.WT_SESSION = nil
        end
    end
}