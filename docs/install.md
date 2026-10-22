# Installation

Sparlectra 0.60.0 is not in the General registry yet. The study takes it
from the public GitHub repository at a fixed commit, set in `Project.toml`:

```toml
[sources]
Sparlectra = {url = "https://github.com/Welthulk/Sparlectra.jl", rev = "a3cd5bc9011b57e5479109f3297f39390a9880e5"}
```

`Manifest.toml` pins every other package. Nothing has to be registered.

## 1. Julia

Install Julia with juliaup.

Linux and macOS:

```
curl -fsSL https://install.julialang.org | sh
```

Windows (PowerShell or cmd):

```
winget install --name Julia --id 9NJNWW8PVKMN -e -s msstore
```

Open a new terminal afterwards. The manifest was resolved with Julia 1.13.2
(`julia_version` in `Manifest.toml`), use that version. Check it with

```
julia --version
```

Only if it does not show 1.13.2:

```
juliaup add 1.13.2
juliaup default 1.13.2
```

`juliaup default` changes the default Julia of your user account. To keep
it, start the study with `julia +1.13.2` instead of `julia`.

Sparlectra needs Julia 1.12 or later. With a version other than 1.13.2 Pkg
warns about the manifest and may resolve other package versions; the
results are then not guaranteed to be identical.

## 2. Git

Needed to clone this repository.

- Linux: `sudo apt install git` (Debian, Ubuntu) or the package manager of
  the distribution.
- macOS: `xcode-select --install`.
- Windows: `winget install --id Git.Git -e`.

## 3. Get the study

The repository is public, cloning needs no credentials:

```
git clone https://github.com/Welthulk/pvpq-study.git
cd pvpq-study
```

## 4. Install the environment

In the `pvpq-study` directory:

```
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

This downloads the General registry, the pinned packages and Sparlectra at
commit a3cd5bc9 from GitHub, then precompiles. On an empty Julia depot this
takes a few minutes.

## 5. Reproduce

```
julia reproduce.jl
```

`reproduce.jl` runs `Pkg.instantiate()` again (fast once installed),
deletes `results/` and writes it new: `runs.csv`, `pairs.csv`,
`decision.txt`, `narrow_lock.csv`, `consistency.csv`,
`sp_case60_narrow.txt`, the Q(U) files (`runs_softpv.csv`,
`pairs_softpv.csv`, `h2_softpv.txt`, `stability_softpv.csv`,
`frozen_softpv.txt`, `softpv_bands.txt`), the final solutions in
`results/solutions/`, the configuration of every run in `results/configs/`
and the five figures. It also rewrites the networks in `cases/`.

Check after a run:

```
git status --short results/ cases/
```

It shows nothing: every file is identical to the committed one. On another
machine (fonts, graphics library) the PNGs may differ in bytes; the CSV
files must not.

## Updating later

- Another Sparlectra commit: change `rev` in `[sources]`, then
  `julia --project=. -e "using Pkg; Pkg.resolve()"` and run
  `reproduce.jl` again.
- Registered Sparlectra 0.60.0, once it exists: delete the `[sources]`
  section from `Project.toml`, start `julia --project=.`, press `]` and
  enter `add Sparlectra@0.60.0`. Then run `reproduce.jl`.
- `Pkg.update()` moves every other package (Plots and its dependencies) to
  the newest compatible version and rewrites `Manifest.toml`. Sparlectra
  stays at the commit in `[sources]`. The figures and, in principle, the
  numbers can change; compare `results/` with `git diff` before committing
  a new manifest.

## Troubleshooting

- `git: command not found` (Windows: "git is not recognized"): install git
  (step 2) and open a new terminal.
- Proxy: set `HTTPS_PROXY` and `HTTP_PROXY` for the package downloads, and
  `git config --global http.proxy http://proxy.example:8080` for
  `git clone`. Pkg fetches Sparlectra through its own git library; if that
  fails behind the proxy, set `JULIA_PKG_USE_CLI_GIT=true` so Pkg uses the
  installed git with its proxy setting. If the Julia package server
  (`pkg.julialang.org`) is blocked, set `JULIA_PKG_SERVER` to a reachable
  mirror, or to an empty string to fetch from GitHub directly.
- The first `Pkg.instantiate()` and the first run are slow because packages
  are precompiled. Later runs use the compile cache.
- `GKS: Open failed` or a Qt message (`qt.qpa`, locale switched to
  `C.UTF-8`): GR has tried to open a window, and the PNGs can come out with
  another layout. `figures.jl` sets `GKSwstype=100` before `using Plots` to
  prevent this.
