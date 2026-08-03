local zip = require("@std/archive/zip")
local archive = require("@std/archive")
local entry = require("@std/archive/entry")
local env = require("@std/env")
local fs = require("@std/fs")

const file = entry.create.file

const normal_path = "./tests/data/archives/zips/normal.zip"
const temp_path = fs.path.join(script:parent(), "temp_zip")
fs.dir.ensure(temp_path, true)

-- readfile: read a real zip off disk
const read = zip.readfile(normal_path)
const hello = read:get("hello.txt")
assert(hello and hello.type == "File", "normal.zip should contain hello.txt as a File")
assert(hello:expect_file():contents() == "hello world\n", `unexpected hello.txt content: {hello:expect_file():contents()}`)

const deep = read:get("dir/subdir/deep.txt")
assert(deep and deep.type == "File", "normal.zip should contain dir/subdir/deep.txt")
assert(deep:expect_file():contents() == "pretty deep\n", `unexpected deep.txt content: {deep:expect_file():contents()}`)

-- load: same archive, but from bytes we read ourselves
const loaded = zip.load(fs.readbytes(normal_path))
assert(#loaded == #read, "zip.load and zip.readfile disagree on entry count")
const loaded_hello = loaded:get("hello.txt")
assert(loaded_hello and loaded_hello.type == "File" and loaded_hello:expect_file():contents() == "hello world\n",
    "zip.load didn't produce the same hello.txt as zip.readfile")

-- create -> serialize -> load roundtrip
const built = zip.create()
built:append(file("a.txt", "aaa"))
built:append(file("nested/b.txt", "bbb"))
const built_back = zip.load(built:serialize("Zip"))
assert(#built_back == 2, `expected 2 entries after zip roundtrip, got {#built_back}`)
const a_entry = built_back:get("a.txt")
const b_entry = built_back:get("nested/b.txt")
assert(a_entry and a_entry.type == "File" and a_entry:expect_file():contents() == "aaa", "a.txt didn't survive the zip roundtrip")
assert(b_entry and b_entry.type == "File" and b_entry:expect_file():contents() == "bbb", "nested/b.txt didn't survive the zip roundtrip")

-- binary content survives a roundtrip intact
const binary_content = string.char(0, 1, 2, 253, 254, 255) .. "\0mid-null\0"
const binary_archive = archive.create()
binary_archive:append(file("bin.dat", binary_content))
const binary_back = zip.load(binary_archive:serialize("Zip")):get("bin.dat")
assert(binary_back and binary_back.type == "File", "bin.dat missing after roundtrip")
assert(binary_back:expect_file():contents() == binary_content, "binary content was corrupted by the zip roundtrip")

-- writefile then readfile
const written_path = fs.path.join(temp_path, "written.zip")
zip.writefile(written_path, built)
assert(fs.path.exists(written_path), "zip.writefile didn't write anything")
const written_back = zip.readfile(written_path)
assert(#written_back == 2, `expected 2 entries in the written zip, got {#written_back}`)
const written_a = written_back:get("a.txt")
assert(written_a and written_a.type == "File" and written_a:expect_file():contents() == "aaa",
    "a.txt didn't survive writefile -> readfile")

-- extract to disk
const extract_path = fs.path.join(temp_path, "extracted")
zip.extract(normal_path, extract_path)
assert(fs.path.exists(fs.path.join(extract_path, "hello.txt")), "extract didn't write hello.txt")
assert(fs.readfile(fs.path.join(extract_path, "hello.txt")) == "hello world\n", "extracted hello.txt has wrong content")
assert(fs.readfile(fs.path.join(extract_path, "dir", "nested.txt")) == "i am nested\n", "extracted nested.txt has wrong content")
assert(fs.readfile(fs.path.join(extract_path, "dir", "subdir", "deep.txt")) == "pretty deep\n", "extracted deep.txt has wrong content")

-- extract also accepts an in-memory Archive instead of a path
const extract_from_archive_path = fs.path.join(temp_path, "extracted_from_archive")
zip.extract(read, extract_from_archive_path)
assert(fs.readfile(fs.path.join(extract_from_archive_path, "hello.txt")) == "hello world\n", "extracting from an Archive instance wrote wrong hello.txt content")
assert(fs.readfile(fs.path.join(extract_from_archive_path, "dir", "subdir", "deep.txt")) == "pretty deep\n", "extracting from an Archive instance wrote wrong deep.txt content")

-- path traversal is refused by default
const traversal_path = "./tests/data/archives/zips/path_traversal.zip"
assert(not pcall(function()
    return zip.readfile(traversal_path)
end), "reading a path traversal zip should error by default")

-- ...and allowed only when explicitly opted into
const traversal = zip.readfile(traversal_path, { allow_unsafe_path_traversals = true })
const good = traversal:get("good/file.txt")
assert(good and good.type == "File", "the benign entry in path_traversal.zip should still be readable")

-- symlink traversal is refused by default too
assert(not pcall(function()
    return zip.readfile("./tests/data/archives/zips/symlink_traversal.zip")
end), "reading a symlink traversal zip should error by default")

-- max_file_size is enforced
const filesize = require("@std/fs/filesize")
assert(not pcall(function()
    return zip.readfile(normal_path, { max_file_size = filesize.bytes(1) })
end), "readfile should error when an entry exceeds max_file_size")

-- mode and mtime survive a create -> serialize -> load roundtrip
const datetime = require("@std/time/datetime")
const set_mtime = datetime.now()
const meta_built = zip.create()
const meta_file = file("meta.txt", "meta")
meta_file:set_unix_mode(0x1a0 --[[ 0o640 ]])
meta_file:set_modified(set_mtime)
meta_built:append(meta_file)
const meta_directory = entry.create.directory("meta_dir/")
meta_directory:set_unix_mode(0x1e8 --[[ 0o750 ]])
meta_built:append(meta_directory)
const meta_back = zip.load(meta_built:serialize("Zip"))

-- zip's MS-DOS timestamps only have 2-second resolution, so allow a small tolerance
const function mtime_close(a: DateTime, b: DateTime)
    return math.abs(a.unix_timestamp - b.unix_timestamp) <= 2
end

const meta_entry = meta_back:get("meta.txt")
assert(meta_entry and meta_entry:unix_mode() == 0x1a0 --[[ 0o640 ]], `expected meta.txt mode 0o640, got: {meta_entry and meta_entry:unix_mode()}`)
const meta_modified = meta_entry:modified()
assert(meta_modified and mtime_close(meta_modified, set_mtime), "meta.txt mtime didn't survive the zip roundtrip")

const meta_dir_entry = meta_back:get("meta_dir/")
assert(meta_dir_entry and meta_dir_entry:unix_mode() == 0x1e8 --[[ 0o750 ]], `expected meta_dir/ mode 0o750, got: {meta_dir_entry and meta_dir_entry:unix_mode()}`)

-- mode and mtime survive an extract-to-disk roundtrip too
const meta_extract_path = fs.path.join(temp_path, "meta_extracted")
zip.writefile(fs.path.join(temp_path, "meta.zip"), meta_built)
zip.extract(fs.path.join(temp_path, "meta.zip"), meta_extract_path)
const extracted_meta_file = fs.file(fs.path.join(meta_extract_path, "meta.txt"))
assert(extracted_meta_file ~= nil, "extract didn't write meta.txt")

const extracted_meta_metadata = extracted_meta_file:metadata()
const extracted_unix_mode = extracted_meta_metadata.permissions.unix_mode
if env.os ~= "Windows" then
    assert(extracted_unix_mode ~= nil, "extracted meta.txt's metadata should include unix_mode on this platform")
    const extracted_meta_mode = bit32.band(extracted_unix_mode, 0x1ff)
    assert(
        extracted_meta_mode == 0x1a0 --[[ 0o640 ]],
        `expected extracted meta.txt to have mode 0o640, got: {string.format("%o", extracted_meta_mode)}`
    )
end

const extracted_modified_at = extracted_meta_metadata.modified_at
assert(extracted_modified_at ~= nil, "extracted meta.txt's metadata should include modified_at")
assert(
    mtime_close(extracted_modified_at, set_mtime),
    "extracted meta.txt should have the mtime recorded in the archive"
)

-- ArchiveOptions.compression_level: "Deflated" with an explicit level round-trips content,
-- and a "best" level compresses at least as well as a "fastest" one
const big = archive.create()
big:append(file("big.txt", string.rep("seal seal seal ", 20000)))

const deflate_low_path = fs.path.join(temp_path, "deflate_low.zip")
const deflate_high_path = fs.path.join(temp_path, "deflate_high.zip")
zip.writefile(deflate_low_path, big, { compression_level = zip.compression("Deflate", 1) })
zip.writefile(deflate_high_path, big, { compression_level = zip.compression("Deflate", 9) })

const deflate_low_back = zip.readfile(deflate_low_path):get("big.txt")
const deflate_high_back = zip.readfile(deflate_high_path):get("big.txt")
assert(
    deflate_low_back and deflate_low_back.type == "File" and deflate_low_back:expect_file():contents() == string.rep("seal seal seal ", 20000),
    "content changed when writing with a low Deflated compression_level"
)
assert(
    deflate_high_back and deflate_high_back.type == "File" and deflate_high_back:expect_file():contents() == string.rep("seal seal seal ", 20000),
    "content changed when writing with a high Deflated compression_level"
)

const deflate_low_size = buffer.len(fs.readbytes(deflate_low_path))
const deflate_high_size = buffer.len(fs.readbytes(deflate_high_path))
assert(
    deflate_high_size <= deflate_low_size,
    `expected Deflated level 9 to compress at least as well as level 1 ({deflate_high_size} vs {deflate_low_size} bytes)`
)

-- "Stored" (no compression) round-trips content and produces a larger file than Deflated
const stored_path = fs.path.join(temp_path, "stored.zip")
zip.writefile(stored_path, big, { compression_level = zip.compression("Store") })
const stored_back = zip.readfile(stored_path):get("big.txt")
assert(
    stored_back and stored_back.type == "File" and stored_back:expect_file():contents() == string.rep("seal seal seal ", 20000),
    "content changed when writing with Stored compression_level"
)
const stored_size = buffer.len(fs.readbytes(stored_path))
assert(
    stored_size > deflate_high_size,
    `expected Stored to be larger than Deflated level 9 ({stored_size} vs {deflate_high_size} bytes)`
)

-- zip.compression validates its own arguments and combinations
assert(not pcall(function()
    return (zip.compression :: any)()
end), "zip.compression() with no mode should error")
assert(not pcall(function()
    return (zip.compression :: any)("Sideways")
end), "zip.compression(\"Sideways\") with an invalid mode should error")
assert(not pcall(function()
    return zip.compression("Store", 5)
end), "zip.compression(\"Store\", 5) should error since level only applies to \"Deflate\"")

-- an out-of-range Deflated level is only rejected once you actually try to write with it
const out_of_range_level = zip.compression("Deflate", 15)
assert(not pcall(function()
    zip.writefile(fs.path.join(temp_path, "out_of_range.zip"), big, { compression_level = out_of_range_level })
    return nil
end), "writing zip with an out-of-range Deflated level (15) should error")

fs.dir.try_remove(temp_path)
