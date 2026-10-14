# Stylus

User styles for the [Stylus](https://github.com/openstyles/stylus) browser extension.

## Gruvbox Material Dark (Medium) - Global Default

[`gruvbox-material-dark-medium.user.css`](./gruvbox-material-dark-medium.user.css) is a catch-all dark theme in the
[gruvbox-material](https://github.com/sainnhe/gruvbox-material) dark/medium palette (the same colors as the superfile
and yazi themes). It applies to every website except the domains in its exclusion list, so sites without a dedicated
style still get a consistent look.

### Install

Open the raw file in a browser with Stylus installed and click **Install style**:

<https://raw.githubusercontent.com/rdrkr/dotfiles/main/.config/stylus/gruvbox-material-dark-medium.user.css>

The style carries an `@updateURL`, so Stylus picks up changes pushed to `main` when it checks for updates.

### Excluding sites

Stylus applies every matching style, so a site with its own style (or one that should stay untouched) has to be
excluded from the global one. Add its domain to the alternation in the `@-moz-document regexp(...)` line at the top of
the file. Domains are regular expressions inside a CSS string, so escape dots with a double backslash and separate
entries with `|`; subdomains of a listed domain are excluded too:

```css
@-moz-document regexp("^(?!https?://(?:[^/]+\\.)?(?:github\\.com|mail\\.google\\.com)(?:[:/?#]|$)).*$") {
```

For a one-off exclusion without editing the file, use **Excluded** in the style's settings in the Stylus manager.
