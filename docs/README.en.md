# Kornucopia

Kornucopia is a local Kanban app with sticky notes for Mac with Apple Silicon and Windows 11. Four columns guide your work: Backlog, Doing, Review and Done. Each column includes a practical tutorial and has its own color.

**[Download the latest release](https://github.com/allanpscheidt/Kornucopia/releases/latest)** · [Português brasileiro](../README.md)

## Version 1.0.2

- Practical tutorials in every column.
- Interface in Brazilian Portuguese, English, Spanish, French and Japanese.
- Language selection saved in Settings. Your notes keep their original text.
- Mac arm64 and portable Windows x64 and ARM64 packages.

Doing starts with a limit of two cards. A popup blocks additional work when the limit is reached. Finish a task and move it to Review before starting another. You can increase the limit in Settings. The board accepts up to 10,000 notes within its safety budget. Windows shows 100 notes per column page; search includes every page.

Version 1.0.2 checks regular files and byte length before reading the primary board and backup. The shared limits are 16 MiB of JSON and 8 MiB of total UTF-8 text, with smaller limits per field. Rejected files are preserved safely when possible; the app tries the backup and warns you. Rejected edits remain in the open editor and can be copied before closing. See the [complete limits](../README.md#salvamento-e-recuperação).

## Install and use

Standard macOS commands, such as Close, follow the system language. Settings controls the language of Kornucopia's controls, alerts and tutorials.

On Mac, macOS 14 or later and Apple Silicon are required. Extract the macOS arm64 ZIP and copy Kornucopia.app to Applications. The app has an ad hoc signature without Developer ID or Apple notarization. Consult [Apple's guidance](https://support.apple.com/en-us/102445) if the system blocks the first launch.

On Windows 11, choose the x64 or ARM64 ZIP for your processor. Extract the whole folder and keep Kornucopia.exe together with Resources. Open the executable. The runtime is included. The current package has no Authenticode signature. Verify the download source and keep system protections enabled.

Create an idea in Backlog, edit its title and notes, then follow the column tutorials. Move cards by dragging or through the editor. Use Settings to choose a language and adjust the work limit. Each column keeps a distinct color: yellow, blue, purple and green.

Changes save automatically. Mac data lives in `~/Library/Application Support/Kornucopia/`; Windows data lives in `%LOCALAPPDATA%\Kornucopia\`. Files are readable JSON, with a backup of the previous state. Include this folder in your regular backups. The app works locally without accounts or cloud synchronization.

See the [full documentation](../README.md), [contribution guide](../CONTRIBUTING.md) and [security policy](../SECURITY.md).
