# Monetization charter

Teal Galaxy is a war between players. Whatever money buys must never change who wins it. This charter
(guide MON-01) is the rule every future store, price and offer is checked against, and it holds before
anything is ever sold: nothing is on sale today.

## Never for sale

- **Power.** No stats, weapons, armour, units, unit caps, ship hulls, building levels, production rates
  or anything else that makes a pilot, a Builder or a faction stronger in a fight or an economy.
- **The war.** War supply, campaign points, orbital control, War Merit and its ranks, faction orders and
  their rewards, planets and sectors. No paid side switch, and nothing that lifts or shortens a side
  lock.
- **Time over other players.** No paid timers, build or travel speed-ups, cooldown skips, jumps,
  queue priority or extra matches.
- **The Coma director.** No paid say in where the Coma pushes, holds or eases off, and nothing that
  makes it go easy on a faction.
- **Randomness.** No loot boxes, paid rolls, gacha or mystery bundles. Whoever pays sees exactly what
  they get before they pay.
- **Information.** No paid intelligence on enemy orders, outposts, fleets or players. Intelligence is
  earned in play, from raids and outpost vaults.

## What may be sold later (Phase 6 at the earliest)

- **Cosmetics only:** paint, decals, carrier and base trim, emotes, nameplates. Titles, monuments and
  commendations earned in the war are never sold, so seeing one always means someone earned it.
- **One premium currency at most,** and every price is shown in real money next to it. Bundles never
  leave a currency remainder that only another purchase can use up.
- **Warbonds** (cosmetic tracks) are bought outright, never expire, and pay out what they list.

## How the store behaves

- No countdowns, "last chance" offers or pressure timers. Anything sold now is sold again.
- No hidden prices. A bundle shows what each part costs on its own.
- Parental controls: spending limits and an off switch, on by default for younger accounts.
- Refunds, age rules and consumer law are reviewed by counsel (the guide's L5 to L8) before the store
  opens, and the store does not open until they are.

## How this is enforced

- The server never reads purchases when it decides a fight, a match, a raid, a ledger credit, an order or
  a campaign. Purchases live apart from the galaxy state those rules read.
- `server/tunables.json` holds every rule number, and none of its fields is paid or tied to a purchase.
  Its schema check (`server/tunables.ts`) rejects unknown fields, so one can't be slipped in.
- A change to this charter, or to what is sold, is announced 30 days ahead, and never takes away
  anything already bought.
