use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use archive::{ArchiveEntry, ArchiveFormat};
use mluau::prelude::*;
use crate::prelude::*;
use crate::std_fs::entry::wrap_io_read_errors;
use crate::std_time::datetime::DateTime;
use crate::std_fs::file_size::FileSize;
use bstr::ByteSlice;

enum EntryType {
    File,
    Directory,
    Symlink
}
const VALID_ENTRY_TYPES: &str = "\"File\", \"Directory\", or \"Symlink\"";
impl EntryType {
    fn from_value(value: LuaValue) -> LuaResult<Self> {
        let s = match value {
            LuaValue::String(s) => s.as_bytes().to_vec(),
            other => {
                return wrap_err!("expected entry.type to be a string ({}), got: {:?}", VALID_ENTRY_TYPES, other);
            }
        };
        let t = if s.eq_ignore_ascii_case(b"file") {
            Self::File
        } else if s.eq_ignore_ascii_case(b"directory") {
            Self::Directory
        } else if s.eq_ignore_ascii_case(b"symlink") {
            Self::Symlink
        } else {
            let displayable = bstr::BStr::new(&s);
            return wrap_err!("expected entry.type to be {}, got: {}", VALID_ENTRY_TYPES, displayable);
        };
        Ok(t)
    }
}

/// Reads `entry.mode`, if present: the Unix permission bits (e.g. `0o644`) to carry through
/// to whichever format the `Archive` gets serialized to.
fn get_mode(t: &LuaTable) -> LuaResult<Option<u32>> {
    match t.raw_get("mode")? {
        LuaValue::Integer(i) => Ok(Some(i as u32)),
        LuaValue::Number(f) => Ok(Some(f as u32)),
        LuaNil => Ok(None),
        other => {
            wrap_err!("expected entry.mode to be a number (Unix permission bits) or nil, got: {:?}", other)
        }
    }
}

/// Reads `entry.mtime`, if present: either a `DateTime` (from `@std/time/datetime`) or a raw Unix
/// timestamp in seconds.
fn get_mtime(t: &LuaTable) -> LuaResult<Option<SystemTime>> {
    match t.raw_get("mtime")? {
        LuaValue::UserData(ud) if ud.is::<DateTime>() => {
            let dt = ud.borrow::<DateTime>().expect("just checked is::<DateTime>()");
            Ok(Some(dt.to_system_time()))
        },
        LuaValue::Integer(i) => Ok(Some(SystemTime::UNIX_EPOCH + Duration::from_secs(i as u64))),
        LuaValue::Number(f) => Ok(Some(SystemTime::UNIX_EPOCH + Duration::from_secs(f as u64))),
        LuaNil => Ok(None),
        other => {
            wrap_err!("expected entry.mtime to be a DateTime (from @std/time), unix timestamp number, or nil, got: {:?}", other)
        }
    }
}

/// When we make archive entries from file we need to ensure that we don't save
/// the entire absolute path of the file as the 'path' because that creates archive
/// with absolute paths (which even we reject by default)
fn archive_entry_from_file<P: AsRef<Path>>(path: P, keep_children: usize) -> Result<ArchiveEntry, std::io::Error> {
    let contents = std::fs::read(&path)?;

    let buffy = std::path::PathBuf::new();
    // get the last n components of the path (usually 1 unless nested dirs)
    // and basically 'collect' (fold) them into a PathBuf that we alloc above
    let components = &mut path
        .as_ref()
        .components()
        .rev()
        .take(keep_children)
        .try_fold(buffy, |mut acc, comp| {
            if let std::path::Component::Normal(c) = comp {
                acc.push(c);
                std::ops::ControlFlow::Continue(acc)
            } else {
                std::ops::ControlFlow::Break(acc)
            }
        });
    
    let path = match components {
        std::ops::ControlFlow::Continue(b) => {
            // components are backwards so we have to reverse them again
            // unfortunately can't do this easily without allocing another PathBuf
            b.components().rev().collect::<PathBuf>()
        },
        std::ops::ControlFlow::Break(_) => {
            std::path::PathBuf::from(path
                .as_ref()
                .file_name()
                .unwrap_or(std::ffi::OsStr::new("<path not found>"))
                .to_owned()
            )
        }
    };

    Ok(ArchiveEntry::file(path, contents))
}

fn archive_entries_from_directory<P: AsRef<Path>>(path: P, memo: &mut Vec<ArchiveEntry>, depth: Option<usize>) -> Result<(), std::io::Error> {
    let path = path.as_ref();

    let depth = depth.unwrap_or(1);

    for entry in std::fs::read_dir(path)? {
        let entry = entry?;
        let path = entry.path();
        if path.is_dir() {
            return archive_entries_from_directory(path, memo, Some(depth + 1));
        } else if path.is_file() {
            memo.push(archive_entry_from_file(&path, depth + 1)?);
        }
    }

    Ok(())
}

pub(super) enum Entries {
    One(ArchiveEntry),
    Many(Vec<ArchiveEntry>)
}

fn archive_entries_from_path(path: &Path) -> LuaResult<Entries> {
    if path.is_file() {
        match archive_entry_from_file(path, 1) {
            Ok(entry) => Ok(Entries::One(entry)),
            Err(err) => {
                wrap_io_read_errors(err, "", path)
            }
        }
    } else if path.is_dir() {
        let mut entries = Vec::new();
        if let Err(err) = archive_entries_from_directory(path, &mut entries, None) {
            return wrap_io_read_errors(err, "", path);
        }
        Ok(Entries::Many(entries))
    } else {
        wrap_err!("expected path to file or directory, got path to something else. If you want to add a symlink, construct it via table.")
    }
}

/// stupid wrapper to make ArchiveEntry from luau tables
/// we omit function_name here because caller should not use ? to propagate errors from this function
pub(super) fn from_value(value: &LuaValue) -> LuaResult<Entries> {
    let t = match value {
        LuaValue::String(p) => {
            let Ok(valid_utf8_path) = p.to_str() else {
                return wrap_err!("path must be valid utf-8");
            };
            // SAFETY: path must be valid utf-8 because we just checked it above
            let path = Path::new(unsafe { valid_utf8_path.as_bytes().to_str_unchecked() });
            let entries = archive_entries_from_path(path)?;
            return Ok(entries);
        },
        LuaValue::Table(t) => t,
        other => {
            return wrap_err!("expected entry to be an ArchiveEntry table (type: {}), got: {:?}", VALID_ENTRY_TYPES, other);
        }
    };

    fn get_path(t: &LuaTable, key: &'static str) -> LuaResult<String> {
        match t.raw_get(key)? {
            LuaValue::String(s) => Ok(s.to_string_lossy()),
            other => {
                wrap_err!("expected entry.{} to be a string, got: {:?}", key, other)
            }
        }
    }

    let typ = EntryType::from_value(t.raw_get("type")?)?;
    let mode = get_mode(t)?;
    let mtime = get_mtime(t)?;
    let mut entry = match typ {
        EntryType::File => {
            let path = get_path(t, "path")?;

            let content = match t.raw_get("content")? {
                LuaValue::String(s) => s.as_bytes().to_vec(),
                LuaValue::Buffer(b) => b.to_vec(),
                other => {
                    return wrap_err!("expected entry.content to be a string or buffer, got: {:?}", other);
                }
            };

            ArchiveEntry::file(path, content)
        },
        EntryType::Directory => {
            let path = get_path(t, "path")?;
            ArchiveEntry::directory(path)
        },
        EntryType::Symlink => {
            let path = get_path(t, "path")?;
            let target = get_path(t, "target")?;
            ArchiveEntry::symlink(path, target)
        }
    };

    if let Some(mode) = mode {
        entry = entry.with_mode(mode);
    }
    if let Some(mtime) = mtime {
        entry = entry.with_mtime(mtime);
    }

    Ok(Entries::One(entry))
}

/// Converts an entry's `mtime` into a `DateTime` userdata (from `@std/time`), or `LuaNil` if
/// the source format didn't record one.
fn mtime_to_lua(mtime: Option<SystemTime>, luau: &Lua) -> LuaValueResult {
    match mtime {
        Some(mtime) => DateTime::from_system_time(mtime, "Archive entry mtime")?.get_userdata(luau),
        None => Ok(LuaNil),
    }
}

pub(super) fn to_table(entry: &ArchiveEntry, luau: &Lua) -> LuaResult<LuaTable> {
    match entry {
        ArchiveEntry::Directory { path, mode, mtime } => {
            TableBuilder::create(luau)?
                .with_value("type", "Directory")?
                .with_value("path", path.to_owned())?
                .with_value("mode", *mode)?
                .with_value("mtime", mtime_to_lua(*mtime, luau)?)?
                .build()
        },
        ArchiveEntry::File { path, data, mode, mtime } => {
            TableBuilder::create(luau)?
                .with_value("type", "File")?
                .with_value("path", path.to_owned())?
                .with_value("content", ok_string(data, luau)?)?
                .with_value("mode", *mode)?
                .with_value("mtime", mtime_to_lua(*mtime, luau)?)?
                .build()
        },
        ArchiveEntry::Symlink { path, target, mode, mtime } => {
            TableBuilder::create(luau)?
                .with_value("type", "Symlink")?
                .with_value("path", path.to_owned())?
                .with_value("target", target.to_owned())?
                .with_value("mode", *mode)?
                .with_value("mtime", mtime_to_lua(*mtime, luau)?)?
                .build()
        }
    }
}

/// Builds the lightweight metadata table returned by `Archive:info`: everything about an
/// entry except its file content, so callers can inspect large archives without paying for a
/// copy of every entry's bytes.
pub(super) fn to_info_table(entry: &ArchiveEntry, luau: &Lua) -> LuaResult<LuaTable> {
    let builder = TableBuilder::create(luau)?
        .with_value("path", entry.path().to_owned())?
        .with_value("mode", entry.mode())?
        .with_value("mtime", mtime_to_lua(entry.mtime(), luau)?)?;

    match entry {
        ArchiveEntry::Directory { .. } => {
            builder
                .with_value("type", "Directory")?
                .build()
        },
        ArchiveEntry::File { data, .. } => {
            builder
                .with_value("type", "File")?
                .with_value("size", FileSize::from_bytes(data.len() as u64).into_userdata(luau)?)?
                .build()
        },
        ArchiveEntry::Symlink { target, .. } => {
            builder
                .with_value("type", "Symlink")?
                .with_value("target", target.to_owned())?
                .build()
        }
    }
}

pub(super) fn archive_format_from_str(f: &str, function_name: &'static str) -> LuaResult<ArchiveFormat> {
    let formats = [
        ("zip", ArchiveFormat::Zip),
        ("tar", ArchiveFormat::Tar),
        ("ar", ArchiveFormat::Ar),
        ("deb", ArchiveFormat::Deb),
        ("targz", ArchiveFormat::TarGz),
        ("tar.gz", ArchiveFormat::TarGz),
        ("tarbz2", ArchiveFormat::TarBz2),
        ("tar.bz2", ArchiveFormat::TarBz2),
        ("tarxz", ArchiveFormat::TarXz),
        ("tar.xz", ArchiveFormat::TarXz),
        ("tarzst", ArchiveFormat::TarZst),
        ("tar.zst", ArchiveFormat::TarZst),
        ("tarlz4", ArchiveFormat::TarLz4),
        ("tar.lz4", ArchiveFormat::TarLz4),
        ("gz", ArchiveFormat::Gz),
        ("bz2", ArchiveFormat::Bz2),
        ("xz", ArchiveFormat::Xz),
        ("lz4", ArchiveFormat::Lz4),
        ("zst", ArchiveFormat::Zst),
        ("sevenz", ArchiveFormat::SevenZ),
        ("7z", ArchiveFormat::SevenZ),
    ];

    for (tag, format) in formats {
        if f.eq_ignore_ascii_case(tag) {
            return Ok(format);
        }
    }

    wrap_err!("{}: format '{}' is not one of the archive/single-file formats that we expected", function_name, f)
}