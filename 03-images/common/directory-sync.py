#!/usr/bin/env python3
"""Copy AD's POSIX users and groups into this container's /etc files.

Run once by session-entrypoint.sh, as root, before it drops to the user.
Afterwards every uidNumber and gidNumber on EFS resolves to a name, so
`ls -l /home` shows edavis rather than 10002.

The result is a snapshot: a user created in AD mid-session shows as a number
until the next session. Sessions last at most 12 hours, and a snapshot needs
no daemon and keeps no credentials after start-up.

Safety rules:
  - Entries without a uidNumber/gidNumber, or below 1000, are skipped.
  - Names must be valid POSIX names; anything else is skipped.
  - Nothing that already exists locally (root, nobody, ...) is replaced,
    by name or by number.

Usage: directory-sync.py <password-file>
  LDAP_URL, LDAP_BASE_DN and LDAP_BIND_DN come from the environment.
"""

import base64
import os
import re
import subprocess
import sys

NAME_RE = re.compile(r"^[a-z_][a-z0-9._-]{0,31}$")
MIN_ID = 1000


def ldap_search(pwfile, ldap_filter, attrs):
    """Run a paged ldapsearch and return its entries.

    Args:
        pwfile: Root-only file holding the bind password.
        ldap_filter: LDAP filter string.
        attrs: Attribute names to request.

    Returns:
        A list of dicts mapping lower-cased attribute name to a list of
        values; the entry's DN is stored under "dn".
    """
    cmd = [
        "ldapsearch", "-x", "-LLL", "-o", "ldif-wrap=no", "-o", "nettimeout=10",
        # AD returns at most 1000 entries per request without paging.
        "-E", "pr=500/noprompt",
        "-H", os.environ["LDAP_URL"], "-D", os.environ["LDAP_BIND_DN"],
        "-y", pwfile, "-b", os.environ["LDAP_BASE_DN"], ldap_filter, *attrs,
    ]
    out = subprocess.run(cmd, check=True, capture_output=True, text=True).stdout

    entries, current = [], {}
    for line in out.splitlines():
        if not line.strip():
            if current:
                entries.append(current)
            current = {}
            continue
        if line.startswith("#") or ":" not in line:
            continue
        key, _, value = line.partition(":")
        # "attr:: value" carries base64 (non-ASCII display names, DNs).
        if value.startswith(":"):
            value = base64.b64decode(value[1:].strip()).decode("utf-8", "replace")
        else:
            value = value.strip()
        current.setdefault(key.lower(), []).append(value)
    if current:
        entries.append(current)
    return entries


def first(entry, attr):
    """Return the first value of attr, or an empty string."""
    return entry.get(attr, [""])[0]


def as_id(value):
    """Return value as an int >= MIN_ID, or None."""
    try:
        number = int(value)
    except ValueError:
        return None
    return number if number >= MIN_ID else None


def clean_gecos(text):
    """Strip characters that would break a passwd line."""
    return re.sub(r"[:,\n\r]", " ", text).strip()


def local_entries(path):
    """Return (names, ids) already present in /etc/passwd or /etc/group."""
    names, ids = set(), set()
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            fields = line.rstrip("\n").split(":")
            if len(fields) >= 3:
                names.add(fields[0])
                ids.add(fields[2])
    return names, ids


def main():
    pwfile = sys.argv[1]

    users = ldap_search(
        pwfile, "(&(objectClass=user)(uidNumber=*)(gidNumber=*))",
        ["sAMAccountName", "uidNumber", "gidNumber", "displayName",
         "givenName", "sn"])
    groups = ldap_search(
        pwfile, "(&(objectClass=group)(gidNumber=*))",
        ["cn", "gidNumber", "member"])

    taken_users, taken_uids = local_entries("/etc/passwd")
    taken_groups, taken_gids = local_entries("/etc/group")

    # ---- users -------------------------------------------------------------
    passwd_lines, shadow_lines = [], []
    name_by_dn = {}
    for entry in users:
        name = first(entry, "samaccountname").lower()
        uid = as_id(first(entry, "uidnumber"))
        gid = as_id(first(entry, "gidnumber"))
        if not NAME_RE.match(name) or uid is None or gid is None:
            continue
        if name in taken_users or str(uid) in taken_uids:
            continue
        gecos = clean_gecos(first(entry, "displayname") or
                            f"{first(entry, 'givenname')} {first(entry, 'sn')}")
        passwd_lines.append(f"{name}:x:{uid}:{gid}:{gecos}:/home/{name}:/bin/bash")
        # Locked password: these accounts are never logged into locally;
        # the entry only keeps PAM (e.g. sudo's account check) satisfied.
        shadow_lines.append(f"{name}:!:::::::")
        taken_users.add(name)
        taken_uids.add(str(uid))
        name_by_dn[entry["dn"][0].lower()] = (name, gid)

    # ---- groups ------------------------------------------------------------
    group_lines = []
    for entry in groups:
        name = first(entry, "cn").lower()
        gid = as_id(first(entry, "gidnumber"))
        if not NAME_RE.match(name) or gid is None:
            continue
        if name in taken_groups or str(gid) in taken_gids:
            continue
        members = sorted(name_by_dn[dn.lower()][0]
                         for dn in entry.get("member", [])
                         if dn.lower() in name_by_dn)
        group_lines.append(f"{name}:x:{gid}:{','.join(members)}")
        taken_groups.add(name)
        taken_gids.add(str(gid))

    # A primary gidNumber with no matching group object still needs a name.
    for name, gid in name_by_dn.values():
        if str(gid) not in taken_gids:
            group_lines.append(f"g{gid}:x:{gid}:")
            taken_gids.add(str(gid))

    for path, lines in (("/etc/passwd", passwd_lines),
                        ("/etc/shadow", shadow_lines),
                        ("/etc/group", group_lines)):
        if lines:
            with open(path, "a", encoding="utf-8") as handle:
                handle.write("\n".join(lines) + "\n")

    print(f"directory-sync: {len(passwd_lines)} users, {len(group_lines)} groups")


if __name__ == "__main__":
    main()
