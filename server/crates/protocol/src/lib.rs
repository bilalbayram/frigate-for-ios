//! Wire types shared by `iwa-agent`, the Iwa relay, and the Apple app.
//!
//! This crate must build for both native targets and `wasm32-unknown-unknown`
//! (the relay runs on Cloudflare Workers), so it avoids OS-specific APIs.

/// Bumped on any incompatible change to agent ↔ relay ↔ app messages.
pub const PROTOCOL_VERSION: u32 = 1;

/// A paired Apple device, identified by the hash of its X25519 public key.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct DeviceId(pub String);

/// When a Frigate review item or event should produce a push.
///
/// Rules are evaluated by `iwa-agent`; the relay never sees them.
#[derive(Debug, Clone, PartialEq)]
pub struct NotificationRule {
    /// `None` applies to every paired device in the household.
    /// Per-device rules are not exposed in the v1 UI, but the field exists so adding them needs no migration.
    pub device_id: Option<DeviceId>,
    /// Empty matches every camera.
    pub cameras: Vec<String>,
    /// Empty matches every zone.
    pub zones: Vec<String>,
    /// Empty matches every label.
    pub labels: Vec<String>,
    pub severity: Severity,
    /// Minimum seconds between pushes for the same camera.
    pub cooldown_seconds: u32,
}

/// Frigate review item severity.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Severity {
    Alert,
    Detection,
}

/// The parts of a Frigate review item a rule matches against.
#[derive(Debug, Clone, PartialEq)]
pub struct ReviewItem<'a> {
    pub camera: &'a str,
    pub zones: &'a [&'a str],
    pub labels: &'a [&'a str],
    pub severity: Severity,
}

impl NotificationRule {
    /// Whether `item` matches this rule's filters. Cooldowns are applied by the caller.
    pub fn matches(&self, item: &ReviewItem<'_>) -> bool {
        fn any_of(filter: &[String], values: &[&str]) -> bool {
            filter.is_empty() || values.iter().any(|value| filter.iter().any(|f| f == value))
        }

        self.severity == item.severity
            && any_of(&self.cameras, &[item.camera])
            && any_of(&self.zones, item.zones)
            && any_of(&self.labels, item.labels)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rule() -> NotificationRule {
        NotificationRule {
            device_id: None,
            cameras: vec!["front_door".into()],
            zones: vec![],
            labels: vec!["person".into()],
            severity: Severity::Alert,
            cooldown_seconds: 60,
        }
    }

    #[test]
    fn matches_camera_and_label() {
        let item = ReviewItem {
            camera: "front_door",
            zones: &["porch"],
            labels: &["person", "dog"],
            severity: Severity::Alert,
        };
        assert!(rule().matches(&item));
    }

    #[test]
    fn rejects_other_camera_severity_or_label() {
        let base = ReviewItem {
            camera: "front_door",
            zones: &[],
            labels: &["person"],
            severity: Severity::Alert,
        };
        assert!(!rule().matches(&ReviewItem { camera: "garage", ..base.clone() }));
        assert!(!rule().matches(&ReviewItem { severity: Severity::Detection, ..base.clone() }));
        assert!(!rule().matches(&ReviewItem { labels: &["car"], ..base }));
    }

    #[test]
    fn empty_filters_match_everything() {
        let rule = NotificationRule { cameras: vec![], labels: vec![], ..rule() };
        let item = ReviewItem {
            camera: "anything",
            zones: &[],
            labels: &[],
            severity: Severity::Alert,
        };
        assert!(rule.matches(&item));
    }
}
