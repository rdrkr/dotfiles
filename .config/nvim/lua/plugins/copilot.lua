return {
    "zbirenbaum/copilot.lua",
    opts = {
        suggestion = {
            enabled = true,
            auto_trigger = true,
            keymap = {
                accept = false, -- handled by nvim-cmp / blink.cmp
                next = "<M-]>",
                prev = "<M-[>",
            },
        },
        panel = { enabled = false },
        filetypes = {
            markdown = true,
            help = true,
        },
    },
}
