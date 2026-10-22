# PV/PQ switching strategies in Sparlectra: same network, different solutions

A small reproducible comparison of the three Q-limit strategies of
[Sparlectra.jl](https://github.com/Welthulk/Sparlectra.jl) 0.60.0: `active_set`,
`classic_simultaneous` and `classic_one_at_a_time`.
That the switching strategy can decide the final solution is known
(Zeng and Chiang, IJEPES 2023; Sundaresh and Rao, Sadhana 2015). This
repository is the open, recomputable version in Julia, plus a case with
machines of a narrow reactive band.

## Layout

| File | Content |
|---|---|
| `run_compare.jl` | one network, three strategies, same start values and tolerance; one CSV line per run (`results/runs.csv`), the final solution of every run (`results/solutions/`) |
| `compare.jl` | pairwise comparison of the final solutions (`results/pairs.csv`) and the decision rule for the main figure (`results/decision.txt`) |
| `figures.jl` | figures as PNG, 1200 x 627 px |
| `reproduce.jl` | everything above from a fresh checkout |
| `config/base.yaml` | settings of every run; per run the strategy and the guard are added (`results/configs/`) |
| `cases/` | the networks as SCF files, written by `run_compare.jl` |

Networks: `case14_zeng` (the case of Zeng and Chiang as shipped with
Sparlectra, `data/scf/case14_zeng_p306_activeSet_A.scf.json`), `sp_case14`,
`sp_case118` (`data/mpower/sp_case118.m`, converted to SCF), and
`sp_case60_narrow`, a copy of `sp_case60` in which the two 40 MW machines
with a voltage regulator (generators 159 and 160) get a reactive band of
4.0 to 5.5 Mvar, 0.015 pu at 100 MVA (`results/sp_case60_narrow.txt`).

Settings: rectangular Newton-Raphson, tolerance 1e-6 pu, at most 80
iterations, classic start, every automatic aid off (rescue, start projection,
automatic damping, merit, trust region, DC fallback). The guard for narrow
reactive bands (`power_flow.qlimits.guard`, default on, `min_q_range_pu` 0.02,
`narrow_range_mode` lock_pq) is on in the runs A and on and off in the runs B.

## Installation

Sparlectra 0.60.0 is not in the General registry yet. The study takes it
directly from the public GitHub repository at a fixed commit, set in
`Project.toml`:

```toml
[sources]
Sparlectra = {url = "https://github.com/Welthulk/Sparlectra.jl", rev = "a3cd5bc9011b57e5479109f3297f39390a9880e5"}
```

`Manifest.toml` pins every other package. Nothing has to be registered.

### 1. Julia

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
(`julia_version` in `Manifest.toml`), use that version:

```
juliaup add 1.13.2
juliaup default 1.13.2
julia --version
```

Sparlectra itself needs Julia 1.12 or later. With a version other than
1.13.2 Pkg warns about the manifest and may resolve other package versions;
the results are then not guaranteed to be identical.

### 2. Git

Needed to clone this repository.

- Linux: `sudo apt install git` (Debian, Ubuntu) or the package manager of
  the distribution.
- macOS: `xcode-select --install`.
- Windows: `winget install --id Git.Git -e`.

### 3. Get the study

The repository is private; your GitHub account needs read access. Over
HTTPS git asks for the user name and a personal access token, over SSH it
uses your SSH key:

```
git clone https://github.com/Welthulk/pvpq-study.git
cd pvpq-study
```

or

```
git clone git@github.com:Welthulk/pvpq-study.git
cd pvpq-study
```

### 4. Install the environment

In the `pvpq-study` directory:

```
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

This downloads the General registry, the pinned packages and Sparlectra at
commit a3cd5bc9 from GitHub (public, no credentials), then precompiles.
On an empty Julia depot this took 2 min 49 s here (AMD Ryzen AI 7 350,
16 threads, Linux, Julia 1.13.2), of which 65 s precompilation.

## Reproduce

```
julia reproduce.jl
```

`reproduce.jl` runs `Pkg.instantiate()` again (fast once installed),
deletes `results/` and writes it new: `runs.csv`, `pairs.csv`,
`decision.txt`, `narrow_lock.csv`, `sp_case60_narrow.txt`, the final
solutions in `results/solutions/`, the configuration of every run in
`results/configs/`, and the two figures. It also rewrites the networks in
`cases/`. It took 62 s on the first run after installation and 55 s on a
later run (same machine and Julia version as above).

Check: run it twice and look at

```
git status --short results/ cases/
```

It shows nothing: the CSV files are identical to the committed ones. On the
machine above the PNG files were byte-identical too; on another machine
(fonts, graphics library) they may differ in bytes without any change in
the numbers.

### Updating later

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

### Troubleshooting

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
  are precompiled (about a minute here, longer on slower machines). Later
  runs use the compile cache.
- Under a `C` locale the plotting library prints a Qt message about
  switching to `C.UTF-8`. It does not affect the results.

## Results

Runs A (guard on):

| Network | Strategy | Converged | Iterations | Buses PV to PQ | Slack P MW | Slack Q Mvar | Losses MW |
|---|---|---|---|---|---|---|---|
| case14_zeng | active_set | yes | 7 | 3 | -0.365 | 22.472 | 21.945 |
| case14_zeng | classic_simultaneous | yes | 9 | 4 | -0.804 | 18.422 | 21.506 |
| case14_zeng | classic_one_at_a_time | yes | 11 | 2 | -0.371 | 22.257 | 21.939 |
| sp_case14 | all three | yes | 4 | 0 | 19.705 | 13.205 | 1.705 |
| sp_case118 | active_set | yes | 5 | 10 | 267.196 | 39.638 | 139.196 |
| sp_case118 | classic_simultaneous | yes | 8 | 10 | 267.196 | 39.638 | 139.196 |
| sp_case118 | classic_one_at_a_time | yes | 35 | 10 | 267.196 | 39.638 | 139.196 |

Pairwise, case14_zeng:

| Pair | max abs dU pu | max abs dTheta deg | buses of other type | d losses MW |
|---|---|---|---|---|
| active_set / classic_simultaneous | 0.0118 | 0.312 | 1 | -0.438 |
| active_set / classic_one_at_a_time | 0.0013 | 0.009 | 1 | -0.006 |
| classic_simultaneous / classic_one_at_a_time | 0.0118 | 0.305 | 2 | 0.433 |

In sp_case14 and sp_case118 the three final solutions agree within 2e-7
degrees and 5e-6 MW.

Runs B, sp_case60_narrow:

| Strategy | Guard | Converged | Iterations |
|---|---|---|---|
| active_set | on / off | yes | 5 / 5 |
| classic_simultaneous | on / off | yes | 7 / 7 |
| classic_one_at_a_time | on / off | yes | 7 / 7 |

The guard (`narrow_range_mode: lock_pq`) keeps a narrow-band machine PV while
its Q lies inside the band and locks it at the limit it reaches; with and
without the guard the active set ends on the same solution. Generator 160
stays PV inside its band. Run as PQ through
`power_flow.qlimits.lock_pv_to_pq_buses`, generator 159 alone converges (5
iterations), generator 160 alone and both together do not (80 iterations).
Sparlectra 0.50.0 locked both machines as PQ at the middle of their band
from the start, and the active set with the guard did not converge (80
iterations).

Figures: `results/fig5a_voltage_profile.png` (main figure, case14_zeng,
selected by the rule in `compare.jl`), `results/fig5b_narrow_guard.png`.

## Limits

- One version of Sparlectra: 0.60.0 from the public GitHub repository at
  commit a3cd5bc9, the development state of the upcoming 0.60 (not in the
  General registry yet). One start (classic), one tolerance.
- "Buses PV to PQ" counts buses that start as PV and end as PQ; switching
  rounds and events are the counters of the solver status
  (`qlimit_active_set_changes`, `pv_pq_switching_events`); no run reported
  an oscillating bus.
- The narrow band of `sp_case60_narrow` is set by hand; two other bands
  (1 Mvar below the base reactive power of each machine, and -1.0 to
  0.5 Mvar) did not converge with any strategy.

## References

- Zeng, Chiang: IJEPES 2023 (PV/PQ switching and multiple solutions).
- Sundaresh, Rao: Sadhana 2015.
