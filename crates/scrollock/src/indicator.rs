use std::process::{Child, Command};
use tracing::{debug, warn};

pub trait Indicator: std::fmt::Debug {
    fn enter_scroll(&mut self) {}
    fn exit_scroll(&mut self) {}
}

#[derive(Debug, Default)]
pub struct NoopIndicator;

impl Indicator for NoopIndicator {}

/// Indicator that spawns/kills an external overlay process.
#[derive(Debug)]
pub struct OverlayIndicator {
    child: Option<Child>,
    command: String,
}

impl OverlayIndicator {
    pub fn new() -> Self {
        // Look for scrollock-indicator in PATH
        let command = "scrollock-indicator".to_string();
        Self {
            child: None,
            command,
        }
    }
}

impl Indicator for OverlayIndicator {
    fn enter_scroll(&mut self) {
        if self.child.is_some() {
            return; // Already showing
        }
        debug!("Indicator: spawning overlay");
        match Command::new(&self.command).spawn() {
            Ok(child) => {
                self.child = Some(child);
            }
            Err(e) => {
                warn!("Failed to spawn indicator overlay: {e}");
            }
        }
    }

    fn exit_scroll(&mut self) {
        if let Some(mut child) = self.child.take() {
            debug!("Indicator: killing overlay");
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}

impl Drop for OverlayIndicator {
    fn drop(&mut self) {
        self.exit_scroll();
    }
}
