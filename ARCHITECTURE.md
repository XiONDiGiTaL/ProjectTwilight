# Architecture

## Principles

1. **Bring your own client.** Gravity resources are decoded at runtime from the player's own installation (read-only). Builds and the repository contain only original code and assets.
2. **One rules core, three modes.** Gameplay rules are pure GDScript with no rendering or network dependencies. Offline play, the co-op host and a dedicated server all run the same rules. Clients only render and send intents.
3. **Rendering is replaceable.** Visual nodes read gameplay state and never mutate it. "Classic" and "enhanced" presentations are separate renderer implementations over the same state.
4. **Data-driven.** Pre-Renewal tables (jobs, skills, items, monsters) live as data with provenance, never as constants scattered through code.
5. **Compatibility is isolated.** eAthena/Hercules protocol adapters live behind an interface and never leak into the rules core.

## Layout (`06_Godot_Project/`)

```text
scripts/
  core/            Settings (autoload)
  resources/       RoResources VFS (autoload), grf/, formats/ (spr, act; gat/gnd/rsw/rsm next), text/ (cp949)
  rendering/       ActSprite (SPR/ACT composer); map renderer next
  gameplay/        progression/ (stat rules); combat/, items/, world/ next
  networking/      InvitationCode; transport/session/sync next
  ui/              main menu
  tools/           developer tools (sprite viewer)
scenes/            main_menu.tscn, tools/
resources/         original data only (e.g. encoding table)
tests/             run_tests.gd, unit/ (synthetic fixtures), integration/ (needs a client)
```

Folders are created only when there is code to put in them.

## Resource pipeline

```text
client dir ─┬─ loose data/ (highest priority)
            └─ GRFs in DATA.INI order ─► GrfArchive (index: lowercase CP949-as-Latin1 key)
                                        │
RoResources.read(path) ─► bytes ─► decoders (SprFile, ActFile, …) ─► cached ─► renderers
```

- Indexing the 3.8 GB reference GRF (261k files) takes about 0.8 s, so no persistent index cache is needed yet.
- Decoders are pure functions over bytes. They are unit-tested with synthetic byte fixtures, so CI needs no game data, and integration-tested against a real client when one is configured.

## Mode separation

| Layer | Offline | Private co-op | MMO |
|---|---|---|---|
| Rules core | local | host process | dedicated server |
| Persistence | local save file (versioned) | host's save | server database |
| Transport | none | ENet direct (invitation code) | dedicated protocol, or eAthena/Hercules adapter |
| Authority | local | host | server |

Offline play never touches networking code paths.
