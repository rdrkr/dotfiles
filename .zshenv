# .zshenv - read by every zsh, before /etc/zsh/zshrc and ~/.zshrc

# Ubuntu (including WSL) runs `compinit` from /etc/zsh/zshrc unless this is
# set. ~/.zshrc runs its own compinit anyway, so the global one only costs
# time - and because the two see different fpaths, each used to invalidate the
# other's dump, which forced a full completion rebuild in every new shell.
skip_global_compinit=1
