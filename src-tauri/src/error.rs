use serde::Serialize;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum CollectorError {
    #[error("读取本机套接字失败: {0}")]
    Netstat(String),
}

#[derive(Debug, Error)]
pub enum AppError {
    #[error(transparent)]
    Collector(#[from] CollectorError),
    #[error("内部状态锁已损坏")]
    Poisoned,
    #[error("{0}")]
    Message(String),
}

impl Serialize for AppError {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.to_string())
    }
}
