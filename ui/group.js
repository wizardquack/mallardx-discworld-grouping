// Discworld Grouping — panel UI logic.
//
// Receives panel:post("roster", roster) pushes from Lua and renders
// the compact roster view per spec §4. Sends "refresh" / "refresh_shields"
// to Lua on the heart / shield button clicks, and "ready" on mount.

const titleEl          = document.getElementById("title");
const refreshEl        = document.getElementById("refresh");
const refreshShieldsEl = document.getElementById("refresh-shields");
const emptyEl          = document.getElementById("empty");
const rosterEl         = document.getElementById("roster");

function hpClass(hp) {
  if (hp === null || hp === undefined) return "";
  if (hp > 70) return "";
  if (hp > 40) return "mid";
  if (hp > 20) return "low";
  return "crit";
}

const SHIELD_TYPES  = ["tpa", "ccc", "eff", "bug", "ms"];
const SHIELD_LABEL = { tpa: "TPA", ccc: "CCC", eff: "EFF", bug: "BUG", ms: "MS" };

const TPA_GLOW_TITLE = {
  invisible:           "invisible",
  "dull red":          "dull red",
  "bright red":        "bright red",
  "wobbling orange":   "wobbling orange",
  "flickering yellow": "flickering yellow",
};

function ucfirstWord(s) {
  if (typeof s !== "string" || s.length === 0) return s;
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function tpaPercentClass(percent) {
  if (percent === 100) return "tpa-100";
  if (percent ===  80) return "tpa-80";
  if (percent ===  60) return "tpa-60";
  if (percent ===  40) return "tpa-40";
  if (percent ===  20) return "tpa-20";
  return "";
}

function tooltipFor(type, state) {
  const up = state && state.up;
  if (type === "tpa") {
    if (up && state.glow && state.percent != null) {
      const glow = TPA_GLOW_TITLE[state.glow] || state.glow;
      return `Transcendent Pneumatic Alleviator — ${glow} glow, ${state.percent}%`;
    }
    if (up) return "Transcendent Pneumatic Alleviator (impact shield)";
    return "Transcendent Pneumatic Alleviator (impact shield) — down";
  }
  if (type === "eff") {
    if (up && state.item) return `Endorphin's Floating Friend — ${state.item}`;
    if (up) return "Endorphin's Floating Friend (intercept shield)";
    return "Endorphin's Floating Friend (intercept shield) — down";
  }
  if (type === "ccc") {
    if (up) {
      const sub = state.substance ? ucfirstWord(state.substance) : null;
      const str = state.strength != null ? `${state.strength}/5` : null;
      const detail = [sub, str].filter(Boolean).join(", ");
      if (detail) return `Chrenedict's Corporeal Covering — ${detail}`;
      return "Chrenedict's Corporeal Covering (skin shield)";
    }
    return "Chrenedict's Corporeal Covering (skin shield) — down";
  }
  if (type === "bug") {
    if (up) {
      const size = state.size ? ucfirstWord(state.size) : null;
      const bugs = state.bugs || null;
      const detail = [size, bugs].filter(Boolean).join(" of ");
      if (detail) return `Bugshield — ${detail}`;
      return "Bugshield (insect cloud)";
    }
    return "Bugshield (insect cloud) — down";
  }
  if (type === "ms") {
    if (up) {
      const deity = state.deity || null;
      const str   = state.strength && state.strength !== "" ? state.strength : null;
      if (deity && str) return `Major Shield — ${deity} (${str})`;
      if (deity)        return `Major Shield — ${deity}`;
      return "Major Shield (divine protection)";
    }
    return "Major Shield (divine protection) — down";
  }
  return "";
}

function makeShieldPill(type, state) {
  const pill = document.createElement("span");
  pill.classList.add("pill", type);
  pill.textContent = SHIELD_LABEL[type];
  pill.title = tooltipFor(type, state);
  if (!state || !state.up) return pill;
  if (type === "tpa" && state.percent != null) {
    const cls = tpaPercentClass(state.percent);
    if (cls) { pill.classList.add(cls); return pill; }
  }
  pill.classList.add("on");
  return pill;
}

function makeBar(kind, value) {
  // kind: "hp" | "gp"; value: number 0..100 or null/undefined for unknown.
  const bar = document.createElement("span");
  bar.classList.add("bar", kind);
  if (value === null || value === undefined) {
    bar.classList.add("unknown");
    return bar;
  }
  if (kind === "hp") {
    const cls = hpClass(value);
    if (cls) bar.classList.add(cls);
  }
  const fill = document.createElement("span");
  fill.className = "fill";
  fill.style.width = Math.max(0, Math.min(100, value)) + "%";
  bar.appendChild(fill);
  return bar;
}

function renderRow(m) {
  const li = document.createElement("li");
  li.className = "row";
  if (m.ghost) li.classList.add("ghost");

  const nameLine = document.createElement("div");
  nameLine.className = "name-line";
  const name = document.createElement("span");
  name.className = "name";
  name.textContent = m.name;
  nameLine.appendChild(name);
  if (m.is_self) {
    const tag = document.createElement("span");
    tag.className = "tag-self";
    tag.textContent = "(you)";
    nameLine.appendChild(tag);
  } else if (m.ghost) {
    const tag = document.createElement("span");
    tag.className = "tag-ghost";
    tag.textContent = "ghost";
    nameLine.appendChild(tag);
  }

  li.appendChild(nameLine);
  li.appendChild(makeBar("hp", m.hp));
  li.appendChild(makeBar("gp", m.gp));

  const shields = m.shields || {};
  const shieldRow = document.createElement("div");
  shieldRow.className = "shields";
  for (const t of SHIELD_TYPES) {
    shieldRow.appendChild(makeShieldPill(t, shields[t]));
  }
  li.appendChild(shieldRow);
  return li;
}

function render(roster) {
  const hasName    = roster.group_name !== null && roster.group_name !== undefined;
  const hasMembers = Array.isArray(roster.members) && roster.members.length > 0;
  // Treat "members exist" as grouped even when the name is unknown
  // (mid-session reconnect: we missed the join event, but gsb /
  // group status reveal the roster).
  const grouped = hasName || hasMembers;
  // Show the group name on its own when known; fall back to a static
  // "Group" label otherwise. Avoids the redundant "Group: foo" prefix.
  titleEl.textContent = hasName ? roster.group_name : "Group";
  refreshEl.hidden        = !grouped;
  refreshShieldsEl.hidden = !grouped;
  emptyEl.hidden   = grouped;
  rosterEl.hidden  = !grouped;

  rosterEl.replaceChildren();
  for (const m of roster.members) rosterEl.appendChild(renderRow(m));
}

refreshEl.addEventListener("click", () => {
  refreshEl.classList.add("pending");
  setTimeout(() => refreshEl.classList.remove("pending"), 200);
  panel.post("refresh", {});
});

refreshShieldsEl.addEventListener("click", () => {
  refreshShieldsEl.classList.add("pending");
  setTimeout(() => refreshShieldsEl.classList.remove("pending"), 200);
  panel.post("refresh_shields", {});
});

panel.on("roster", (payload) => render(payload));

// Tell Lua we're mounted; expect a fresh roster push back.
panel.post("ready", {});
