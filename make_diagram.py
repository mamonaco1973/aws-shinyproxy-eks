#!/usr/bin/env python3
"""Generate the README architecture diagram, one SVG per colour scheme.

Two files rather than one self-switching file: GitHub strips <style> blocks
from inline SVG, so a `prefers-color-scheme` media query inside the document is
silently dropped. The README pairs them with <picture>, which GitHub honours.

A README diagram is studied, not narrated, so it is COMPLETE rather than
minimal: the ECS control plane, the image registry, the secret store, the NAT
gateway and the Samba gateway's view of EFS are all on it. The Windows admin
host is the one omission -- it administers AD and plays no part in a session.

Run:  python3 make_diagram.py
"""

import os

HERE = os.path.dirname(os.path.abspath(__file__))

# ------------------------------------------------------------------------------
# Geometry and style (shared with the other projects' diagrams)
# ------------------------------------------------------------------------------
NW, NH = 420, 110                          # node width, height
GUTTER = 200                               # between columns: room for a label
MARGIN = 40
COL = [MARGIN + i * (NW + GUTTER) for i in range(3)]
ROW = [40, 240, 440, 640]
W = MARGIN * 2 + NW * 3 + GUTTER * 2
H = ROW[3] + NH + 40
TITLE_PX, SUB_PX, EDGE_PX = 26, 17, 16

THEMES = {
    "dark": {
        "bg": "#0d1117", "panel": "#161b22", "text": "#e6edf3",
        "muted": "#8b949e", "line": "#58a6ff", "local": "#39c5bb",
        "purple": "#c39be8", "navy": "#c8d6e8", "blue": "#58a6ff",
        "amber": "#f2c163", "store": "#7ee787",
    },
    "light": {
        "bg": "#ffffff", "panel": "#f6f8fa", "text": "#1f2328",
        "muted": "#59636e", "line": "#0969da", "local": "#137e77",
        "purple": "#8250df", "navy": "#475467", "blue": "#0969da",
        "amber": "#9a6700", "store": "#1a7f37",
    },
}

# Lucide icon paths, on a 24-unit grid.
ICONS = {
    "globe": ['<circle cx="12" cy="12" r="10"/>',
              '<path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/>',
              '<path d="M2 12h20"/>'],
    "route": ['<circle cx="6" cy="19" r="3"/>', '<circle cx="18" cy="5" r="3"/>',
              '<path d="M12 19h4.5a3.5 3.5 0 0 0 0-7h-8a3.5 3.5 0 0 1 0-7H12"/>'],
    "network": ['<rect x="16" y="16" width="6" height="6" rx="1"/>',
                '<rect x="2" y="16" width="6" height="6" rx="1"/>',
                '<rect x="9" y="2" width="6" height="6" rx="1"/>',
                '<path d="M5 16v-3a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v3"/>',
                '<path d="M12 12V8"/>'],
    "layers": ['<path d="m12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83'
               'l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/>',
               '<path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/>',
               '<path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/>'],
    "database": ['<ellipse cx="12" cy="5" rx="9" ry="3"/>',
                 '<path d="M3 5V19A9 3 0 0 0 21 19V5"/>',
                 '<path d="M3 12A9 3 0 0 0 21 12"/>'],
    "key": ['<path d="M2.586 17.414A2 2 0 0 0 2 18.828V21a1 1 0 0 0 1 1h3a1 1 0 0 0 '
            '1-1v-1a1 1 0 0 1 1-1h1a1 1 0 0 0 1-1v-1a1 1 0 0 1 1-1h.172a2 2 0 0 0 '
            '1.414-.586l.814-.814a6.5 6.5 0 1 0-4-4z"/>',
            '<circle cx="16.5" cy="7.5" r=".5"/>'],
    "monitor": ['<rect width="20" height="14" x="2" y="3" rx="2"/>',
                '<line x1="8" x2="16" y1="21" y2="21"/>',
                '<line x1="12" x2="12" y1="17" y2="21"/>'],
    "terminal": ['<polyline points="4 17 10 11 4 5"/>',
                 '<line x1="12" x2="20" y1="19" y2="19"/>'],
    "users": ['<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/>',
              '<circle cx="9" cy="7" r="4"/>',
              '<path d="M22 21v-2a4 4 0 0 0-3-3.87"/>',
              '<path d="M16 3.13a4 4 0 0 1 0 7.75"/>'],
    "shield": ['<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 '
               '4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 '
               '1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/>'],
    "code": ['<polyline points="16 18 22 12 16 6"/>',
             '<polyline points="8 6 2 12 8 18"/>'],
    "package": ['<path d="m7.5 4.27 9 5.15"/>',
                '<path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 '
                '3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/>',
                '<path d="m3.3 7 8.7 5 8.7-5"/>', '<path d="M12 22V12"/>'],
    "folder": ['<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9'
               'L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>'],
    "server": ['<rect width="20" height="8" x="2" y="2" rx="2" ry="2"/>',
               '<rect width="20" height="8" x="2" y="14" rx="2" ry="2"/>',
               '<line x1="6" x2="6.01" y1="6" y2="6"/>',
               '<line x1="6" x2="6.01" y1="18" y2="18"/>'],
}

NODES = {}


def _r(nid):
    """Return (left, top, right, bottom, centre-x, centre-y) for a node."""
    x, y = NODES[nid][0], NODES[nid][1]
    return x, y, x + NW, y + NH, x + NW / 2, y + NH / 2


def gutter_x(c):
    """Centre of the gutter to the right of column c."""
    return COL[c] + NW + GUTTER / 2


# ------------------------------------------------------------------------------
# Layout
# ------------------------------------------------------------------------------
# The request path runs down the middle column: browser -> ALB -> ShinyProxy
# -> the user's session task -> EFS. ShinyProxy and the session tasks are the
# subject (amber) and share a dashed ECS-cluster boundary. Identity sits on
# the left (domain controller, and the Samba gateway joined to it); the AWS
# services ECS leans on stack down the right: Secrets Manager injects the
# bind password, ECR supplies both images, the NAT gateway carries outbound
# traffic from the private tasks.
#
# id: (x, y, colour key, icon, title, subtitle)
NODES.update({
    "browser":  (COL[0], ROW[0], "navy", "globe", "Browser", "HTTPS only, no client"),
    "alb":      (COL[1], ROW[0], "blue", "route", "Load Balancer",
                 "self-signed cert, public subnets"),
    "secrets":  (COL[2], ROW[0], "store", "key", "Secrets Manager",
                 "AD + LDAP bind credentials"),
    "dc":       (COL[0], ROW[1], "purple", "users", "mini-AD (Samba DC)",
                 "users, groups, uid/gid, DNS"),
    "sp":       (COL[1], ROW[1], "amber", "shield", "ShinyProxy",
                 "ECS service, 1 task: login + proxy"),
    "ecs":      (COL[2], ROW[1], "blue", "layers", "ECS / Fargate",
                 "runs a task definition per session"),
    "gateway":  (COL[0], ROW[2], "navy", "server", "Samba Gateway",
                 "domain-joined EC2, SMB view of EFS"),
    "sessions": (COL[1], ROW[2], "amber", "code", "App Sessions",
                 "VS Code or RStudio, 1 task per user"),
    "ecr":      (COL[2], ROW[2], "store", "package", "ECR",
                 "VS Code, RStudio, ShinyProxy"),
    "efs":      (COL[1], ROW[3], "store", "folder", "EFS",
                 "/home and /efs, shared"),
    "nat":      (COL[2], ROW[3], "navy", "network", "NAT Gateway",
                 "outbound for the private tasks"),
})

alb, brw, sec = _r("alb"), _r("browser"), _r("secrets")
dc, sp, ecs = _r("dc"), _r("sp"), _r("ecs")
gw, ss, ecr = _r("gateway"), _r("sessions"), _r("ecr")
efs, nat = _r("efs"), _r("nat")
OFF = 22                      # lines entering a side above/below its centre

# id: (path, colour key, label, label_x, label_y, anchor)
EDGES = {
    "e_https":  (f"M{brw[2]},{brw[5]} L{alb[0] - 5},{alb[5]}", "line",
                 "HTTPS :443", gutter_x(0), brw[5] - 12, "middle"),
    "e_alb":    (f"M{alb[4]},{alb[3]} L{alb[4]},{sp[1] - 5}", "line",
                 "HTTP :8080", alb[4] - 16, (alb[3] + sp[1]) / 2 + 6, "end"),
    "e_signin": (f"M{sp[0]},{sp[5] - OFF} L{dc[2] + 5},{dc[5] - OFF}", "purple",
                 "LDAP sign-in", gutter_x(0), sp[5] - OFF - 12, "middle"),
    "e_run":    (f"M{sp[2]},{sp[5] - OFF} L{ecs[0] - 5},{ecs[5] - OFF}", "blue",
                 "RunTask / StopTask", gutter_x(1), sp[5] - OFF - 12, "middle"),
    "e_secret": (f"M{sec[4]},{sec[3]} L{sec[4]},{ecs[1] - 5}", "store",
                 "bind password", sec[4] + 14, (sec[3] + ecs[1]) / 2 + 6, "start"),
    "e_ecr":    (f"M{ecr[4]},{ecr[1]} L{ecr[4]},{ecs[3] + 5}", "store",
                 "image pulls", ecr[4] + 14, (ecs[3] + ecr[1]) / 2 + 6, "start"),
    "e_launch": (f"M{ecs[0]},{ecs[5] + OFF} H{gutter_x(1)} V{ss[5] - OFF} "
                 f"H{ss[2] + 5}", "blue",
                 "launches", gutter_x(1) + 12, (ecs[5] + ss[5]) / 2 + 6, "start"),
    "e_proxy":  (f"M{sp[4]},{sp[3]} L{sp[4]},{ss[1] - 5}", "amber",
                 "HTTP + WebSocket", sp[4] - 16, (sp[3] + ss[1]) / 2 + 6, "end"),
    "e_uid":    (f"M{ss[0]},{ss[5] - OFF} H{gutter_x(0)} V{dc[5] + OFF} "
                 f"H{dc[2] + 5}", "purple",
                 "LDAP uid/gid", gutter_x(0) - 12, (dc[5] + ss[5]) / 2 + 6, "end"),
    "e_nfs":    (f"M{ss[4]},{ss[3]} L{ss[4]},{efs[1] - 5}", "store",
                 "NFS (TLS)", ss[4] + 14, (ss[3] + efs[1]) / 2 + 6, "start"),
    "e_nat":    (f"M{ss[2]},{ss[5] + OFF} H{gutter_x(1)} V{nat[5]} H{nat[0] - 5}",
                 "navy", "Open VSX, CRAN", gutter_x(1) + 12, (ss[5] + nat[5]) / 2 + 20,
                 "start"),
    "e_smb":    (f"M{gw[4]},{gw[3]} V{efs[5]} H{efs[0] - 5}", "store",
                 "NFS mount, SMB out", (gw[4] + efs[0]) / 2, efs[5] - 12, "middle"),
    "e_member": (f"M{gw[4]},{gw[1]} L{gw[4]},{dc[3] + 5}", "purple",
                 "domain member", gw[4] + 14, (dc[3] + gw[1]) / 2 + 6, "start"),
}

# The ECS cluster: ShinyProxy and every session task run inside it.
PAD = 18
CLUSTER = (sp[0] - PAD, sp[1] - PAD, NW + PAD * 2, ss[3] - sp[1] + PAD * 2)
CLUSTER_LABEL = "ECS cluster (Fargate)"

ALT = ("A browser reaches an internet-facing load balancer over HTTPS; it forwards "
       "to ShinyProxy, an ECS service, which signs users in against the mini-AD "
       "domain controller over LDAP, then calls ECS RunTask to launch a dedicated "
       "Fargate task running the chosen app, VS Code or RStudio, for each user "
       "and proxies HTTP and WebSocket traffic to it. ECS pulls the images from ECR and injects the "
       "LDAP bind password from Secrets Manager. Each session task resolves the "
       "user's uid and gid over LDAP, mounts the shared EFS file system for "
       "/home and /efs, and reaches Open VSX and package mirrors through a NAT "
       "gateway. A domain-joined Samba gateway mounts the same EFS file system "
       "and shares it over SMB.")

# ------------------------------------------------------------------------------
# Rendering
# ------------------------------------------------------------------------------
FONT = "-apple-system, BlinkMacSystemFont, Segoe UI, Helvetica, Arial, sans-serif"


def node_svg(nid, t):
    """Render one service box: rounded panel, icon, title, subtitle."""
    x, y, key, icon, title, sub = NODES[nid]
    colour = t[key]
    scale = 1.25
    isz = 24 * scale
    ix, iy = x + 20, y + (NH - isz) / 2
    tx = x + 20 + isz + 14
    return "".join([
        f'<rect x="{x}" y="{y}" width="{NW}" height="{NH}" rx="10" ry="10" '
        f'fill="{t["panel"]}" stroke="{colour}" stroke-width="2"/>',
        f'<g transform="translate({ix},{iy}) scale({scale})" fill="none" '
        f'stroke="{colour}" stroke-width="2" stroke-linecap="round" '
        f'stroke-linejoin="round">' + "".join(ICONS[icon]) + "</g>",
        f'<text x="{tx}" y="{y + NH/2 - 4}" font-family="{FONT}" '
        f'font-size="{TITLE_PX}" font-weight="600" fill="{t["text"]}">{title}</text>',
        f'<text x="{tx}" y="{y + NH/2 + 22}" font-family="{FONT}" '
        f'font-size="{SUB_PX}" fill="{t["muted"]}">{sub}</text>',
    ])


def edge_svg(eid, t):
    """Render one arrow plus its label (on a background chip, so lines that
    pass behind a label never cut through its text)."""
    d, key, label, lx, ly, anchor = EDGES[eid]
    colour = t[key]
    out = (f'<path d="{d}" fill="none" stroke="{colour}" stroke-width="2" '
           f'marker-end="url(#a_{eid})"/>')
    if label:
        out += (f'<text x="{lx}" y="{ly}" text-anchor="{anchor}" '
                f'font-family="{FONT}" font-size="{EDGE_PX}" font-weight="600" '
                f'fill="{colour}" stroke="{t["bg"]}" stroke-width="6" '
                f'paint-order="stroke">{label}</text>')
    return out


def build(t):
    """Assemble the diagram for one theme."""
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
           f'viewBox="0 0 {W} {H}" role="img" aria-label="{ALT}">', "<defs>"]
    # One marker per edge: a shared marker cannot carry per-edge colour.
    for eid, spec in EDGES.items():
        out.append(
            f'<marker id="a_{eid}" viewBox="0 0 10 10" refX="9" refY="5" '
            f'markerWidth="5" markerHeight="5" orient="auto-start-reverse">'
            f'<path d="M0,0 L10,5 L0,10 z" fill="{t[spec[1]]}"/></marker>')
    out.append("</defs>")
    out.append(f'<rect width="{W}" height="{H}" fill="{t["bg"]}"/>')
    cx, cy, cw, ch = CLUSTER
    out.append(f'<rect x="{cx}" y="{cy}" width="{cw}" height="{ch}" rx="14" '
               f'ry="14" fill="none" stroke="{t["muted"]}" stroke-width="1.5" '
               f'stroke-dasharray="7 6"/>')
    for eid in EDGES:
        out.append(edge_svg(eid, t))
    for nid in NODES:
        out.append(node_svg(nid, t))
    # Below the boundary, clear of the NFS line running down its centre.
    out.append(f'<text x="{cx + 12}" y="{cy + ch + 22}" font-family="{FONT}" '
               f'font-size="{EDGE_PX}" font-weight="600" fill="{t["muted"]}">'
               f'{CLUSTER_LABEL}</text>')
    out.append("</svg>")
    return "".join(out)


def main():
    for name, theme in THEMES.items():
        path = os.path.join(HERE, f"architecture-{name}.svg")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(build(theme))
        print(f"  architecture-{name}.svg")


if __name__ == "__main__":
    main()
