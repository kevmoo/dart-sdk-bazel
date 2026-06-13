#!/usr/bin/env python3
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

import os
import sys
import urllib.request
import zipfile

# CIPD dependencies to fetch
# Map local path (relative to SDK root) to the key in DEPS
CIPD_DEPS = {
    "third_party/devtools": "sdk/third_party/devtools"
}


def parse_deps(deps_file_path):
    with open(deps_file_path, 'r') as f:
        content = f.read()

    global_dict = {}

    def Var(name):
        return global_dict.get('vars', {}).get(name, '')

    global_dict['Var'] = Var

    try:
        exec(content, global_dict)
    except Exception as e:
        print(f"Error executing DEPS: {e}", file=sys.stderr)
        sys.exit(1)

    deps_dict = global_dict.get('deps', {})
    return deps_dict


def is_empty_dir(path):
    if not os.path.exists(path):
        return True
    try:
        contents = os.listdir(path)
        return not contents
    except Exception:
        return False


def fetch_cipd_dep(dest_path, dep_val):
    if not isinstance(dep_val, dict) or dep_val.get('dep_type') != 'cipd':
        print(f"Error: {dest_path} is not a CIPD dependency in DEPS", file=sys.stderr)
        return False

    packages = dep_val.get('packages')
    if not packages or not isinstance(packages, list) or len(packages) == 0:
        print(f"Error: No packages found for {dest_path}", file=sys.stderr)
        return False

    pkg_info = packages[0]
    package = pkg_info.get('package')
    version = pkg_info.get('version')

    if not package or not version:
        print(f"Error: Invalid package info for {dest_path}", file=sys.stderr)
        return False

    # Download URL
    url = f"https://chrome-infra-packages.appspot.com/dl/{package}/+/{version}"

    print(f"Downloading {url} to {dest_path}...")
    zip_path = dest_path + ".zip"
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)

    try:
        urllib.request.urlretrieve(url, zip_path)
    except Exception as e:
        print(f"Failed to download {url}: {e}", file=sys.stderr)
        return False

    print(f"Extracting {zip_path} to {dest_path}...")
    try:
        # Ensure dest_path exists and is empty before extracting
        os.makedirs(dest_path, exist_ok=True)
        with zipfile.ZipFile(zip_path, 'r') as zip_ref:
            zip_ref.extractall(dest_path)
    except Exception as e:
        print(f"Failed to extract {zip_path}: {e}", file=sys.stderr)
        # Clean up partial extraction if possible
        try:
            for root, dirs, files in os.walk(dest_path, topdown=False):
                for name in files:
                    os.remove(os.path.join(root, name))
                for name in dirs:
                    os.rmdir(os.path.join(root, name))
        except Exception:
            pass
        return False
    finally:
        if os.path.exists(zip_path):
            os.remove(zip_path)

    print(f"Successfully fetched {dest_path}")
    return True


def main():
    sdk_root = os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    deps_file = os.path.join(sdk_root, 'DEPS')
    deps = parse_deps(deps_file)

    success = True
    for local_path, dep_key in CIPD_DEPS.items():
        dest_path = os.path.join(sdk_root, local_path)
        if os.path.exists(dest_path) and not is_empty_dir(dest_path):
            print(
                f"Directory {dest_path} already exists and is not empty, skipping fetch."
            )
            continue

        if dep_key not in deps:
            print(
                f"Warning: Dependency key {dep_key} not found in DEPS, skipping."
            )
            continue

        if not fetch_cipd_dep(dest_path, deps[dep_key]):
            success = False

    if not success:
        sys.exit(1)


if __name__ == '__main__':
    main()
