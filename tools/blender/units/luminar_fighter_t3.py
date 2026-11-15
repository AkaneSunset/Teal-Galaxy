"""The Luminar Accord's fighter, Mk III (Rev 2): see luminar_fighter.py."""

from units.luminar_fighter import make


def build(Part):
    return make(Part, 3)
