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

{ pkgs ? import <nixpkgs> {}, withUnfreePkgs ? false, useNightlyToolchain ? true }:

with builtins;
let
  inherit (pkgs) stdenv lib;

  # Tockloader v1.11.0
  tockloader = import (pkgs.fetchFromGitHub {
    owner = "tock";
    repo = "tockloader";
    rev = "v1.11.0";
    sha256 = "sha256-bPEfpfOZOjOiazqRgn1cnqe4ohLPvocuENKoZx/Qw80=";
  }) { inherit pkgs withUnfreePkgs; };

  # Rust toolchain overlay
  rust_overlay = import "${pkgs.fetchFromGitHub {
    owner = "nix-community";
    repo = "fenix";
    rev = "1a92c6d75963fd594116913c23041da48ed9e020";
    sha256 = "sha256-L3vZfifHmog7sJvzXk8qiKISkpyltb+GaThqMJ7PU9Y=";
  }}/overlay.nix";

  nixpkgs = import <nixpkgs> { overlays = [ rust_overlay ]; };

  # Use nightly development toolchain by default because Miri is not supported
  # by the MSRV (Minimum Supported Rust Version) toolchain.
  rustBuild = if useNightlyToolchain then (
    nixpkgs.fenix.fromToolchainFile { file = ./nightly/rust-toolchain.toml; }
  ) else (
    nixpkgs.fenix.fromToolchainFile { file = ./rust-toolchain.toml; }
  );

in
  pkgs.mkShell {
    name = "tock-dev";

    buildInputs = with pkgs; [
      # --- Toolchains ---
      rustBuild
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

    LD_LIBRARY_PATH="${stdenv.cc.cc.lib}/lib64:$LD_LIBRARY_PATH";

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
