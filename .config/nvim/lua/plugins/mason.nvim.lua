return {
    "mason-org/mason.nvim",
    dependencies = { "Zeioth/mason-extra-cmds", opts = {} },
    cmd = {
        "Mason",
        "MasonInstall",
        "MasonUninstall",
        "MasonUninstallAll",
        "MasonLog",
        "MasonUpdate",
        "MasonUpdateAll", -- this cmd is provided by mason-extra-cmds
    },
    opts = {},
}

