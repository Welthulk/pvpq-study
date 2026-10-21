# PV/PQ switching strategies in Sparlectra: same network, different solutions

A small reproducible comparison of the three Q-limit strategies of
[Sparlectra.jl](https://github.com/Welthulk/Sparlectra.jl) 0.50.0 (General
registry): `active_set`, `classic_simultaneous` and `classic_one_at_a_time`.
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

## Reproduce

```
julia reproduce.jl
```

Two runs give identical CSV files and figures.

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
| active_set | on | no | 80 (limit) |
| active_set | off | yes | 5 |
| classic_simultaneous | on / off | yes | 7 / 7 |
| classic_one_at_a_time | on / off | yes | 7 / 7 |

The guard acts in the active-set strategy only (the classic runs report no
guarded bus). It runs both machines as PQ at the middle of their band
(4.75 Mvar). Without the guard, generator 160 stays PV inside its band. Run
as PQ through `power_flow.qlimits.lock_pv_to_pq_buses` instead of the guard,
generator 159 alone converges (5 iterations), generator 160 alone and both
together do not (80 iterations).

Figures: `results/fig5a_voltage_profile.png` (main figure, case14_zeng,
selected by the rule in `compare.jl`), `results/fig5b_narrow_guard.png`.

## Limits

- One version of Sparlectra (0.50.0), one start (classic), one tolerance.
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
