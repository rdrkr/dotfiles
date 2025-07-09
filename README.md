# ✨ Dotfiles

My personal dotfiles, managed with `stow` and a custom installer script.

## 🚀 Installation

1. Install XCode Command Line Tools:

   ```bash
   xcode-select --install
   ```

   If you encounter an error, you can also try:

   ```bash
   sudo xcode-select --reset
   ```

   This step is necessary to ensure that the required build tools are available.

2. **Install Homebrew and Git:**

   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && brew install git
   ```

3. **Clone the repository:**

   ```bash
   git clone https://github.com/rdrkr/dotfiles.git ~/.dotfiles
   ```

4. **Navigate to the repository:**

   ```bash
   cd ~/.dotfiles
   ```

## 🛠️ Usage

This repository includes a custom `install.sh` script to manage the setup.

### Restore

To restore the dotfiles and install all the dependencies from the `Brewfile`, run the following command:

```bash
./install.sh restore
```

### Backup

To update the `Brewfile` with your current setup and automatically commit and push the changes, run:

```bash
./install.sh backup
```

### Schedule

To schedule hourly backups of your `Brewfile` using cron, run:

```bash
./install.sh schedule
```

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
