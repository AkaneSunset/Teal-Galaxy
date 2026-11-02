// Titles for helping win a planet. Every campaign match a pilot's side wins on a planet credits
// them the points it scored, by mode. When the campaign ends, each pilot of the faction that won
// the planet (took it, or held it) with titles.points (500) or more in one mode earns that mode's
// title for the planet: 500 points won for Cinder in Space Battles is "Ghost of Cinder". Titles are
// prestige only; nothing in a fight reads them.
//
// In the galaxy as g.titles: credit (planet -> this campaign's points by mode and pilot; never sent
// to apps but each pilot's own) and the titles themselves on each pilot's record (pilots[].titles,
// which everyone sees).

const T = require('./tunables.ts');

// Each mode's title, before the planet's name.
const TITLES: Record<string, string> = {
  sector: 'Warlord of',
  supremacy: 'Lion of',
  space: 'Ghost of',
  facility: 'Champion of',
  defense: 'Bulwark of',
};

interface Credit {
  campaign: number; // the campaign's startsAt these points are for
  modes: Record<string, Record<string, { faction: string; points: number }>>; // mode -> pilot -> points
}
interface Galaxy {
  titles?: { credit: Record<string, Credit> };
  pilots?: Record<string, { titles?: string[]; [key: string]: unknown }>;
  war: {
    campaigns?: Record<string, { startsAt: number; endsAt: number }>;
    planets: { id: string; name: string }[];
  };
  [key: string]: unknown;
}
type Award = { name: string; title: string; mode: string; points: number };

const round1 = (x: number) => Math.round(x * 10) / 10;

function titleFor(mode: string, planetName: string): string | null {
  return TITLES[mode] ? `${TITLES[mode]} ${planetName}` : null;
}

// The planet's credit for the campaign running there, started afresh when a new one begins.
function creditOf(g: Galaxy, planet: string): Credit | null {
  const c = g.war.campaigns?.[planet];
  if (!c) return null;
  g.titles ||= { credit: {} };
  const cur = g.titles.credit[planet];
  if (cur && cur.campaign === c.startsAt) return cur;
  return (g.titles.credit[planet] = { campaign: c.startsAt, modes: {} });
}

// A campaign match on `planet` won by `faction` scored `points`: each of `names` (the winning side's
// pilots) is credited them. Returns each pilot's total in that mode now.
function credit(g: Galaxy, { planet, mode, faction, names, points }: { planet: string; mode: string; faction: string; names: string[]; points: number }): Record<string, number> {
  const out: Record<string, number> = {};
  const cr = points > 0 && TITLES[mode] ? creditOf(g, planet) : null;
  if (!cr) return out;
  const by = (cr.modes[mode] ||= {});
  for (const name of new Set(names)) {
    const e = (by[name] ||= { faction, points: 0 });
    if (e.faction !== faction) Object.assign(e, { faction, points: 0 }); // points count for one side
    e.points = round1(e.points + points);
    out[name] = e.points;
  }
  return out;
}

// A pilot's points this campaign on every planet, by mode, with what each title needs: for their
// app (welcome, and after each match they win).
function progress(g: Galaxy, name: string): { planet: string; mode: string; points: number; title: string | null; need: number }[] {
  const need = T.get().titles.points;
  const out = [];
  for (const [planet, cr] of Object.entries(g.titles?.credit || {})) {
    if (cr.campaign !== g.war.campaigns?.[planet]?.startsAt) continue;
    const wp = g.war.planets.find((p) => p.id === planet);
    for (const [mode, by] of Object.entries(cr.modes)) if (by[name]) out.push({ planet, mode, points: by[name].points, title: titleFor(mode, wp?.name || planet), need });
  }
  return out;
}

// A planet's campaign ended and `winner` took or held it: every one of its pilots with enough
// points in a mode earns that mode's title for the planet (once; a pilot keeps it). Returns the
// awards, for the war log. The planet's credit is cleared.
function award(g: Galaxy, planet: string, winner: string | null): Award[] {
  const cr = g.titles?.credit[planet];
  if (!cr) return [];
  delete g.titles!.credit[planet];
  if (!winner) return [];
  const need = T.get().titles.points;
  const wp = g.war.planets.find((p) => p.id === planet);
  const out: Award[] = [];
  for (const [mode, by] of Object.entries(cr.modes)) {
    const title = titleFor(mode, wp?.name || planet);
    if (!title) continue;
    for (const [name, e] of Object.entries(by)) {
      if (e.faction !== winner || e.points < need) continue;
      const p = g.pilots?.[name];
      if (!p) continue;
      p.titles ||= [];
      if (!p.titles.includes(title)) p.titles.push(title);
      out.push({ name, title, mode, points: e.points });
    }
  }
  return out;
}

module.exports = { TITLES, titleFor, credit, progress, award };
