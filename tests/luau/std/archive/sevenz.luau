local sevenz = require("@std/archive/sevenz")
local archive = require("@std/archive")
local entry = require("@std/archive/entry")
local fs = require("@std/fs")

const file = entry.create.file
const directory = entry.create.directory

const temp_path = fs.path.join(script:parent(), "temp_sevenz")
fs.dir.ensure(temp_path, true)

const binary_content = string.char(0, 1, 2, 253, 254, 255) .. "\0mid-null\0"

const original = archive.create()
original:append(file("hello.txt", "hello world\n"))
original:append(directory("dir"))
original:append(file("dir/nested.txt", "i am nested\n"))
original:append(file("bin.dat", binary_content))

local function assert_contents(loaded: Archive, context: string)
    const hello = loaded:get("hello.txt")
    assert(hello and hello.type == "File", `{context}: hello.txt missing or not a File`)
    assert(hello:expect_file():contents() == "hello world\n", `{context}: unexpected hello.txt content: {hello:expect_file():contents()}`)

    const nested = loaded:get("dir/nested.txt")
    assert(nested and nested.type == "File", `{context}: dir/nested.txt missing`)
    assert(nested:expect_file():contents() == "i am nested\n", `{context}: unexpected nested.txt content: {nested:expect_file():contents()}`)

    const bin = loaded:get("bin.dat")
    assert(bin and bin.type == "File", `{context}: bin.dat missing`)
    assert(bin:expect_file():contents() == binary_content, `{context}: binary content was corrupted`)
end

-- create() gives back a usable, empty Archive
assert(#sevenz.create() == 0, "sevenz.create() should return an empty Archive")

-- serialize -> load roundtrip
const bytes = original:serialize("7z")
assert(buffer.len(bytes) > 0, "serializing to 7z produced an empty buffer")
assert_contents(sevenz.load(bytes), "sevenz.load")

-- writefile -> readfile roundtrip
const written_path = fs.path.join(temp_path, "written.7z")
sevenz.writefile(written_path, original)
assert(fs.path.exists(written_path), "sevenz.writefile didn't write anything")
assert_contents(sevenz.readfile(written_path), "sevenz.readfile")

-- load(readbytes(...)) agrees with readfile
assert_contents(sevenz.load(fs.readbytes(written_path)), "sevenz.load from readbytes")

-- 7z has the magic signature '7z' BC AF 27 1C
assert(buffer.readstring(bytes, 0, 2) == "7z", "7z output missing its '7z' magic bytes")

-- extract to disk
const extract_path = fs.path.join(temp_path, "extracted")
sevenz.extract(written_path, extract_path)
assert(
    fs.readfile(fs.path.join(extract_path, "hello.txt")) == "hello world\n",
    "extracted hello.txt has wrong content"
)
assert(
    fs.readfile(fs.path.join(extract_path, "dir", "nested.txt")) == "i am nested\n",
    "extracted dir/nested.txt has wrong content"
)

-- extract also accepts an in-memory Archive instead of a path
const extract_from_archive_path = fs.path.join(temp_path, "extracted_from_archive")
sevenz.extract(sevenz.readfile(written_path), extract_from_archive_path)
assert(
    fs.readfile(fs.path.join(extract_from_archive_path, "hello.txt")) == "hello world\n",
    "extracting from an Archive instance wrote wrong hello.txt content"
)
assert(
    fs.readfile(fs.path.join(extract_from_archive_path, "dir", "nested.txt")) == "i am nested\n",
    "extracting from an Archive instance wrote wrong dir/nested.txt content"
)

-- 7z actually compresses
const big = archive.create()
big:append(file("big.txt", string.rep("seal seal seal ", 20000)))
assert(
    buffer.len(big:serialize("7z")) < buffer.len(big:serialize("Tar")),
    "7z didn't compress relative to a plain tar"
)

-- loading something that isn't 7z should error
assert(not pcall(function()
    return sevenz.load(original:serialize("Zip"))
end), "loading a zip as 7z should error")

fs.dir.try_remove(temp_path)
