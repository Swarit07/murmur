#!/usr/bin/env python3
"""Writes the license notices for the Rust crates inside FluidAudio's NemoTextProcessing.xcframework.

FluidAudio links a prebuilt text-processing-rs (built with its `fst-engine` feature) and only
summarizes that library's Rust dependencies. This walks text-processing-rs's Cargo.lock from the
crates that feature enables, downloads each crate from crates.io, and copies out its license files.

  Scripts/rust-crate-notices.py [--tag v0.3.1]

Writes Licenses/packages/fluidaudio/text-processing-rs/RUST-CRATES.md. Rerun it when FluidAudio moves to
a new text-processing-rs release (FluidAudio/Package.swift names the tag in the xcframework URL), then
run Scripts/gen-notices.py. Standard library only; Python 3.11+ (tomllib).
"""
import io
import sys
import tarfile
import tomllib
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "Licenses" / "packages" / "fluidaudio" / "text-processing-rs" / "RUST-CRATES.md"
REPO = "https://raw.githubusercontent.com/FluidInference/text-processing-rs"
# The xcframework is built with `--features fst-engine` (FluidAudio/ThirdPartyLicenses/NemoTextProcessing-LICENSE.md).
FEATURES = ["fst-engine"]
# Needed to build but not compiled into the library: a build-script helper, and getrandom's
# dependencies for UEFI and WASI. Proc-macro crates are detected from their own Cargo.toml.
BUILD_ONLY = {"autocfg"}
OTHER_PLATFORMS = {"r-efi", "wasip2", "wit-bindgen"}
USER_AGENT = "murmur-notices (https://github.com/Swarit07/murmur)"
# Copyright lines for crates that ship no license file, from text-processing-rs's THIRD-PARTY-LICENSES.md.
COPYRIGHT = {"rustfst": "Copyright (c) Alexandre Caulier and the rustfst contributors."}


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def roots(manifest, features):
    """The dependencies a build with `features` turns on: the required ones plus `dep:` features."""
    deps = manifest.get("dependencies", {})
    enabled = {name for name, spec in deps.items() if not (isinstance(spec, dict) and spec.get("optional"))}
    for feature in features:
        for item in manifest.get("features", {}).get(feature, []):
            if item.startswith("dep:"):
                enabled.add(item[4:])
    return sorted(enabled)


def closure(lock, start, stop=lambda package: False):
    """Every package reachable from `start` in Cargo.lock, as {(name, version): package}. The walk
    includes a package for which `stop` is true but doesn't go past it."""
    packages = {}
    for package in lock["package"]:
        packages.setdefault(package["name"], []).append(package)

    def find(dep):
        name, *version = dep.split(" ")
        candidates = packages[name]
        if version:
            candidates = [c for c in candidates if c["version"] == version[0]]
        return candidates[0]

    seen, stack = {}, list(start)
    while stack:
        package = find(stack.pop())
        key = (package["name"], package["version"])
        if key not in seen:
            seen[key] = package
            if not stop(package):
                stack.extend(package.get("dependencies", []))
    return seen


def crate_files(name, version):
    """The crate's Cargo.toml and its license files, from crates.io."""
    data = fetch(f"https://static.crates.io/crates/{name}/{name}-{version}.crate")
    files = {}
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
        for member in tar.getmembers():
            parts = member.name.split("/")
            if len(parts) != 2 or not member.isfile():
                continue
            base = parts[1]
            if base == "Cargo.toml" or base.upper().startswith(("LICENSE", "LICENCE", "COPYING", "NOTICE")):
                files[base] = tar.extractfile(member).read().decode("utf-8", errors="replace")
    return files


def categories(lock, start, proc_macros):
    """"linked" for crates compiled into the library; "build" for macros, build helpers and what only
    they use; "other" for what only other platforms use."""
    build = proc_macros | BUILD_ONLY
    linked = closure(lock, start, stop=lambda p: p["name"] in build | OTHER_PLATFORMS)
    linked = {k for k in linked if k[0] not in build | OTHER_PLATFORMS}
    on_apple = closure(lock, start, stop=lambda p: p["name"] in OTHER_PLATFORMS)
    on_apple = {k for k in on_apple if k[0] not in OTHER_PLATFORMS}
    result = {}
    for key in closure(lock, start):
        result[key] = "linked" if key in linked else "build" if key in on_apple else "other"
    return result


def notice_files(spdx, files):
    """The license files to reproduce. Where the crate offers MIT as one choice ("MIT OR Apache-2.0"),
    Murmur takes MIT, so the MIT file is enough; otherwise every license file the crate ships."""
    choices = {part.strip(" ()") for part in spdx.replace("/", " OR ").split(" OR ")}
    mit = {name: text for name, text in files.items() if "MIT" in name.upper()}
    if "MIT" in choices and " AND " not in spdx and mit:
        return mit
    return files


def main(argv):
    tag = argv[argv.index("--tag") + 1] if "--tag" in argv else "v0.3.1"
    manifest = tomllib.loads(fetch(f"{REPO}/{tag}/Cargo.toml").decode())
    lock = tomllib.loads(fetch(f"{REPO}/{tag}/Cargo.lock").decode())
    start = roots(manifest, FEATURES)
    downloaded = {}
    for (name, version) in sorted(closure(lock, start)):
        files = crate_files(name, version)
        downloaded[(name, version)] = (tomllib.loads(files.pop("Cargo.toml")), files)
    proc_macros = {n for (n, _), (m, _) in downloaded.items() if m.get("lib", {}).get("proc-macro")}
    kinds = categories(lock, start, proc_macros)
    groups = {"linked": [], "build": [], "other": []}
    for (name, version), (crate_manifest, files) in sorted(downloaded.items()):
        spdx = crate_manifest.get("package", {}).get("license", "see license files")
        groups[kinds[(name, version)]].append((name, version, spdx, files))
        print(f"{name} {version}: {spdx}, {len(files)} license file(s), {kinds[(name, version)]}")

    out = [f"# Rust crates in NemoTextProcessing.xcframework (text-processing-rs {tag})\n",
           "<!-- Generated by Scripts/rust-crate-notices.py from text-processing-rs's Cargo.lock and the crates' own "
           "license files on crates.io. -->\n",
           f"text-processing-rs is built with `--features {' '.join(FEATURES)}`. These are the crates that build reaches "
           "in its Cargo.lock. Where a crate offers MIT among several licenses (\"MIT OR Apache-2.0\"), Murmur uses it "
           "under MIT and only the MIT text is reproduced. Crates used only to build the library, or only on other "
           "platforms, aren't in Murmur and are listed without their texts.\n"]
    titles = {"linked": "Compiled into the library",
              "build": "Used only to build it (macros and build scripts, not in the binary)",
              "other": "Only for other platforms (UEFI, WASI; not in the macOS binary)"}
    for key in ("linked", "build", "other"):
        out.append(f"## {titles[key]}\n")
        for name, version, spdx, files in groups[key]:
            out.append(f"### {name} {version}\n\n- **License:** {spdx}\n- **Source:** https://crates.io/crates/{name}/{version}\n")
            if name in COPYRIGHT:
                out.append(f"- **Copyright:** {COPYRIGHT[name]}\n")
            if not files:
                out.append("- The crate ships no license file; it's licensed under the SPDX expression above.\n")
            if key != "linked":
                continue
            for base, text in sorted(notice_files(spdx, files).items()):
                out.append(f"#### {base}\n\n```text\n{text.rstrip()}\n```\n")
    OUT.write_text("\n".join(out), encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)}: {sum(len(g) for g in groups.values())} crates "
          f"({len(groups['linked'])} linked, {len(groups['build'])} build-only, {len(groups['other'])} other platforms)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
