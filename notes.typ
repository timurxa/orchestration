it's true that we should abstract away some of the materialization process. say we want to properly support basically arbitrary containers for the special types, like Location. the point of this is that the type is associated with a mechanism for how to use that type at runtime.

so for instance, say we have an object like:
```nim
type
  Problem* = object
    goal*: string
    further_description*: Location
```
what does this actually mean? well we say that `goal` is an object that's passed around in memory simply. it's sent to an LLM via a simple inclusion in the instructions, and it's received via direct input in a dynamic tool call.

`Location` is different. it's an object stored in the file system, and `Location` is just a reference to it. how is it "sent" to the LLM? in the case of a file or a directory, it can be copied into its artifact directory. even though we have the guarantee that the data is immutable, optimizations may mean that old data still needs to be materialized. a question here is whether simply viewing the data should be separate from for example copying it into the artifact directory. for simplicity sake and since it'll probably cover most cases, viewing data will be the same as materializing it. for things like `string`'s this is trivial while for `Location`, materialization potentially means applying $Delta$'s and forming the file or directory. then, submission for a `Location` means creating a file or directory. the point of submission is to give enough information for future materializations.

one question is what if we want to pass a whole codebase around? this is a situation for a directory `Location`. for inputs, it should be that we implicitly materialize them for the LLM.

then, do we need any more abstractions? an interesting question is what if we want to for example pass a specific git commit around. here materialization might look like checking out a branch and submitting would be like pushing a git commit. this is quite interesting and is a fair abstraction over the concept of artifacts.

what if we have something like
```nim
type
  Problem* = object
    goal*: string
    further_description*: Location
  ProblemSet* = object
    a*: Problem
    b*: Problem
    c*: Problem
```
