--[=[
    Reading an archive in one format and serializing it to another should preserve its contents
    exactly, so this walks a single archive through every container format and back out again.
]=]
local archive = require("@std/archive")
local zip = require("@std/archive/zip")
local tar = require("@std/archive/tar")
local ar = require("@std/archive/ar")
local deb = require("@std/archive/deb")
local sevenz = require("@std/archive/sevenz")
local entry = require("@std/archive/entry")
local gzip = require("@std/serde/gzip")
local xz = require("@std/serde/xz")
local bz2 = require("@std/serde/bz2")

const file = entry.create.file

type ArchiveFormat = archive.ArchiveFormat
type ArchiveOptions = archive.ArchiveOptions

const binary_content = string.char(0, 1, 2, 253, 254, 255) .. "\0mid-null\0"

-- start from a real zip on disk rather than something we built in memory
const source = zip.readfile("./tests/data/archives/zips/normal.zip")

type Loader = {
    name: string,
    format: ArchiveFormat,
    load: (bytes: buffer, options: ArchiveOptions?) -> Archive,
}

const loaders: { Loader } = {
    { name = "zip", format = "Zip", load = zip.load },
    { name = "tar", format = "Tar", load = tar.uncompressed.load },
    { name = "tar.gz", format = "TarGz", load = tar.gz.load },
    { name = "tar.bz2", format = "TarBz2", load = tar.bz2.load },
    { name = "tar.xz", format = "TarXz", load = tar.xz.load },
    { name = "tar.lz4", format = "TarLz4", load = tar.lz4.load },
    { name = "tar.zst", format = "TarZst", load = tar.zst.load },
    { name = "7z", format = "7z", load = sevenz.load },
}

const function file_contents(a: Archive): { [string]: string }
    const files: { [string]: string } = {}
    for _, path in a:paths() do
        const e = a:get(path)
        if e and e.type == "File" then
            files[path] = e:expect_file():contents()
        end
    end
    return files
end

const expected = file_contents(source)
assert(expected["hello.txt"] == "hello world\n", "the source zip should contain hello.txt")
assert(expected["dir/subdir/deep.txt"] == "pretty deep\n", "the source zip should contain deep.txt")

-- every container format preserves the file contents of the archive read from a zip
for _, loader in loaders do
    const converted = loader.load(source:serialize(loader.format))
    const actual = file_contents(converted)
    for path, content in expected do
        assert(actual[path] ~= nil, `zip -> {loader.name}: lost file {path}`)
        assert(actual[path] == content, `zip -> {loader.name}: {path} content changed`)
    end
    for path in actual do
        assert(expected[path] ~= nil, `zip -> {loader.name}: invented a file that wasn't there: {path}`)
    end
end

-- chain conversions: zip -> tar.gz -> 7z -> zip should still round back to the original contents
const chained = zip.load(
    sevenz.load(
        tar.gz.load(source:serialize("TarGz")):serialize("7z")
    ):serialize("Zip")
)
const chained_files = file_contents(chained)
for path, content in expected do
    assert(chained_files[path] == content, `chained conversion changed {path}`)
end

-- binary content survives every container format
for _, loader in loaders do
    const bin = archive.create()
    bin:append(file("bin.dat", binary_content))
    const back = loader.load(bin:serialize(loader.format)):get("bin.dat")
    assert(back and back.type == "File", `{loader.name}: bin.dat missing after conversion`)
    assert(back:expect_file():contents() == binary_content, `{loader.name}: binary content was corrupted`)
end

-- ar and deb are flat containers, so they round trip an archive with no directory entries
const flat = archive.create()
flat:append(file("hello.txt", "hello world\n"))
flat:append(file("bin.dat", binary_content))
const flat_containers: { [string]: Archive } = {
    ar = ar.load(flat:serialize("Ar")),
    deb = deb.load(flat:serialize("Deb")),
}
for name, loaded in flat_containers do
    const hello = loaded:get("hello.txt")
    assert(hello and hello.type == "File" and hello:expect_file():contents() == "hello world\n", `{name}: hello.txt changed`)
    const bin = loaded:get("bin.dat")
    assert(bin and bin.type == "File" and bin:expect_file():contents() == binary_content, `{name}: binary content changed`)
end

--[=[
    Single-file formats hold one entry's contents rather than a tree, so an Archive serialized to
    one of them should be readable by the matching @std/serde library, and vice versa.
]=]
const single = archive.create()
single:append(file("only.txt", "just the one file\n"))

assert(
    buffer.tostring(gzip.decompress(single:serialize("Gz"))) == "just the one file\n",
    "serde.gzip should be able to decompress an Archive serialized to Gz"
)
assert(
    buffer.tostring(xz.decompress(single:serialize("Xz"))) == "just the one file\n",
    "serde.xz should be able to decompress an Archive serialized to Xz"
)
assert(
    buffer.tostring(bz2.decompress(single:serialize("Bz2"))) == "just the one file\n",
    "serde.bz2 should be able to decompress an Archive serialized to Bz2"
)

-- serializing a multi-entry archive to a single-file format should error rather than quietly
-- dropping everything but the first entry
assert(not pcall(function()
    return source:serialize("Gz")
end), "serializing a multi-entry archive to Gz should error")

--[=[
    ArchiveEntryFile:compress(format) compresses just that one entry's contents, without needing
    to wrap it in an Archive first.
]=]
const only = assert(single:get("only.txt")):expect_file()

assert(
    buffer.tostring(gzip.decompress(only:compress("Gz"))) == "just the one file\n",
    "ArchiveEntryFile:compress(\"Gz\") should produce bytes serde.gzip can decompress"
)
assert(
    buffer.tostring(xz.decompress(only:compress("Xz"))) == "just the one file\n",
    "ArchiveEntryFile:compress(\"Xz\") should produce bytes serde.xz can decompress"
)
assert(
    buffer.tostring(bz2.decompress(only:compress("Bz2"))) == "just the one file\n",
    "ArchiveEntryFile:compress(\"Bz2\") should produce bytes serde.bz2 can decompress"
)

-- compressing a non-file entry should error, not panic
const only_dir = entry.create.directory("only_dir") :: any
assert(not pcall(function()
    return only_dir:compress("Gz")
end), "compressing a Directory entry should error")

-- compressing to a container format (not a SingleFileFormat) should error, not silently misbehave
assert(not pcall(function()
    return (only :: any):compress("Zip")
end), "compress(\"Zip\") should error since Zip isn't a single-file format")
