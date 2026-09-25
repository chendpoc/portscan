use std::mem::{size_of, MaybeUninit};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct ProcessStart {
    pub seconds: u64,
    pub microseconds: u64,
}

/// Read an instance discriminator from macOS rather than treating a PID as stable identity.
pub fn process_start(pid: u32) -> Option<ProcessStart> {
    let pid = i32::try_from(pid).ok().filter(|pid| *pid > 0)?;
    let expected = i32::try_from(size_of::<libc::proc_bsdinfo>()).ok()?;
    let mut info = MaybeUninit::<libc::proc_bsdinfo>::uninit();
    // SAFETY: the buffer has the exact size required for PROC_PIDTBSDINFO. We only
    // read it when macOS reports that all bytes were initialized.
    let written = unsafe {
        libc::proc_pidinfo(
            pid,
            libc::PROC_PIDTBSDINFO,
            0,
            info.as_mut_ptr().cast(),
            expected,
        )
    };
    if written != expected {
        return None;
    }
    // SAFETY: a full-size successful proc_pidinfo result initialized the struct.
    let info = unsafe { info.assume_init() };
    (info.pbi_pid == pid as u32).then_some(ProcessStart {
        seconds: info.pbi_start_tvsec,
        microseconds: info.pbi_start_tvusec,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use sysinfo::{Pid, ProcessRefreshKind, ProcessesToUpdate, System};

    #[test]
    fn current_pid_is_visible_with_matching_start_time() {
        let pid = std::process::id();
        let start = process_start(pid).expect("macOS should reveal this process start time");
        let mut system = System::new();
        system.refresh_processes_specifics(
            ProcessesToUpdate::All,
            true,
            ProcessRefreshKind::nothing().with_memory(),
        );
        let process = system
            .process(Pid::from_u32(pid))
            .expect("all-process scan should contain this process");
        assert_eq!(start.seconds, process.start_time());
        assert!(system.processes().len() > 1);
    }
}
