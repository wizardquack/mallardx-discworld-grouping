-- Roster state machine for discworld-grouping.
--
-- Pure Lua; no host-API dependencies. Tests load this directly into a
-- vanilla mlua::Lua state (see src-tauri/tests/discworld_grouping_plugin.rs).
--
-- Usage:
--   local group = require("group")
--   local roster = group.make()
--   roster.on_you_joined(group_name)
--   roster.on_other_joined(player)
--   roster.on_status_self(player, hp, hpmax, gp, gpmax)
--   ...
--   local snap = roster.snapshot()             -- Lua table
--   local snap_json = roster.snapshot_json()   -- JSON string for iframe push

local status_maps = require("status_maps")
local shield_store = require("shield_store")

local M = {}

local function now_seconds()
  return os.time()
end

-- Find a member row by name (case-sensitive). Returns index or nil.
local function find_index(members, name)
  for i, m in ipairs(members) do
    if m.name == name then return i end
  end
  return nil
end

-- Quow's FilterPlayerName, adapted. Title-case the input, then look for
-- an exact roster-name match, then a per-word match. Returns the
-- canonical roster name or nil.
local function filter_player_name(members, raw)
  if type(raw) ~= "string" or raw == "" then return nil end
  -- Title-case each word ("sir bigwig jones" → "Sir Bigwig Jones").
  local titled = raw:gsub("(%a)(%w*)", function(a, b) return a:upper() .. b:lower() end)
  if find_index(members, titled) then return titled end
  for word in titled:gmatch("%w+") do
    if find_index(members, word) then return word end
  end
  return nil
end

function M.make()
  local roster = {
    group_name      = nil,
    last_refresh_at = nil,
    members         = {},
  }

  local sstore = shield_store.make()

  local function self_row()
    return roster.members[1]
  end

  -- Idempotent member-add. Skips if `player` already matches a roster
  -- row by exact name. Used by `on_other_joined` (a join event) and by
  -- `on_shield_cleared` (a `group shields` arcane header), so a
  -- shields-first refresh still surfaces every group member.
  local function ensure_member(player)
    if type(player) ~= "string" or player == "" then return end
    if find_index(roster.members, player) then return end
    roster.members[#roster.members + 1] = {
      name      = player,
      hp        = nil,
      gp        = nil,
      ghost     = false,
      is_self   = false,
      joined_at = now_seconds(),
    }
  end

  function roster.on_you_joined(group_name)
    roster.group_name      = group_name
    roster.last_refresh_at = nil   -- prior group's age chip is stale; reset
    roster.members = {
      {
        name      = "You",
        hp        = nil,
        gp        = nil,
        ghost     = false,
        is_self   = true,
        joined_at = now_seconds(),
      },
    }
  end

  function roster.on_you_left()
    roster.group_name      = nil
    roster.last_refresh_at = nil
    roster.members         = {}
    sstore.clear()
  end

  -- Set the group name without resetting the roster. Used when we
  -- discover the name from the verbose `group status` banner during a
  -- mid-session reconnect (we never saw the join event). Skips if a
  -- name is already known — the join event is authoritative.
  function roster.on_banner_group_name(name)
    if roster.group_name == nil and type(name) == "string" and name ~= "" then
      roster.group_name = name
    end
  end

  -- Wire-side names from the join/leave triggers can arrive with
  -- non-title-case (Discworld allows e.g. `aVocado` / `sYa`). Roster
  -- rows added via on_status_other are stored title-cased through
  -- filter_player_name, so a raw lookup on `aVocado` would miss the
  -- `Avocado` row. Normalize at both add and remove paths so the
  -- handlers stay aligned regardless of wire casing.
  local function normalize(raw)
    if type(raw) ~= "string" or raw == "" then return raw end
    local matched = filter_player_name(roster.members, raw)
    if matched then return matched end
    -- No existing row matches; title-case so the row we *create* lines
    -- up with what on_status_other would produce for the same wire name.
    local titled = raw:gsub("(%a)(%w*)", function(a, b) return a:upper() .. b:lower() end)
    return titled
  end

  -- Self shields are stored under a stable sentinel key — never under
  -- the live row name. The self row's name changes ("You" → "Bigwig"
  -- the first time on_status_self runs), and if we keyed self entries
  -- by the live name the rename would orphan them on the next refresh.
  -- snapshot() below looks up the self row's shields by this sentinel
  -- and other members' by their wire name.
  local SELF_KEY = "self"

  -- Fold any non-self row whose name matches `canonical` into the self
  -- row: transfer that row's shield state to SELF_KEY, then drop the
  -- row. Called after a self-row rename in on_status_self.
  --
  -- This handles the order: `Arcane protection for Quack:-` lands
  -- before we know the user is Quack (no char.info yet, or it hasn't
  -- arrived in time), so on_shield_cleared falls through to
  -- ensure_member and adds a stranger "Quack" row with shields under
  -- the "Quack" key. Once gsb arrives and the self row gets renamed
  -- to "Quack", that stranger row is unambiguously the user — fold
  -- it in instead of leaving a duplicate.
  local function absorb_duplicate_into_self(canonical)
    if type(canonical) ~= "string" or canonical == "" then return end
    for i = #roster.members, 2, -1 do
      if roster.members[i].name == canonical then
        local prev = sstore.snapshot_for(canonical)
        if prev then
          for _, t in ipairs(shield_store.TYPES) do
            local cell = prev[t]
            if cell and cell.up then sstore.on_up(SELF_KEY, t, cell) end
          end
          sstore.on_player_left(canonical)
        end
        table.remove(roster.members, i)
      end
    end
  end

  function roster.on_other_joined(player)
    ensure_member(normalize(player))
  end

  function roster.on_other_left(player)
    local name = normalize(player)
    local idx = find_index(roster.members, name)
    if idx then table.remove(roster.members, idx) end
    sstore.on_player_left(name)
  end

  function roster.on_status_self(player, hp, hpmax, gp, gpmax)
    local row = self_row()
    if not row then
      -- gs landed before a you-joined trigger fired; create the self
      -- row defensively. Group name unknown; leave as nil.
      row = {
        name      = player or "You",
        hp        = nil,
        gp        = nil,
        ghost     = false,
        is_self   = true,
        joined_at = now_seconds(),
      }
      roster.members = { row }
    end
    -- Canonicalise the wire name so the self row matches the same
    -- form shield events and other-row writes use. Then collapse any
    -- non-self row with that same canonical name (created by
    -- on_shield_cleared before we knew the user's identity).
    local canonical = (player and player ~= "") and normalize(player) or row.name
    row.name  = canonical
    row.ghost = false
    if type(hp) == "number" and type(hpmax) == "number" and hpmax > 0 then
      row.hp = math.floor(hp / hpmax * 100 + 0.5)
    end
    if type(gp) == "number" and type(gpmax) == "number" and gpmax > 0 then
      row.gp = math.floor(gp / gpmax * 100 + 0.5)
    end
    absorb_duplicate_into_self(canonical)
    roster.last_refresh_at = now_seconds()
  end

  function roster.on_status_other(raw_player, hp_word, gp_word)
    -- normalize falls through to a title-cased form when no row
    -- matches, so the row we *create* below stores the canonical name.
    -- Discworld emits inconsistent casing across commands ("AVocado" in
    -- `group status`, "aVocado" in the leave event); canonicalising on
    -- write keeps the roster aligned regardless of which command we
    -- saw first.
    local player = normalize(raw_player)
    local idx    = find_index(roster.members, player)
    local row
    if idx then
      row = roster.members[idx]
    else
      -- Placeholder-promotion: verbose `group status` uses the same
      -- "<name> is <hp> and <gp>." shape for self as for others, so
      -- self lines reach this handler. If the self row is still on
      -- the placeholder name "You" (no `gs` / no GMCP char.info has
      -- landed yet) AND we've never seen this name before, assume it
      -- IS self and rename the placeholder rather than creating a
      -- stranger row. In practice the GMCP char.info subscription in
      -- main.lua almost always renames the self row before this code
      -- path can fire — this is the cold-start safety net.
      local self_r = roster.members[1]
      if self_r and self_r.is_self and self_r.name == "You" then
        self_r.name = player
        row = self_r
      else
        row = {
          name      = player,
          hp        = nil,
          gp        = nil,
          ghost     = false,
          is_self   = false,
          joined_at = now_seconds(),
        }
        roster.members[#roster.members + 1] = row
      end
    end
    row.hp    = status_maps.hp[hp_word] or row.hp
    row.gp    = status_maps.gp[gp_word] or row.gp
    row.ghost = false
    roster.last_refresh_at = now_seconds()
  end

  -- Authoritative rename — driven by the GMCP `char.info` frame at
  -- login (see main.lua). Idempotent; safe to call on every char.info
  -- delivery. Refuses to rename onto a name that already belongs to
  -- another roster row (Discworld names are unique, but defensive).
  function roster.set_self_name(name)
    if type(name) ~= "string" or name == "" then return end
    local self_r = roster.members[1]
    if not self_r or not self_r.is_self then return end
    if self_r.name == name then return end
    local collision = find_index(roster.members, name)
    if collision and collision ~= 1 then return end
    self_r.name = name
  end

  function roster.on_status_ghost(raw_player)
    local player = normalize(raw_player)
    local idx    = find_index(roster.members, player)
    local row
    if idx then
      row = roster.members[idx]
    else
      row = {
        name      = player,
        hp        = nil,
        gp        = nil,
        ghost     = false,
        is_self   = false,
        joined_at = now_seconds(),
      }
      roster.members[#roster.members + 1] = row
    end
    row.hp    = 0
    row.gp    = 0
    row.ghost = true
    roster.last_refresh_at = now_seconds()
  end

  -- protection_report.lua emits shield events with subject = the
  -- wire-captured player name (it can't tell "self" from any other
  -- name). Canonicalise the subject so the shield-store key matches
  -- the roster row name regardless of how the wire spelled it
  -- ("Arcane protection for sYa:-" vs "SYa is unhurt and refreshed."
  -- — both should land on the same "Sya" row). Then compare against
  -- members[1].name so the chip routes to SELF_KEY when on_status_self
  -- has already renamed the self row.
  local function resolve_subject(subject)
    if subject == "self" then return SELF_KEY end
    if type(subject) ~= "string" or subject == "" then return subject end
    local canonical = normalize(subject)
    local me = roster.members[1]
    if me and me.is_self and canonical == me.name then
      return SELF_KEY
    end
    return canonical
  end

  function roster.on_shield_up(subject, type_, details)
    local name = resolve_subject(subject)
    if type(name) ~= "string" or name == "" then return end
    sstore.on_up(name, type_, details)
  end

  function roster.on_shield_down(subject, type_)
    local name = resolve_subject(subject)
    if type(name) ~= "string" or name == "" then return end
    sstore.on_down(name, type_)
  end

  -- shield.cleared — magic plugin saw a "Arcane protection for X:-"
  -- header (or "X has no arcane or divine protection"). Reset every
  -- cell for that subject; the body lines that follow the header
  -- repopulate via on_shield_up.
  --
  -- `group shields` is the only wire source for `Arcane protection
  -- for X:-` headers in Discworld, so a `shield.cleared` for a non-
  -- self subject is an authoritative "X is in the group" observation.
  -- Use it to keep `roster.members` in sync from this command too:
  -- ensure_member adds a row if missing so a shields-first refresh
  -- (or a shields-only refresh with no prior `group status`) still
  -- populates the chip grid against the correct member list.
  function roster.on_shield_cleared(subject)
    local name = resolve_subject(subject)
    if type(name) ~= "string" or name == "" then return end
    if name ~= SELF_KEY then ensure_member(name) end
    sstore.on_cleared(name)
  end

  function roster.ensure_member(player) ensure_member(player) end

  function roster.snapshot()
    -- Returns a shallow copy of the roster (members are copied so callers
    -- can't mutate internal state by accident).
    local members = {}
    for i, m in ipairs(roster.members) do
      members[i] = {
        name      = m.name,
        hp        = m.hp,
        gp        = m.gp,
        ghost     = m.ghost,
        is_self   = m.is_self,
        joined_at = m.joined_at,
        shields   = (m.is_self and sstore.snapshot_for(SELF_KEY))
                    or sstore.snapshot_for(m.name)
                    or shield_store.default_row(),
      }
    end
    return {
      group_name      = roster.group_name,
      last_refresh_at = roster.last_refresh_at,
      members         = members,
    }
  end

  function roster.snapshot_json()
    -- mlua's vanilla state doesn't ship a JSON encoder; the plugin
    -- runtime injects `json.encode` via the host. For unit-test
    -- convenience this helper falls back to a hand-rolled encoder when
    -- `json` isn't present in the global table.
    local snap = roster.snapshot()
    if rawget(_G, "json") and _G.json.encode then
      return _G.json.encode(snap)
    end
    return M._encode(snap)
  end

  return roster
end

-- Minimal JSON encoder used by snapshot_json when `json` isn't injected
-- (i.e. under the vanilla mlua test harness). Handles only the shapes
-- the roster snapshot can produce: nil, bool, number, string, array,
-- string-keyed map.
local function encode_value(v)
  if v == nil then return "null" end
  local t = type(v)
  if t == "boolean" then return tostring(v) end
  if t == "number"  then return tostring(v) end
  if t == "string"  then
    return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
  end
  if t == "table"   then
    -- Array iff keys are 1..#v with no gaps.
    local n = #v
    local is_array = true
    local count = 0
    for k in pairs(v) do
      count = count + 1
      if type(k) ~= "number" then is_array = false; break end
    end
    if is_array and count == n then
      local parts = {}
      for i = 1, n do parts[i] = encode_value(v[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local parts = {}
    for k, vv in pairs(v) do
      parts[#parts + 1] = '"' .. tostring(k) .. '":' .. encode_value(vv)
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  error("unsupported type for snapshot_json: " .. t)
end

function M._encode(value) return encode_value(value) end

return M
