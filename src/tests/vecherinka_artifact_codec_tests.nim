import std/[json, options, os, paths, strutils, tempfiles, unittest]
import ../api/vecherinka
import ../api/vecherinka_store

type
  CodecCount = range[1..3]
  CodecRatio = range[0.0..1.0]
  CodecKind = enum
    ckPrimary,
    ckSecondary
  CodecIndex = distinct int64
  CodecLeaf = object
    count: CodecCount
    index: CodecIndex
    label: string
  CodecChoice = object
    note: string
    case kind: CodecKind
    of ckPrimary:
      primaryRank: CodecCount
      primary: tuple[name: string, payload: Blob]
    of ckSecondary:
      secondaryRank: CodecCount
      secondary: Option[BlobTree]
  CodecRoot = object
    fixed: array[-1..1, CodecCount]
    ratio: CodecRatio
    values: seq[Option[CodecLeaf]]
    choice: CodecChoice

declare_artifact_codec(CodecRoot, encodeCodecRoot, decodeCodecRoot)
declare_artifact_codec(Blob, encodeBlob, decodeBlob)
declare_artifact_codec(CodecIndex, encodeCodecIndex, decodeCodecIndex)
declare_artifact_codec(int64, encodeCodecInt, decodeCodecInt)

proc pass_serialized(value: string): string {.nimcall.} = value

suite "generated artifact JSON codec":
  test "round trips nested values and deterministic BlobTree bytes":
    let tree = BlobTree(suggestedFilename: "bundle", entries: @[
      BlobTreeEntry(path: "z/data.bin", kind: btekFile,
        bytes: @[0'u8, 255'u8]),
      BlobTreeEntry(path: "empty", kind: btekDirectory)])
    let root = CodecRoot(
      fixed: array[-1..1, CodecCount]([CodecCount(1), CodecCount(2),
        CodecCount(3)]),
      ratio: 0.25,
      values: @[some(CodecLeaf(count: 3, index: CodecIndex(9), label: "leaf")),
        none[CodecLeaf]()],
      choice: CodecChoice(
        kind: ckSecondary,
        note: "tree",
        secondaryRank: 2,
        secondary: some[BlobTree](tree)))
    let encoded = encodeCodecRoot(root)
    check encoded == encodeCodecRoot(root)
    let decoded = decodeCodecRoot(encoded)
    check decoded.fixed == root.fixed
    check decoded.ratio == root.ratio
    check decoded.values.len == root.values.len
    check decoded.values[0].isSome
    check decoded.values[0].get.count == root.values[0].get.count
    check int64(decoded.values[0].get.index) == int64(root.values[0].get.index)
    check decoded.values[0].get.label == root.values[0].get.label
    check decoded.values[1].isNone
    check decoded.choice.kind == ckSecondary
    check decoded.choice.note == root.choice.note
    check decoded.choice.secondary.get.entries.len == 2
    check decoded.choice.secondary.get.entries[1].path == "z/data.bin"
    check decoded.choice.secondary.get.entries[1].bytes == @[0'u8, 255'u8]

  test "round trips active variant branch and Blob contents":
    let root = CodecRoot(
      fixed: array[-1..1, CodecCount]([CodecCount(1), CodecCount(2),
        CodecCount(3)]),
      ratio: 0.25,
      values: @[],
      choice: CodecChoice(
        kind: ckPrimary,
        note: "blob",
        primaryRank: 3,
        primary: (name: "small", payload: blobFromBytes(@[1'u8, 2'u8], "x.bin"))))
    let decoded = decodeCodecRoot(encodeCodecRoot(root))
    check decoded.choice.kind == ckPrimary
    check decoded.choice.primary.name == "small"
    check decoded.choice.primary.payload.bytes == @[1'u8, 2'u8]

  test "rejects wrong type key and out-of-range values":
    let encoded = encodeCodecRoot(CodecRoot(
      fixed: array[-1..1, CodecCount]([CodecCount(1), CodecCount(2),
        CodecCount(3)]), values: @[],
      choice: CodecChoice(kind: ckPrimary, note: "", primaryRank: 1,
        primary: (name: "n", payload: blobFromBytes(@[], "x.bin")))))
    let wrong_key = encoded.replace("CodecRoot|", "OtherRoot|")
    expect ValueError:
      discard decodeCodecRoot(wrong_key)

    var malformed = parseJson(encoded)
    var malformed_value = malformed["value"]
    var malformed_fixed = malformed_value["fixed"]
    malformed_fixed.elems[0] = newJString("99")
    expect ValueError:
      discard decodeCodecRoot($malformed)

    malformed = parseJson(encoded)
    malformed_value = malformed["value"]
    malformed_value["ratio"] = newJFloat(2.0)
    expect ValueError:
      discard decodeCodecRoot($malformed)

  test "distinct scalar identity stays separate from its base type":
    let distinct_json = parseJson(encodeCodecIndex(CodecIndex(5)))
    let base_json = parseJson(encodeCodecInt(5'i64))
    check distinct_json["type"].getStr != base_json["type"].getStr
    check int64(decodeCodecIndex($distinct_json)) == 5
    check decodeCodecInt($base_json) == 5

  test "Blob payload survives a SQLite workflow close and reopen":
    let root = createTempDir("vecherinka-blob-store-", "", getTempDir())
    defer: removeDir(root)
    let database = Path(root / "run.sqlite3")
    let metadata = StoreMetadata(run_id: "blob-run", workflow_id: "blob-test",
      workflow_fingerprint: "blob-test-v1", workflow_manifest_json: "{}",
      codec_version: 1, checkpoint_version: checkpoint_format_version)
    let blob = blobFromBytes(@[0'u8, 1, 127, 128, 255], "payload.bin")
    let entry = Flow[string](flow_key: "entry", kind: fk_it,
      projector: pass_serialized)
    let top = Flow[string](flow_key: "top", kind: fk_top,
      root: "blob", entry: true, body: entry)
    let run = create_sqlite_run(@[top], encodeBlob(blob), database, metadata,
      @[top, entry])
    check run.finished
    check run.output.isSome

    let reopened = open_vecherinka_store(database, metadata)
    let decoded = decodeBlob(reopened.artifact(run.output.get).get.payload_text)
    check decoded.suggestedFilename == "payload.bin"
    check decoded.bytes == blob.bytes
    reopened.close()
