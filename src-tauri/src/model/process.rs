use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EvidenceState {
    Available,
    Restricted,
    Unavailable,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PathEvidence {
    pub state: EvidenceState,
    pub path: Option<String>,
    pub message: Option<String>,
}

impl PathEvidence {
    pub fn available(path: String) -> Self {
        Self {
            state: EvidenceState::Available,
            path: Some(path),
            message: None,
        }
    }

    pub fn restricted(message: impl Into<String>) -> Self {
        Self {
            state: EvidenceState::Restricted,
            path: None,
            message: Some(message.into()),
        }
    }

    pub fn unavailable(message: impl Into<String>) -> Self {
        Self {
            state: EvidenceState::Unavailable,
            path: None,
            message: Some(message.into()),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AncestryNode {
    pub key: ProcessKey,
    pub name: String,
    pub relationship_verified: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcessKey {
    pub pid: u32,
    pub start_sec: u64,
    /// macOS proc_bsdinfo precision. None means identity-sensitive actions are disabled.
    pub start_usec: Option<u64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ProcessState {
    Running,
    Sleeping,
    Stopped,
    Zombie,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcessEntry {
    pub key: ProcessKey,
    pub name: String,
    /// None until a second, sufficiently spaced sample of this process instance.
    pub cpu_percent: Option<f32>,
    /// Resident memory (RSS) in bytes, when a process record is available.
    pub rss_bytes: Option<u64>,
    pub status: ProcessState,
    pub parent_pid: Option<u32>,
    pub cwd: PathEvidence,
    pub executable: PathEvidence,
    pub context_display: Option<String>,
    pub context_kind: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ProcessDetail {
    pub key: ProcessKey,
    /// OS-provided argv, preserving argument boundaries. None means unavailable.
    pub command: Option<Vec<String>>,
    pub exe: Option<String>,
    pub cwd: PathEvidence,
    pub executable: PathEvidence,
    pub app_bundle: Option<String>,
    pub collected_at: String,
    pub verified_at: String,
    pub ancestry: Vec<AncestryNode>,
    pub ancestry_incomplete: bool,
    pub start_time_iso: Option<String>,
}
