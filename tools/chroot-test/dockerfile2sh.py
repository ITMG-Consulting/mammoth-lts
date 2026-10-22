#!/usr/bin/env python3
"""Turns a (simple) Dockerfile into a shell script runnable in a chroot: ENV, RUN, COPY, WORKDIR. No Docker here."""
import os
import shlex
import sys

dockerfile, ctx = sys.argv[1], sys.argv[2]
lines, buf = [], ""
for raw in open(dockerfile):
    line = raw.rstrip("\n")
    if buf and line.lstrip().startswith("#"):
        continue  # Docker drops comment lines inside an instruction
    if not buf and (not line.strip() or line.lstrip().startswith("#")):
        continue
    if line.endswith("\\"):
        buf += line + "\n"
        continue
    lines.append(buf + line)
    buf = ""

out = ["set -eux"]
for instr in lines:
    op, _, rest = instr.strip().partition(" ")
    flat = rest.replace("\\\n", " ")
    op = op.upper()
    if op == "ENV":
        rest = flat.strip()
        first = rest.split(None, 1)[0]
        if "=" in first:
            out.append("export " + rest.replace("\n", " "))
        else:
            k, v = rest.split(None, 1)
            out.append(f'export {k}="{" ".join(v.split())}"')
    elif op == "RUN":
        out.append("(\n" + rest + "\n)")
    elif op == "COPY":
        args = shlex.split(flat)
        args = [a for a in args if not a.startswith("--")]
        *srcs, dst = args
        for s in srcs:
            src = os.path.join(ctx, s)
            if s.endswith("/"):
                out.append(f"mkdir -p {dst} && cp -a {src}. {dst}")
            elif "*" in s:
                out.append(f"cp -a {src} {dst}")
            else:
                out.append(f"cp -a {src} {dst}")
    elif op == "WORKDIR":
        out.append(f"mkdir -p {rest} && cd {rest}")
print("\n".join(out))
