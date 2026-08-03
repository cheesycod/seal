local deb = require("@std/archive/deb")
local ar = require("@std/archive/ar")
local tar = require("@std/archive/tar")
local archive = require("@std/archive")
local entry = require("@std/archive/entry")
local fs = require("@std/fs")

const file = entry.create.file

const temp_path = fs.path.join(script:parent(), "temp_deb")
fs.dir.ensure(temp_path, true)

--[=[
    A .deb is an ar archive with three members in a fixed order, so this builds a realistically
    shaped one: the format marker, plus the control and data tarballs a real package carries.
]=]
const control = archive.create()
control:append(file("control", "Package: seal\nVersion: 0.0.8\n"))

const data = archive.create()
data:append(file("usr/bin/seal", "#!/bin/sh\necho seal\n"))

const package = deb.create()
package:append(file("debian-binary", "2.0\n"))
package:append(file("control.tar.gz", control:serialize("TarGz")))
package:append(file("data.tar.gz", data:serialize("TarGz")))

assert(#deb.create() == 0, "deb.create() should return an empty Archive")

-- serialize -> load roundtrip, with the member order a .deb requires
const bytes = package:serialize("Deb")
assert(buffer.readstring(bytes, 0, 8) == "!<arch>\n", "deb output missing the ar '!<arch>' magic bytes")

const loaded = deb.load(bytes)
const paths = loaded:paths()
assert(#loaded == 3, `expected 3 members in the deb, got {#loaded}`)
assert(paths[1] == "debian-binary", `debian-binary must come first, got {paths[1]}`)
assert(paths[2] == "control.tar.gz", `control.tar.gz must come second, got {paths[2]}`)
assert(paths[3] == "data.tar.gz", `data.tar.gz must come third, got {paths[3]}`)

const marker = loaded:get("debian-binary")
assert(marker and marker.type == "File", "debian-binary missing")
assert(marker:expect_file():contents() == "2.0\n", `unexpected debian-binary content: {marker:expect_file():contents()}`)

-- the nested tarballs survive intact and can be read back out as archives
const control_member = loaded:get("control.tar.gz")
assert(control_member and control_member.type == "File", "control.tar.gz missing")
const control_back = tar.gz.load(buffer.fromstring(control_member:expect_file():contents()))
const control_file = control_back:get("control")
assert(control_file and control_file.type == "File", "control file missing from the nested control.tar.gz")
assert(
    control_file:expect_file():contents() == "Package: seal\nVersion: 0.0.8\n",
    `unexpected control content: {control_file:expect_file():contents()}`
)

const data_member = loaded:get("data.tar.gz")
assert(data_member and data_member.type == "File", "data.tar.gz missing")
const data_back = tar.gz.load(buffer.fromstring(data_member:expect_file():contents()))
const binary = data_back:get("usr/bin/seal")
assert(binary and binary.type == "File", "usr/bin/seal missing from the nested data.tar.gz")
assert(binary:expect_file():contents() == "#!/bin/sh\necho seal\n", `unexpected data content: {binary:expect_file():contents()}`)

-- writefile -> readfile roundtrip
const written_path = fs.path.join(temp_path, "written.deb")
deb.writefile(written_path, package)
assert(fs.path.exists(written_path), "deb.writefile didn't write anything")
const written_back = deb.readfile(written_path)
assert(#written_back == 3, `expected 3 members after writefile -> readfile, got {#written_back}`)
const written_marker = written_back:get("debian-binary")
assert(written_marker and written_marker.type == "File" and written_marker:expect_file():contents() == "2.0\n",
    "debian-binary didn't survive writefile -> readfile")

-- extract to disk
const extract_path = fs.path.join(temp_path, "extracted")
deb.extract(written_path, extract_path)
assert(fs.readfile(fs.path.join(extract_path, "debian-binary")) == "2.0\n", "extracted debian-binary has wrong content")
assert(fs.path.exists(fs.path.join(extract_path, "data.tar.gz")), "extract didn't write data.tar.gz")

-- extract also accepts an in-memory Archive instead of a path
const extract_from_archive_path = fs.path.join(temp_path, "extracted_from_archive")
deb.extract(written_back, extract_from_archive_path)
assert(fs.readfile(fs.path.join(extract_from_archive_path, "debian-binary")) == "2.0\n", "extracting from an Archive instance wrote wrong debian-binary content")
assert(fs.path.exists(fs.path.join(extract_from_archive_path, "data.tar.gz")), "extracting from an Archive instance didn't write data.tar.gz")

-- deb and ar are the same container, so each reads the other's output
assert(#ar.load(bytes) == 3, "ar should be able to read deb bytes, since a deb is an ar")
const as_ar = archive.create()
as_ar:append(file("hello.txt", "hello world\n"))
assert(#deb.load(as_ar:serialize("Ar")) == 1, "deb should be able to read ar bytes")

-- deb inherits ar's flat-files-only constraint
const with_dir = archive.create()
with_dir:append(entry.create.directory("dir"))
assert(not pcall(function()
    return with_dir:serialize("Deb")
end), "serializing an archive containing a directory to deb should error")

fs.dir.try_remove(temp_path)
