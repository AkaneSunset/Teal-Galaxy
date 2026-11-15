"""The Coma Conglomerate's line infantry: one faceless soldier in a sealed graphite shell traced
in gold, a smooth egg of a helmet, a long curved beam rifle held across the body, and a ring of
amber light standing behind one shoulder. The game draws a squad as several of these.

About 2.3 m tall (drawn a little over life size, like the other factions' soldiers).
"""

from units.coma_kit import *  # noqa: F401,F403


def build(Part):
    body, right = Part(), Part()
    # Legs: long and slim, the knee plates swelling, small pointed feet.
    tube(right, [(0.15, 1.08, 0.0), (0.17, 0.58, 0.05), (0.17, 0.1, -0.02)], [0.12, 0.1, 0.08], GRAPHITE, sides=7)
    shell(right, (0.16, 0.85, 0.03), (0.13, 0.24, 0.14), GRAPHITE, PLAIN, "y", sides=8, stacks=4)
    shell(right, (0.17, 0.06, 0.06), (0.08, 0.06, 0.17), GRAPHITE, PLAIN, "y", sides=6, stacks=3)
    # The body: hips, a narrow waist, a curved chest, gold traced down it.
    shell(body, (0, 1.12, 0.0), (0.25, 0.14, 0.15), GRAPHITE, PLAIN, "y", sides=10, stacks=4)
    shell(body, (0, 1.28, 0.0), (0.16, 0.16, 0.12), DEEP, PLAIN, "y", sides=8, stacks=3)
    shell(body, (0, 1.58, 0.01), (0.26, 0.25, 0.17), GRAPHITE, PLAIN, "y", sides=12, stacks=5)
    for sx in (-1, 1):
        tube(body, bezier((sx * 0.06, 1.8, 0.15), (sx * 0.2, 1.6, 0.2), (sx * 0.05, 1.32, 0.13), n=5), 0.014, GOLD, sides=4)
    tube(body, [(-0.17, 1.75, 0.1), (-0.22, 1.5, 0.12)], 0.025, LIT, PAINT, sides=4)
    # The head: a smooth egg of a helmet, a gold line down its middle.
    tube(body, [(0, 1.8, 0.0), (0, 1.9, 0.02)], 0.06, DEEP, sides=6)
    shell(body, (0, 2.06, 0.03), (0.12, 0.17, 0.15), GRAPHITE, PLAIN, "y", sides=10, stacks=6)
    tube(body, bezier((0, 2.24, 0.0), (0, 2.18, 0.17), (0, 1.94, 0.18), n=5), 0.012, GOLD, sides=4)
    # Shoulders and arms, both hands on the rifle.
    shell(right, (0.28, 1.74, 0.0), (0.13, 0.11, 0.14), GRAPHITE, PLAIN, "y", sides=8, stacks=4)
    tube(right, [(0.3, 1.7, 0.0), (0.33, 1.42, 0.1), (0.18, 1.3, 0.3)], [0.06, 0.055, 0.045], GRAPHITE, sides=6)
    tube(body, [(-0.3, 1.7, 0.0), (-0.3, 1.45, 0.18), (-0.08, 1.45, 0.42)], [0.06, 0.055, 0.045], GRAPHITE, sides=6)
    # The rifle: a long curved blade of a gun, held across, gold along its spine.
    gun = bezier((0.36, 1.12, -0.1), (0.05, 1.45, 0.55), (-0.2, 1.36, 1.45), n=10)
    tube(body, gun, taper(10, 0.085, 0.025, 1.0), GRAPHITE, sides=6, squash=0.6)
    tube(body, [(p[0], p[1] + 0.04, p[2]) for p in gun[1:10]], 0.012, GOLD, sides=4)
    body.lathe(gun[-1], (-0.15, -0.05, 1), [(0, 0.022), (0.03, 0.022)], AMBER, GLOW, sides=6)
    # The ring of light behind its left shoulder.
    ring(body, (-0.28, 1.95, -0.18), (0.25, 0, 1), 0.26, 0.012, sides=20)
    body.mirrored(right)
    return {"body": body, "top": None, "top_at": (0, 0, 0), "muzzle": (-0.21, 1.36, 1.5), "view": 0.45}
