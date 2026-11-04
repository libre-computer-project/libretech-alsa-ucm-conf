#!/usr/bin/env python3
"""Check a UCM2 tree loads on an alsa-lib whose Syntax ceiling is MAX (default 7).

alsa-lib refuses a configuration whose `Syntax` exceeds its SYNTAX_VERSION_MAX
(alsa-lib 1.2.14, Debian 13: 7; 1.2.15+: 8) and rejects the constructs it gates
on a higher conf_format. This walks every file under ucm2/ and reports:

  syntax      a `Syntax N` line with N > MAX
  append      If.<id>.Append / If.<id>.Prepend blocks (If without Condition, v8)
  verb-config a use-case verb `Config` block (v8; LibraryConfig...Config is older and allowed)
  variant     a SectionDevice name carrying a `:variant` suffix (v8 device variants)
  optional    `Optional` inside an Include block (alsa-lib 1.2.15+)
  dangling    a static include `File "/..."` whose target is missing from the tree
              (a warning: upstream ships a few -- v1.2.14 has 4 -- so it never
              fails the syntax verdict; with --dangling-baseline <ucm2-dir> the
              ones that baseline does not already have are errors)

usage: check-syntax.py [--max N] [--dangling-baseline <ucm2-dir>] <ucm2-dir>
       check-syntax.py --self-test <git-repo>   # must accept upstream v1.2.14, must reject v1.2.16.1
Exit 0 = clean; 1 = findings (printed); 2 = usage.
"""
import os
import re
import subprocess
import sys
import tempfile

SYNTAX = re.compile(r"^\s*Syntax\s+(\d+)")
APPEND = re.compile(r"\bIf\.[^\s.{]+\.(Append|Prepend)\b")
VERB_CONFIG = re.compile(r"(\bSectionUseCase\.\"[^\"]*\"\.Config\b|^\s*Config\s*(\.|\{))")
VARIANT = re.compile(r"SectionDevice\.\"[A-Za-z0-9_]+:[^\"]*\"")
INCLUDE_FILE = re.compile(r"\bFile\s+\"(/[^\"$]+)\"")
OPTIONAL = re.compile(r"^\s*Optional\s+(true|false|yes|no|1|0)\b")


def check(root, maxv):
    findings = []
    for d, _dirs, files in os.walk(root):
        for name in files:
            path = os.path.join(d, name)
            rel = os.path.relpath(path, root)
            if os.path.islink(path) and not os.path.exists(path):
                findings.append(("dangling", rel, 0, "broken symlink"))
                continue
            try:
                with open(path, encoding="utf-8", errors="replace") as f:
                    lines = f.readlines()
            except OSError as e:
                findings.append(("read", rel, 0, str(e)))
                continue
            for n, line in enumerate(lines, 1):
                code = line.split("#", 1)[0]
                m = SYNTAX.match(code)
                if m and int(m.group(1)) > maxv:
                    findings.append(("syntax", rel, n, line.strip()))
                if APPEND.search(code):
                    findings.append(("append", rel, n, line.strip()))
                if VERB_CONFIG.search(code) and "LibraryConfig" not in code:
                    findings.append(("verb-config", rel, n, line.strip()))
                if VARIANT.search(code):
                    findings.append(("variant", rel, n, line.strip()))
                if OPTIONAL.match(code):
                    findings.append(("optional", rel, n, line.strip()))
                for target in INCLUDE_FILE.findall(code):
                    if not os.path.exists(os.path.join(root, target.lstrip("/"))):
                        findings.append(("dangling", rel, n, target))
    return findings


def self_test(repo):
    ok = True
    for tag, want_clean in (("v1.2.14", True), ("v1.2.16.1", False)):
        with tempfile.TemporaryDirectory() as tmp:
            arc = subprocess.run(["git", "-C", repo, "archive", tag, "ucm2"],
                                 check=True, stdout=subprocess.PIPE).stdout
            subprocess.run(["tar", "-x", "-C", tmp], input=arc, check=True)
            n = len([f for f in check(os.path.join(tmp, "ucm2"), 7) if f[0] != "dangling"])
        good = (n == 0) == want_clean
        ok &= good
        print(f"{'ok  ' if good else 'FAIL'} {tag}: {n} finding(s), expected "
              f"{'none' if want_clean else 'some'}")
    return 0 if ok else 1


def main(argv):
    maxv = 7
    baseline = None
    if argv[:1] == ["--self-test"] and len(argv) == 2:
        return self_test(argv[1])
    while argv[:1] in (["--max"], ["--dangling-baseline"]):
        if argv[0] == "--max":
            maxv = int(argv[1])
        else:
            baseline = argv[1]
        argv = argv[2:]
    if len(argv) != 1:
        print(__doc__)
        return 2
    findings = check(argv[0], maxv)
    known = set()
    if baseline:
        known = {(f[1], f[3]) for f in check(baseline, 99) if f[0] == "dangling"}
    errors = 0
    for kind, rel, n, text in findings:
        if kind == "dangling" and (rel, text) in known:
            label = "dangling-baseline"
        elif kind == "dangling" and baseline is None:
            label = "dangling-warn"
        else:
            label = kind
            errors += 1
        print(f"{label:17} {rel}:{n}: {text}")
    print(f"SCOPE root={argv[0]} max_syntax={maxv} errors={errors} "
          f"warnings={len(findings) - errors} baseline={baseline or '-'}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
