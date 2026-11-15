"""The Ashen Collective's air transport (provisional): a fixed-wing airlifter for two infantry
squads. A long faceted fuselage to a sharp nose, a high straight wing, two podded jet engines
under it with lit fans, and a faceted T-tail. Lines of the side's light along its seams.

About 18 m long and 19 m across. The origin is its middle.
"""

from units.ashen_kit import *  # noqa: F401,F403


def build(Part):
    body, right = Part(), Part()
    loft(body, [(-9.2, 2.2, 0.35, 0.35), (-6.4, 1.1, 1.3, 1.0), (-2.5, 0.4, 1.8, 1.55), (2.5, 0.35, 1.8, 1.5), (5.8, 0.05, 1.1, 1.0), (8.8, -0.5, 0.0, 0.0)])
    loft(body, [(3.4, 1.4, 0.0, 0.0), (4.4, 1.45, 0.75, 0.3), (5.8, 1.0, 0.55, 0.2), (6.4, 0.75, 0.0, 0.0)], GLASS)
    # The high wing and its root fairing.
    plate(right, [(0.8, 1.6), (9.4, 0.4), (9.4, -0.9), (0.8, -1.3)], 1.75, 0.3, bevel=0.25)
    loft(body, [(-1.6, 1.75, 0.0, 0.0), (-0.8, 1.85, 1.1, 0.35), (1.4, 1.85, 1.1, 0.35), (2.2, 1.75, 0.0, 0.0)])
    edge(right, (0.9, 1.75, 1.62), (9.35, 1.75, 0.45), 0.07, 0.08, face=(0, 0, 1))
    edge(right, (1.75, 0.6, 2.5), (1.6, 0.9, -5.5), 0.06, 0.06, face=(1, 0, 0))
    # Engines on pylons under the wing.
    engine(right, (3.8, 0.85, 1.9), 0.8, 3.2, intake=True)
    right.box((0.25, 0.8, 1.6), (3.8, 1.35, 0.4), PLATE)
    # The T-tail.
    fin(body, (0.0, 1.8, -5.6), (0.0, 5.2, -8.0), 3.2, 1.8, 0.24)
    plate(right, [(0.0, -7.6), (3.6, -8.7), (3.6, -9.4), (0.0, -9.6)], 5.2, 0.18)
    edge(body, (0.0, 5.32, -8.0), (0.0, 5.32, -9.6), 0.06, 0.06, face=(0, 1, 0))
    hexagon(body, (0, 1.95, -3.2), 0.45, (0, 1, 0), RAISED, PLAIN)
    body.mirrored(right)
    fly = 12.0
    return {"body": body, "top": None, "top_at": (0, 0, 0), "views": air_views(fly, 1.15), "fly": fly, "span": 3.0}
