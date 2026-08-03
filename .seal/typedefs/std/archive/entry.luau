--[=[
    Constructors of `ArchiveEntry` instances for `@std/archive` functions and `Archive` methods.
]=]
export type entry = {
    --[=[
        Create new entries (file/directory/symlink)
    ]=]
    create: {
        --[=[
            Create a new file `ArchiveEntry` with default unix permissions and no modified time.

            Call methods on this to set unix_mode and modified time.
        ]=]
        file: (path: string, contents: string | buffer) -> ArchiveEntryFile,
        --[=[
            Create a new directory `ArchiveEntry` with default unix permissions and no modified time.

            Call methods on this to set unix_mode and modified time.
        ]=]
        directory: (path: string) -> ArchiveEntryDirectory,
        --[=[
            Create a new symlink `ArchiveEntry` with default unix permissions and no modified time.

            Call methods on this to set unix_mode and modified time.
        ]=]
        symlink: (path: string, target: string) -> ArchiveEntrySymlink,
    },
    --[=[
        Create an `ArchiveEntry` from existing files/directories on disk. Preserves unix permissions
        and modified time if present. Returns a single ArchiveEntry when `path` points to a file,
        or `{ ArchiveEntry }` if path points to a directory. You can pass the return of this
        directly to `Archive:append`.
        
        Not able to create symlinks right now.
    ]=]
    read: (path: string, as: string?) -> ArchiveEntry | { ArchiveEntry },
}

return {} :: entry