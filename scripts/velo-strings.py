# Velo: toglie "Monal" dai valori delle traduzioni (le chiavi restano uguali, servono per la ricerca).
# SPDX-License-Identifier: AGPL-3.0-only
import pathlib, re

line = re.compile(r'^(\s*"(?:[^"\\]|\\.)*"\s*=\s*")(.*)(";\s*)$')
changed = 0
for root in ["Monal/localization", "Monal/shareSheet-iOS/localization"]:
    for f in pathlib.Path(root).rglob("*.strings"):
        raw = f.read_bytes()
        enc = "utf-16" if raw[:2] in (b"\xff\xfe", b"\xfe\xff") else "utf-8"
        text = raw.decode(enc)
        out = []
        for l in text.split("\n"):
            m = line.match(l)
            if m and "Monal" in m.group(2):
                l = m.group(1) + m.group(2).replace("Monal", "Velo") + m.group(3)
                changed += 1
            out.append(l)
        f.write_bytes("\n".join(out).encode(enc))
print("frasi corrette:", changed)
