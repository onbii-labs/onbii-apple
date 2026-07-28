#!/usr/bin/env python3
"""How does recognition hold up across a whole archive?

Runs `coverage.py` over every transcribed object in an archive and sorts the
results by how noisy each recording was. One object tells you how one recording
went; the spread tells you what the recogniser is actually sensitive to.

    ./archive-coverage.py "~/…/Onbii Archive"

Reports, per object: the device that captured it, its own ambient floor, how
much of it is speech-level, and how much of *that* produced no words.

Two caveats, both important before reading anything into the numbers:

- "Speech-level" is 8 dB above each recording's own ambient floor, so a noisy
  recording counts more non-speech as speech-level and its "missed" figure is
  overstated. Compare the ordering, not the absolute values.
- The floor is a property of the room and the input chain together. A device
  that applies automatic gain lifts its own floor, so a high floor does not by
  itself mean a loud place.

Requires ffmpeg on PATH. No third-party Python packages.
"""

import json
import pathlib
import re
import subprocess
import sys

COVERAGE = pathlib.Path(__file__).resolve().parent / "coverage.py"


def measure(bundle: pathlib.Path) -> tuple | None:
    manifest = json.loads((bundle / "manifest.json").read_text())
    source = next(
        (r for r in manifest["resources"] if r.get("role") == "source"), None
    )
    if source is None or not (bundle / source["path"]).exists():
        return None

    captured_by = next(
        (
            event["agent"]["name"]
            for event in manifest["provenance"]
            if event["action"] in ("captured", "imported")
        ),
        "unknown",
    )
    output = subprocess.run(
        [sys.executable, str(COVERAGE), str(bundle)],
        capture_output=True, text=True,
    ).stdout
    floor = re.search(r"ambient floor\s+(-?[\d.]+)", output)
    speech = re.search(r"speech-level audio\s+(\d+)%", output)
    missed = re.search(r"no words\s+(\d+)%", output)
    if not (floor and speech and missed):
        return None

    return (
        bundle.name.removesuffix(".onbii")[:34],
        captured_by.replace(" microphone capture", "").replace(" file import", " import"),
        float(floor.group(1)),
        int(speech.group(1)),
        int(missed.group(1)),
    )


def report(archive: pathlib.Path) -> None:
    rows = [
        row for row in (
            measure(bundle) for bundle in sorted(archive.glob("*.onbii"))
            if (bundle / "derived" / "transcript.json").exists()
        ) if row
    ]
    rows.sort(key=lambda row: row[2])

    print(f"{'object':<34} {'captured by':<14} {'floor':>8} {'speech':>7} {'missed':>7}")
    for name, captured_by, floor, speech, missed in rows:
        print(f"{name:<34} {captured_by:<14} {floor:>8.1f} {speech:>6}% {missed:>6}%")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(f"usage: {sys.argv[0]} <archive directory>")
    report(pathlib.Path(sys.argv[1]).expanduser())
