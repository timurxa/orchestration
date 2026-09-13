# Slice 2 — safe `Location` path helpers

## Purpose

Make relative artifact references safe before generated materialization uses them.

## Files

- `src/vecherinka_runtime.nim` or a small artifact utility module
- path-focused tests

## Work

Implement exported runtime helpers:

- `location_path(root, location)`;
- `validate_relative_location(location)`;
- `safe_existing_location(root, location)`;
- `copy_location(source_root, destination_root, location)`;
- safe root containment check;
- recursive directory merge helper for later joins.

Reject:

- absolute paths;
- empty paths where an actual payload is required;
- `..` components;
- NUL bytes;
- normalized paths outside root;
- source symlink escape;
- destination symlink escape;
- missing source;
- destination collision with incompatible file/directory type.

Use canonical paths for existing targets. Fresh destination roots must not contain symlink parents.

## Test gate

- relative file succeeds;
- relative directory succeeds;
- nested relative path succeeds;
- missing source fails;
- absolute source fails;
- `../outside` fails;
- symlink to outside fails;
- symlinked destination parent fails;
- file/directory collision fails;
- same-content merge collision succeeds only when policy allows;
- conflicting merge collision fails.

## Done when

All later generated code can call one safe helper instead of constructing `root / Path(location)` directly.

