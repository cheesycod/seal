export type entry = {
    create: {
        file: (path: string, contents: string | buffer) -> ArchiveEntryFile,
        directory: (path: string) -> ArchiveEntryDirectory,
        symlink: (path: string, target: string) -> ArchiveEntrySymlink,
    },
    from: (path: string, as: string) -> ArchiveEntry,
}

return {} :: entry