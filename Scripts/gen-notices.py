#!/usr/bin/env python3
"""Writes THIRD_PARTY_NOTICES.md and the legal files the app bundles (LEGAL_DOCS.md L3).

Inputs:
  Package.resolved         Swift packages: identity, version, URL.
  Licenses/packages.json   Per package: display name, use, SPDX id, whether it ships in Murmur.app,
                           and its license files (paths inside the package checkout, copied under
                           Licenses/packages/<identity>/ by --refresh-from; "manual_files" are kept by hand).
  Licenses/manual.json     Fonts, model weights and shared license texts (anything not a Swift package).
  LICENSE, PRIVACY.md      Murmur's own license and privacy notes.

Outputs:
  THIRD_PARTY_NOTICES.md
  Sources/UI/Resources/Legal/{LICENSE, PRIVACY.md, THIRD_PARTY_NOTICES.md, notices.json}

Usage:
  Scripts/gen-notices.py                          regenerate the outputs
  Scripts/gen-notices.py --check                  fail if an output is stale or a package lacks notices (CI)
  Scripts/gen-notices.py --refresh-from DIR       copy package license files from SwiftPM checkouts in DIR
                                                  (e.g. App/build/SourcePackages/checkouts), then regenerate

Standard library only, so it runs on CI without Swift.
"""
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LICENSES = ROOT / "Licenses"
LEGAL = ROOT / "Sources" / "UI" / "Resources" / "Legal"
NOTICES = ROOT / "THIRD_PARTY_NOTICES.md"


class NoticeError(Exception):
    pass


def read(path):
    return path.read_text(encoding="utf-8")


def load_inputs(root=ROOT):
    licenses = root / "Licenses"
    resolved = json.loads(read(root / "Package.resolved"))
    pins = {pin["identity"]: pin for pin in resolved["pins"]}
    packages = json.loads(read(licenses / "packages.json"))
    manual = json.loads(read(licenses / "manual.json"))
    return pins, packages, manual


def problems(pins, packages, manual, root=ROOT):
    """Everything that makes the notices incomplete. Empty when all is well."""
    licenses = root / "Licenses"
    found = []
    for identity in sorted(set(pins) - set(packages)):
        found.append(f"Package.resolved lists '{identity}', which Licenses/packages.json doesn't describe. "
                     f"Add it there, then run Scripts/gen-notices.py --refresh-from <checkouts>.")
    for identity in sorted(set(packages) - set(pins)):
        found.append(f"Licenses/packages.json describes '{identity}', which Package.resolved no longer lists. Remove it.")
    for identity, info in sorted(packages.items()):
        for key in ("name", "use", "spdx", "shipped", "files"):
            if key not in info:
                found.append(f"Licenses/packages.json: '{identity}' has no '{key}'.")
        for rel in info.get("files", []) + info.get("manual_files", []):
            if not (licenses / "packages" / identity / rel).is_file():
                found.append(f"Missing license file Licenses/packages/{identity}/{rel}.")
    for font in manual.get("fonts", []):
        for rel in font["files"]:
            if not (licenses / rel).is_file():
                found.append(f"Missing license file Licenses/{rel}.")
        bundled = root / font["bundled_copy"]
        if not bundled.is_file():
            found.append(f"Missing bundled font license {font['bundled_copy']}.")
        elif any((licenses / rel).is_file() and read(licenses / rel) != read(bundled) for rel in font["files"]):
            found.append(f"{font['bundled_copy']} differs from Licenses/{font['files'][0]}.")
    for text in manual.get("texts", []):
        if not (licenses / text["file"]).is_file():
            found.append(f"Missing license file Licenses/{text['file']}.")
    spdx_texts = {text["spdx"] for text in manual.get("texts", [])}
    for model in manual.get("models", []):
        if model["spdx"] not in spdx_texts:
            found.append(f"Model '{model['name']}' is {model['spdx']}, which has no entry in manual.json 'texts'.")
    return found


def package_url(pin):
    url = pin["location"]
    return url[:-4] if url.endswith(".git") else url


def package_texts(identity, info, root=ROOT):
    base = root / "Licenses" / "packages" / identity
    return [(rel, read(base / rel)) for rel in info["files"] + info.get("manual_files", [])]


def model_text_name(model, manual):
    return next(t["name"] for t in manual["texts"] if t["spdx"] == model["spdx"])


def fence(text):
    """A code fence longer than any backtick run in `text`."""
    longest = run = 0
    for ch in text:
        run = run + 1 if ch == "`" else 0
        longest = max(longest, run)
    return "`" * max(3, longest + 1)


def details(label, text):
    f = fence(text)
    return f"<details><summary>{label}</summary>\n\n{f}text\n{text.rstrip()}\n{f}\n\n</details>\n"


def build_markdown(pins, packages, manual, root=ROOT):
    license_text = read(root / "LICENSE")
    copyright_line = next((line for line in license_text.splitlines() if line.startswith("Copyright")), "")
    shipped = sorted((i for i in packages if packages[i]["shipped"]), key=lambda i: packages[i]["name"].lower())
    build_only = sorted((i for i in packages if not packages[i]["shipped"]), key=lambda i: packages[i]["name"].lower())
    out = []
    out.append("# Third-party notices\n")
    out.append("<!-- Generated by Scripts/gen-notices.py from Package.resolved and Licenses/. Edit those, not this file. -->\n")
    out.append(f"Murmur is released under the MIT License ({copyright_line}); see [LICENSE](LICENSE). "
               "It is built on the open-source work below, each under its own license. "
               "The app shows these notices in Help & setup › Acknowledgements.\n")
    out.append("- [Fonts](#fonts) (in the app)\n- [Swift packages in the app](#swift-packages-in-the-app)\n"
               "- [Models Murmur downloads](#models-murmur-downloads) (not in the app)\n"
               "- [Swift packages used only to build](#swift-packages-used-only-to-build)\n"
               "- [License texts](#license-texts)\n")
    out.append("The app icon, brand mark, menu bar glyph, UI icons and sounds are original to Murmur and covered by its MIT License.\n")

    out.append("## Fonts\n")
    for font in manual["fonts"]:
        out.append(f"### {font['name']}\n")
        out.append(f"- **Version:** {font['version']}\n- **License:** {font['spdx']}\n- **Source:** {font['url']}\n"
                   f"- **Used for:** {font['use']}\n")
        for rel in font["files"]:
            out.append(details("License text", read(root / "Licenses" / rel)))

    out.append("## Swift packages in the app\n")
    for identity in shipped:
        info, pin = packages[identity], pins[identity]
        out.append(f"### {info['name']} {pin['state'].get('version', pin['state'].get('revision', '')[:10])}\n")
        out.append(f"- **License:** {info['spdx']}\n- **Source:** {package_url(pin)}\n- **Used for:** {info['use']}\n")
        if info.get("note"):
            out.append(f"- **Note:** {info['note']}\n")
        for rel, text in package_texts(identity, info, root):
            out.append(details(rel, text))

    out.append("## Models Murmur downloads\n")
    out.append("These aren't part of the app or this repository. Murmur downloads them unchanged from Hugging Face "
               "the first time they're used (see [PRIVACY.md](PRIVACY.md)). Each stays under its own license.\n")
    for model in manual["models"]:
        out.append(f"### {model['name']}\n")
        out.append(f"- **License:** {model['spdx']} (text under [License texts](#license-texts): "
                   f"{model_text_name(model, manual)})\n- **Source:** https://huggingface.co/{model['repo']}\n"
                   f"- **Attribution:** {model['attribution']}\n")

    out.append("## Swift packages used only to build\n")
    out.append("These are in `Package.resolved` but aren't compiled into Murmur.app.\n")
    for identity in build_only:
        info, pin = packages[identity], pins[identity]
        out.append(f"### {info['name']} {pin['state'].get('version', '')}\n")
        out.append(f"- **License:** {info['spdx']}\n- **Source:** {package_url(pin)}\n- **Used for:** {info['use']}\n")
        for rel, text in package_texts(identity, info, root):
            out.append(details(rel, text))

    out.append("## License texts\n")
    for text in manual["texts"]:
        out.append(f"### {text['name']}\n")
        out.append(details(text["spdx"], read(root / "Licenses" / text["file"])))
    return "\n".join(out)


def build_json(pins, packages, manual, root=ROOT):
    """What the app's Acknowledgements view shows: sections of entries with their full license text."""
    license_text = read(root / "LICENSE")
    copyright_line = next((line for line in license_text.splitlines() if line.startswith("Copyright")), "")
    shipped = sorted((i for i in packages if packages[i]["shipped"]), key=lambda i: packages[i]["name"].lower())

    def joined(parts):
        return "\n\n".join(text.rstrip() for _, text in parts) + "\n"

    sections = [
        {"title": "Murmur", "entries": [{
            "name": "Murmur", "license": "MIT", "detail": copyright_line, "text": license_text}]},
        {"title": "Fonts", "entries": [{
            "name": font["name"], "license": font["spdx"], "detail": font["use"],
            "text": joined([(rel, read(root / "Licenses" / rel)) for rel in font["files"]])} for font in manual["fonts"]]},
        {"title": "Swift packages", "entries": [{
            "name": packages[i]["name"], "license": packages[i]["spdx"],
            "detail": " · ".join(x for x in (pins[i]["state"].get("version"), packages[i]["use"]) if x),
            "text": joined(package_texts(i, packages[i], root))} for i in shipped]},
        {"title": "Models Murmur downloads", "entries": [{
            "name": model["name"], "license": model["spdx"], "detail": f"huggingface.co/{model['repo']}",
            "text": f"{model['attribution']}\n\nThe full license is under License texts: {model_text_name(model, manual)}.\n"}
            for model in manual["models"]]},
        {"title": "License texts", "entries": [{
            "name": text["name"], "license": text["spdx"], "detail": "",
            "text": read(root / "Licenses" / text["file"])} for text in manual["texts"]]},
    ]
    return json.dumps({"copyright": copyright_line, "sections": sections}, indent=1, ensure_ascii=False) + "\n"


def outputs(root=ROOT):
    pins, packages, manual = load_inputs(root)
    found = problems(pins, packages, manual, root)
    if found:
        raise NoticeError("\n".join(found))
    notices = build_markdown(pins, packages, manual, root)
    legal = root / "Sources" / "UI" / "Resources" / "Legal"
    return {
        root / "THIRD_PARTY_NOTICES.md": notices,
        legal / "THIRD_PARTY_NOTICES.md": notices,
        legal / "notices.json": build_json(pins, packages, manual, root),
        legal / "LICENSE": read(root / "LICENSE"),
        legal / "PRIVACY.md": read(root / "PRIVACY.md"),
    }


def refresh(checkouts, root=ROOT):
    """Copies each package's license files out of its SwiftPM checkout."""
    _, packages, _ = load_inputs(root)
    folders = {p.name.lower(): p for p in Path(checkouts).iterdir() if p.is_dir()}
    missing = []
    for identity, info in packages.items():
        source = folders.get(identity)
        if source is None:
            missing.append(f"no checkout for '{identity}' in {checkouts}")
            continue
        for rel in info["files"]:
            src = source / rel
            if not src.is_file():
                missing.append(f"{identity}: {rel} not found in its checkout")
                continue
            dst = root / "Licenses" / "packages" / identity / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dst)
    return missing


def main(argv):
    if len(argv) >= 2 and argv[0] == "--refresh-from":
        missing = refresh(argv[1])
        if missing:
            print("\n".join(missing), file=sys.stderr)
            return 1
        argv = argv[2:]
    check = argv == ["--check"]
    if argv and not check:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        files = outputs()
    except NoticeError as error:
        print(f"Third-party notices are incomplete:\n{error}", file=sys.stderr)
        return 1
    stale = [path for path, text in files.items() if not path.is_file() or read(path) != text]
    if check:
        if stale:
            print("Stale (run Scripts/gen-notices.py):\n" + "\n".join(str(p.relative_to(ROOT)) for p in stale), file=sys.stderr)
            return 1
        print("Third-party notices are up to date.")
        return 0
    for path in stale:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(files[path], encoding="utf-8")
        print(f"wrote {path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
