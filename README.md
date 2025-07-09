# ✨ Dotfiles

![Last Commit](https://img.shields.io/github/last-commit/ronendruker/dotfiles?style=for-the-badge&logo=github&color=cba6f7&logoColor=cba6f7)
![License](https://img.shields.io/github/license/ronendruker/dotfiles?style=for-the-badge&logo=gitbook&color=a6e3a1&logoColor=a6e3a1)

My personal dotfiles, managed with `stow` and a custom installer script.

## 🚀 Installation

1.  **Install Homebrew and Git:**

    ```bash
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" && brew install git
    ```

2.  **Clone the repository:**

    ```bash
    git clone https://github.com/ronendruker/dotfiles.git ~/.dotfiles
    ```

3.  **Navigate to the repository:**

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

##  license

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.