"""The Luminar Accord's Undertow light tank, Mk III (Rev 2): see luminar_tank_t2.py."""

from units.luminar_tank_t2 import make


def build(Part):
    return make(Part, 3)
