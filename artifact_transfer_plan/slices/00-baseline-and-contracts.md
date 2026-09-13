# Slice 0 — baseline and contracts

## Purpose

Freeze current behavior before artifact changes. Establish names, boundaries, and test fixtures.

## Work

1. Record current branch and dirty files.
2. Do not overwrite unrelated working-tree changes.
3. Confirm current test/build commands from project instructions.
4. Add focused test fixture types for later slices:
   - scalar field;
   - nested object;
   - `Location`;
   - `seq[Location]`;
   - `Option[Location]`;
   - tagged output variant.
5. Define metadata API and output decoder result API in planning notes before implementation.
6. Keep current fake transport tests unchanged until new fields exist.

## Contract

```nim
type ArtifactID* = uint64

type ArtifactMeta* = object
  id*: ArtifactID
  artifact_dir*: Path
```

Suggested decoder result avoids constructing invalid generated artifacts:

```nim
type ModelMaterialization*[A] = object
  ok*: bool
  value*: Option[A]
  error*: string
```

## Test gate

- Existing runtime execution test passes.
- Existing model lowering test passes.
- Existing interface test passes.
- Existing IPC reader test passes.
- No generated source behavior changes yet.

## Done when

Current baseline recorded in `PROGRESS.md`; fixture plan clear; no implementation started accidentally.

