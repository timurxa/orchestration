## Content values for files and directory trees at Vecherinka boundaries.

import std/[algorithm, os, paths, strutils, tables]
import std/dirs

type
  Blob* = object
    suggestedFilename*: string
    bytes*: seq[byte]

  BlobTreeEntryKind* = enum
    btekDirectory,
    btekFile

  BlobTreeEntry* = object
    path*: string
    case kind*: BlobTreeEntryKind
    of btekDirectory:
      discard
    of btekFile:
      bytes*: seq[byte]

  BlobTree* = object
    suggestedFilename*: string
    entries*: seq[BlobTreeEntry]

proc normalizeRelativePath*(path: string): string =
  ## Canonical tree paths use `/`; reject traversal instead of resolving it.
  if path.len == 0 or '\0' in path:
    raise newException(ValueError, "relative path is empty or contains NUL")
  let normalized = path.replace('\\', '/')
  if normalized[0] == '/' or
      (normalized.len >= 2 and normalized[0].isAlphaAscii and
        normalized[1] == ':'):
    raise newException(ValueError, "absolute paths are not allowed: " & path)

  var parts: seq[string]
  for part in normalized.split('/'):
    if part == "..":
      raise newException(ValueError, "parent traversal is not allowed: " & path)
    if part.len > 0 and part != ".":
      parts.add(part)
  if parts.len == 0:
    raise newException(ValueError, "relative path has no name: " & path)
  parts.join("/")

proc checked_filename(name: string): string =
  result = normalizeRelativePath(name)
  if '/' in result:
    raise newException(ValueError, "suggested filename must be one name: " & name)

proc bytes_from_string(contents: string): seq[byte] =
  result = newSeq[byte](contents.len)
  for index, value in contents:
    result[index] = byte(value)

proc string_from_bytes(contents: openArray[byte]): string =
  result = newString(contents.len)
  for index, value in contents:
    result[index] = char(value)

proc blobFromBytes*(contents: openArray[byte]; suggestedFilename: string): Blob =
  Blob(suggestedFilename: checked_filename(suggestedFilename),
    bytes: @contents)

proc blobFromFile*(source: Path): Blob =
  let info = getFileInfo($source, followSymlink = false)
  if info.kind in {pcLinkToFile, pcLinkToDir}:
    raise newException(IOError, "symbolic links are not supported: " & $source)
  if info.kind != pcFile or info.isSpecial:
    raise newException(IOError, "expected a regular file: " & $source)
  let name = $lastPathPart(source)
  if name.len == 0:
    raise newException(ValueError, "file has no suggested filename: " & $source)
  Blob(suggestedFilename: checked_filename(name),
    bytes: bytes_from_string(readFile($source)))

proc entry_cmp(left, right: BlobTreeEntry): int =
  result = cmp(left.path, right.path)
  if result == 0:
    result = cmp(ord(left.kind), ord(right.kind))

proc canonicalBlobTree*(tree: BlobTree): BlobTree =
  result.suggestedFilename = checked_filename(tree.suggestedFilename)
  result.entries = newSeqOfCap[BlobTreeEntry](tree.entries.len)
  var kinds = initTable[string, BlobTreeEntryKind]()
  for entry in tree.entries:
    let path = normalizeRelativePath(entry.path)
    if kinds.hasKey(path):
      raise newException(ValueError, "duplicate directory-tree path: " & path)
    kinds[path] = entry.kind
    case entry.kind
    of btekDirectory:
      result.entries.add(BlobTreeEntry(path: path, kind: btekDirectory))
    of btekFile:
      result.entries.add(BlobTreeEntry(path: path, kind: btekFile,
        bytes: @(entry.bytes)))

  for path, kind in kinds:
    var parent = path
    while true:
      let slash = parent.rfind('/')
      if slash < 0:
        break
      parent.setLen(slash)
      if kinds.hasKey(parent) and kinds[parent] == btekFile:
        raise newException(ValueError,
          "file is also used as a directory: " & parent)
  result.entries.sort(entry_cmp)

proc collect_directory(source: Path; prefix: string;
    entries: var seq[BlobTreeEntry]) =
  for kind, path in walkDir(source, checkDir = true):
    let name = $lastPathPart(path)
    let relative = normalizeRelativePath(
      if prefix.len == 0: name else: prefix & "/" & name)
    case kind
    of pcDir:
      entries.add(BlobTreeEntry(path: relative, kind: btekDirectory))
      collect_directory(path, relative, entries)
    of pcFile:
      let info = getFileInfo($path, followSymlink = false)
      if info.kind in {pcLinkToFile, pcLinkToDir}:
        raise newException(IOError,
          "symbolic links are not supported: " & $path)
      if info.kind != pcFile or info.isSpecial:
        raise newException(IOError, "expected a regular file: " & $path)
      entries.add(BlobTreeEntry(path: relative, kind: btekFile,
        bytes: bytes_from_string(readFile($path))))
    of pcLinkToFile, pcLinkToDir:
      raise newException(IOError, "symbolic links are not supported: " & $path)

proc blobTreeFromDirectory*(source: Path): BlobTree =
  let rootInfo = getFileInfo($source, followSymlink = false)
  if rootInfo.kind in {pcLinkToFile, pcLinkToDir}:
    raise newException(IOError, "symbolic links are not supported: " & $source)
  if rootInfo.kind != pcDir:
    raise newException(IOError, "expected a directory: " & $source)
  let name = $lastPathPart(source)
  if name.len == 0:
    raise newException(ValueError, "directory has no suggested filename: " & $source)
  result.suggestedFilename = checked_filename(name)
  collect_directory(source, "", result.entries)
  result = canonicalBlobTree(result)

proc verifyWorkspaceBlobPath*(workingDir: Path; relativePath: string;
    expectDirectory: bool): string =
  ## Optional confinement helper. Default worker Blob outputs use the
  ## unrestricted resolve/verify helpers below instead.
  try:
    let canonical = normalizeRelativePath(relativePath)
    var source = workingDir
    let components = canonical.split('/')
    for index, component in components:
      source = source / Path(component)
      let info = getFileInfo($source, followSymlink = false)
      if info.kind in {pcLinkToFile, pcLinkToDir}:
        return "symbolic links are not supported: " & relativePath
      if index < components.high and info.kind != pcDir:
        return "path ancestor is not a directory: " & relativePath
    if not source.isRelativeTo(workingDir):
      return "path is outside working directory: " & relativePath
    let info = getFileInfo($source, followSymlink = false)
    if expectDirectory:
      if info.kind != pcDir:
        return "expected a directory: " & relativePath
    elif info.kind != pcFile or info.isSpecial:
      return "expected a regular file: " & relativePath
    ""
  except CatchableError as error:
    error.msg

proc resolveBlobOutputPath*(workingDir: Path; outputPath: string): Path =
  ## Blob outputs may come from anywhere the worker process can access.
  if outputPath.len == 0 or '\0' in outputPath:
    raise newException(ValueError, "output path is empty or contains NUL")
  let candidate = if isAbsolute(outputPath):
    Path(outputPath)
  else:
    workingDir / Path(outputPath)
  Path(absolutePath($candidate))

proc verifyBlobOutputPath*(workingDir: Path; outputPath: string;
    expectDirectory: bool): string =
  try:
    let source = resolveBlobOutputPath(workingDir, outputPath)
    let info = getFileInfo($source, followSymlink = false)
    if info.kind in {pcLinkToFile, pcLinkToDir}:
      return "symbolic links are not supported: " & outputPath
    if expectDirectory:
      if info.kind != pcDir:
        return "expected a directory: " & outputPath
    elif info.kind != pcFile or info.isSpecial:
      return "expected a regular file: " & outputPath
    ""
  except CatchableError as error:
    error.msg

proc require_new_destination(destination: Path) =
  if fileExists($destination) or dirExists($destination) or
      symlinkExists($destination):
    raise newException(IOError,
      "materialization destination already exists: " & $destination)

proc materializeBlob*(blob: Blob; destination: Path) =
  discard checked_filename(blob.suggestedFilename)
  require_new_destination(destination)
  let parent = Path(parentDir($destination))
  if $parent != "" and not dirExists($parent):
    createDir($parent)
  writeFile($destination, string_from_bytes(blob.bytes))

proc materializeBlobTree*(source: BlobTree; destination: Path) =
  ## Validate every path and conflict before creating the destination tree.
  let tree = canonicalBlobTree(source)
  require_new_destination(destination)
  createDir($destination)
  for entry in tree.entries:
    let target = destination / Path(entry.path)
    case entry.kind
    of btekDirectory:
      createDir($target)
    of btekFile:
      let parent = Path(parentDir($target))
      if not dirExists($parent):
        createDir($parent)
      writeFile($target, string_from_bytes(entry.bytes))

proc materializeBlobUnique*(blob: Blob; artifactDir: Path;
    usedNames: var seq[string]): string =
  let parts = splitFile(blob.suggestedFilename)
  var suffix = 0
  while true:
    let name = parts.name & (if suffix == 0: "" else: "-" & $suffix) & parts.ext
    let target = artifactDir / Path(name)
    if name notin usedNames and not fileExists($target) and
        not dirExists($target) and not symlinkExists($target):
      materializeBlob(blob, target)
      usedNames.add(name)
      return name
    inc suffix

proc materializeBlobTreeUnique*(tree: BlobTree; artifactDir: Path;
    usedNames: var seq[string]): string =
  var suffix = 0
  while true:
    let name = tree.suggestedFilename &
      (if suffix == 0: "" else: "-" & $suffix)
    let target = artifactDir / Path(name)
    if name notin usedNames and not fileExists($target) and
        not dirExists($target) and not symlinkExists($target):
      materializeBlobTree(tree, target)
      usedNames.add(name)
      return name
    inc suffix
