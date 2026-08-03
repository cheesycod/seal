-- tests entry.read: reading files/directories off disk into ArchiveEntry/{ ArchiveEntry }

local entry = require("@std/archive/entry")
local archive = require("@std/archive")
local fs = require("@std/fs")

const temp_path = fs.path.join(script:parent(), "temp_entry_read")
fs.dir.try_remove(temp_path)
fs.dir.ensure(temp_path, true)

--[=[
    project/
        root.txt
        src/
            main.txt
            utils/
                helper.txt
        docs/
            readme.txt
]=]
const project_path = fs.path.join(temp_path, "project")
fs.writetree(project_path, fs.tree()
    :with_file("root.txt", "root")
    :with_tree("src", fs.tree()
        :with_file("main.txt", "main")
        :with_tree("utils", fs.tree()
            :with_file("helper.txt", "helper")
        )
    )
    :with_tree("docs", fs.tree()
        :with_file("readme.txt", "readme")
    )
)

local function paths_of(entries: { ArchiveEntry }): { string }
    const paths = {}
    for _, e in entries do
        table.insert(paths, e:path())
    end
    table.sort(paths)
    return paths
end

local function contains(paths: { string }, path: string): boolean
    for _, p in paths do
        if p == path then
            return true
        end
    end
    return false
end

-- reading a directory with no `as` roots everything under the directory's own basename,
-- and every file/subdirectory is visited exactly once (regression test: previously only
-- the *first* subdirectory encountered was recursed into, and every nested file's path
-- was clobbered to be the same as the (nonexistent) `as` argument instead of joined)
const default_entries = entry.read(project_path) :: { ArchiveEntry }
assert(type(default_entries) == "table", "reading a directory should return a table of entries")
const default_paths = paths_of(default_entries)

assert(#default_entries == 8, `expected 8 entries (4 directories + 4 files), got {#default_entries}`)
assert(contains(default_paths, "project"), "missing root directory entry 'project'")
assert(contains(default_paths, "project/root.txt"), "missing 'project/root.txt'")
assert(contains(default_paths, "project/src"), "missing 'project/src' directory entry")
assert(contains(default_paths, "project/src/main.txt"), "missing 'project/src/main.txt'")
assert(contains(default_paths, "project/src/utils"), "missing 'project/src/utils' directory entry")
assert(contains(default_paths, "project/src/utils/helper.txt"), "missing 'project/src/utils/helper.txt'")
assert(contains(default_paths, "project/docs"), "missing 'project/docs' directory entry")
assert(contains(default_paths, "project/docs/readme.txt"), "missing 'project/docs/readme.txt'")

-- no entry should have collapsed to just "project" (the old bug: every nested file/dir
-- got the top-level `as`/basename verbatim instead of having its relative path joined on)
local misplaced = 0
for _, p in default_paths do
    if p == "project" then
        misplaced += 1
    end
end
assert(misplaced == 1, `expected exactly 1 entry at path "project" (the root dir itself), got {misplaced}`)

-- file contents/paths actually correspond to the right entry, not swapped/duplicated
const as_archive = archive.create()
as_archive:append(default_entries)
const main_txt = as_archive:expect("project/src/main.txt")
assert(main_txt:expect_file():contents() == "main", "project/src/main.txt has wrong contents")
const helper_txt = as_archive:expect("project/src/utils/helper.txt")
assert(helper_txt:expect_file():contents() == "helper", "project/src/utils/helper.txt has wrong contents")
const readme = as_archive:expect("project/docs/readme.txt")
assert(readme:expect_file():contents() == "readme", "project/docs/readme.txt has wrong contents")

-- `as` as a string re-roots the whole tree, joining nested paths onto it (not overwriting them)
const rerooted_entries = entry.read(project_path, "custom/root") :: { ArchiveEntry }
const rerooted_paths = paths_of(rerooted_entries)
assert(contains(rerooted_paths, "custom/root"), "missing re-rooted directory entry 'custom/root'")
assert(contains(rerooted_paths, "custom/root/root.txt"), "missing 'custom/root/root.txt'")
assert(contains(rerooted_paths, "custom/root/src/main.txt"), "missing 'custom/root/src/main.txt'")
assert(contains(rerooted_paths, "custom/root/src/utils/helper.txt"), "missing 'custom/root/src/utils/helper.txt'")
assert(not contains(rerooted_paths, "project"), "re-rooted read should not contain any 'project'-rooted paths")

-- `as` as a number keeps that many trailing path components of the directory being read,
-- instead of just its own basename
const kept_entries = entry.read(project_path, 2) :: { ArchiveEntry }
const kept_paths = paths_of(kept_entries)
const expected_root = fs.path.join("temp_entry_read", "project")
assert(contains(kept_paths, expected_root), `missing kept-components root directory entry '{expected_root}'`)
assert(
    contains(kept_paths, fs.path.join(expected_root, "src", "main.txt")),
    `missing '{fs.path.join(expected_root, "src", "main.txt")}'`
)

-- reading a single file with no `as` defaults to just the file's own basename
const single_default = entry.read(fs.path.join(project_path, "src", "main.txt")) :: ArchiveEntry
assert(single_default:path() == "main.txt", `expected single file default path "main.txt", got {single_default:path()}`)
assert(single_default:expect_file():contents() == "main", "single file default read has wrong contents")

-- reading a single file with a string `as` uses it as the exact archive path, nested or not
const single_named = entry.read(fs.path.join(project_path, "src", "main.txt"), "renamed/main.txt") :: ArchiveEntry
assert(single_named:path() == "renamed/main.txt", `expected "renamed/main.txt", got {single_named:path()}`)

-- reading a single file with a numeric `as` keeps that many trailing path components
const single_kept = entry.read(fs.path.join(project_path, "src", "main.txt"), 2) :: ArchiveEntry
assert(single_kept:path() == fs.path.join("src", "main.txt"), `expected "src/main.txt", got {single_kept:path()}`)

-- an empty directory still produces its own (empty) Directory entry, not nothing
const empty_dir = fs.path.join(temp_path, "empty")
fs.dir.ensure(empty_dir, true)
const empty_entries = entry.read(empty_dir) :: { ArchiveEntry }
assert(#empty_entries == 1, `expected exactly 1 entry (the empty dir itself), got {#empty_entries}`)
assert(empty_entries[1].type == "Directory", "the sole entry for an empty directory should be a Directory")
assert(empty_entries[1]:path() == "empty", `expected path "empty", got {empty_entries[1]:path()}`)

-- :try_file()/:try_directory()/:try_symlink() narrow to the matching type, returning nil (not erroring)
-- when self isn't that type; :expect_file()/etc should still error in that case
const file_entry = entry.create.file("some.txt", "contents")
const dir_entry = entry.create.directory("some_dir")
const symlink_entry = entry.create.symlink("some_link", "some.txt")

assert(file_entry:try_file() ~= nil, "try_file on a File entry should return itself, not nil")
assert(file_entry:try_directory() == nil, "try_directory on a File entry should return nil")
assert(file_entry:try_symlink() == nil, "try_symlink on a File entry should return nil")

assert(dir_entry:try_directory() ~= nil, "try_directory on a Directory entry should return itself, not nil")
assert(dir_entry:try_file() == nil, "try_file on a Directory entry should return nil")
assert(dir_entry:try_symlink() == nil, "try_symlink on a Directory entry should return nil")

assert(symlink_entry:try_symlink() ~= nil, "try_symlink on a Symlink entry should return itself, not nil")
assert(symlink_entry:try_file() == nil, "try_file on a Symlink entry should return nil")
assert(symlink_entry:try_directory() == nil, "try_directory on a Symlink entry should return nil")

assert(pcall(function()
    return dir_entry:expect_file()
end) == false, "expect_file on a Directory entry should error, not return nil")
assert(pcall(function()
    return file_entry:expect_directory()
end) == false, "expect_directory on a File entry should error, not return nil")
assert(pcall(function()
    return file_entry:expect_symlink()
end) == false, "expect_symlink on a File entry should error, not return nil")

fs.dir.try_remove(temp_path)
