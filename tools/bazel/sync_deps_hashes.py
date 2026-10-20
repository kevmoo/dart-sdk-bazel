#!/usr/bin/env python3
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.
"""Maintains and validates tools/bazel/deps_hashes.bzl against DEPS.

Usage:
  python3 tools/bazel/sync_deps_hashes.py --update   # Stream & compute SHA-256s
  python3 tools/bazel/sync_deps_hashes.py --check    # Offline parity check (<50ms)
"""

import argparse
import ast
import concurrent.futures
import hashlib
import os
import sys
import urllib.request

CIPD_PLATFORMS = (
    "linux-amd64",
    "linux-arm64",
    "mac-amd64",
    "mac-arm64",
    "windows-amd64",
    "windows-arm64",
)

CHROME_PLATFORMS = (
    "linux64",
    "mac-arm64",
    "mac-x64",
    "win64",
)


def _load_deps(deps_path):
    with open(deps_path, "r", encoding="utf-8") as f:
        content = f.read()
    scope = {}
    scope["Var"] = lambda name: scope.get("vars", {}).get(name, "")
    exec(content, scope)
    return scope.get("deps", {})


def _git_url_and_commit(entry):
    raw = entry["url"] if isinstance(entry, dict) else entry
    url, commit = raw.split("@", 1)
    if url.endswith(".git"):
        url = url[:-4]
    return url, commit


def _resolve_github_archive_url(url, commit):
    clean = url[:-4] if url.endswith(".git") else url
    if clean.startswith("https://github.com/") or clean.startswith("http://github.com/"):
        return f"{clean}/archive/{commit}.tar.gz"
    if "/external/github.com/" in clean:
        gh_path = clean.split("/external/github.com/", 1)[1]
        return f"https://github.com/{gh_path}/archive/{commit}.tar.gz"
    if clean == "https://boringssl.googlesource.com/boringssl":
        return f"https://github.com/google/boringssl/archive/{commit}.tar.gz"
    return None


def compute_expected_urls(deps_path):
    """Derive all deterministic archive URLs fetched by Bazel repository rules."""
    deps = _load_deps(deps_path)
    urls = set()

    # 1. Toolchain & sysroot CIPD archives (build/toolchain/linux/clang_repo.bzl)
    for key in ("sdk/buildtools/linux-x64/clang", "sdk/buildtools/sysroot/linux"):
        pkg = deps[key]["packages"][0]
        urls.add(
            f"https://chrome-infra-packages.appspot.com/dl/{pkg['package']}/+/{pkg['version']}"
        )

    # 2. Platform-parameterized prebuilt Dart SDK CIPD archives (third_party.bzl)
    sdk_pkg = deps["sdk/tools/sdks/dart-sdk"]["packages"][0]
    for plat in CIPD_PLATFORMS:
        resolved_pkg = sdk_pkg["package"].replace("${{platform}}", plat)
        urls.add(
            f"https://chrome-infra-packages.appspot.com/dl/{resolved_pkg}/+/{sdk_pkg['version']}"
        )

    # 3. Platform-independent CIPD archives (devtools, co19)
    for key in ("sdk/third_party/devtools", "sdk/tests/co19/src"):
        pkg = deps[key]["packages"][0]
        urls.add(
            f"https://chrome-infra-packages.appspot.com/dl/{pkg['package']}/+/{pkg['version']}"
        )

    # 4. Public browser & WebDriver archives (chrome, chromedriver, firefox)
    chrome_ver = deps["sdk/third_party/browsers/chrome"]["packages"][0]["version"]
    if chrome_ver.startswith("version:"):
        chrome_ver = chrome_ver.split(":", 1)[1]
    for plat in CHROME_PLATFORMS:
        urls.add(
            f"https://storage.googleapis.com/chrome-for-testing-public/{chrome_ver}/{plat}/chrome-{plat}.zip"
        )
        urls.add(
            f"https://storage.googleapis.com/chrome-for-testing-public/{chrome_ver}/{plat}/chromedriver-{plat}.zip"
        )

    ff_ver = deps["sdk/third_party/browsers/firefox"]["packages"][0]["version"]
    if ff_ver.startswith("version:"):
        ff_ver = ff_ver.split(":", 1)[1]
    urls.add(
        f"https://archive.mozilla.org/pub/firefox/releases/{ff_ver}/linux-x86_64/en-US/firefox-{ff_ver}.tar.xz"
    )
    urls.add(
        f"https://archive.mozilla.org/pub/firefox/releases/{ff_ver}/mac/en-US/Firefox%20{ff_ver}.pkg"
    )

    # 5. Deterministic GitHub source archives for C++ overlay repositories.
    # Pure Gitiles +archive/*.tar.gz endpoints (icu, zlib) synthesize dynamic
    # gzip header timestamps per request and cannot carry static SHA-256 pins.
    for key in (
        "sdk/third_party/boringssl/src",
        "sdk/third_party/perfetto/src",
        "sdk/third_party/binaryen/src",
    ):
        url, commit = _git_url_and_commit(deps[key])
        gh_url = _resolve_github_archive_url(url, commit)
        if gh_url:
            urls.add(gh_url)

    return urls


def load_existing_hashes(bzl_path):
    if not os.path.exists(bzl_path):
        return {}
    with open(bzl_path, "r", encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=bzl_path)
    for node in tree.body:
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "DEPS_SHA256":
                    return ast.literal_eval(node.value)
    return {}


def _is_valid_sha256(digest):
    return (
        isinstance(digest, str)
        and len(digest) == 64
        and all(c in "0123456789abcdef" for c in digest)
    )


def _fetch_sha256(url):
    req = urllib.request.Request(url, headers={"User-Agent": "dart-sdk-bazel-sync/1.0"})
    hasher = hashlib.sha256()
    with urllib.request.urlopen(req, timeout=180) as resp:
        while True:
            chunk = resp.read(1024 * 1024)
            if not chunk:
                break
            hasher.update(chunk)
    return url, hasher.hexdigest()


def write_hashes_bzl(bzl_path, mapping):
    lines = [
        "# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file",
        "# for details. All rights reserved. Use of this source code is governed by a",
        "# BSD-style license that can be found in the LICENSE file.",
        "",
        '"""Content-addressed SHA-256 digests for external archives declared in DEPS.',
        "",
        "Generated by: python3 tools/bazel/sync_deps_hashes.py --update",
        "Verified offline in presubmit by: python3 tools/bazel/sync_deps_hashes.py --check",
        '"""',
        "",
        "DEPS_SHA256 = {",
    ]
    for url in sorted(mapping.keys()):
        lines.append(f'    "{url}": "{mapping[url]}",')
    lines.append("}")
    lines.append("")
    with open(bzl_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true", help="Offline parity check (<50ms)")
    group.add_argument("--update", action="store_true", help="Stream & update deps_hashes.bzl")
    parser.add_argument("--reverify", action="store_true", help="Re-download existing URLs too")
    args = parser.parse_args()

    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    deps_path = os.path.join(repo_root, "DEPS")
    bzl_path = os.path.join(repo_root, "tools", "bazel", "deps_hashes.bzl")

    expected_urls = compute_expected_urls(deps_path)
    existing = load_existing_hashes(bzl_path)

    if args.check:
        actual_urls = set(existing.keys())
        missing = sorted(expected_urls - actual_urls)
        stale = sorted(actual_urls - expected_urls)
        malformed = sorted(u for u, d in existing.items() if not _is_valid_sha256(d))
        if missing or stale or malformed:
            if missing:
                print("Missing URLs in tools/bazel/deps_hashes.bzl:")
                for u in missing:
                    print(f"  - {u}")
            if stale:
                print("Stale URLs in tools/bazel/deps_hashes.bzl:")
                for u in stale:
                    print(f"  - {u}")
            if malformed:
                print("Malformed SHA-256 digests in tools/bazel/deps_hashes.bzl:")
                for u in malformed:
                    print(f"  - {u}: {existing[u]!r}")
            print("Run `python3 tools/bazel/sync_deps_hashes.py --update` to synchronize.")
            return 1
        print(f"DEPS SHA-256 lockfile OK ({len(existing)} deterministic URLs verified offline).")
        return 0

    updated = {}
    to_fetch = []
    for url in sorted(expected_urls):
        if not args.reverify and url in existing and _is_valid_sha256(existing[url]):
            updated[url] = existing[url]
        else:
            to_fetch.append(url)

    if to_fetch:
        print(f"Computing SHA-256 digests for {len(to_fetch)} archive URL(s)...")
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            futures = {pool.submit(_fetch_sha256, u): u for u in to_fetch}
            for fut in concurrent.futures.as_completed(futures):
                url, digest = fut.result()
                updated[url] = digest
                print(f"  {digest}  {url}")

    write_hashes_bzl(bzl_path, updated)
    print(f"Wrote {len(updated)} SHA-256 entries to {bzl_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
