#!/usr/bin/env python3
"""Run the same Lua cells against xeus-lua built before and after PR #62.

Every case uses print(), so it produces stdout on both sides and the comparison
doesn't depend on the last-value display that PR #62 introduced. The only thing
that differs between the two kernels is the xeus-lua commit -- the Lua, xeus and
xeus-zmq builds are identical.
"""

import os
import shutil
import subprocess
import sys
import tempfile

from jupyter_client.manager import start_new_kernel

# (label, cell source, what plain `lua` prints for the same code)
CASES = [
    ("local, then print it",          'local n = 3\nprint(n)',                            "3"),
    ("two locals",                    'local a = 1\nlocal b = 2\nprint(a + b)',           "3"),
    ("local function, then call it",  'local function f() return 7 end\nprint(f())',      "7"),
    ("local string",                  'local s = "hi"\nprint(s)',                         "hi"),
    ("global, not local  [control]",  'g = 5\nprint(g)',                                  "5"),
    ("last line not an expr [control]", 'local n = 4\nfor i = 1, 1 do print(n) end',      "4"),
]


def kernelspec_dir(prefix, store_path):
    """A JUPYTER_PATH containing just this build's kernelspec."""
    root = os.path.join(prefix, "jupyter")
    dest = os.path.join(root, "kernels", "xlua")
    shutil.copytree(os.path.join(store_path, "share", "jupyter", "kernels", "xlua"), dest)
    for dirpath, _dirnames, filenames in os.walk(root):
        os.chmod(dirpath, 0o755)
        for f in filenames:
            os.chmod(os.path.join(dirpath, f), 0o644)
    return root


def run_cases(store_path, tmp):
    os.environ["JUPYTER_PATH"] = kernelspec_dir(tmp, store_path)
    # The kernel greets on its own stdout; keep it out of the table.
    km, kc = start_new_kernel(kernel_name="xlua", stdout=subprocess.DEVNULL)
    try:
        results = []
        for _label, code, _want in CASES:
            kc.execute(code)
            printed, errored = [], False
            while True:
                try:
                    msg = kc.get_iopub_msg(timeout=30)
                except Exception:
                    break
                mt, content = msg["msg_type"], msg["content"]
                if mt == "status" and content.get("execution_state") == "idle":
                    break
                if mt == "stream" and content["name"] == "stdout":
                    printed.append(content["text"])
                elif mt == "error":
                    errored = True
            kc.get_shell_msg(timeout=30)
            results.append("<error>" if errored else "".join(printed).strip())
        return results
    finally:
        km.shutdown_kernel(now=True)


def main():
    before_path, after_path = sys.argv[1], sys.argv[2]

    with tempfile.TemporaryDirectory() as tmp:
        before = run_cases(before_path, os.path.join(tmp, "before"))
    with tempfile.TemporaryDirectory() as tmp:
        after = run_cases(after_path, os.path.join(tmp, "after"))

    w = max(len(label) for label, _, _ in CASES)
    print(f"\n{'cell':<{w}}  {'lua prints':>10}  {'before #62':>12}  {'after #62':>12}")
    print("-" * (w + 42))

    regressions = 0
    for (label, _code, want), b, a in zip(CASES, before, after):
        broke = b == want and a != want
        regressions += broke
        print(f"{label:<{w}}  {want:>10}  {b:>12}  {a:>12}" + ("   <-- regressed" if broke else ""))

    print(f"\n{regressions} of {len(CASES)} cells regressed.")
    return 1 if regressions else 0


if __name__ == "__main__":
    sys.exit(main())
