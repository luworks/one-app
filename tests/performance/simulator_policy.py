"""Owned performance simulator selection after the PosterBoard incident.

Selection is explicit and versioned; it never boots, erases or configures devices.
A fresh boot observation is not app/measurement acceptance or a permanent fix.
"""
ACTIVE_NAME = 'Today-Performance-Control-20261018'
ACTIVE_UDID = '3C81EAF3-122A-462D-8B6D-9A858EE7E66A'
QUARANTINED_UDID = '3243BEDB-4F6A-4807-AE9E-30115C528377'


def require_active(udid):
    if udid.upper() == QUARANTINED_UDID:
        raise ValueError('Quarantined PosterBoard crash-loop simulator; keep it shut down')
    if udid.upper() != ACTIVE_UDID:
        raise ValueError('Explicit owned performance simulator required; see simulator_policy.py')


def validate_command(name, command):
    if name != ACTIVE_NAME:
        raise ValueError('Retired or unowned simulator name; use ACTIVE_NAME from simulator_policy.py')
    if any(QUARANTINED_UDID in part.upper() for part in command):
        raise ValueError('Command targets the quarantined simulator; it must not run')
    if not any(ACTIVE_UDID in part.upper() for part in command):
        raise ValueError('Command must explicitly include the active simulator UDID')
