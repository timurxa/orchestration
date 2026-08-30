import std/[paths, tables]

type
  ArtifactID* = uint64
  Artifact = object
    id: ArtifactID
    relative_path: Path
    derivatives: seq[ArtifactTransformation]
  ArtifactTransformation = object
    description: string
    after: ArtifactID
  ArtifactStorage = object
    roots: seq[ArtifactID]
    artifacts: Table[ArtifactID, Artifact]
