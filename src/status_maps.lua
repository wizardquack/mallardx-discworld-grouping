-- Word-status → percentage tables for discworld-grouping.
--
-- Ported verbatim from Quow's QuowMinimap.xml lines 26202–26228.
-- Pure data; loaded into a vanilla mlua::Lua state by the unit tests
-- in src-tauri/tests/discworld_grouping_plugin.rs.

return {
  hp = {
    ["unhurt"]              = 100,
    ["almost unhurt"]       = 95,
    ["scratched"]           = 90,
    ["slightly hurt"]       = 80,
    ["slightly injured"]    = 70,
    ["injured"]             = 60,
    ["slightly wounded"]    = 50,
    ["wounded"]             = 40,
    ["badly wounded"]       = 30,
    ["heavily wounded"]     = 20,
    ["seriously wounded"]   = 15,
    ["critically wounded"]  = 10,
    ["near death"]          = 5,
  },
  gp = {
    ["refreshed"]           = 100,
    ["clear of mind"]       = 90,
    ["concentrated"]        = 80,
    ["slightly confused"]   = 70,
    ["confused"]            = 60,
    ["slightly fatigued"]   = 50,
    ["fatigued"]            = 40,
    ["very fatigued"]       = 30,
    ["highly fatigued"]     = 20,
    ["severely fatigued"]   = 10,
    ["near unconscious"]    = 5,
  },
}
