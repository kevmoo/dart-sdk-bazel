# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

import sys
import json
import os


def parse_deps(deps_file_path, dep_name):
    with open(deps_file_path, 'r') as f:
        content = f.read()

    # Setup the execution context for DEPS
    global_dict = {}

    # We define Var to read from global_dict['vars']
    def Var(name):
        return global_dict.get('vars', {}).get(name, '')

    global_dict['Var'] = Var

    # Run the DEPS file in our context
    try:
        exec(content, global_dict)
    except Exception as e:
        print(f"Error executing DEPS: {e}", file=sys.stderr)
        sys.exit(1)

    vars_dict = global_dict.get('vars', {})
    deps_dict = global_dict.get('deps', {})

    # Map the requested dep_name to its DEPS key
    # In DEPS, keys are usually: "sdk/third_party/boringssl/src"
    # We can check if any key ends with the requested dep_name,
    # or specifically map them.

    # Let's do a suffix match or direct mapping:
    dep_key = None

    # Known mappings to be precise:
    mappings = {
        "boringssl": "sdk/third_party/boringssl/src",
        "zlib": "sdk/third_party/zlib",
        "icu": "sdk/third_party/icu",
        "perfetto": "sdk/third_party/perfetto/src",
        "prebuilt_dart_sdk": "sdk/tools/sdks/dart-sdk",
        "chrome": "sdk/third_party/browsers/chrome",
        "chromedriver": "sdk/third_party/webdriver/chrome",
        "firefox": "sdk/third_party/browsers/firefox",
        "devtools": "sdk/third_party/devtools",
        "co19": "sdk/tests/co19/src",
        "dart_co19_tests": "sdk/tests/co19/src",
    }

    if dep_name in mappings:
        dep_key = mappings[dep_name]
    else:
        # Fallback to suffix match
        for k in deps_dict.keys():
            if k.endswith(f"/{dep_name}") or k.endswith(f"/{dep_name}/src"):
                dep_key = k
                break

    if not dep_key or dep_key not in deps_dict:
        print(f"Dependency '{dep_name}' not found in DEPS", file=sys.stderr)
        sys.exit(1)

    dep_val = deps_dict[dep_key]

    result = {}

    if isinstance(dep_val, str):
        # Format is URL@REV
        if '@' in dep_val:
            url, rev = dep_val.split('@', 1)
            result['url'] = url
            result['commit'] = rev
            result['dep_type'] = 'git'
        else:
            result['url'] = dep_val
            result['dep_type'] = 'git'
    elif isinstance(dep_val, dict):
        if dep_val.get('dep_type') == 'cipd':
            result['dep_type'] = 'cipd'
            packages = dep_val.get('packages', [])
            if packages and isinstance(packages[0], dict):
                result['package'] = packages[0].get('package')
                result['version'] = packages[0].get('version')
        else:
            # Git repo with dict format (e.g. url, condition)
            url_val = dep_val.get('url')
            if url_val:
                if '@' in url_val:
                    url, rev = url_val.split('@', 1)
                    result['url'] = url
                    result['commit'] = rev
                else:
                    result['url'] = url_val
                result['dep_type'] = 'git'

    # Normalize Git URLs (strip .git suffix if present, etc.)
    if 'url' in result and result['url'].endswith('.git'):
        result['url'] = result['url'][:-4]

    if 'dep_type' not in result:
        print(f"Error: Could not resolve dependency details for '{dep_name}'",
              file=sys.stderr)
        sys.exit(1)

    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python3 parse_deps.py <DEPS_PATH> <DEP_NAME>",
              file=sys.stderr)
        sys.exit(1)
    parse_deps(sys.argv[1], sys.argv[2])
