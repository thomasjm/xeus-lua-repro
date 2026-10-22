# xeus-lua: PR #62 makes a cell's locals invisible to its last expression

A cell that declares a `local` and then ends with an expression evaluates that
expression in a **different Lua chunk**, so the local is out of scope and resolves
as a nil global:

```lua
local n = 3
print(n)        --> nil        (plain `lua` prints 3)
```

This repro builds xeus-lua at the commit before and the commit after
[PR #62](https://github.com/jupyter-xeus/xeus-lua/pull/62) and runs the same cells
through both kernels.

```
nix run github:thomasjm/xeus-lua-repro
```

Output:

```
cell                             lua prints    before #62     after #62
-------------------------------------------------------------------------
local, then print it                      3             3           nil   <-- regressed
two locals                                3             3       <error>   <-- regressed
local function, then call it              7             7       <error>   <-- regressed
local string                             hi            hi           nil   <-- regressed
global, not local  [control]              5             5             5
last line not an expr [control]           4             4             4

4 of 6 cells regressed.
```

The two controls isolate the cause: globals are fine, and a cell whose last line
isn't an expression is fine. Only `local` + an expression on the last line breaks.

Both kernels are built from the same Lua 5.4, xeus 6.0.5 and xeus-zmq 4.0.0, with
widgets off. The only variable is the xeus-lua commit:

| | commit |
| --- | --- |
| before | [`46b00ca`](https://github.com/jupyter-xeus/xeus-lua/commit/46b00ca34388ac187bcd83d1d749adcb96315126) (the PR's merge parent) |
| after | [`0462359`](https://github.com/jupyter-xeus/xeus-lua/commit/0462359f60cbf1e368f13d689e42fd882acf34f6) (the PR's merge commit) |

Every case uses `print()` rather than a bare last expression, so it produces output
on both sides and the comparison does not depend on the last-value display that
PR #62 introduced.

## Cause

`execute_request_impl` splits the cell with `split_lua_block` and then runs the two
halves as two separate chunks:

```cpp
// execute the head without printing anything
auto head_result = lua.safe_script(head, sol::script_pass_on_error);
...
// wrap tail in a function
std::string wrapped_tail = "function _xeus_lua_return_expression() return \n " + tail + "\n end";
auto wrapped_tail_result = lua.safe_script(wrapped_tail, sol::script_pass_on_error);
```

A top-level `local` belongs to its chunk, so it is gone by the time the second
chunk runs, and the tail sees only globals.

## Fix

Evaluate the head and the tail as one chunk, which is what a `.lua` file does:

```cpp
std::string combined = head + "\nreturn \n" + tail;
sol::protected_function_result tail_value = lua.safe_script(combined, sol::script_pass_on_error);
```

That is nine lines replacing sixteen, keeps the last-value display PR #62 added,
and makes all six cells above agree with plain `lua`. It also leaves cross-cell
scoping alone: a `local` still does not survive into the next cell, a global still
does.

See `fix.patch`.

## Affected releases

`git tag --contains 0462359` → **0.9.1, 0.9.2, 0.10.0, 0.10.1** — every release
since 2026-03-10, including the current tip of `main`.
