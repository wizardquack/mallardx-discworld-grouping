-- Discworld Grouping — bundled flagship plugin.
--
-- See README.md for installation and
-- docs/superpowers/specs/2026-05-28-discworld-grouping-design.md for
-- the design.

local group_module = require("group")

local panel  = mud.panel("group")
local roster = group_module.make()

-- ---------------------------------------------------------------------
-- Iframe bridge — push a fresh full-roster snapshot on every change
-- and on iframe `ready`. iframe → Lua `refresh` triggers `mud.send("gs")`.
-- ---------------------------------------------------------------------

local function push_roster()
  panel:post("roster", roster.snapshot())
end

panel:on_message("ready", function()
  push_roster()
end)

-- The panel has two refresh controls — one per Discworld command,
-- because the two commands' outputs are disjoint:
--   - `group status brief` carries the per-member roster lines we
--     actually parse (numeric self vitals, word-bucket other vitals,
--     ghost markers). The verbose `group status` form produces the
--     same per-member lines plus a `+++|name|+++` banner, but the
--     join event already populates group_name authoritatively, so
--     the banner is just spam from the refresh path. The banner
--     trigger stays registered for the case where a user types
--     `group status` directly into the input bar.
--   - `group shields` carries the per-member "Arcane protection for
--     X:-" blocks that discworld-magic's protection_report parses.
panel:on_message("refresh", function()
  mud.send("group status brief")
end)

panel:on_message("refresh_shields", function()
  mud.send("group shields")
end)

-- ---------------------------------------------------------------------
-- Authoritative self-name discovery via the char.info mirror.
--
-- discworld-vitals owns the `char.info` GMCP subscription. It writes
-- each top-level scalar to a world var under `char.info.<key>` and
-- re-broadcasts the frame as `net.mallard.discworld.char_info`. We
-- subscribe to that event for live updates and read `capname` (title-
-- cased — matches wire form) out of the var store.
--
-- This runs before any verbose `group status` line for self could hit
-- the placeholder-promotion fallback in `on_status_other`, so the self
-- row carries its true name as soon as the user is logged in.
events.on("net.mallard.discworld.char_info", function()
  local name = vars.get("char.info.capname")
  if type(name) ~= "string" or name == "" then return end
  roster.set_self_name(name)
  push_roster()
end)

-- ---------------------------------------------------------------------
-- Cross-plugin events — shield state from discworld-magic.
--
-- discworld-magic owns all shield wire-parsing (self + other-player) and
-- emits the unified shield.up / shield.down events. We update the
-- per-row chip grid and push a fresh snapshot to the iframe.
-- ---------------------------------------------------------------------

events.on("net.mallard.discworld.shield.up", function(d)
  if type(d) ~= "table" then return end
  roster.on_shield_up(d.subject, d.type, d)
  push_roster()
end)

events.on("net.mallard.discworld.shield.down", function(d)
  if type(d) ~= "table" then return end
  roster.on_shield_down(d.subject, d.type)
  push_roster()
end)

-- `Arcane protection for X:-` headers and "X has no arcane protection"
-- lines fire shield.cleared via discworld-magic's protection_report
-- module. Wipe every cell for that subject so the body lines that
-- follow the header (parsed by the same module) can repopulate from a
-- clean slate.
events.on("net.mallard.discworld.shield.cleared", function(d)
  if type(d) ~= "table" then return end
  roster.on_shield_cleared(d.subject)
  push_roster()
end)

-- ---------------------------------------------------------------------
-- Trigger registrations.
--
-- Patterns use Rust regex syntax (mud.trigger compiles via the regex
-- crate). Rust regex does NOT support lookaround, so Quow's `(?!\[|>)`
-- negative lookahead from QuowMinimap.xml is dropped — the anchored
-- `^[A-Za-z]+` leading character class already excludes lines that
-- start with `[` or `>`.
--
-- Captures are positional; see examples/plugins/discworld-sailing for
-- the precedent.
-- ---------------------------------------------------------------------

-- You joined: [groupname] You have joined the group.
--
-- char.info almost always lands at login — long before the user
-- creates or joins a group — so by the time on_you_joined fires the
-- self row's true name is already cached in the var store (written
-- there by discworld-vitals). Read it back and apply it immediately so
-- the row starts out named (without this, the event subscriber above
-- no-ops at login because there's no self row yet, and the panel sits
-- on the "You" placeholder until the next char.info push that may
-- never come).
mud.trigger([==[^\[([^\]]+)\] You have joined the group\.$]==], function(m)
  roster.on_you_joined(m[1] or "")
  local capname = vars.get("char.info.capname")
  if type(capname) == "string" and capname ~= "" then
    roster.set_self_name(capname)
  end
  push_roster()
end)

-- You left: [groupname] You have left the group.
mud.trigger([==[^\[([^\]]+)\] You have left the group\.$]==], function()
  roster.on_you_left()
  push_roster()
end)

-- Other joined: [groupname] Player has joined the group.
mud.trigger([==[^\[([^\]]+)\] ([A-Za-z]+) has joined the group\.$]==], function(m)
  roster.on_other_joined(m[2] or "")
  push_roster()
end)

-- Other left: [groupname] Player has left the group.
mud.trigger([==[^\[([^\]]+)\] ([A-Za-z]+) has left the group\.$]==], function(m)
  roster.on_other_left(m[2] or "")
  push_roster()
end)

-- Self gs line: Player; Hp: x/y Gp: x/y.
-- No `$` anchor — leader gets `(L)` suffix in some contexts.
-- Use m:raw to keep the player name a string regardless of how the
-- regex evolves: m[1] would auto-coerce a future all-digits capture
-- to a number, which would break downstream table-key uses.
-- The numeric captures auto-coerce through the field accessor.
mud.trigger(
  [==[^([A-Za-z]+); Hp: (\d+)/(\d+) Gp: (\d+)/(\d+)\.]==],
  function(m)
    roster.on_status_self(
      m:raw(1) or "",
      m[2] or 0, m[3] or 1,
      m[4] or 0, m[5] or 1
    )
    push_roster()
  end)

-- Other gs line: Player is <hp-word> and <gp-word>.
-- No `$` anchor — `gsb` appends ` (Idle: X:YY) (L)` markers after the
-- period; `group status` verbose appends `   Idle: X:YY.  He is the
-- current leader of the group.` etc. Match through the first period.
mud.trigger(
  [==[^ *([A-Za-z]+) is (unhurt|almost unhurt|scratched|slightly hurt|slightly injured|injured|slightly wounded|wounded|badly wounded|heavily wounded|seriously wounded|critically wounded|near death) and (refreshed|clear of mind|concentrated|slightly confused|confused|slightly fatigued|fatigued|very fatigued|highly fatigued|severely fatigued|near unconscious)\.]==],
  function(m)
    roster.on_status_other(m[1] or "", m[2] or "", m[3] or "")
    push_roster()
  end)

-- Other gs line (ghost): Player is perfectly healthy, for a ghost.
mud.trigger(
  [==[^ *([A-Za-z]+) is perfectly healthy, for a ghost\.]==],
  function(m)
    roster.on_status_ghost(m[1] or "")
    push_roster()
  end)

-- Verbose `group status` banner: leading spaces, run of `+`, then
-- `|<group-name>|`, then more `+`. Mallard advertises cols=999 over
-- NAWS so this banner arrives as a single un-wrapped line.
-- Only sets group_name when we don't already have one from a join
-- event (avoids overriding the authoritative source).
mud.trigger([==[^ *\++\|([^|]+)\|\++]==], function(m)
  roster.on_banner_group_name(m[1] or "")
  push_roster()
end)
