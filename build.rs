use std::{env, path::PathBuf};

fn main() {
    if cfg!(feature = "mock") {
        return;
    }

    // Get SDK paths (trim whitespace/quotes to be resilient to env var formatting)
    let dlss_sdk = env::var("DLSS_SDK")
        .expect("DLSS_SDK environment variable not set. Consult the dlss_wgpu readme.")
        .trim_matches(|c: char| c == '"' || c.is_whitespace())
        .to_string();
    let vulkan_sdk = env::var("VULKAN_SDK")
        .expect("VULKAN_SDK environment variable not set")
        .trim_matches(|c: char| c == '"' || c.is_whitespace())
        .to_string();
    let out_dir = PathBuf::from(env::var("OUT_DIR").unwrap());

    let dlss_sdk = PathBuf::from(dlss_sdk);
    let vulkan_sdk = PathBuf::from(vulkan_sdk);

    // Verify expected headers exist
    let vulkan_include = vulkan_sdk.join(if cfg!(target_os = "windows") { "Include" } else { "include" });
    let vulkan_header = vulkan_include.join("vulkan").join("vulkan.h");
    if !vulkan_header.exists() {
        panic!(
            "Could not find Vulkan header at {}. Ensure VULKAN_SDK points to a valid Vulkan SDK installation.",
            vulkan_header.display()
        );
    }

    // Link to needed libraries
    #[cfg(not(target_os = "windows"))]
    {
        println!("cargo:rustc-link-search=native={}/lib/Linux_x86_64", dlss_sdk.display());
        println!("cargo:rustc-link-lib=static=nvsdk_ngx");
        println!("cargo:rustc-link-lib=dylib=stdc++");
        println!("cargo:rustc-link-lib=dylib=dl");
    }
    #[cfg(target_os = "windows")]
    {
        println!("cargo:rustc-link-search=native={}/lib/Windows_x86_64/x64", dlss_sdk.display());
        #[cfg(not(target_feature = "crt-static"))]
        println!("cargo:rustc-link-lib=static=nvsdk_ngx_d");
        #[cfg(target_feature = "crt-static")]
        println!("cargo:rustc-link-lib=static=nvsdk_ngx_s");
    }

    // Generate rust bindings
    bindgen::Builder::default()
        .header(format!("{}/src/wrapper.h", env!("CARGO_MANIFEST_DIR")))
        .parse_callbacks(Box::new(bindgen::CargoCallbacks::new()))
        .wrap_static_fns(true)
        .wrap_static_fns_path(out_dir.join("wrap_static_fns"))
        // clang_arg takes each argument as a separate string (no shell splitting), so we pass -I and the path separately.
        .clang_arg("-I")
        .clang_arg(dlss_sdk.join("include").display().to_string())
        .clang_arg("-I")
        .clang_arg(vulkan_include.display().to_string())
        .allowlist_item(".*NGX.*")
        .blocklist_item("Vk.*")
        .blocklist_item("PFN_vk.*")
        .blocklist_item(".*Cuda.*")
        .blocklist_item(".*CUDA.*")
        .generate()
        .unwrap()
        .write_to_file(out_dir.join("bindings.rs"))
        .unwrap();

    // Generate and link a library for static inline functions
    cc::Build::new()
        .file(out_dir.join("wrap_static_fns.c"))
        .include(dlss_sdk.join("include"))
        .include(vulkan_include)
        .compile("wrap_static_fns");
}
