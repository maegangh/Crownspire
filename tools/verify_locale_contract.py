#!/usr/bin/env python3
"""Verify crownspire_ui locale CSV vs compiled Translation resources.

Checks key counts, Citadel English terminology, and Turkish internal consistency.
Does not rewrite translations.
"""

from __future__ import annotations

import csv
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCALE_DIR = ROOT / "locales"
CSV_PATH = LOCALE_DIR / "crownspire_ui.csv"
EN_TRES = LOCALE_DIR / "crownspire_ui.en.tres"
TR_TRES = LOCALE_DIR / "crownspire_ui.tr.tres"

KEY_RE = re.compile(r'\[&"",\s*&"([^"]+)"\]:\s*\[&"(.*?)"\]', re.DOTALL)
EXPECTED_CITADEL = {
    "HUD_CASTLE": "CASTLE",
    "PROFILE_CITADEL": "Citadel",
    "PROFILE_LOCATION_SHARED": "Castle location shared to Kingdom Chat.",
    "PROFILE_CASTLE_SHARE_LABEL_FMT": "[Castle] %s",
}
EXPECTED_TR = {
    "HUD_CASTLE": "KALE",
    "PROFILE_CITADEL": "KALE",
    "PROFILE_CASTLE_SHARE_LABEL_FMT": "[Kale] %s",
}


def tres_messages(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    out: dict[str, str] = {}
    for m in KEY_RE.finditer(text):
        out[m.group(1)] = m.group(2).replace("\\n", "\n")
    return out


def main() -> int:
    errors: list[str] = []
    with CSV_PATH.open(encoding="utf-8", newline="") as f:
        rows = list(csv.DictReader(f))
    csv_keys = [r["keys"] for r in rows]
    csv_en = {r["keys"]: r["en"] for r in rows}
    csv_tr = {r["keys"]: r["tr"] for r in rows}
    if len(csv_keys) != len(set(csv_keys)):
        errors.append("CSV has duplicate keys")
    if len(csv_keys) != 137:
        errors.append(f"CSV key count {len(csv_keys)} != 137")

    if not EN_TRES.is_file():
        errors.append("missing en.tres")
        print("\n".join(errors))
        return 1
    en = tres_messages(EN_TRES)
    if set(en) != set(csv_keys):
        missing = sorted(set(csv_keys) - set(en))
        extra = sorted(set(en) - set(csv_keys))
        if missing:
            errors.append(f"en.tres missing keys: {missing}")
        if extra:
            errors.append(f"en.tres extra keys: {extra}")

    for key, expected in EXPECTED_CITADEL.items():
        if csv_en.get(key) != expected:
            errors.append(f"CSV en {key} expected {expected!r} got {csv_en.get(key)!r}")
        if en.get(key) != expected:
            errors.append(f"en.tres {key} expected {expected!r} got {en.get(key)!r}")

    if TR_TRES.is_file():
        tr = tres_messages(TR_TRES)
        if set(tr) != set(csv_keys):
            missing = sorted(set(csv_keys) - set(tr))
            extra = sorted(set(tr) - set(csv_keys))
            if missing:
                errors.append(f"tr.tres missing keys: {missing}")
            if extra:
                errors.append(f"tr.tres extra keys: {extra}")
        for key, expected in EXPECTED_TR.items():
            if csv_tr.get(key) != expected:
                errors.append(f"CSV tr {key} expected {expected!r} got {csv_tr.get(key)!r}")
            if tr.get(key) != expected:
                errors.append(f"tr.tres {key} expected {expected!r} got {tr.get(key)!r}")
        if "Citadel" in csv_tr.get("HUD_CASTLE", "") or "Citadel" in csv_tr.get("PROFILE_CITADEL", ""):
            errors.append("Turkish HUD/PROFILE citadel keys unexpectedly switched to English Citadel")

    translation_bins = list(LOCALE_DIR.glob("*.translation"))
    if errors:
        for e in errors:
            print(f"[locale] FAIL: {e}")
        return 1
    print(
        f"[locale] PASS — {len(csv_keys)} keys; Citadel EN OK; Turkish KALE consistent; "
        f"{len(translation_bins)} .translation binaries present"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
