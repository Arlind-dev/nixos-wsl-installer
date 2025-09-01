# My NixOS Config

This guide outlines the steps to set up NixOS on Windows Subsystem for Linux (WSL), including importing **my NixOS configuration**.

## Disclaimer

This project isn't finished; it's currently barely usable.

## Installing My NixOS on WSL

1. **Run the Setup Script**

   Open PowerShell and run:

   ```PowerShell
   iex (irm "https://raw.githubusercontent.com/Arlind-dev/nixos-wsl-installer/main/wsl-install/setup-wsl.ps1")
   ```

   The script will check if it is running with administrative privileges and will restart itself with elevated permissions if necessary.

2. **Launch WSL:**

   Simply type:

   ```PowerShell
   wsl
   ```
