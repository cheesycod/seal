local tar = require("@std/archive/tar")
local archive = require("@std/archive")
local entry = require("@std/archive/entry")
local fs = require("@std/fs")

const file = entry.create.file
const directory = entry.create.directory
const symlink = entry.create.symlink

type ArchiveFormat = archive.ArchiveFormat

const temp_path = fs.path.join(script:parent(), "temp_tar")
fs.dir.ensure(temp_path, true)

-- every tar variant, paired with the ArchiveFormat that Archive:serialize uses for it
type Variant = {
    name: string,
    lib: typeof(tar.gz) | typeof(tar.uncompressed),
    format: ArchiveFormat,
    extension: string,
}

const variants: { Variant } = {
    { name = "uncompressed", lib = tar.uncompressed, format = "Tar", extension = ".tar" },
    { name = "gz", lib = tar.gz, format = "TarGz", extension = ".tar.gz" },
    { name = "xz", lib = tar.xz, format = "TarXz", extension = ".tar.xz" },
    { name = "bz2", lib = tar.bz2, format = "TarBz2", extension = ".tar.bz2" },
    { name = "lz4", lib = tar.lz4, format = "TarLz4", extension = ".tar.lz4" },
    { name = "zst", lib = tar.zst, format = "TarZst", extension = ".tar.zst" },
}

const binary_content = string.char(0, 1, 2, 253, 254, 255) .. "\0mid-null\0"

local function sample(): Archive
    const a = archive.create()
    a:append(file("hello.txt", "hello world\n"))
    a:append(directory("dir"))
    a:append(file("dir/nested.txt", "i am nested\n"))
    a:append(file("bin.dat", binary_content))
    return a
end

local function assert_contents(loaded: Archive, variant: string)
    const hello = loaded:get("hello.txt")
    assert(hello and hello.type == "File", `tar.{variant}: hello.txt missing or not a File`)
    assert(hello:expect_file():contents() == "hello world\n", `tar.{variant}: unexpected hello.txt content: {hello:expect_file():contents()}`)

    const nested = loaded:get("dir/nested.txt")
    assert(nested and nested.type == "File", `tar.{variant}: dir/nested.txt missing`)
    assert(nested:expect_file():contents() == "i am nested\n", `tar.{variant}: unexpected nested.txt content: {nested:expect_file():contents()}`)

    const bin = loaded:get("bin.dat")
    assert(bin and bin.type == "File", `tar.{variant}: bin.dat missing`)
    assert(bin:expect_file():contents() == binary_content, `tar.{variant}: binary content was corrupted`)
end

for _, variant in variants do
    const original = sample()

    -- create() gives back a usable, empty Archive
    const created = variant.lib.create()
    assert(#created == 0, `tar.{variant.name}.create() should return an empty Archive`)

    -- serialize -> load roundtrip
    const bytes = original:serialize(variant.format)
    assert(buffer.len(bytes) > 0, `tar.{variant.name}: serialize produced an empty buffer`)
    const loaded = variant.lib.load(bytes)
    assert_contents(loaded, variant.name)

    -- writefile -> readfile roundtrip
    const written_path = fs.path.join(temp_path, `written{variant.extension}`)
    variant.lib.writefile(written_path, original)
    assert(fs.path.exists(written_path), `tar.{variant.name}.writefile didn't write anything`)
    assert_contents(variant.lib.readfile(written_path), variant.name)

    -- load(readbytes(...)) agrees with readfile
    assert_contents(variant.lib.load(fs.readbytes(written_path)), variant.name)

    -- extract to disk
    const extract_path = fs.path.join(temp_path, `extracted_{variant.name}`)
    variant.lib.extract(written_path, extract_path)
    assert(
        fs.readfile(fs.path.join(extract_path, "hello.txt")) == "hello world\n",
        `tar.{variant.name}: extracted hello.txt has wrong content`
    )
    assert(
        fs.readfile(fs.path.join(extract_path, "dir", "nested.txt")) == "i am nested\n",
        `tar.{variant.name}: extracted dir/nested.txt has wrong content`
    )

    -- extract also accepts an in-memory Archive instead of a path
    const extract_from_archive_path = fs.path.join(temp_path, `extracted_from_archive_{variant.name}`)
    variant.lib.extract(loaded, extract_from_archive_path)
    assert(
        fs.readfile(fs.path.join(extract_from_archive_path, "hello.txt")) == "hello world\n",
        `tar.{variant.name}: extracting from an Archive instance wrote wrong hello.txt content`
    )
    assert(
        fs.readfile(fs.path.join(extract_from_archive_path, "dir", "nested.txt")) == "i am nested\n",
        `tar.{variant.name}: extracting from an Archive instance wrote wrong dir/nested.txt content`
    )
end

-- the compressed variants should actually be smaller than the plain tar
const big = archive.create()
big:append(file("big.txt", string.rep("seal seal seal ", 20000)))
const plain_size = buffer.len(big:serialize("Tar"))
for _, variant in variants do
    if variant.name == "uncompressed" then
        continue
    end
    const compressed_size = buffer.len(big:serialize(variant.format))
    assert(
        compressed_size < plain_size,
        `tar.{variant.name} didn't compress: {compressed_size} bytes vs {plain_size} for a plain tar`
    )
end

-- ArchiveOptions.compression_level: writing with an explicit level round-trips content
-- correctly, and a "best" level compresses at least as well as a "fastest" one
const compression_levels = {
    gz = { low = 1, high = 9 },
    xz = { low = 1, high = 9 },
    bz2 = { low = 1, high = 9 },
    lz4 = { low = 0, high = 16 },
    zst = { low = -5, high = 19 },
}

for _, variant in variants do
    const levels = compression_levels[variant.name]
    if not levels then
        continue
    end

    const lib = variant.lib :: typeof(tar.gz)

    const low_path = fs.path.join(temp_path, `compression_low{variant.extension}`)
    const high_path = fs.path.join(temp_path, `compression_high{variant.extension}`)
    lib.writefile(low_path, big, { compression_level = lib.compression(levels.low) })
    lib.writefile(high_path, big, { compression_level = lib.compression(levels.high) })

    const low_content = variant.lib.readfile(low_path):get("big.txt")
    const high_content = variant.lib.readfile(high_path):get("big.txt")
    assert(
        low_content and low_content.type == "File" and low_content:expect_file():contents() == string.rep("seal seal seal ", 20000),
        `tar.{variant.name}: content changed when writing with a low compression_level`
    )
    assert(
        high_content and high_content.type == "File" and high_content:expect_file():contents() == string.rep("seal seal seal ", 20000),
        `tar.{variant.name}: content changed when writing with a high compression_level`
    )

    const low_size = buffer.len(fs.readbytes(low_path))
    const high_size = buffer.len(fs.readbytes(high_path))
    assert(
        high_size <= low_size,
        `tar.{variant.name}: expected level {levels.high} to compress at least as well as level {levels.low} ({high_size} vs {low_size} bytes)`
    )
end

-- a compression_level built for a different format is rejected when actually writing,
-- not when the ArchiveCompressionLevel itself is constructed
assert(pcall(function()
    return tar.xz.compression(6)
end), "tar.xz.compression(6) should succeed on its own")
assert(not pcall(function()
    tar.gz.writefile(fs.path.join(temp_path, "wrong_format.tar.gz"), big, { compression_level = tar.xz.compression(6) })
    return nil
end), "writing tar.gz with a tar.xz compression_level should error")

-- an in-range-for-u32-but-out-of-range-for-gzip level is likewise only rejected at write time
const out_of_range_level = tar.gz.compression(15)
assert(not pcall(function()
    tar.gz.writefile(fs.path.join(temp_path, "out_of_range.tar.gz"), big, { compression_level = out_of_range_level })
    return nil
end), "writing tar.gz with an out-of-range compression level (15) should error")

-- every .compression() throws when called with missing or wrong-typed args, instead of
-- silently defaulting or panicking
assert(not pcall(function()
    (tar.gz.compression :: any)()
    return nil
end), "tar.gz.compression() with no level should error")
assert(not pcall(function()
    (tar.gz.compression :: any)("not a number")
    return nil
end), "tar.gz.compression(string) should error")
assert(not pcall(function()
    (tar.zst.compression :: any)(nil)
    return nil
end), "tar.zst.compression(nil) should error")

-- reading a tar as the wrong variant should error rather than silently misbehave
assert(not pcall(function()
    return tar.gz.load(sample():serialize("TarBz2"))
end), "loading a tar.bz2 as tar.gz should error")

--[=[
    Symlinks are always preserved when loading into memory (inspecting a symlink entry is
    harmless); `allow_symlinks` gates *materializing* them on disk, which is the dangerous part.
]=]
const linked = archive.create()
linked:append(file("real.txt", "real"))
linked:append(symlink("link.txt", "real.txt"))
const linked_bytes = linked:serialize("Tar")

const link = tar.uncompressed.load(linked_bytes):get("link.txt")
assert(link and link.type == "Symlink", "the symlink should survive a tar roundtrip")
assert(link:expect_symlink():target() == "real.txt", `unexpected symlink target: {link:expect_symlink():target()}`)

-- ...but extracting one to disk requires opting in
const linked_path = fs.path.join(temp_path, "linked.tar")
tar.uncompressed.writefile(linked_path, linked)
assert(not pcall(function()
    tar.uncompressed.extract(linked_path, fs.path.join(temp_path, "linked_out"))
    return true
end), "extracting a tar containing a symlink should error unless allow_symlinks is set")

fs.dir.try_remove(temp_path)
