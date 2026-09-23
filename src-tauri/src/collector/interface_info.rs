use sysinfo::Networks;

use crate::model::InterfaceInfo;

pub struct InterfaceInfoCollector {
    networks: Networks,
}

impl InterfaceInfoCollector {
    pub fn new() -> Self {
        Self {
            networks: Networks::new_with_refreshed_list(),
        }
    }

    pub fn collect(&mut self) -> Vec<InterfaceInfo> {
        self.networks.refresh(true);
        self.networks
            .iter()
            .map(|(name, data)| InterfaceInfo {
                name: name.clone(),
                received_bytes: data.total_received(),
                transmitted_bytes: data.total_transmitted(),
            })
            .collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lists_at_least_the_loopback_interface() {
        let mut collector = InterfaceInfoCollector::new();
        let interfaces = collector.collect();
        assert!(
            interfaces.iter().any(|interface| interface.name == "lo0"),
            "expected lo0, got {interfaces:?}"
        );
    }
}
