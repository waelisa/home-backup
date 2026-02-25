# 🏠 Home Folder Backup Utility

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-1.1.4-blue.svg)](#)
[![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25.svg)](https://www.gnu.org/software/bash/)

A bulletproof, modular backup tool for Linux home folders. Built to provide the efficiency of Time Machine snapshots with the technical rigor of Bit Rot protection.

🚀 Key Features

    True Incremental Backups: Uses rsync with --link-dest to create "snapshots." Files that haven't changed are hard-linked to the previous backup, consuming zero extra disk space.

    Bit Rot Protection: Includes a Verification Mode (--verify) that uses checksums to detect silent data corruption on aging hardware.

    Modular Architecture: Logic is split into .functions (core engine) and .modules (advanced features like GPG encryption and Network mounting).

    Universal Path Detection: Works seamlessly on local disks, USB drives, or network mounts with built-in mount-sensing safety.

    Atomic Symlinks: The latest pointer is only updated if the backup is 100% successful.

    Smart Exclusions: Automatically detects and excludes cache, trash, and temporary files from common software (Chrome, VS Code, Steam, etc.).

🛠️ Installation & Setup

    Clone the repository:
```bash
    git clone https://github.com/waelisa/home-backup.git
    cd home-backup
```
    Make the script executable:
```bash
    chmod +x home-backup.sh
```

📖 Usage
Interactive Mode (TUI)

Simply run the script to access the beautiful gum-powered menu:
```bash
./home-backup.sh
```
CLI Arguments
```bash
    Standard Backup: ./home-backup.sh --backup

    Verify Mode (Checksums): ./home-backup.sh --verify

    Dry Run: ./home-backup.sh --dry-run

    Restore: ./home-backup.sh --restore
```

🛡️ The 3-2-1 Strategy

This utility is designed to help you achieve a professional backup standard:

    3 Copies: Your original data + 2 historical snapshots (adjustable via MAX_BACKUPS).

    2 Media: Support for local SSD/HDD and external USB drives.

    1 Off-site: Prepped for cloud/offsite storage via the Encryption Module (GPG).

🏗️ Project Structure

    home-backup.sh: Main entry point and CLI/TUI handler.

    home-backup.functions: Core logic (rsync engine, disk checks, pathing).

    home-backup.modules: Extended features (Encryption, Integrity checks, Auto-Eject).

👤 Author

Wael Isa

    Website: [wael.name](https://www.wael.name)

    GitHub: @waelisa

📜 License

This project is licensed under the MIT License. Use it, change it, share it.
---

## ☕ Support the Project

[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg)](https://www.paypal.me/WaelIsa)
