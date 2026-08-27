#!/usr/bin/env python3
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

import os
import json


def get_language_version(pubspec_path, default="3.13"):
    if not os.path.exists(pubspec_path):
        return default
    try:
        with open(pubspec_path, 'r') as f:
            in_env = False
            for line in f:
                stripped = line.strip()
                if not stripped or stripped.startswith('#'):
                    continue
                if stripped.startswith('environment:'):
                    in_env = True
                    continue
                elif in_env and not line.startswith(
                        ' ') and not line.startswith('-') and ':' in stripped:
                    in_env = False

                if in_env and stripped.startswith('sdk:'):
                    val = stripped.split(':',
                                         1)[1].strip().strip("'").strip('"')
                    val = val.replace('^', '').replace('>=',
                                                       '').replace('>',
                                                                   '').strip()
                    parts = val.split(' ')[0].split('.')
                    if len(parts) >= 2:
                        try:
                            major, minor = int(parts[0]), int(parts[1])
                            def_major, def_minor = [
                                int(x) for x in default.split('.')
                            ]
                            if (major, minor) > (def_major, def_minor):
                                return default
                        except ValueError:
                            pass
                        return f"{parts[0]}.{parts[1]}"
    except Exception:
        pass
    return default


def main():
    sdk_root = os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    dart_tool_dir = os.path.join(sdk_root, '.dart_tool')
    os.makedirs(dart_tool_dir, exist_ok=True)

    packages = {}

    # 1. Parse root pubspec.yaml for workspace packages
    root_pubspec = os.path.join(sdk_root, 'pubspec.yaml')
    if os.path.exists(root_pubspec):
        with open(root_pubspec, 'r') as f:
            in_workspace = False
            for line in f:
                line = line.rstrip()
                if not line or line.strip().startswith('#'):
                    continue
                if line.startswith('workspace:'):
                    in_workspace = True
                    continue
                elif line and not line.startswith(' ') and not line.startswith(
                        '-'):
                    in_workspace = False

                if in_workspace:
                    if line.strip().startswith('-'):
                        pkg_path = line.strip().lstrip('-').strip()
                        dir_path = os.path.join(sdk_root, pkg_path)
                        if os.path.exists(os.path.join(dir_path,
                                                       'pubspec.yaml')):
                            pkg_name = os.path.basename(pkg_path)
                            with open(os.path.join(dir_path, 'pubspec.yaml'),
                                      'r') as pf:
                                for pline in pf:
                                    if pline.startswith('name:'):
                                        pkg_name = pline.split(':', 1)[1].split(
                                            '#',
                                            1)[0].strip().strip("'").strip('"')
                                        break
                            packages[pkg_name] = {
                                "name":
                                    pkg_name,
                                "rootUri":
                                    f"../{pkg_path}",
                                "packageUri":
                                    "lib/",
                                "languageVersion":
                                    get_language_version(
                                        os.path.join(dir_path, 'pubspec.yaml'))
                            }

    # 2. Parse root pubspec.yaml for overrides
    root_pubspec = os.path.join(sdk_root, 'pubspec.yaml')
    if os.path.exists(root_pubspec):
        with open(root_pubspec, 'r') as f:
            in_overrides = False
            curr_pkg = None
            for line in f:
                line = line.rstrip()
                if not line or line.strip().startswith('#'):
                    continue
                if line.startswith('dependency_overrides:'):
                    in_overrides = True
                    continue
                elif line and not line.startswith(' '):
                    in_overrides = False

                if in_overrides:
                    if line.startswith('  ') and not line.startswith('    '):
                        curr_pkg = line.split(':', 1)[0].strip()
                    elif line.startswith('    ') and curr_pkg:
                        parts = line.strip().split(':', 1)
                        if len(parts) == 2 and parts[0].strip() == 'path':
                            pkg_path = parts[1].split(
                                '#', 1)[0].strip().strip("'").strip('"')
                            pubspec_path = os.path.join(sdk_root, pkg_path,
                                                        'pubspec.yaml')
                            packages[curr_pkg] = {
                                "name":
                                    curr_pkg,
                                "rootUri":
                                    f"../{pkg_path}",
                                "packageUri":
                                    "lib/",
                                "languageVersion":
                                    get_language_version(pubspec_path)
                            }
                            curr_pkg = None

    config = {
        "configVersion": 2,
        "packages": list(packages.values()),
        "generated": "2026-06-04T08:00:00Z",
        "generator": "generate_debug_package_config.py"
    }

    output_file = os.path.join(dart_tool_dir, 'package_config.json')
    with open(output_file, 'w') as f:
        json.dump(config, f, indent=2)
    print(
        f"Generated synthetic package config with {len(packages)} packages at {output_file}"
    )


if __name__ == '__main__':
    main()
