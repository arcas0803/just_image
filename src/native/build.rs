// rav1d's x86_64 assembly uses PC-relative references to tables defined in
// Rust. Bind those references inside the ELF shared library at link time.
fn main() {
    let arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    let os = std::env::var("CARGO_CFG_TARGET_OS").unwrap();
    if arch == "x86_64" && matches!(os.as_str(), "android" | "linux") {
        println!("cargo::rustc-link-arg-cdylib=-Wl,-Bsymbolic");
    }
}
