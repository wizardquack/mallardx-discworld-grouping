# Discworld Grouping

Shows the active group's roster (group name + member list) with
per-member HP/GP bars in a compact panel.

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

# Cross-plugin communication

This plugin has an optional dependency on the discworld-magic plugin.
If you have it, you will get richer information on shielding for each
group member.

## Credit

Many thanks to Quow, whose work on similar plugins was invaluable in
designing and building this one.
