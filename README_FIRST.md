# Ragnarok Online Pre-Renewal Research Workspace

This workspace is for inspecting an authorized Ragnarok Online client installation and reconstructing a historically consistent Pre-Renewal game in Godot 4.

## Start here

1. Keep the original client installation intact. Do not patch, modify, or overwrite it.
2. Copy the complete client directory into `01_Client_Original/Client_Files` (or point the inventory script at the original directory).
3. Run `Inventory-ROClient.ps1` from PowerShell. It records filenames, sizes, timestamps, and SHA-256 hashes. It does not copy or modify client files.
4. Put GRF archives in `01_Client_Original/GRF` if you are keeping a separate archival copy. Preserve all original archives and filenames.
5. Obtain reference source repositories separately and place local clones in `03_Reference_Sources`.
6. Ask the agent to inspect first and produce an inventory/report before extracting, converting, or implementing anything.

## Client files to preserve

Collect the entire installed client directory when possible, not just selected files. At minimum, preserve any that exist:

- `Ragexe.exe`, `RagexeRE.exe`, `Ragnarok.exe`, `Setup.exe`
- `data.grf`, `rdata.grf`, `sdata.grf`, and any other `.grf` archives
- `System/` and `data/` directories, including `.lub`, `.lua`, `.ini`, `.xml`, `.txt`, `.bmp`, `.spr`, `.act`, `.gat`, `.gnd`, `.rsw`, `.rsm`, `.str` files
- `BGM/` and other audio directories
- Client DLLs, configuration files, patch manifests, and version files

Do not assume every file type is present or that filenames are consistent between client generations.

## Reference repositories

Clone these into the corresponding directories, retaining their Git history:

- rAthena: https://github.com/rathena/rathena
- Hercules: https://github.com/HerculesWS/Hercules
- Archived eAthena reference: https://github.com/Casual-Ragnarok/eAthena-archived

Useful reference sites:

- RateMyServer: https://ratemyserver.net/
- iRO Wiki: https://irowiki.org/
- eAthena history: https://www.eathena.org/history.html

For rAthena, inspect the Pre-Renewal database and source separately from Renewal. Do not assume current emulator behavior is identical to a specific historical client build.

## Important handling rules

- Keep original GRFs and client binaries read-only.
- Do not commit proprietary client assets or extracted game data to a public repository.
- Keep source assets, converted assets, and generated/imported assets separate.
- Record the exact client build, executable hash, archive hashes, and extraction tool/version.
- Do not merge `data.grf`, `rdata.grf`, or loose `data/` files until archive precedence and conflicts have been documented.
- Do not treat the install date or archive filename as proof of Pre-Renewal mechanics.
- Use the selected historical target version as the gameplay authority. Newer clients may be used as asset sources only where compatible.
- Do not let the agent overwrite source files or run destructive conversions.

## Expected first deliverables from the reverse-engineering agent

1. Client build identification report: executable names, hashes, version clues, RAG/RAGRE distinction, packet version clues.
2. GRF inventory: archive names, hashes, file counts, duplicate paths, and precedence observations.
3. Resource-format inventory: maps, sprites, animations, models, effects, UI, Lua/LUB, and audio.
4. Data-source comparison: Pre-Renewal versus Renewal tables and conflicts.
5. Compatibility matrix: which newer assets/data can be reused for the chosen Pre-Renewal target.
6. Risk register: unknowns, uncertain historical values, missing resources, and legal/technical constraints.
7. Proposed Godot architecture before implementation.

The first phase is inspection and documentation only. No gameplay implementation until the inventory and target ruleset have been approved.
