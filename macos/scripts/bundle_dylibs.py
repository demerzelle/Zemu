#!/usr/bin/env python3
"""Copies a dylib and everything it links from outside the system into Contents/Frameworks,
rewriting install names to @rpath so the app runs on Macs without Homebrew.

usage: bundle_dylibs.py <frameworks-dir> <dylib>...
"""
import os, shutil, subprocess, sys

SYSTEM = ("/usr/lib/", "/System/")


def deps(path):
    out = subprocess.run(["otool", "-L", path], capture_output=True, text=True, check=True).stdout
    lines = out.splitlines()[1:]
    return [l.strip().split(" (")[0] for l in lines if l.strip()]


def rpaths(path):
    out = subprocess.run(["otool", "-l", path], capture_output=True, text=True, check=True).stdout.splitlines()
    found = []
    for i, l in enumerate(out):
        if "cmd LC_RPATH" in l:
            for j in range(i, min(i + 4, len(out))):
                if out[j].strip().startswith("path "):
                    found.append(out[j].strip().split(" ")[1])
    return found


def resolve(ref, owner):
    if ref.startswith("@loader_path/"):
        return os.path.normpath(os.path.join(os.path.dirname(owner), ref[len("@loader_path/"):]))
    if ref.startswith("@rpath/"):
        for rp in rpaths(owner):
            rp = rp.replace("@loader_path", os.path.dirname(owner))
            cand = os.path.join(rp, ref[len("@rpath/"):])
            if os.path.exists(cand):
                return os.path.normpath(cand)
        for base in ("/opt/homebrew/lib", "/usr/local/lib"):
            cand = os.path.join(base, ref[len("@rpath/"):])
            if os.path.exists(cand):
                return cand
        return None
    return ref


def main():
    fw = sys.argv[1]
    os.makedirs(fw, exist_ok=True)
    queue = [(p, os.path.basename(p)) for p in sys.argv[2:]]
    done = {}
    while queue:
        src, name = queue.pop()
        if name in done:
            continue
        real = os.path.realpath(src)
        dst = os.path.join(fw, name)
        shutil.copy2(real, dst)
        os.chmod(dst, 0o755)
        done[name] = dst
        for ref in deps(real):
            if ref.startswith(SYSTEM):
                continue
            path = resolve(ref, real)
            if path is None or path.startswith(SYSTEM):
                continue
            dep_name = os.path.basename(ref)
            if dep_name == name:
                continue
            queue.append((path, dep_name))
    for name, dst in done.items():
        args = ["install_name_tool", "-id", "@rpath/" + name]
        for ref in deps(dst):
            base = os.path.basename(ref)
            if ref.startswith(SYSTEM) or base == name:
                continue
            if base in done and ref != "@rpath/" + base:
                args += ["-change", ref, "@rpath/" + base]
        for rp in rpaths(dst):
            subprocess.run(["install_name_tool", "-delete_rpath", rp, dst], capture_output=True)
        subprocess.run(args + [dst], check=True, capture_output=True)
        subprocess.run(["install_name_tool", "-add_rpath", "@loader_path", dst], capture_output=True)
    print(f"bundled {len(done)} libraries into {fw}")


if __name__ == "__main__":
    main()
