# Lua package manager benchmarks

## Background

The LDE project published benchmarks of its Lua package manager, claiming it is much faster than Lux.
On review, the benchmarks raised some concerns:

### Posted benchmarks - Cold install

- Lde's cold installs look too fast to be true.

![busted cold install benchmarks](https://github.com/user-attachments/assets/b4817cf5-22dd-4293-9016-f31a210f4022)
![lfs cold install benchmarks](https://github.com/user-attachments/assets/55e20fd3-62d6-4e6b-8551-bd1b7065bd8c)

### Posted benchmarks - Warm install

- Lux's warm install is about as slow as its cold install.

![warm install benchmarks](https://github.com/user-attachments/assets/2069f6ee-9af5-47ea-8701-59735c1618fc)

## Findings

We reproduced the benchmarks using [hyperfine](https://github.com/sharkdp/hyperfine),
the Lux Nix flake, and the [lde-nix](https://github.com/lde-org/lde-nix) flake.

### Problems - Cold install

#### Potentially unfavourable environment for Lux

The [lde benchmarks](https://github.com/lde-org/lde/blob/1cc3c6248fe0a15a65183337aacf8f877332d344/benchmarks/src/init.lua)
run [in an unfavourable environment](https://github.com/lde-org/lde/blob/master/.github/workflows/benchmark.yml) for Lux,
with no Lua installation and no pkg-config/pkgconf for Lux to detect it.
Because of this, in each cold run in the LDE benchmarks Lux has to:

- Fetch the Lua sources.
- Build and install Lua from source.
- Install the package.

That may explain why Lux's cold installs look slower than usual.

#### Lde 0.9.1 doesn't actually install the package.

With lde 0.9.1 (provided by the lde-nix flake) in the devShell, we ran:

```bash
lde --tree /tmp/lde install busted
```

It completed almost instantly.
The install tree contained a single file, `tools/busted`, with the following content:

```bash
#!/bin/sh
exec lde x rocks:busted "$@"
```

This is not a busted installation. Executing that file causes lde to install busted, which explains why the cold "install" appears so fast.

The lde codebase contains [a commit](https://github.com/lde-org/lde/commit/1e1d7b0088782d8ec91a9e39838a40e0e239a7b2) addressing this:

```gitcommit
feat: build package on lde install <package>

No longer only lazily does this when you first invoke the tool. Behavior
in-line with luarocks and more fair for the benchmark..
```

It appears that published results were not updated to reflect this change.

#### Suppressing stdout only for lde

Curiously, the [lde benchmarks only appear to suppres `stdout` for lde](https://github.com/lde-org/lde/blob/1cc3c6248fe0a15a65183337aacf8f877332d344/benchmarks/src/init.lua#L95):

```lua
process.exec("lde", { "--tree", tmpdir .. "/lde", "install", "rocks:busted" }, { stdout = "null" })
```

vs

```lua
process.exec("lx", { "--tree", tmpdir .. "/rocks", "install", "busted" })
```

Terminal standard I/O writes introduce measurable execution overhead (especially under heavy logging).
By explicitly discarding stdout for `lde` while allowing `luarocks` and `lx` to write uninhibited output to standard stream buffers,
`lde` receives an unfair performance advantage.
To ensure the benchmark is fair, stdout handling should be standardized across all tools
(e.g., silencing all tools uniformly or permitting all to write).

### Problems - Warm install

The reason Lux performs so poorly in lde's "warm" install benchmarks is visible in [the benchmark source](https://github.com/lde-org/lde/blob/1cc3c6248fe0a15a65183337aacf8f877332d344/benchmarks/src/init.lua#L112):

```lua
code, _, stderr = process.exec("lx", { "--tree", tmpdir .. "/rocks", "install", "--force", "busted" })
```

Looking at `lx install --help`:

```
Usage: lx install [OPTIONS] [PACKAGE_REQ]...

Arguments:
  [PACKAGE_REQ]...  Package or list of packages to install

Options:
      --pin    Pin the packages so that they don't get updated
      --force  Reinstall without prompt if a package is already installed
  -h, --help   Print help
```

The `--force` flag forces a reinstall, so this does not measure a warm install.
It appears to be used to bypass Lux's `<package> already exists. Overwrite?` prompt.
For a warm install, `--no-prompt` should be used instead.

## Our hyperfine benchmarks

Here are the results of our hyperfine benchmarks:

### Install busted (cold)

![busted cold install benchmarks](https://github.com/user-attachments/assets/4a35d269-a86d-47bd-b27e-ebc16b279ba5)

### Install busted (warm)

![busted warm install benchmarks](https://github.com/user-attachments/assets/e2639d65-c593-40d3-bbe6-66cf6669e0f0)

### Install luafilesystem (cold)

![lfs cold install benchmarks](https://github.com/user-attachments/assets/99b3ac92-88c2-433a-90bc-223a2b0235ef)

## Reproducing

This repository contains a [Nix flake](./flake.nix) with the following packages:

- `busted-cold`
- `busted-warm`
- `lfs-build`

The environment (as of writing this README) is:

- Hyperfine version 1.20.0 to run the benchmarks.
- Lux imported from the [lux flake](https://github.com/lumen-oss/lux/blob/main/flake.nix), version 0.40.0.
  Note: the [flake input](./flake.nix) is unpinned and follows `main`, so the version may drift over time.
- Lde built in [lde.nix](./lde.nix), version 0.10.0.
- Luarocks version 3.13.0.
- pkg-config
- Lua 5.1

## Running the benchmarks

- Use `nix develop` to enter a devShell (must have flakes enabled).
- Run one of the benchmarks: `busted-cold`, `busted-warm` or `lfs-build`.

> ![NOTE]
>
> The devShell is needed for pkg-config to be set up correctly.

### Benchmark parameters

The hyperfine parameters are defined in [flake.nix](./flake.nix):

- Cold installs (`busted-cold`, `lfs-build`): `--warmup 0 --runs 5`, with a `--prepare` step that clears the install tree between runs.
- Warm installs (`busted-warm`): `--warmup 2 --runs 10`, with the packages pre-installed before benchmarking.
