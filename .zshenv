# .zshenv - read by every zsh, before /etc/zsh/zshrc and ~/.zshrc

# Ubuntu (including WSL) runs `compinit` from /etc/zsh/zshrc unless this is
# set. ~/.zshrc runs its own compinit anyway, so the global one only costs
# time - and because the two see different fpaths, each used to invalidate the
# other's dump, which forced a full completion rebuild in every new shell.
skip_global_compinit=1

# XDG config root. Set here rather than in ~/.zshrc so non-interactive shells
# get it too: Rootshell (and any `ssh host cmd`) starts tmux without reading
# ~/.zshrc, and tmux.conf builds every plugin path from this variable - left
# unset, the tmux server loads no plugins or theme.
export XDG_CONFIG_HOME="${HOME}/.config"
