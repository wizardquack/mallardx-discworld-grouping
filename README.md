# Discworld Grouping

A Mallard bundled plugin for Discworld MUD. Shows the active group's
roster (group name + member list) with per-member HP/GP bars in a
compact iframe panel docked to the right.

## Install (dev)

```sh
bash scripts/reinstall.sh
```

Then restart Mallard or toggle the plugin in the manager.

## What it does

- Auto-tracks group join/leave events (yours and others').
- Per-member HP/GP bars update from the `gs` (group status brief)
  output. The user is in control — there's no background polling; the
  panel's `⟳` button (or typing `gs` yourself) refreshes everyone in
  one round-trip.
- Dead members are flagged with a `ghost` badge.
- Empty placeholder when you're not in a group.
- A five-pill shield row (T C E B M) per member: TPA / CCC / EFF / BUG /
  MS. v1 wires TPA and EFF — including a per-player TPA glow ladder
  fed from passive combat output. CCC/BUG/MS are placeholders pending a
  follow-up. State flows from `discworld-magic` via the cross-plugin
  `net.mallard.discworld.shield.up/.down` event surface.

## Auto-enable

`[worlds] match = ["discworld.starturtle.net:*"]` — enabled by default
on Discworld worlds; no-op elsewhere.

## Design

Design specs live in the [Mallard repo](https://github.com/wizardquack/mallard) under `docs/superpowers/specs/`:

- Roster + HP/GP panel: `2026-05-28-discworld-grouping-design.md`
- Shield row + cross-plugin event surface: `2026-05-28-discworld-group-shields-design.md`
