use std::process::Command;

use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LsofSample {
    pub line_count: usize,
}

/// Count local internet sockets reported by `lsof -nP -i`.
///
/// This is a side check against the netstat2 snapshot. It does not probe other hosts.
pub fn sample() -> Result<LsofSample, String> {
    let output = Command::new("/usr/sbin/lsof")
        .args(["-nP", "-i"])
        .output()
        .map_err(|err| format!("无法运行 lsof: {err}"))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let line_count = stdout
        .lines()
        .skip(1)
        .filter(|line| !line.trim().is_empty())
        .count();

    if !output.status.success() && line_count == 0 {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if stderr.is_empty() {
            return Err(format!("lsof 退出码 {}", output.status));
        }
        return Err(stderr);
    }

    Ok(LsofSample { line_count })
}
