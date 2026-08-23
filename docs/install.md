# Install

*seal* is a command-line/terminal application. To install and use *seal*, you'll need to use a terminal, such as Windows Terminal with PowerShell on Windows, Terminal on macOS, Konsole on Linux, Termux on Android, etc. Some terminal experience is recommended, but as long as you're willing to learn and look up stuff as needed, you should easily be able to use and install *seal*.

## Windows

1. Download the [latest release](<https://github.com/deviaze/seal/releases/latest>) of *seal* for your system, or if you want the most up-to-date beta, download the newest [build artifact from GitHub Actions](https://github.com/deviaze/seal/actions). I don't recommend building *seal* from source on Windows unless you already have a functioning Rust toolchain installed (because it's more annoying to set up on Windows).
2. If Microsoft Defender flags *seal* for whatever reason, send me a message on Discord or an email so I can recompile the release artifacts and pray rustc doesn't produce something that gets false flagged by Defender's AI tools. *seal* is not a virus/trojan/etc., so any such flags are false positives.
3. Once you've downloaded *seal*, you need to copy/move it somewhere in your `$PATH` to make it accessible in your terminal. If you don't know how to do this, don't worry, [read the tutorial on installing *seal* with *seal*](/docs/seal_install_script.md).
4. Close and reopen your Windows Terminal and make sure running `seal --help` displays *seal*'s help message. This should ensure *seal* is available in your `$PATH`.

## macOS

1. Due to macOS reasons, the least hassle way to install *seal* on macOS is by cloning and building it from source. See the instructions at the bottom for how to do this. Alternatively, you can download the [latest release](<https://github.com/deviaze/seal/releases/latest>) or a recent [build artifact](https://github.com/deviaze/seal/actions), and bypass macOS' security/signing restrictions by doing the `sudo xattr -rd com.apple.quarantine path/to/seal` thing.
2. Move *seal* to a location like `/usr/local/bin/seal` or `~/bin/seal`.
3. Because *seal* is not signed/notarized, macOS will block it from running by default. To allow it, first run `./seal --help` to cause macOS to show a warning, and then go to Mac **System Settings → Privacy & Security** and check the bottom for a message like "seal was blocked from use because it is not from an identified developer." Click **Allow Anyway**.
4. Go back to your terminal and try `./seal --help` again. This may cause another warning to pop up with another confirmation dialog. Click **Open**.
5. To ensure *seal* is available everywhere, make sure it's added to your shell's `$PATH`. For example, if you placed it in `~/bin`, add `export PATH="$HOME/bin:$PATH"` to your shell config (`.zshrc`, `.bash_profile`, etc.)
6. Every time you update, redownload, or recompile *seal* you might have to redo those steps and explicitly allow it again. You can also disable Gatekeeper entirely if you want to (look up documentation for that if you're so inclined)
7. Confirm *seal* works by running `seal --help`.

## Linux

1. Download either the [latest release](<https://github.com/deviaze/seal/releases/latest>) of *seal*, a recent [build artifact](<https://github.com/deviaze/seal/actions>), or by building *seal* from source.
2. Move *seal* to `~/.local/bin/seal` (or wherever else you're comfortable) and make sure it's added to your `$PATH` with `export PATH="$HOME/.local/bin:$PATH` or similar.
3. Confirm *seal* works by running `seal --help`.

## Android (Termux)

1. Download an Android release artifact from the [latest release](<https://github.com/deviaze/seal/releases/latest>) or follow the Android instructions below.
2. Build from source following the instructions below.
3. Ping me on Discord if you're having trouble getting *seal* to work on Android.

## Building/installing from source

### Android specific instructions

1. You need the Rust toolchain installed w/ nightly. Getting Rust Nightly installed on Termux is a big PITA so I'mma try to help you not have to discover everything yourself like I did.
2. `pkg update && pkg upgrade` your package manager.
3. You have to add the [Termux User Repository (TUR)](<https://github.com/termux-user-repository/tur>) with `pkg install tur-repo`
4. Now you can install rustc, cargo, and nightly with `pkg install rustc-nightly`
5. To make Rust default to nightly you need to set an environment variable: `export RUSTC=$PREFIX/opt/rust-nightly/bin/rustc` in your shell config file.

### All platforms

1. Clone the repository with `git clone seal-runtime/seal` or `gh repo clone seal-runtime/seal`.
2. `cd` into `seal`
3. Run `cargo build --release`. If you don't have a Rust toolchain installed, you should probably install it via `rustup` unless you're on Android (see the instructions above).
4. Copy the release artifact at `./target/release/seal` (or `.\target\release\seal.exe` on Windows) to somewhere in your `$PATH` (such as `$HOME/.local/bin/seal(.exe)` or `/usr/bin/seal`).
