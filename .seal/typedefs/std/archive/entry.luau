export type entry = {
    create: {
        file: (path: string, contents: string | buffer) -> ArchiveEntryFile,
        directory: (path: string) -> ArchiveEntryDirectory,
        symlink: (path: string, target: string) -> ArchiveEntrySymlink,
    },
    read: (path: string, as: string?) -> ArchiveEntry | { ArchiveEntry },
}

return {} :: entry