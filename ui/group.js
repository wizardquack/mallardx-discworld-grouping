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

const SHIELD_TYPES  = ["tpa", "eff", "ccc", "bug", "ms"];
const SHIELD_LABEL = { tpa: "TPA", eff: "EFF", ccc: "CCC", bug: "BUG", ms: "MS" };
const SHIELD_TITLE = {
  tpa: "Transcendent Pneumatic Alleviator",
  eff: "Endorphin's Floating Friend",
  ccc: "Chrenedict's Corporeal Covering",
  bug: "Bugshield",
  ms:  "Major Shield",
};

const STATUS_LABEL = { up: "Up", down: "Down", unknown: "Unknown" };
const STATUS_COLOR = { up: "ok", down: "bad", unknown: "muted" };

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

function shieldStatus(state) {
  if (!state) return "unknown";
  return state.up ? "up" : "down";
}

function shieldDetailRows(type, state) {
  if (!state || !state.up) return [];
  const rows = [];
  if (type === "tpa") {
    if (state.glow)            rows.push({ label: "Glow",   value: state.glow });
    if (state.percent != null) rows.push({ label: "Charge", value: `${state.percent}%` });
  } else if (type === "eff") {
    if (state.item) rows.push({ label: "Item", value: state.item });
  } else if (type === "ccc") {
    if (state.substance)        rows.push({ label: "Substance", value: ucfirstWord(state.substance) });
    if (state.strength != null) rows.push({ label: "Strength",  value: `${state.strength}/5` });
  } else if (type === "bug") {
    if (state.size) rows.push({ label: "Size",    value: ucfirstWord(state.size) });
    if (state.bugs) rows.push({ label: "Insects", value: state.bugs });
  } else if (type === "ms") {
    if (state.deity)                                  rows.push({ label: "Deity",    value: state.deity });
    if (state.strength && state.strength !== "")      rows.push({ label: "Strength", value: state.strength });
  }
  return rows;
}

function tooltipPayload(type, state) {
  const status = shieldStatus(state);
  return {
    title: SHIELD_TITLE[type],
    rows: [
      { label: "Status", value: STATUS_LABEL[status], valueColor: STATUS_COLOR[status] },
      ...shieldDetailRows(type, state),
    ],
  };
}

function makeShieldChip(type, state) {
  const chip = document.createElement("span");
  chip.classList.add("chip", type);
  chip.textContent = SHIELD_LABEL[type];
  chip.setAttribute("data-mallard-tooltip", JSON.stringify(tooltipPayload(type, state)));
  if (!state || !state.up) return chip;
  if (type === "tpa" && state.percent != null) {
    const cls = tpaPercentClass(state.percent);
    if (cls) { chip.classList.add(cls); return chip; }
  }
  chip.classList.add("up");
  return chip;
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
    shieldRow.appendChild(makeShieldChip(t, shields[t]));
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
