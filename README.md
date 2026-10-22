# PV/PQ switching strategies in Sparlectra: same network, different solutions

A small reproducible comparison of the three Q-limit strategies of
[Sparlectra.jl](https://github.com/Welthulk/Sparlectra.jl) 0.60.0: `active_set`,
`classic_simultaneous` and `classic_one_at_a_time`.
That the switching strategy can decide the final solution is known
(Zeng et al., IJEPES 2023 [2]; Sundaresh and Rao, Sadhana 2015 [3]). This
repository is the open, recomputable version in Julia, plus a case with
machines of a narrow reactive band, and a check whether each converged
solution is an admissible operating point.

## Layout

| File | Content |
|---|---|
| `run_compare.jl` | one network, three strategies, same start values and tolerance; one CSV line per run (`results/runs.csv`), the final solution of every run (`results/solutions/`), the band of the narrow band case (`results/sp_case60_narrow.txt`), the lock list check (`results/narrow_lock.csv`) and the physical check of every solution (`results/consistency.csv`) |
| `admissibility.jl` | the physical check, called by `run_compare.jl` for every solved run |
| `compare.jl` | pairwise comparison of the final solutions (`results/pairs.csv`) and the decision rule for the main figure (`results/decision.txt`) |
| `figures.jl` | figures as PNG, 1200 x 627 px, drawn offscreen (`GKSwstype=100`) |
| `reproduce.jl` | everything above from a fresh checkout |
| `config/base.yaml` | settings of every run; per run the strategy and the guard are added (`results/configs/`) |
| `cases/` | the networks as SCF files, written by `run_compare.jl` |

Networks: `case14_zeng` (the case of Zeng and Chiang as shipped with
Sparlectra, `data/scf/case14_zeng_p306_activeSet_A.scf.json`), `sp_case14`,
`sp_case118` (`data/mpower/sp_case118.m`, converted to SCF), and
`sp_case60_narrow`, a copy of `sp_case60` (`cases/sp_case60.scf.json`, as
shipped with Sparlectra) in which the two 40 MW machines
with a voltage regulator (generators 159 and 160) get a reactive band of
4.0 to 5.5 Mvar, 0.015 pu at 100 MVA (`results/sp_case60_narrow.txt`).

Settings: rectangular Newton-Raphson, tolerance 1e-6 pu, at most 80
iterations, classic start, every automatic aid off (rescue, start projection,
automatic damping, merit, trust region, DC fallback). The outer control loop
is off (`control.enabled: false`): the tap changer of sp_case14 and the two
phase-shifting transformers and the SVC of sp_case60 stay at the positions of
the case file, so every run is one Newton solve with the Q-limit strategy
alone (`control_status` in `runs.csv`). The guard for narrow reactive bands
(`power_flow.qlimits.guard`, default on, `min_q_range_pu` 0.02,
`narrow_range_mode` lock_pq) is on in the runs A and on and off in the runs B.
Under lock_pq the guard keeps a PV bus with a narrower band PV and takes it
out of the PQ to PV release, so the first limit it reaches holds it there.
`narrow_band_pv_buses` in `runs.csv` counts these buses; the solver counter
`guarded` counts only buses the guard turns into PQ before the solve and
stays 0 for them.

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

The repository is public; cloning needs no credentials:

```
git clone https://github.com/Welthulk/pvpq-study.git
cd pvpq-study
```

### 4. Install the environment

In the `pvpq-study` directory:

```
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

This downloads the General registry, the pinned packages and Sparlectra at
commit a3cd5bc9 from GitHub (public, no credentials), then precompiles.
On an empty Julia depot this took 2 min 49 s here (16 threads, Linux,
Julia 1.13.2), of which 65 s precompilation.

## Reproduce

```
julia reproduce.jl
```

`reproduce.jl` runs `Pkg.instantiate()` again (fast once installed),
deletes `results/` and writes it new: `runs.csv`, `pairs.csv`,
`decision.txt`, `narrow_lock.csv`, `consistency.csv`,
`sp_case60_narrow.txt`, the final solutions in `results/solutions/`, the
configuration of every run in `results/configs/`, and the two figures. It
also rewrites the networks in `cases/`. Two runs one after the other took
55.8 s and 61.9 s wall time (`time julia reproduce.jl`, same
machine and Julia version as above).

Check: after a run, look at

```
git status --short results/ cases/
```

It shows nothing: every file, the PNGs included, is identical to the
committed one. On the machine above two runs of `reproduce.jl` in a row
gave byte-identical files in `results/` and `cases/`. On another machine
(fonts, graphics library) the PNGs may differ in bytes; the CSV files must
not.

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
- `GKS: Open failed` or a Qt message (`qt.qpa`, locale switched to
  `C.UTF-8`): GR has tried to open a window, and the PNGs can come out with
  another layout (title cut off). `figures.jl` sets `GKSwstype=100` before
  `using Plots` to prevent this.

## Results

Runs A (guard on):

| Network | Strategy | Converged | Iterations | Buses PV to PQ | Slack P MW | Slack Q Mvar | Losses MW |
|---|---|---|---|---|---|---|---|
| case14_zeng | active_set | yes | 7 | 3 | -0.365 | 22.472 | 21.945 |
| case14_zeng | classic_simultaneous | yes | 9 | 4 | -0.804 | 18.422 | 21.506 |
| case14_zeng | classic_one_at_a_time | yes | 11 | 2 | -0.371 | 22.257 | 21.939 |
| sp_case14 | all three | yes | 1 | 0 | 19.726 | 13.261 | 1.726 |
| sp_case118 | active_set | yes | 5 | 10 | 267.196 | 39.638 | 139.196 |
| sp_case118 | classic_simultaneous | yes | 8 | 10 | 267.196 | 39.638 | 139.196 |
| sp_case118 | classic_one_at_a_time | yes | 35 | 10 | 267.196 | 39.638 | 139.196 |

Pairwise, case14_zeng:

| Pair | max abs dU pu | max abs dTheta deg | buses of other type | d losses MW |
|---|---|---|---|---|
| active_set / classic_simultaneous | 0.0118 | 0.312 | 1 | -0.438 |
| active_set / classic_one_at_a_time | 0.0013 | 0.009 | 1 | -0.006 |
| classic_simultaneous / classic_one_at_a_time | 0.0118 | 0.305 | 2 | 0.433 |

In sp_case14 the three final solutions are identical, in sp_case118 they
agree within 2e-7 degrees and 5e-6 MW.

Runs B, sp_case60_narrow:

| Strategy | Guard | Converged | Iterations |
|---|---|---|---|
| active_set | on / off | yes | 4 / 4 |
| classic_simultaneous | on / off | yes | 4 / 4 |
| classic_one_at_a_time | on / off | yes | 4 / 4 |

Both machines would need more than their band at the set point
(`sp_case60_narrow.txt`: 7.258 and 5.711 Mvar against 5.5 Mvar). The active
set ends with both at 5.5 Mvar. The two classic strategies end on one
solution with Birkkamp_110 at 5.5 Mvar and Westtal_110 still holding its
voltage with 6.136 Mvar, 0.636 Mvar above its limit. Between the active set
and the classic solutions the voltage differs by up to 0.0333 pu and the
angle by 0.461 degrees; losses differ by 0.141 MW (`pairs.csv`).

With and without the guard each strategy ends on the same solution: every
column of `runs.csv` and every difference in `pairs.csv` is equal. Both
machines are under the guard (`narrow_band_pv_buses` 2). The guard only
stops the PQ to PV release; in this case it changes no result.

Run as PQ through `power_flow.qlimits.lock_pv_to_pq_buses`, generator 159
alone converges (7 iterations), generator 160 alone and both together do not
(80 iterations).
`narrow_lock.csv` lists Sparlectra bus indices (11, 25), while
`sp_case60_narrow.txt` names the SCF node numbers of the generators (6,
60); both are the same buses, Birkkamp_110 and Westtal_110.

Figures: `results/fig5a_voltage_profile.png` (main figure, case14_zeng,
selected by the rule in `compare.jl`), `results/fig5b_narrow_guard.png`.

### Physical admissibility

A converged power flow is not yet an operating point. Every final solution
is checked at each bus with a voltage-regulating or reference unit
(`admissibility.jl`): one row per bus and run in `results/consistency.csv`,
the number of violating buses per check in `runs.csv` and
`narrow_lock.csv` (`viol_a`, `viol_b`, `viol_c`), and the number of buses
that fail any of the three checks (`inconsistent_buses`).

The criterion follows Zhao, Chiang, Li and Ju [1]. A generator either holds
its voltage set point with its reactive power inside the limits, or it runs
at one of its limits. A voltage below the set point requires Q at the upper
limit (eq. 6 of the paper), a voltage above the set point Q at the lower
limit (eq. 7). At the upper limit the voltage must therefore be at or below
the set point, at the lower limit at or above it. A machine at its upper
limit with the voltage above the set point could lower its excitation and
get back to the set point; the solution does not describe what its regulator
would do. The paper calls such a solution abnormal, and one such bus is
enough. It also links these conditions to the voltage stability criterion
that dU/dQ at a bus must be positive.

How it is tested:

- State of each bus from the solved values: `vset` when
  |U - U_set| <= 1e-6 pu (the slack always), else `qmax` or `qmin` when Q
  is within 1e-3 Mvar of that limit, else `none`.
- (a) At `qmax` U <= U_set + 1e-6 pu (eq. 7), at `qmin`
  U >= U_set - 1e-6 pu (eq. 6). A bus
  in state `none` (neither at its set point nor at a limit) fails as well.
- (b) At `vset`: Q_min - 1e-3 Mvar <= Q <= Q_max + 1e-3 Mvar.
- (c) At `qmax` and `qmin`: the reactive injection of the bus is raised by
  1e-3 pu (0.1 Mvar), every bus type is kept, and the power flow is solved
  again from the solved state (Newton, 1e-12 pu). The check requires
  dU/dQ = (U_new - U) / 1e-3 > 0. The diagonal entry of the inverse reduced
  Jacobian (J_QV - J_Qtheta J_Ptheta^-1 J_PV) is written next to it
  (`dudq_jacobian`); `runs.csv` also gets the smallest real eigenvalue of
  that matrix (`qv_min_eig`).

Q limits and set points come from Sparlectra: `getQLimits_pu` and the set
points the solver holds, read before the solve. On a bus with a regulating
or reference unit `getQLimits_pu` is the sum of the limits of those units
plus the fixed Q of the other generator units of the bus, which do not widen
the band; it bounds the total generator Q of the bus. In the four networks
every regulated bus has one generator unit (`gen_units` in
`consistency.csv`), so the bus limits are those of the machine. Q is the total generator Q of
the bus, from the solved voltages with the Sparlectra Ybus of the working
net the solver uses (closed bus couplers contracted), plus the load of the
bus. The script stops if this Ybus does not reproduce P at every bus except
the slack and Q at every bus without a regulating unit within 1e-3 MW or
Mvar. The Q of the Sparlectra report is kept in `q_report_MVar`. The
tolerances are constants in `admissibility.jl`, chosen here; the paper gives
none.

Checks (a), (b), (c) after Zhao et al. 2008 (eq. 3, 5, 6, 7 and the sign of
dU/dQ): buses at a limit, violating buses per check, buses that fail any
check.

| Network | Strategy | Guard | Lock list | Regulated buses | At a limit | (a) | (b) | (c) | Inconsistent buses | qv_min_eig |
|---|---|---|---|---|---|---|---|---|---|---|
| case14_zeng | active_set | on | - | 5 | 3 | 0 | 0 | 0 | 0 | 0.856 |
| case14_zeng | classic_simultaneous | on | - | 5 | 4 | 3 | 0 | 0 | 3 | 0.103 |
| case14_zeng | classic_one_at_a_time | on | - | 5 | 2 | 0 | 1 | 0 | 1 | 2.610 |
| sp_case14 | active_set | on | - | 3 | 0 | 0 | 0 | 0 | 0 | 0.396 |
| sp_case14 | classic_simultaneous | on | - | 3 | 0 | 0 | 0 | 0 | 0 | 0.396 |
| sp_case14 | classic_one_at_a_time | on | - | 3 | 0 | 0 | 0 | 0 | 0 | 0.396 |
| sp_case118 | active_set | on | - | 54 | 10 | 0 | 0 | 0 | 0 | 7.858 |
| sp_case118 | classic_simultaneous | on | - | 54 | 10 | 0 | 0 | 0 | 0 | 7.858 |
| sp_case118 | classic_one_at_a_time | on | - | 54 | 10 | 0 | 0 | 0 | 0 | 7.858 |
| sp_case60_narrow | active_set | on | - | 4 | 2 | 0 | 0 | 0 | 0 | 0.007 |
| sp_case60_narrow | active_set | off | - | 4 | 2 | 0 | 0 | 0 | 0 | 0.007 |
| sp_case60_narrow | classic_simultaneous | on | - | 4 | 1 | 0 | 1 | 0 | 1 | 0.070 |
| sp_case60_narrow | classic_simultaneous | off | - | 4 | 1 | 0 | 1 | 0 | 1 | 0.070 |
| sp_case60_narrow | classic_one_at_a_time | on | - | 4 | 1 | 0 | 1 | 0 | 1 | 0.070 |
| sp_case60_narrow | classic_one_at_a_time | off | - | 4 | 1 | 0 | 1 | 0 | 1 | 0.070 |
| sp_case60_narrow | active_set | off | 11 | 4 | 2 | 1 | 0 | 0 | 1 | - |

Q is computed from the solved voltages on the contracted network (closed
bus couplers merged, as the solver does; the only closed coupler in
sp_case60_narrow joins Neubach_110 and Neubach_110b). At Birkkamp_110, a PV
bus at its upper limit and not at a coupler, the Sparlectra report of the two
classic strategies gives 7.258 Mvar generator Q, above the limit of 5.5 Mvar;
the voltages give 5.500 Mvar. The active set report agrees with the voltages.

The lock list runs with bus 25 and with 11 and 25 did not converge and are
not checked; their rows in `consistency.csv` carry no type, Q or U.

Violating buses:

| Run | Bus | State | Q Mvar | Limits Mvar | U pu | U_set pu | dU/dQ | Fails |
|---|---|---|---|---|---|---|---|---|
| case14_zeng, classic_simultaneous | 2 | qmax | 50.000 | -40 .. 50 | 1.0568 | 1.045 | 0.968 | (a) |
| case14_zeng, classic_simultaneous | 3 | qmax | 40.000 | 0 .. 40 | 1.0179 | 1.010 | 0.999 | (a) |
| case14_zeng, classic_simultaneous | 6 | qmax | 24.000 | -6 .. 24 | 1.0790 | 1.070 | 0.889 | (a) |
| case14_zeng, classic_one_at_a_time | 6 | vset (PV) | 24.678 | -6 .. 24 | 1.0700 | 1.070 | - | (b) |
| sp_case60_narrow, both classic strategies, guard on and off | 25 Westtal_110 | vset (PV) | 6.136 | 4.0 .. 5.5 | 1.0200 | 1.020 | - | (b) |
| sp_case60_narrow, lock list 11 | 11 Birkkamp_110 | qmin | 4.000 | 4.0 .. 5.5 | 0.9855 | 1.010 | 0.805 | (a) |

dU/dQ in pu per pu at 100 MVA.

- case14_zeng: of the three converged solutions only the active set one is
  admissible. `classic_simultaneous` ends with three machines at their
  upper limit and the voltage above the set point (eq. 7).
  `classic_one_at_a_time` leaves bus 6 as PV with 24.678 Mvar, above its
  limit of 24 Mvar (eq. 5).
- Check (c) passes at every bus at a limit, also at the three buses that
  fail (a). The sign of the local V-Q sensitivity at the final state with
  all bus types held (the criterion the paper cites from Kundur) does not
  find these buses; only the voltage-side test does. The perturbation
  argument of the paper is about the step from PV to PQ during the
  switching, which (c) does not model, so this does not contradict the
  paper.
- sp_case14 and sp_case118: all three solutions pass; the 10 buses of
  sp_case118 at a limit sit on the correct side of their set point.
- sp_case60_narrow: the active set solution is admissible. Both machines
  run at 5.5 Mvar below their set points (Birkkamp_110 0.9966 pu against
  1.01, Westtal_110 0.9883 pu against 1.02). The smallest eigenvalue of the
  reduced Jacobian is 0.007, a tenth of that of the classic solutions, and
  dU/dQ at Westtal_110 is 5.6 pu/pu: this operating point is much closer to
  voltage instability. The classic solutions are not admissible: Westtal_110
  holds 1.02 pu with 6.136 Mvar, above its limit (eq. 5), in all four
  classic runs.
- With the lock list on bus 11 the run converges, but Birkkamp_110 is held
  at its lower limit of 4.0 Mvar with 0.9855 pu, below its set point (eq.
  6): its regulator would raise Q. This converged point is not an admissible
  operating point.
- In sp_case60_narrow Sparlectra keeps the bus type of both machines at PV
  in the solved net, also when the bus runs at a limit with the voltage off
  its set point. "Buses PV to PQ" reads the Sparlectra bus types and is
  therefore 0 for this case.

## Limits

- One version of Sparlectra: 0.60.0 from the public GitHub repository at
  commit a3cd5bc9, the development state of the upcoming 0.60 (not in the
  General registry yet). One start (classic), one tolerance.
- "Buses PV to PQ" counts buses that start as PV and end as PQ; switching
  rounds and events are the counters of the solver status
  (`qlimit_active_set_changes`, `pv_pq_switching_events`).
- The narrow band of `sp_case60_narrow` is set by hand.
- Tap changers, phase shifters and the SVC stay at the positions of the case
  files; the interaction of the Q-limit strategies with an outer control
  loop is not part of this study.
- The physical check covers eq. 3, 5, 6 and 7 of [1] and the sign of
  dU/dQ at the regulated buses at a limit. At a bus held at its set point
  dU/dQ is zero by definition and not tested; load buses enter only
  through `qv_min_eig`. Not run: a continuation power flow or loadability
  limit, which [1] uses as independent check, and the load increase test
  for the lower branch of the PV curve.

## References

1. Jinquan Zhao, Hsiao-Dong Chiang, Hua Li, Ping Ju: "On PV-PQ bus type
   switching logic in power flow computation", Hohai University, Nanjing,
   and Cornell University, Ithaca. The paper does not print venue or year;
   it is cited as 16th Power Systems Computation Conference (PSCC),
   Glasgow, 2008.
2. Zeng, Chiang, Neves, Alberto: "On the accuracy of power flow and load
   margin calculation caused by incorrect logical PV/PQ switching:
   Analytics and improved methods", International Journal of Electrical
   Power and Energy Systems 147 (2023) 108905.
3. Sundaresh, Rao: Sadhana 2015.
