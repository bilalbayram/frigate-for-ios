fn main() {
    println!(
        "iwa-agent {} (protocol v{})",
        env!("CARGO_PKG_VERSION"),
        iwa_protocol::PROTOCOL_VERSION
    );
}
