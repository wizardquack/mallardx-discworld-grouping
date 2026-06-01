-- Discworld Grouping — per-player shield state store.
--
-- Pure Lua; no host-API dependencies. Tests load this directly into a
-- vanilla mlua::Lua state (see src-tauri/tests/discworld_grouping_plugin.rs).
--
-- Design: docs/superpowers/specs/2026-05-28-discworld-group-shields-design.md
--
-- Tracks the per-player chip grid keyed by canonical roster name. The
-- "up" boolean is the master signal; detail fields (`percent`, `glow`,
-- `item`, `substance`, `strength`, `size`, `bugs`, `deity`) are sticky
-- — they persist across subsequent on_up calls that don't supply a new
-- value, and clear on on_down.
--
-- Usage:
--   local SS = require("shield_store")
--   local store = SS.make()
--   store.on_up("Brodfist", "tpa", { percent = 60, glow = "bright red" })
--   store.on_down("Brodfist", "tpa")
--   store.on_player_left("Brodfist")
--   local row = store.snapshot_for("Brodfist")    -- table | nil

local M = {}

M.TYPES = { "tpa", "ccc", "eff", "bug", "ms" }

-- Lookup set built from TYPES for O(1) validation.
local TYPE_SET = {}
for _, t in ipairs(M.TYPES) do TYPE_SET[t] = true end

local function default_row()
  return {
    tpa = { up = false }, ccc = { up = false }, eff = { up = false },
    bug = { up = false }, ms  = { up = false },
  }
end

function M.make()
  local store = { shields = {} }

  local function row(name)
    if not store.shields[name] then store.shields[name] = default_row() end
    return store.shields[name]
  end

  function store.on_up(player, type_, details)
    if type(player) ~= "string" or player == "" then return end
    if not TYPE_SET[type_] then return end
    local cell = row(player)[type_]
    cell.up = true
    if type(details) == "table" then
      if details.percent   ~= nil then cell.percent   = details.percent   end
      if details.glow      ~= nil then cell.glow      = details.glow      end
      if details.item      ~= nil then cell.item      = details.item      end
      if details.substance ~= nil then cell.substance = details.substance end
      if details.strength  ~= nil then cell.strength  = details.strength  end
      if details.size      ~= nil then cell.size      = details.size      end
      if details.bugs      ~= nil then cell.bugs      = details.bugs      end
      if details.deity     ~= nil then cell.deity     = details.deity     end
    end
  end

  function store.on_down(player, type_)
    if type(player) ~= "string" or player == "" then return end
    if not TYPE_SET[type_] then return end
    if not store.shields[player] then return end
    local cell = store.shields[player][type_]
    cell.up        = false
    cell.percent   = nil
    cell.glow      = nil
    cell.item      = nil
    cell.substance = nil
    cell.strength  = nil
    cell.size      = nil
    cell.bugs      = nil
    cell.deity     = nil
  end

  -- on_cleared resets every shield cell for `player` back to its
  -- empty/off shape — used when the magic plugin emits shield.cleared
  -- after a "Arcane protection for X:-" header or a "X has no arcane
  -- protection" line. The body lines that follow the header repopulate
  -- via on_up; if none arrive the chips stay dim.
  function store.on_cleared(player)
    if type(player) ~= "string" or player == "" then return end
    store.shields[player] = default_row()
  end

  function store.on_player_left(player)
    if type(player) ~= "string" or player == "" then return end
    store.shields[player] = nil
  end

  function store.snapshot_for(player)
    return store.shields[player]
  end

  function store.clear()
    store.shields = {}
  end

  return store
end

-- Exposed for `group.lua` so a member row always has a populated
-- `shields` field even when nothing has been observed for them yet.
function M.default_row()
  return default_row()
end

return M
