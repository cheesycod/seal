local ar = require("@std/archive/ar")
local archive = require("@std/archive")
local entry = require("@std/archive/entry")
local fs = require("@std/fs")

const file = entry.create.file
const directory = entry.create.directory
const symlink = entry.create.symlink

const temp_path = fs.path.join(script:parent(), "temp_ar")
fs.dir.ensure(temp_path, true)

const binary_content = string.char(0, 1, 2, 253, 254, 255) .. "\0mid-null\0"

-- ar is a flat container: files only, no directory tree
const original = archive.create()
original:append(file("hello.txt", "hello world\n"))
original:append(file("second.txt", "second\n"))
original:append(file("bin.dat", binary_content))

local function assert_contents(loaded: Archive, context: string)
    const hello = loaded:get("hello.txt")
    assert(hello and hello.type == "File", `{context}: hello.txt missing or not a File`)
    assert(hello:expect_file():contents() == "hello world\n", `{context}: unexpected hello.txt content: {hello:expect_file():contents()}`)

    const second = loaded:get("second.txt")
    assert(second and second.type == "File", `{context}: second.txt missing`)
    assert(second:expect_file():contents() == "second\n", `{context}: unexpected second.txt content: {second:expect_file():contents()}`)

    const bin = loaded:get("bin.dat")
    assert(bin and bin.type == "File", `{context}: bin.dat missing`)
    assert(bin:expect_file():contents() == binary_content, `{context}: binary content was corrupted`)
end

assert(#ar.create() == 0, "ar.create() should return an empty Archive")

-- serialize -> load roundtrip
const bytes = original:serialize("Ar")
assert(buffer.readstring(bytes, 0, 8) == "!<arch>\n", "ar output missing its '!<arch>' magic bytes")
const loaded = ar.load(bytes)
assert(#loaded == 3, `expected 3 entries after the ar roundtrip, got {#loaded}`)
assert_contents(loaded, "ar.load")

-- entry order is preserved
const paths = loaded:paths()
assert(paths[1] == "hello.txt", `expected paths[1] == "hello.txt", got {paths[1]}`)
assert(paths[2] == "second.txt", `expected paths[2] == "second.txt", got {paths[2]}`)

-- writefile -> readfile roundtrip
const written_path = fs.path.join(temp_path, "written.a")
ar.writefile(written_path, original)
assert(fs.path.exists(written_path), "ar.writefile didn't write anything")
assert_contents(ar.readfile(written_path), "ar.readfile")
assert_contents(ar.load(fs.readbytes(written_path)), "ar.load from readbytes")

-- extract to disk
const extract_path = fs.path.join(temp_path, "extracted")
ar.extract(written_path, extract_path)
assert(
    fs.readfile(fs.path.join(extract_path, "hello.txt")) == "hello world\n",
    "extracted hello.txt has wrong content"
)
assert(
    fs.readfile(fs.path.join(extract_path, "second.txt")) == "second\n",
    "extracted second.txt has wrong content"
)

-- extract also accepts an in-memory Archive instead of a path
const extract_from_archive_path = fs.path.join(temp_path, "extracted_from_archive")
ar.extract(loaded, extract_from_archive_path)
assert(
    fs.readfile(fs.path.join(extract_from_archive_path, "hello.txt")) == "hello world\n",
    "extracting from an Archive instance wrote wrong hello.txt content"
)
assert(
    fs.readfile(fs.path.join(extract_from_archive_path, "second.txt")) == "second\n",
    "extracting from an Archive instance wrote wrong second.txt content"
)

-- ar can't represent directories or symlinks, and should say so rather than silently dropping them
const with_dir = archive.create()
with_dir:append(directory("dir"))
assert(not pcall(function()
    return with_dir:serialize("Ar")
end), "serializing an archive containing a directory to ar should error")

const with_symlink = archive.create()
with_symlink:append(file("real.txt", "real"))
with_symlink:append(symlink("link.txt", "real.txt"))
assert(not pcall(function()
    return with_symlink:serialize("Ar")
end), "serializing an archive containing a symlink to ar should error")

-- loading something that isn't an ar should error
assert(not pcall(function()
    return ar.load(original:serialize("Zip"))
end), "loading a zip as ar should error")

fs.dir.try_remove(temp_path)
