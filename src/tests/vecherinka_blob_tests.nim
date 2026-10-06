import std/[os, paths, sequtils, tempfiles, unittest]
import ../api/vecherinka_blob

suite "Vecherinka Blob values":
  test "normalizes separators and rejects unsafe paths":
    check normalizeRelativePath("nested\\folder//./payload.bin") ==
      "nested/folder/payload.bin"
    for path in ["", ".", "../secret", "nested/../../secret", "/etc/passwd",
        "\\\\server\\share", "C:\\secret", "name\0tail"]:
      expect ValueError:
        discard normalizeRelativePath(path)

  test "file import and materialization preserve binary bytes":
    let root = Path(createTempDir("vecherinka-blob-file-", ""))
    let source = root / Path("input.dat")
    let target = root / Path("out") / Path("copy.dat")
    writeFile($source, "a\0b\xff")

    let blob = blobFromFile(source)
    check blob.suggestedFilename == "input.dat"
    check blob.bytes == @[byte('a'), 0'u8, byte('b'), 0xff'u8]
    materializeBlob(blob, target)
    check readFile($target) == "a\0b\xff"
    expect IOError:
      materializeBlob(blob, target)

  test "tree import sorts paths, retains empty directories, and materializes":
    let root = Path(createTempDir("vecherinka-blob-tree-", ""))
    let source = root / Path("source-tree")
    let target = root / Path("restored")
    createDir($(source / Path("empty")))
    createDir($(source / Path("nested")))
    writeFile($(source / Path("z.txt")), "z")
    writeFile($(source / Path("nested") / Path("a.bin")), "a\0b")

    let tree = blobTreeFromDirectory(source)
    check tree.suggestedFilename == "source-tree"
    check tree.entries.mapIt(it.path) == @["empty", "nested", "nested/a.bin", "z.txt"]
    check tree.entries[0].kind == btekDirectory
    check tree.entries[2].kind == btekFile
    materializeBlobTree(tree, target)
    check dirExists($(target / Path("empty")))
    check readFile($(target / Path("nested") / Path("a.bin"))) == "a\0b"
    check readFile($(target / Path("z.txt"))) == "z"

  test "manual trees canonicalize names and reject conflicts":
    let tree = BlobTree(suggestedFilename: "bundle",
      entries: @[
        BlobTreeEntry(path: "z\\last.txt", kind: btekFile, bytes: @[2'u8]),
        BlobTreeEntry(path: "a/./first.txt", kind: btekFile, bytes: @[1'u8]),
        BlobTreeEntry(path: "a", kind: btekDirectory)])
    let canonical = canonicalBlobTree(tree)
    check canonical.entries.mapIt(it.path) == @["a", "a/first.txt", "z/last.txt"]
    expect ValueError:
      discard canonicalBlobTree(BlobTree(suggestedFilename: "bad",
        entries: @[
          BlobTreeEntry(path: "same", kind: btekDirectory),
          BlobTreeEntry(path: "same/", kind: btekDirectory)]))
    expect ValueError:
      discard canonicalBlobTree(BlobTree(suggestedFilename: "bad",
        entries: @[
          BlobTreeEntry(path: "file", kind: btekFile, bytes: @[1'u8]),
          BlobTreeEntry(path: "file/child", kind: btekFile, bytes: @[2'u8])]))
    expect ValueError:
      discard canonicalBlobTree(BlobTree(suggestedFilename: "bad",
        entries: @[
          BlobTreeEntry(path: "file", kind: btekFile, bytes: @[1'u8]),
          BlobTreeEntry(path: "file/child", kind: btekDirectory)]))

  test "tree materialization rejects traversal before writing":
    let root = Path(createTempDir("vecherinka-blob-invalid-tree-", ""))
    let target = root / Path("out")
    expect ValueError:
      materializeBlobTree(BlobTree(suggestedFilename: "bundle",
        entries: @[BlobTreeEntry(path: "../escape", kind: btekFile,
          bytes: @[1'u8])]), target)
    check not dirExists($target)

  test "file and directory symlinks are rejected":
    let root = Path(createTempDir("vecherinka-blob-symlink-", ""))
    let file = root / Path("real.txt")
    let fileLink = root / Path("file-link")
    let directory = root / Path("real-dir")
    let directoryLink = root / Path("dir-link")
    writeFile($file, "data")
    createDir($directory)
    createSymlink($file, $fileLink)
    createSymlink($directory, $directoryLink)
    expect IOError:
      discard blobFromFile(fileLink)
    expect IOError:
      discard blobTreeFromDirectory(directoryLink)
    expect IOError:
      discard blobTreeFromDirectory(root)
