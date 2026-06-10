#!/usr/bin/env python3
import sys
import os

# Add tools/ to path so we can import utils
sys.path.append(os.path.normpath(os.path.join(os.path.dirname(__file__), '..')))
import utils

def main():
    # Stable keys (trigger rebuilds if changed)
    sdk_version = utils.GetVersion(no_git_hash=True)
    if sdk_version:
        print(f"STABLE_SDK_VERSION {sdk_version}")
    else:
        print("STABLE_SDK_VERSION 0.0.0-unknown")
    
    # Volatile keys (do not trigger rebuilds unless --stamp is passed)
    try:
        git_hash = utils.GetGitRevision()
        if not git_hash or len(git_hash) != 40:
            git_hash = "unknown"
    except Exception:
        git_hash = "unknown"
    print(f"SDK_GIT_HASH {git_hash}")

if __name__ == "__main__":
    main()
