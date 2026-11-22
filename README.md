# w_core

Core framework resource for **Wraith Framework RedM** (Lua 5.4 / OneSync).

Manages character persistence (`players`), money accounts, jobs, gangs, player metadata, database-backed staff ranks & ACE permissions, server bans, and core roleplay/admin commands.

## Key Features

- **Player Lifecycle:** Multi-character loading, saving, citizen IDs, routing buckets, and metadata synchronization.
- **Economy & Accounts:** Server-authoritative `cash` and `bank` balances via `player.Functions.AddMoney / RemoveMoney / SetMoney / GetMoney`.
- **Jobs & Gangs:** Configurable jobs (including `police` and `doctor`), grades, duty status, and gang definitions with dynamic registration exports.
- **Permissions & Bans:** Hierarchical ACE groups (`god` -> `admin` -> `mod`), database-backed staff ranks (`w_ranks`), and online/offline ban management (`BanPlayer`, `UnbanId`, `GetBans`).
- **Built-In Commands:** `/id`, `/cid`, `/job`, `/gang`, `/me`, `/do`, `/ooc`, `/tp`, `/tpm`, `/dv`, `/dh`, `/setjob`, `/setgang`, `/givemoney`, `/setmoney`, `/closeserver`, `/openserver`.

## Installation

1. Import `wcore.sql` into your MariaDB/MySQL database.
2. Place `w_core` in `resources/[wraith]/w_core`.
3. Add `ensure w_core` to `server.cfg` right after `ensure w_lib`.

## Quick Usage

```lua
local WCore = exports.w_core:GetCoreObject()

-- Server
local player = WCore.Functions.GetPlayer(source)
if player then
    player.Functions.AddMoney('cash', 50, 'reward')
end
```

## Documentation & Links

- **Developer Docs:** https://wraith-core.github.io/docs/#/core/w_core
- **txAdmin Recipe:** https://github.com/Wraith-Core/txAdminRecipe

## License

GPL-3.0 — see [LICENSE](LICENSE).
