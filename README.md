# Action1 Software Repository

Quick reference for repository layout, required files, templates and how to build application zips.

## Overview
This repo contains mac application release folders and a helper `mac/build.sh` script to package a version directory into `app-version.zip`. The script is interactive by default and supports tab-completion for paths.

## Recommended folder layout
Place application versions under `<Platform>/<AppName>/<Version>/`. Example:
```bash
.
├── build.sh
├── mac/
│   ├── VirtualBuddy/
│   │   └── 2.1/
│   │       ├── VirtualBuddy.app
│   │       ├── install.sh
│   │       ├── common.sh
│   │       └── any other release files
│   └── MyApp/
│       └── 1.0/
└── windows/
    └── Office365Apps/
        └── 16.0.012/
            ├── Office.xml
            ├── Office.exe
            └── any other release files
```     

You may also place versions directly at repo root `<AppName>/<Version>/` if preferred.

## Required files
- The version folder must contain the files you want in the zip (the script zips the contents of the version folder into the zip root).
- `mac/build.sh` — packager script (executable).
    - This will be unique to each package/version, but will mostly follow the same logic as the temmplate scripts
- `.gitignore` — should contain `local_mnt/` to ignore mount folders and build artifacts (zips, dmgs, pkgs).

Example `.gitignore` entries:
- local_mnt/
- *.zip
- *.dmg
- *.pkg

## Template / helper files
- Any common install or helper scripts shared between releases (e.g. `common.sh`) should live alongside the release files inside the version folder (or referenced with relative paths inside install scripts).
- There is no mandatory centralized template location; place templates inside `mac/<AppName>/templates/` if you want a canonical place.

## build.sh (mac/build.sh) — usage
Make script executable:
```bash
chmod +x mac/build.sh
```

Run non-interactively:
```bash
# from repository root (or any folder)
mac/build.sh -a VirtualBuddy -v 2.1
# explicit source and output
mac/build.sh -a VirtualBuddy -v 2.1 -s ./ViartualBuddy/2.1 -o ./dist
```

Run interactively (prompts if missing):
```bash
cd mac
./build.sh
# prompts:
#  Application name (e.g. VirtualBuddy):
#  Version (e.g. 2.1):
#  (if auto-detect fails) Source folder ... (tab completion supported)
```

Options:
- -a APP    Application name (required)
- -v VER    Version (required)
- -s SRC    Explicit source folder (absolute or relative to current working dir)
- -o OUT    Output directory (default: mac/dist)
- -h        Help

Behavior:
- The script prefers resolving `./<App>/<Ver>` from the directory you run it from (run-root). If not found it falls back to `mac/<App>/<Ver>` relative to the script location (repo root).
- If multiple candidate version folders are found you will be prompted to choose.
- The script excludes `local_mnt` folders and `.DS_Store` when creating the zip.
- Output zip name: `<App>-<Ver>.zip` in the output directory.

## Troubleshooting
- If the script finds duplicate paths, it's usually because you ran it from `mac/` and the script also searched the repo root; duplicates are deduplicated in recent versions, but ensure you run from the intended directory.
- Common cause of "not found" is spelling mismatch (e.g. `ViartualBuddy` vs `VirtualBuddy`). Either rename the folder to match APP, or run with `-s` using the correct path.
- Avoid running as `sudo` unless necessary — it changes the effective working directory environment for tab completion and permissions.
- Ensure `mac/build.sh` is not duplicated in the file (no appended markdown or extra content); the script must be valid shell.

## Examples
From repo root, pack VirtualBuddy 2.1:
```bash
mac/build.sh -a VirtualBuddy -v 2.1
```

From inside `mac/` with tab-completion:
```bash
cd mac
./build.sh
# respond to prompts; use tab to complete ./ViartualBuddy/2.1 (or correct spelling)
```

## Notes
- Keep `.gitignore` updated to exclude build artifacts and `local_mnt` mount points.
- If you need advanced fuzzy matching, edit `mac/build.sh` — current script uses case-insensitive contains and interactive selection for ambiguous matches.
