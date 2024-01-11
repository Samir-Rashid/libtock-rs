# Licensed under the Apache License, Version 2.0 or the MIT License.
# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright Tock Contributors 2022.

# Shell expression for the Nix package manager
#
# This nix expression creates an environment with necessary packages installed:
#
#  * `tockloader`
#  * rust
#
# To use:
#
#  $ nix-shell
#

{ pkgs ? import <nixpkgs> { }, withUnfreePkgs ? false }:

with builtins;
let
  inherit (pkgs) stdenv lib;

  # Tockloader v1.11.0
  tockloader = import
    (pkgs.fetchFromGitHub {
      owner = "tock";
      repo = "tockloader";
      rev = "v1.11.0";
      sha256 = "sha256-bPEfpfOZOjOiazqRgn1cnqe4ohLPvocuENKoZx/Qw80=";
    })
    { inherit pkgs withUnfreePkgs; };

  # Rust toolchain overlay
  rust_overlay = import "${pkgs.fetchFromGitHub {
    owner = "nix-community";
    repo = "fenix";
    rev = "ffa0a8815be591767f82d42c63d88bfa4026a967"; # bruh
    sha256 = "sha256-JOrXleSdEKuymCyxg7P4GTTATDhBdfeyWcd1qQQlIYw=";
  }}/overlay.nix";

  nixpkgs = import <nixpkgs> { overlays = [ rust_overlay ]; };

  # Use nightly development toolchain by default because Miri is not supported
  # by the MSRV (Minimum Supported Rust Version) toolchain.

  nightlyToolchain = nixpkgs.fenix.fromToolchainName {
    name = (lib.importTOML ./nightly/rust-toolchain.toml).toolchain.channel;
    sha256 = "sha256-R/ONZzJaWQr0pl5RoXFIbnxIE3m6oJWy/rr2W0wXQHQ=";
  };
  # combine the toolchain components
  combinedToolchain =
    nightlyToolchain.withComponents
      ((lib.importTOML ./nightly/rust-toolchain.toml).toolchain.components ++
        (lib.importTOML ./rust-toolchain.toml).toolchain.components ++ [ "cargo" ]);
  rustBuild =
    nixpkgs.fenix.combine
      (
        foldl'
          (acc: item: acc ++ [ nixpkgs.fenix.targets.${item}.latest.rust-std ])
          [ combinedToolchain ]
          ((lib.importTOML ./rust-toolchain.toml).toolchain.targets)
      );

  #rustBuildNightly = (
  #  nixpkgs.fenix.fromToolchainFile { file = ./nightly/rust-toolchain.toml; }
  #);
  # nixpkgs.fenix.toolchainOf {
  #   # file = ./nightly/rust-toolchain.toml; 
  #   channel = (lib.importTOML ./nightly/rust-toolchain.toml).toolchain.channel;
  # };

in
pkgs.mkShell
{
  name = "tock-dev";

  buildInputs = with pkgs; [
    # --- Toolchains ---
    rustBuild
    #rustBuildNightly
    openocd

    # --- Convenience and support packages ---
    python3Full
    tockloader

    # Required for tools/print_tock_memory_usage.py
    python3Packages.cxxfilt


    # --- CI support packages ---
    qemu

    # --- Flashing tools ---
    # If your board requires J-Link to flash and you are on NixOS,
    # add these lines to your system wide configuration.

    # Enable udev rules from segger-jlink package
    # services.udev.packages = [
    #     pkgs.segger-jlink
    # ];

    # Add "segger-jlink" to your system packages and accept the EULA:
    # nixpkgs.config.segger-jlink.acceptLicense = true;
  ];

  LD_LIBRARY_PATH = "${stdenv.cc.cc.lib}/lib64:$LD_LIBRARY_PATH";

  # Instruct the Tock gnumake-based build system to not check for rustup and
  # assume all requirend tools are installed and available in the $PATH
  NO_RUSTUP = "1";

  # The defaults "objcopy" and "objdump" are wrong (stem from the standard
  # environment for x86), use "llvm-obj{copy,dump}" as defined in the makefile
  shellHook = ''
    unset OBJCOPY
    unset OBJDUMP
  '';
}
