use std::ffi::CStr;
use std::mem::{size_of, MaybeUninit};
use std::path::{Path, PathBuf};

use super::macos_identity::{process_start, ProcessStart};
use crate::model::{EvidenceState, PathEvidence, ProcessKey};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProcessContextSnapshot {
    pub cwd: PathEvidence,
    pub executable: PathEvidence,
    pub context_display: Option<String>,
    pub context_kind: Option<String>,
}

pub fn read_process_context(key: ProcessKey) -> ProcessContextSnapshot {
    let identity = match key.start_usec {
        Some(microseconds) => ProcessStart {
            seconds: key.start_sec,
            microseconds,
        },
        None => {
            return empty_context(
                EvidenceState::Unavailable,
                "Process identity is unavailable",
            );
        }
    };
    if process_start(key.pid) != Some(identity) {
        return empty_context(EvidenceState::Unavailable, "Process exited or changed");
    }

    let cwd = read_cwd(key.pid);
    let executable = read_executable(key.pid);

    if process_start(key.pid) != Some(identity) {
        return ProcessContextSnapshot {
            cwd: PathEvidence::unavailable("Process exited during context read"),
            executable: PathEvidence::unavailable("Process exited during context read"),
            context_display: None,
            context_kind: None,
        };
    }

    let (context_display, context_kind) = display_context(&cwd, &executable);
    ProcessContextSnapshot {
        cwd,
        executable,
        context_display,
        context_kind,
    }
}

pub fn verified_cwd_for_terminal(key: ProcessKey) -> Result<String, String> {
    let expected = key.start_usec.map(|microseconds| ProcessStart {
        seconds: key.start_sec,
        microseconds,
    });
    let Some(expected) = expected else {
        return Err("Process identity is unavailable".into());
    };
    if process_start(key.pid) != Some(expected) {
        return Err("Process exited or changed".into());
    }
    let cwd = read_cwd(key.pid);
    if process_start(key.pid) != Some(expected) {
        return Err("Process exited during working-directory verification".into());
    }
    match cwd.state {
        EvidenceState::Available => {
            let path = cwd
                .path
                .ok_or_else(|| "Working directory path missing".to_string())?;
            if !Path::new(&path).is_dir() {
                return Err("Working directory is not an existing directory".into());
            }
            Ok(path)
        }
        EvidenceState::Restricted => Err(cwd
            .message
            .unwrap_or_else(|| "Working directory is restricted by macOS".into())),
        EvidenceState::Unavailable => Err(cwd
            .message
            .unwrap_or_else(|| "Working directory is unavailable".into())),
    }
}

fn empty_context(state: EvidenceState, message: &str) -> ProcessContextSnapshot {
    let evidence = PathEvidence {
        state,
        path: None,
        message: Some(message.into()),
    };
    ProcessContextSnapshot {
        cwd: evidence.clone(),
        executable: evidence,
        context_display: None,
        context_kind: None,
    }
}

fn flatten_vip_path(path: &[[libc::c_char; 32]; 32]) -> Option<String> {
    let mut bytes = Vec::new();
    'segments: for segment in path {
        for &byte in segment {
            let byte = byte as u8;
            if byte == 0 {
                break 'segments;
            }
            bytes.push(byte);
            if bytes.len() >= 1024 {
                return None;
            }
        }
    }
    if bytes.is_empty() {
        return None;
    }
    String::from_utf8(bytes).ok()
}

fn read_cwd(pid: u32) -> PathEvidence {
    let pid = match i32::try_from(pid) {
        Ok(value) if value > 0 => value,
        _ => return PathEvidence::unavailable("Invalid process id"),
    };
    let mut info = MaybeUninit::<libc::proc_vnodepathinfo>::uninit();
    let expected = i32::try_from(size_of::<libc::proc_vnodepathinfo>()).unwrap_or(i32::MAX);
    // SAFETY: `info` matches the size required by PROC_PIDVNODEPATHINFO.
    let written = unsafe {
        libc::proc_pidinfo(
            pid,
            libc::PROC_PIDVNODEPATHINFO,
            0,
            info.as_mut_ptr().cast(),
            expected,
        )
    };
    if written <= 0 {
        return cwd_error();
    }
    if written != expected {
        return PathEvidence::unavailable("Incomplete working-directory response from macOS");
    }
    // SAFETY: macOS initialized the full struct.
    let info = unsafe { info.assume_init() };
    flatten_vip_path(&info.pvi_cdir.vip_path).map_or_else(
        || PathEvidence::unavailable("Working directory path unavailable from macOS"),
        PathEvidence::available,
    )
}

fn read_executable(pid: u32) -> PathEvidence {
    let pid = match i32::try_from(pid) {
        Ok(value) if value > 0 => value,
        _ => return PathEvidence::unavailable("Invalid process id"),
    };
    let mut buffer = [0u8; 1024];
    let written =
        unsafe { libc::proc_pidpath(pid, buffer.as_mut_ptr().cast(), buffer.len() as u32) };
    if written <= 0 {
        return exe_error();
    }
    path_from_cstr(&buffer).map_or_else(
        || PathEvidence::unavailable("Executable path unavailable from macOS"),
        PathEvidence::available,
    )
}

fn cwd_error() -> PathEvidence {
    match std::io::Error::last_os_error().raw_os_error() {
        Some(libc::EPERM) | Some(libc::EACCES) => {
            PathEvidence::restricted("macOS denied working-directory access")
        }
        Some(libc::ESRCH) => PathEvidence::unavailable("Process exited"),
        _ => PathEvidence::unavailable("Working directory unavailable from macOS"),
    }
}

fn exe_error() -> PathEvidence {
    match std::io::Error::last_os_error().raw_os_error() {
        Some(libc::EPERM) | Some(libc::EACCES) => {
            PathEvidence::restricted("macOS denied executable path access")
        }
        Some(libc::ESRCH) => PathEvidence::unavailable("Process exited"),
        _ => PathEvidence::unavailable("Executable path unavailable from macOS"),
    }
}

fn path_from_cstr(bytes: &[u8]) -> Option<String> {
    let cstr = CStr::from_bytes_until_nul(bytes).ok()?;
    let text = cstr.to_str().ok()?;
    if text.is_empty() {
        return None;
    }
    Some(text.to_string())
}

pub fn app_bundle_from_executable(path: &str) -> Option<String> {
    let path = PathBuf::from(path);
    for ancestor in path.ancestors() {
        let file_name = ancestor.file_name()?.to_str()?;
        if file_name.ends_with(".app") {
            return ancestor.to_str().map(str::to_string);
        }
    }
    None
}

pub fn abbreviate_home_with(path: &str, home: &str) -> String {
    if home.is_empty() {
        return path.to_string();
    }
    let prefix = format!("{home}/");
    if path == home {
        return "~".into();
    }
    if path.starts_with(&prefix) {
        return format!("~{}", &path[home.len()..]);
    }
    path.to_string()
}

pub fn abbreviate_home(path: &str) -> String {
    abbreviate_home_with(path, std::env::var("HOME").as_deref().unwrap_or(""))
}

fn display_context(
    cwd: &PathEvidence,
    executable: &PathEvidence,
) -> (Option<String>, Option<String>) {
    if cwd.state == EvidenceState::Available {
        if let Some(path) = cwd.path.as_deref() {
            return (Some(abbreviate_home(path)), Some("cwd".into()));
        }
    }
    if executable.state == EvidenceState::Available {
        if let Some(path) = executable.path.as_deref() {
            if let Some(app) = app_bundle_from_executable(path) {
                return (
                    Some(format!("App: {}", abbreviate_home(&app))),
                    Some("app".into()),
                );
            }
            return (
                Some(format!("Executable: {}", abbreviate_home(path))),
                Some("executable".into()),
            );
        }
    }
    if cwd.state == EvidenceState::Restricted || executable.state == EvidenceState::Restricted {
        return (
            Some("Restricted by macOS".into()),
            Some("restricted".into()),
        );
    }
    (
        Some("Unavailable from macOS".into()),
        Some("unavailable".into()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::mem::size_of;

    #[test]
    fn proc_vnodepathinfo_matches_macos_payload_size() {
        assert_eq!(size_of::<libc::proc_vnodepathinfo>(), 2352);
    }

    #[test]
    fn current_process_context_is_available_or_explicitly_restricted() {
        let pid = std::process::id();
        let start = process_start(pid).expect("start token");
        let key = ProcessKey {
            pid,
            start_sec: start.seconds,
            start_usec: Some(start.microseconds),
        };
        let snapshot = read_process_context(key);
        if snapshot.cwd.state != EvidenceState::Available
            && snapshot.cwd.state != EvidenceState::Restricted
        {
            panic!(
                "unexpected cwd state {:?}: {:?}",
                snapshot.cwd.state, snapshot.cwd.message
            );
        }
    }

    #[test]
    fn terminal_refuses_without_verified_cwd() {
        let key = ProcessKey {
            pid: std::process::id(),
            start_sec: 1,
            start_usec: Some(1),
        };
        assert!(verified_cwd_for_terminal(key).is_err());
    }

    #[test]
    fn abbreviate_home_with_is_pure() {
        assert_eq!(
            abbreviate_home_with("/Users/tester/code/portscan", "/Users/tester"),
            "~/code/portscan"
        );
    }

    fn pack_vip_path(text: &str) -> [[libc::c_char; 32]; 32] {
        let mut path = [[0 as libc::c_char; 32]; 32];
        for (index, byte) in text.bytes().enumerate() {
            if index >= 1024 {
                break;
            }
            path[index / 32][index % 32] = byte as libc::c_char;
        }
        path
    }

    #[test]
    fn flatten_vip_path_handles_empty_and_nested_segments() {
        assert_eq!(flatten_vip_path(&pack_vip_path("")), None);
        assert_eq!(
            flatten_vip_path(&pack_vip_path("/tmp/nested/path")),
            Some("/tmp/nested/path".into())
        );
    }

    #[test]
    fn flatten_vip_path_handles_unicode_and_early_nul() {
        let unicode = "/tmp/测试/🚀";
        assert_eq!(
            flatten_vip_path(&pack_vip_path(unicode)),
            Some(unicode.into())
        );
        let mut packed = pack_vip_path("/tmp/short");
        packed[0][4] = 0;
        assert_eq!(flatten_vip_path(&packed), Some("/tmp".into()));
    }

    #[test]
    fn flatten_vip_path_rejects_missing_terminator_in_full_buffer() {
        let full = [[1 as libc::c_char; 32]; 32];
        assert_eq!(flatten_vip_path(&full), None);
    }

    #[test]
    fn flatten_vip_path_rejects_invalid_utf8() {
        let mut invalid = pack_vip_path("bad");
        invalid[0][3] = 0xFF_u8 as libc::c_char;
        assert_eq!(flatten_vip_path(&invalid), None);
    }
}
