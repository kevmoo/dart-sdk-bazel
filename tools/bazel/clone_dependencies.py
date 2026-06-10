#!/usr/bin/env python3
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

import os
import sys
import subprocess
import json

# Repositories to clone
REPOS = [
    "third_party/pkg/core",
    "third_party/pkg/tools",
    "third_party/pkg/test",
    "third_party/pkg/native",
    "third_party/pkg/ecosystem",
    "third_party/pkg/dart_style",
    "third_party/pkg/dartdoc",
    "third_party/pkg/http",
    "third_party/pkg/i18n",
    "third_party/pkg/leak_tracker",
    "third_party/pkg/protobuf",
    "third_party/pkg/pub",
    "third_party/pkg/shelf",
    "third_party/pkg/sync_http",
    "third_party/pkg/tar",
    "third_party/pkg/vector_math",
    "third_party/pkg/webdev",
    "third_party/pkg/web",
]


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
        # Consider it empty if it has no files or only has .git
        return not contents or contents == ['.git']
    except Exception:
        return False


def clone_repo(repo_path, dep_val):
    if isinstance(dep_val, str):
        if '@' in dep_val:
            url, rev = dep_val.split('@', 1)
        else:
            url = dep_val
            rev = 'HEAD'
    elif isinstance(dep_val, dict):
        url_val = dep_val.get('url')
        if url_val and '@' in url_val:
            url, rev = url_val.split('@', 1)
        else:
            url = url_val
            rev = 'HEAD'
    else:
        print(f"Unknown dependency format for {repo_path}: {dep_val}")
        return

    if not url:
        print(f"Warning: No URL found for dependency {repo_path}, skipping.")
        return

    if url.endswith('.git'):
        url = url[:-4]

    # If the directory already exists and has files (other than .git), we skip it
    # to preserve developer local state.
    if os.path.exists(repo_path) and not is_empty_dir(repo_path):
        print(
            f"Directory {repo_path} already exists and is not empty, skipping clone."
        )
        return

    # Sanitize environment to prevent parent git config leaks
    git_env = os.environ.copy()
    for key in list(git_env.keys()):
        if key.startswith('GIT_'):
            del git_env[key]

    # Ensure parent dir exists
    os.makedirs(os.path.dirname(repo_path), exist_ok=True)

    is_git = os.path.exists(os.path.join(repo_path, '.git'))
    if not is_git:
        print(f"Initializing new git repository in {repo_path}...")
        os.makedirs(repo_path, exist_ok=True)
        subprocess.run(["git", "-c", "advice.defaultBranchName=false", "init"],
                       env=git_env,
                       cwd=repo_path,
                       check=True)
        subprocess.run(["git", "remote", "add", "origin", url],
                       env=git_env,
                       cwd=repo_path,
                       check=True)
    else:
        print(f"Reusing existing git repository in {repo_path}...")
        try:
            subprocess.run(["git", "remote", "set-url", "origin", url],
                           env=git_env,
                           cwd=repo_path,
                           check=True)
        except subprocess.CalledProcessError:
            # If set-url fails (e.g. no origin remote configured yet), try adding it
            subprocess.run(["git", "remote", "add", "origin", url],
                           env=git_env,
                           cwd=repo_path,
                           check=True)

    # Configure advice locally for this repository so it applies to all fetch/checkout/init calls
    subprocess.run(["git", "config", "advice.defaultBranchName", "false"],
                   env=git_env,
                   cwd=repo_path,
                   check=True)
    subprocess.run(["git", "config", "advice.detachedHead", "false"],
                   env=git_env,
                   cwd=repo_path,
                   check=True)

    # Try fetching the specific revision directly first (faster, shallow)
    try:
        subprocess.run(["git", "fetch", "--depth=1", "origin", rev],
                       env=git_env,
                       cwd=repo_path,
                       check=True)
        subprocess.run(["git", "checkout", "FETCH_HEAD"],
                       env=git_env,
                       cwd=repo_path,
                       check=True)
    except subprocess.CalledProcessError:
        print(f"Direct fetch of {rev} failed, falling back to full fetch...")
        subprocess.run(["git", "fetch", "origin"],
                       env=git_env,
                       cwd=repo_path,
                       check=True)
        subprocess.run(["git", "checkout", rev],
                       env=git_env,
                       cwd=repo_path,
                       check=True)


def main():
    sdk_root = os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    deps_file = os.path.join(sdk_root, 'DEPS')
    deps = parse_deps(deps_file)

    lock_dir = os.path.join(sdk_root, '.clone_dependencies.lock')
    acquired_lock = False
    for _ in range(300):
        try:
            os.mkdir(lock_dir)
            try:
                with open(os.path.join(lock_dir, 'pid'), 'w') as f:
                    f.write(str(os.getpid()))
                acquired_lock = True
                break
            except OSError:
                try:
                    os.rmdir(lock_dir)
                except Exception:
                    pass
                continue
        except FileExistsError:
            pid_file = os.path.join(lock_dir, 'pid')
            try:
                with open(pid_file, 'r') as f:
                    pid = int(f.read().strip())
                try:
                    os.kill(pid, 0)
                    pid_running = True
                except OSError as e:
                    import errno
                    pid_running = e.errno == errno.EPERM
                if not pid_running:
                    print(
                        f"Detected stale lock (PID {pid} is not running). Clearing it."
                    )
                    temp_stale_dir = lock_dir + ".stale." + str(os.getpid())
                    try:
                        os.rename(lock_dir, temp_stale_dir)
                        try:
                            os.remove(os.path.join(temp_stale_dir, 'pid'))
                        except Exception:
                            pass
                        try:
                            os.rmdir(temp_stale_dir)
                        except Exception:
                            pass
                    except Exception:
                        pass
                    continue
            except Exception:
                import time
                try:
                    # Fallback modification time check: 5 minutes (300s)
                    if time.time() - os.path.getmtime(lock_dir) > 300:
                        print(
                            "Detected stale lock (older than 5 minutes). Clearing it."
                        )
                        temp_stale_dir = lock_dir + ".stale." + str(os.getpid())
                        try:
                            os.rename(lock_dir, temp_stale_dir)
                            try:
                                os.remove(os.path.join(temp_stale_dir, 'pid'))
                            except Exception:
                                pass
                            try:
                                os.rmdir(temp_stale_dir)
                            except Exception:
                                pass
                        except Exception:
                            pass
                        continue
                except Exception:
                    pass
            import time
            time.sleep(1)

    if not acquired_lock:
        print("Error: Could not acquire lock for cloning dependencies",
              file=sys.stderr)
        sys.exit(1)

    try:
        for repo in REPOS:
            dep_key = None
            for k in deps.keys():
                if k.endswith(repo):
                    dep_key = k
                    break

            if not dep_key:
                print(
                    f"Warning: Repository {repo} not found in DEPS, skipping.")
                continue

            clone_repo(os.path.join(sdk_root, repo), deps[dep_key])

        # Create sentinel file to signal successful clone to Bzlmod
        sentinel_path = os.path.join(sdk_root, 'third_party', 'pkg', '.cloned_sentinel')
        os.makedirs(os.path.dirname(sentinel_path), exist_ok=True)
        with open(sentinel_path, 'w') as f:
            f.write('cloned')
    finally:
        try:
            os.remove(os.path.join(lock_dir, 'pid'))
        except Exception:
            pass
        try:
            os.rmdir(lock_dir)
        except Exception:
            pass


if __name__ == '__main__':
    main()
