local bz2 = require("@std/serde/bz2")
local filesize = require("@std/fs/filesize")
local fs = require("@std/fs")

-- roundtrip from a string
const text = "hello there, seal!"
const compressed = bz2.compress(text)
assert(buffer.tostring(bz2.decompress(compressed)) == text, "bz2 string roundtrip failed")

-- roundtrip from a buffer
const bytes = buffer.fromstring(text)
assert(buffer.tostring(bz2.decompress(bz2.compress(bytes))) == text, "bz2 buffer roundtrip failed")

-- bzip2 magic bytes ('B' 'Z' 'h')
assert(buffer.readstring(compressed, 0, 3) == "BZh", "bz2 output missing BZh magic bytes")

-- repetitive data should actually get smaller
const repetitive = string.rep("seal seal seal ", 2000)
const squished = bz2.compress(repetitive)
assert(buffer.len(squished) < #repetitive, "bz2 didn't compress repetitive data")
assert(buffer.tostring(bz2.decompress(squished)) == repetitive, "bz2 roundtrip of repetitive data failed")

-- binary-safe: all byte values, including embedded nulls
const binary = buffer.create(256)
for i = 0, 255 do
    buffer.writeu8(binary, i, i)
end
const binary_out = bz2.decompress(bz2.compress(binary))
assert(buffer.len(binary_out) == 256, "bz2 binary roundtrip changed length")
for i = 0, 255 do
    assert(buffer.readu8(binary_out, i) == i, `bz2 binary roundtrip corrupted byte {i}`)
end

-- empty input
assert(buffer.len(bz2.decompress(bz2.compress(""))) == 0, "bz2 empty roundtrip failed")

-- max_size is respected
assert(
    buffer.tostring(bz2.decompress(compressed, filesize.megabytes(1))) == text,
    "bz2 decompress failed with a generous max_size"
)
const too_small = pcall(function()
    return bz2.decompress(squished, filesize.bytes(16))
end)
assert(not too_small, "bz2 decompress should error when output exceeds max_size")

-- we can decompress a real .bz2 file made by the bzip2 CLI
const fixture = fs.readfile("./tests/data/archives/compressed/hello.txt")
assert(
    buffer.tostring(bz2.decompress(fs.readbytes("./tests/data/archives/compressed/hello.txt.bz2"))) == fixture,
    "bz2 couldn't decompress a real CLI-compressed .bz2 file"
)

-- bad input should error, not panic
assert(not pcall(function()
    return bz2.decompress(buffer.fromstring("definitely not bz2 compressed"))
end), "bz2 decompress should error on non-bz2 data")

assert(not pcall(function()
    return (bz2 :: any).compress(nil)
end), "bz2 compress should error without content")

-- the level param round-trips and a high level compresses at least as well as a low one
const level_low = bz2.compress(repetitive, 1)
const level_high = bz2.compress(repetitive, 9)
assert(buffer.tostring(bz2.decompress(level_low)) == repetitive, "bz2 roundtrip with a low level failed")
assert(buffer.tostring(bz2.decompress(level_high)) == repetitive, "bz2 roundtrip with a high level failed")
assert(
    buffer.len(level_high) <= buffer.len(level_low),
    `expected bz2 level 9 to compress at least as well as level 1 ({buffer.len(level_high)} vs {buffer.len(level_low)} bytes)`
)

-- an out-of-range level is rejected, not silently clamped
assert(not pcall(function()
    return bz2.compress(repetitive, 15)
end), "bz2 compress should error on an out-of-range level (15)")
