# Details

Every file, setting and run of the study. The short version is the
[README](../README.md), installation in [install.md](install.md).

## Files

| File | Content |
|---|---|
| `run_compare.jl` | one network, three strategies, same start values and tolerance; one CSV line per run (`results/runs.csv`), the final solution of every run (`results/solutions/`), the band of the narrow band case (`results/sp_case60_narrow.txt`), the lock list check (`results/narrow_lock.csv`) and the physical check of every solution (`results/consistency.csv`) |
| `admissibility.jl` | the physical check, called by `run_compare.jl` for every solved run |
| `compare.jl` | pairwise comparison of the final solutions (`results/pairs.csv`) and the decision rule for the main figure (`results/decision.txt`) |
| `softpv.jl` | Q(U) droop, P(U) and Soft-PV after Kataoka instead of the voltage regulator of chosen generators (`results/runs_softpv.csv`, `results/stability_softpv.csv`, `results/frozen_softpv.txt`, `results/solutions/softpv/`, `results/softpv_bands.txt`) |
| `compare_softpv.jl` | Q(U) solutions against the switched ones (`results/pairs_softpv.csv`, `results/h2_softpv.txt`) |
| `figures.jl` | figures as PNG, 1200 x 627 px, drawn offscreen (`GKSwstype=100`) |
| `reproduce.jl` | everything above from a fresh checkout |
| `config/base.yaml` | settings of every run; per run the strategy and the guard are added (`results/configs/`) |
| `cases/` | the networks as SCF files, written by `run_compare.jl`; the Q(U) variants in `cases/softpv/`, written by `softpv.jl` |

Figures: `results/fig5a_voltage_profile.png` (main figure, case14_zeng,
selected by the rule in `compare.jl`, `decision.txt`),
`results/fig5b_narrow_guard.png`, `results/fig6_zeng_softpv.png`,
`results/fig7_narrow_softpv.png`, `results/fig8_kataoka.png`.

## Networks

- `case14_zeng`: the case of Zeng and Chiang as shipped with Sparlectra
  (`data/scf/case14_zeng_p306_activeSet_A.scf.json`).
- `sp_case14`.
- `sp_case118` (`data/mpower/sp_case118.m`, converted to SCF).
- `sp_case60_narrow`: a copy of `sp_case60` (`cases/sp_case60.scf.json`, as
  shipped with Sparlectra) in which the two 40 MW machines with a voltage
  regulator (generators 159 and 160) get a reactive band of 4.0 to 5.5
  Mvar, 0.015 pu at 100 MVA (`results/sp_case60_narrow.txt`).

## Settings

Rectangular Newton-Raphson, tolerance 1e-6 pu, at most 80 iterations per
Newton solve (the classic strategies restart Newton after each switching
pass, and `iterations` sums all passes, so a failed classic run can show
more than 80), classic start, every automatic aid off (rescue, start projection, automatic
damping, merit, trust region, DC fallback). The outer control loop is off
(`control.enabled: false`): the tap changer of sp_case14 and the two
phase-shifting transformers and the SVC of sp_case60 stay at the positions
of the case file, so every run is one Newton solve with the Q-limit
strategy alone (`control_status` in `runs.csv`).

The guard for narrow reactive bands (`power_flow.qlimits.guard`, default
on, `min_q_range_pu` 0.02, `narrow_range_mode` lock_pq) is on in the runs A
and on and off in the runs B. Under lock_pq the guard keeps a PV bus with a
narrower band PV and takes it out of the PQ to PV release, so the first
limit it reaches holds it there. `narrow_band_pv_buses` in `runs.csv`
counts these buses; the solver counter `guarded` counts only buses the
guard turns into PQ before the solve and stays 0 for them.

## Start vectors

The classic start (`start_mode` classic, no projection) begins from the
voltages stored in the case file. `case14_zeng`, `sp_case118` and every file
that `exportSCF` writes carry 1.0 pu and 0 degrees at the PQ buses.
`sp_case14`, `sp_case60`, `sp_case60_narrow` and the two contracted copies
in `cases/softpv/` carry a solved state (in sp_case60 PQ buses 0.92 to
1.03 pu, angles -25 to 9 degrees). sp_case14 therefore converges in 1
iteration, and sp_case60_narrow in 4 instead of 7 from 1.0 pu and 0
degrees.

## Switched runs

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

"Buses PV to PQ" counts buses that start as PV and end as PQ; switching
rounds and events are the counters of the solver status
(`qlimit_active_set_changes`, `pv_pq_switching_events`).

Pairwise, case14_zeng (`pairs.csv`):

| Pair | max abs dU pu | max abs dTheta deg | buses of other type | d losses MW |
|---|---|---|---|---|
| active_set / classic_simultaneous | 0.0118 | 0.312 | 1 | -0.438 |
| active_set / classic_one_at_a_time | 0.0013 | 0.009 | 1 | -0.006 |
| classic_simultaneous / classic_one_at_a_time | 0.0118 | 0.305 | 2 | 0.433 |

In sp_case14 the three final solutions are identical, in sp_case118 they
agree within 2e-7 degrees and 5e-6 MW.

Runs B, sp_case60_narrow: every strategy converges in 4 iterations, with
and without the guard. Both machines would need more than their band at the
set point (`sp_case60_narrow.txt`: 7.258 and 5.711 Mvar against 5.5 Mvar).
The active set ends with both at 5.5 Mvar. The two classic strategies end
on one solution with Birkkamp_110 at 5.5 Mvar and Westtal_110 still holding
its voltage with 6.136 Mvar, 0.636 Mvar above its limit. Between the active
set and the classic solutions the voltage differs by up to 0.0333 pu and
the angle by 0.461 degrees; losses differ by 0.141 MW.

With and without the guard each strategy ends on the same solution: every
column of `runs.csv` and every difference in `pairs.csv` is equal. Both
machines are under the guard (`narrow_band_pv_buses` 2). The guard only
stops the PQ to PV release; in this case it changes no result.

In sp_case60_narrow Sparlectra keeps the bus type of both machines at PV in
the solved net, also when the bus runs at a limit with the voltage off its
set point. "Buses PV to PQ" is therefore 0 for this case.

Run as PQ through `power_flow.qlimits.lock_pv_to_pq_buses`, generator 159
alone converges (7 iterations), generator 160 alone and both together do
not (80 iterations). `narrow_lock.csv` lists Sparlectra bus indices (11,
25), `sp_case60_narrow.txt` the SCF node numbers of the generators (6, 60);
both are the same buses, Birkkamp_110 and Westtal_110.

### Q hysteresis

The classic strategies accept a Q overshoot below the hysteresis of 0.01 pu
(1 Mvar at 100 MVA). Westtal_110 under classic_simultaneous (0.636 Mvar
above its limit) and bus 6 of case14_zeng under classic_one_at_a_time
(0.678 Mvar above its limit of 24 Mvar) stay PV for this reason, and the
final Q check of the solver reports `within_hysteresis`. The classic loop and the final check read the
hysteresis from the net (`net.q_hyst_pu`, `net.final_q_accept_pu`, import
defaults 0.01 and 0.02 pu). Setting `power_flow.qlimits.hysteresis_pu: 0`
in the config passed to `run_sparlectra` alone changes nothing: these runs
come out like the committed rows of `runs.csv` and `consistency.csv`. With
both net fields also set to 0:

- case14_zeng, classic_one_at_a_time: 14 iterations, bus 6 at 24 Mvar
  (1.0687 pu), slack Q 22.472 Mvar, the active set solution; final check ok.
- sp_case60_narrow, classic_simultaneous: 5 iterations, both machines at
  5.5 Mvar (0.9966 and 0.9883 pu), slack Q 23.159 Mvar, the active set
  solution; final check ok.

These runs are not part of `reproduce.jl`. Not run with hysteresis 0:
classic_simultaneous on case14_zeng, classic_one_at_a_time on
sp_case60_narrow, sp_case118.

## Admissibility check

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
get back to the set point. The paper calls such a solution abnormal, and
one such bus is enough. It also links these conditions to the criterion
that dU/dQ at a bus must be positive.

How it is tested:

- State of each bus from the solved values: `vset` when
  |U - U_set| <= 1e-6 pu (the slack always), else `qmax` or `qmin` when Q
  is within 1e-3 Mvar of that limit, else `none`.
- (a) At `qmax` U <= U_set + 1e-6 pu (eq. 7), at `qmin`
  U >= U_set - 1e-6 pu (eq. 6). A bus in state `none` fails as well.
- (b) At `vset`: Q_min - 1e-3 Mvar <= Q <= Q_max + 1e-3 Mvar (eq. 5).
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
plus the fixed Q of the other generator units of the bus. In the four
networks every regulated bus has one generator unit (`gen_units` in
`consistency.csv`), so the bus limits are those of the machine.

Q is the total generator Q of the bus, from the solved voltages with the
Sparlectra Ybus of the working net the solver uses (closed bus couplers
contracted), plus the load of the bus. The script stops if this Ybus does
not reproduce P at every bus except the slack and Q at every bus without a
regulating unit within 1e-3 MW or Mvar. The Q of the Sparlectra report is
kept in `q_report_MVar`. The only closed coupler in sp_case60_narrow joins
Neubach_110 and Neubach_110b. At Birkkamp_110, a PV bus at its upper limit
and not at a coupler, the Sparlectra report of the two classic strategies
gives 7.258 Mvar generator Q; the voltages give 5.500 Mvar. The active set
report agrees with the voltages.

The tolerances are constants in `admissibility.jl`, chosen here; the paper
gives none.

| Network | Strategy | Guard | Lock list | Regulated buses | At a limit | (a) | (b) | (c) | Inconsistent buses | qv_min_eig |
|---|---|---|---|---|---|---|---|---|---|---|
| case14_zeng | active_set | on | - | 5 | 3 | 0 | 0 | 0 | 0 | 0.856 |
| case14_zeng | classic_simultaneous | on | - | 5 | 4 | 3 | 0 | 0 | 3 | 0.103 |
| case14_zeng | classic_one_at_a_time | on | - | 5 | 2 | 0 | 1 | 0 | 1 | 2.610 |
| sp_case14 | all three | on | - | 3 | 0 | 0 | 0 | 0 | 0 | 0.396 |
| sp_case118 | all three | on | - | 54 | 10 | 0 | 0 | 0 | 0 | 7.858 |
| sp_case60_narrow | active_set | on, off | - | 4 | 2 | 0 | 0 | 0 | 0 | 0.007 |
| sp_case60_narrow | both classic | on, off | - | 4 | 1 | 0 | 1 | 0 | 1 | 0.070 |
| sp_case60_narrow | active_set | off | 11 | 4 | 2 | 1 | 0 | 0 | 1 | - |

The lock list runs with bus 25 and with 11 and 25 did not converge and are
not checked; their rows in `consistency.csv` carry no type, Q or U.

Violating buses (dU/dQ in pu per pu at 100 MVA):

| Run | Bus | State | Q Mvar | Limits Mvar | U pu | U_set pu | dU/dQ | Fails |
|---|---|---|---|---|---|---|---|---|
| case14_zeng, classic_simultaneous | 2 | qmax | 50.000 | -40 .. 50 | 1.0568 | 1.045 | 0.968 | (a) |
| case14_zeng, classic_simultaneous | 3 | qmax | 40.000 | 0 .. 40 | 1.0179 | 1.010 | 0.999 | (a) |
| case14_zeng, classic_simultaneous | 6 | qmax | 24.000 | -6 .. 24 | 1.0790 | 1.070 | 0.889 | (a) |
| case14_zeng, classic_one_at_a_time | 6 | vset (PV) | 24.678 | -6 .. 24 | 1.0700 | 1.070 | - | (b) |
| sp_case60_narrow, both classic, guard on and off | 25 Westtal_110 | vset (PV) | 6.136 | 4.0 .. 5.5 | 1.0200 | 1.020 | - | (b) |
| sp_case60_narrow, lock list 11 | 11 Birkkamp_110 | qmin | 4.000 | 4.0 .. 5.5 | 0.9855 | 1.010 | 0.805 | (a) |

- Check (c) passes at every bus at a limit, also at the three buses that
  fail (a). The sign of the local V-Q sensitivity at the final state with
  all bus types held does not find these buses; only the voltage-side test
  does. The perturbation argument of the paper is about the step from PV to
  PQ during the switching, which (c) does not model.
- sp_case118: the 10 buses at a limit sit on the correct side of their set
  point.
- sp_case60_narrow, active set: both machines at 5.5 Mvar below their set
  points (Birkkamp_110 0.9966 pu against 1.01, Westtal_110 0.9883 pu against
  1.02). The smallest eigenvalue of the reduced Jacobian is 0.007, a tenth
  of that of the classic solutions, and dU/dQ at Westtal_110 is 5.6 pu/pu:
  this operating point is much closer to voltage instability.
- With the lock list on bus 11 the run converges, but Birkkamp_110 is held
  at its lower limit of 4.0 Mvar with 0.9855 pu, below its set point (eq.
  6): its regulator would raise Q. This is not an admissible operating
  point.

## Q(U) droop

A generator that holds its voltage is a PV bus until Q reaches a limit,
then a PQ bus. Kataoka [3] replaces this switch by a smooth Q-V curve
(hyperbolic or sigmoid), so the power flow has no bus type switching. Zhao
et al. [1] (section 5) object that such a curve masks the true face of the
problem: with the switching logic the solution point of every generator
lies on a stable branch, with a smooth curve it can lie on an unstable one.

Here the voltage regulator of chosen generators is replaced by a Sparlectra
`QUController` with a linear droop, not Kataoka's sigmoid: Q_max at
U_set - dU, Q_min at U_set + dU, clamped outside, so Q is in the middle of
the band at U_set. dU is 0.5, 1, 2 and 5 % of U_set. The bus is PQ; its Q
follows |U| and enters the Jacobian with the slope. With P(U)
(`PUController`) P stays at P_base up to U_set + dU and falls linearly to
0.8 P_base at U_set + 2 dU. The files carry the old name `softpv`.

| Variant | Network | Q(U) at | Runs |
|---|---|---|---|
| Z-all | case14_zeng | the four PV generators (buses 1, 2, 3, 6) | 4 dU x 3 strategies |
| Z-one | case14_zeng | buses 2 and 6, buses 1 and 3 stay PV | 4 dU x 3 strategies |
| N-band | sp_case60_narrow | generators 159 and 160, droop over their band 4.0 to 5.5 Mvar | 4 dU x 3 strategies |
| N-fail | sp_case60 with two other bands of 159 and 160: -1.0 to 0.5 Mvar (`m1p0_0p5`), and 1.5 Mvar wide with the upper limit 1 Mvar below the base Q (`qbase_m1`, `softpv_bands.txt`) | 159 and 160 | 4 dU, active set; each band also switched with the three strategies |
| N-pu | as N-fail | Q(U) and P(U) at 159 and 160 | dU 1 and 2 %, active set |
| Z-pu | case14_zeng | Q(U) and P(U) at the four PV generators | dU 1 and 2 %, active set |
| 118-all | sp_case118 | all 53 PV generators | dU 0.5 and 1 %, 3 strategies |

Settings as for the switched runs, every aid off. Every Q(U) and P(U) file
is written by `exportSCF`, so the PQ buses start on 1.0 pu and 0 degrees,
and a Q(U) bus is PQ. In the main runs (start `uset`) the Q(U) buses start
on their former set point; Z-all and Z-one also run with start `flat` (Q(U)
buses on 1.0 pu). The switched comparison runs start classic from their
file: N-band from the solved state of `sp_case60_narrow_contracted`, N-fail
from the exported `nfail_*_switched` files on 1.0 pu. A run that does not
converge is repeated with `autodamp: true` and marked `damped`.

SCF carries the characteristics (`extra.<machine>.qu_control`,
`pu_control`); `softpv.jl` writes every variant to `cases/softpv/` and
solves it from that file.

Coupler note: the pinned Sparlectra does not solve P(U) or Q(U) on a net
with a closed bus coupler, and sp_case60 has one (Neubach_110 to
Neubach_110b). The sp_case60 variants therefore carry the contraction the
solver does for the switched runs: line 89 starts at Neubach_110, the
coupler is open, Neubach_110b is an isolated bus. With switching this file
gives the solutions of `sp_case60_narrow` (max |dU| 0 without the isolated
bus, `pairs_softpv.csv`).

Q of a Q(U) machine is its characteristic at the solved U. The script stops
if this differs by more than 1e-3 Mvar from the Q of the solved voltages
and the Ybus. The generator Q stored at the node is not used; at the pinned
commit it keeps the nameplate value for Q(U) units.

Files: `runs_softpv.csv` (columns of `runs.csv`, plus variant, file, band,
control, start, `shape` (`droop`, `kataoka`, `-` for switched runs), dU,
the Kataoka parameters, P(U) on, damped, and per Q(U) bus U, Q, P,
U - U_set and the position on the characteristic, separated by `;`:
`clamp_max`, `slope`, `clamp_min` for the droop), `pairs_softpv.csv` (every converged Q(U) solution against every
converged switched solution of the same network), `h2_softpv.txt`,
`stability_softpv.csv` (per bus, with position and |U - U_set|),
`frozen_softpv.txt`, the solutions in
`results/solutions/softpv/`.

Perturbation check (`stability_softpv.csv`), as check (c): bus types held,
Q(U) buses PQ at their solved Q (droop off), Q raised by 0.1 Mvar, power
flow solved again; dU/dQ > 0 passes. `qv_min_eig` is the smallest
eigenvalue of the reduced Jacobian. `dudq_qu` and `qv_min_eig_qu` are the
same with the slope of each droop on the diagonal (droop on, P(U) not
included).

### Results

case14_zeng, Q(U) at all four PV generators, start `uset`. Only the slack
still regulates its voltage, so no Q-limit strategy has a PV bus to act on
(0 PV/PQ events in every run); the identical solutions of the three
strategies follow from that. Set points 1.06, 1.045, 1.01, 1.07 pu.

| dU % | Iterations | U at bus 1, 2, 3, 6 (pu) | Q (Mvar) | max abs dU to active set (pu) |
|---|---|---|---|---|
| 0.5 | 5 | 1.0670, 1.0400, 1.0013, 1.0642 | 0, 48.39, 40, 24 | 0.0050 |
| 1 | 5 | 1.0673, 1.0366, 0.9981, 1.0600 | 7.75, 41.12, 40, 22.95 | 0.0086 |
| 2 | 6 | 1.0666, 1.0315, 0.9914, 1.0526 | 17.25, 34.05, 38.45, 21.17 | 0.0160 |
| 5 | 5 | 1.0566, 1.0171, 0.9727, 1.0351 | 26.61, 29.07, 34.76, 18.78 | 0.0336 |
| switched, active set | 7 | 1.0720, 1.0450, 1.0062, 1.0687 | 0, 48.84, 40, 24 | |

The steeper the droop, the closer the solution to the active set solution,
the only switched one that fulfils eq. 5 to 7 (`h2_softpv.txt`,
`results/fig6_zeng_softpv.png`). At dU 0.5 % it has the same states (bus 1
at Q_min, bus 2 in the band, buses 3 and 6 at Q_max), with U about dU away
from the switched values. dU/dQ is positive at every Q(U) bus.

With start `flat` the same network ends on another solution: U 0.722,
0.664, 0.594 and 0.704 pu, all four machines at Q_max, losses 51.8 MW
instead of 22.1 to 22.9 MW with start `uset`. dU/dQ is negative at buses 1,
2 and 3 (-0.10 to -0.19), the smallest eigenvalue -0.62 with and without
the droop: an unstable low-voltage solution. dU 0.5 and 5 % reach it in 7
and 8 iterations, dU 1 and 2 % do not converge and reach it damped in 8.
Every strategy gives the same.

Z-one, start `uset`: at dU 2 and 5 % all three strategies converge to one
solution (6, 9, 9 iterations), both machines on the slope. At dU 0.5 %
classic_simultaneous does not converge, at dU 1 % classic_one_at_a_time;
both reach damped a solution with U 0.850 and 0.891 pu at buses 2 and 6,
dU/dQ -0.82 and -0.43, smallest eigenvalue -0.13, and 2 inconsistent
buses. The other two strategies agree within 1e-8 pu.

Z-one, start `flat`: at dU 0.5 % the active set does not converge, also
damped (80 iterations); classic_simultaneous reaches the low-voltage
solution above only damped (14 iterations), classic_one_at_a_time the
high-voltage one in 14. At dU 1 % the active set (7) and
classic_simultaneous (9) reach the high-voltage solution,
classic_one_at_a_time the low-voltage one damped (17). At dU 2 and 5 %
every strategy gives the solution of start `uset` (6 to 10 iterations).
With this start the strategy at the remaining PV buses decides whether the
run converges and on which branch it ends.

N-band, sp_case60_narrow: every dU and strategy converges in 6 iterations,
the strategies agree; the one remaining PV bus, Ostfeld_220 (band -100 to
100 Mvar), has no PV/PQ event in any run. At dU 0.5 and 1 % both machines
run at 5.5 Mvar with 0.9966 and 0.9883 pu, the active set solution (max abs
dU below 1e-6 pu). At 2 % Birkkamp_110 is on the slope (5.30 Mvar), at 5 %
both (5.02 and 5.41 Mvar, max abs dU 0.0137 pu). No run comes near the
classic solution, in which Westtal_110 holds 1.02 pu with 6.136 Mvar: a
droop clamped at Q_max has no such point (`results/fig7_narrow_softpv.png`).
dU/dQ is at least 0.68.

N-fail, band -1.0 to 0.5 Mvar: no run converges: switched with any
strategy (undamped only), Q(U) at any dU and Q(U) with P(U), each also
damped. Band `qbase_m1`: switched, the active set converges in 7 iterations
(0 inconsistent buses), the classic strategies in 5 (2 inconsistent buses).
Q(U) converges at every dU (6, 6, 7, 8 iterations); up to dU 2 % it gives
the active set solution (max abs dU 2.3e-6 pu), both machines at Q_max with
0.9897 and 0.9411 pu, dU/dQ at least 0.99.

P(U): Z-pu does not converge undamped at dU 1 and 2 %; damped (26 and 48
iterations) it ends on the Z-all solution with P at P_base. In N-pu, band
`qbase_m1`, it converges (7 and 9 iterations) to a solution with Westtal_110
at 0.864 pu and Birkkamp_110 at 0.972 pu, Q at Q_max and P at 40 MW as in
N-fail: the same injections at other voltages. dU/dQ is -9.7 at
Westtal_110 and -0.19 at Birkkamp_110, the smallest eigenvalue -0.0035, the
unstable branch. P(U) is not active at either solution (U below
U_set + dU) and only changes the Newton path.

118-all, dU 0.5 and 1 %: no strategy converges undamped; damped, all three
give one solution in 49 iterations, max abs dU 0.0030 and 0.0054 pu to the
switched solution. With the droop off the smallest eigenvalue is -0.0097
and -0.0089 and dU/dQ is negative at all 53 buses; with the droop on it is
7.7 and 8.9 and dU/dQ is positive at all 53. The check with the droop off treats a bus on the slope like a PV
machine frozen at a Q inside its band, a case check (c) of the switched
runs never tests. It rejects the switched active set solution of
sp_case118 as well: with every machine frozen at its solved Q its smallest
eigenvalue is -0.0116, against 7.86 with the PV buses held
(`frozen_softpv.txt`). For buses on the slope the check with the droop on
is the one that applies, and it passes. In case14_zeng the switched active
set solution with every machine frozen gives +0.093, and every Q(U) bus of
Z-all with start `uset` passes both checks.

Iterations: with the active set and start `uset`, steepness costs no
iterations here (5 to 8 at every dU in Z-all, Z-one, N-band and N-fail
band `qbase_m1`). With start `flat` the active set fails in Z-all at dU 1
and 2 % (undamped) and in Z-one at dU 0.5 % (also damped). In Z-one every
undamped failure is at dU 0.5 or 1 % and every run at 2 and 5 % converges:
there a steep droop costs convergence, depending on start and strategy. In
Z-all there is no such pattern.

## Soft-PV after Kataoka

Kataoka [3] keeps the generator PV inside its band and rounds the corners
at the limits. Here this is a `QUController` with four points, linear,
clamped outside:

    (U_set - dU_in - dU_c, Q_max), (U_set - dU_in, Q_max - delta),
    (U_set + dU_in, Q_min + delta), (U_set + dU_in + dU_c, Q_min)

delta is 10 % of the band. The middle segment covers 80 % of the band on
2 dU_in, so the bus holds U_set within dU_in. Each corner covers the last
10 % of the band on dU_c. Six characteristics: dU_in 0.1 and 0.05 %, dU_c
1, 2 and 5 %. Start `uset`, settings and damped repeat as for the droop,
files `cases/softpv/k_*.scf.json`, column `shape` = `kataoka`. Position on
the characteristic: `clamp_max`, `corner_max`, `mid`, `corner_min`,
`clamp_min`.

| Variant | Network | Soft-PV at | Runs |
|---|---|---|---|
| K-zall | case14_zeng | the four PV generators | 6 characteristics x 3 strategies |
| K-nband | sp_case60_narrow, coupler contracted | 159 and 160, band 4.0 to 5.5 Mvar | 6 characteristics, active set |
| K-118 | sp_case118 | all 53 PV generators | dU_in 0.1 %, dU_c 2 %, 3 strategies |

Max |dU| in pu to the switched active set solution, active set, start
`uset`, iterations in brackets (`h2_softpv.txt`):

| dU_in % | dU_c % | K-zall | K-nband |
|---|---|---|---|
| 0.1 | 1 | 0.0076 (5) | below 1e-6 (7) |
| 0.1 | 2 | 0.0122 (5) | 0.0008 (6) |
| 0.1 | 5 | 0.4127 (13) | 0.0046 (6) |
| 0.05 | 1 | 0.0073 (6) | below 1e-6 (6) |
| 0.05 | 2 | 0.0119 (5) | 0.0008 (6) |
| 0.05 | 5 | 0.4127 (13) | 0.0045 (6) |
| droop 0.5 % | | 0.0050 (5) | below 1e-6 (6) |

K-zall: for each characteristic the three strategies give the same
solution (max |dU| 0, 0 PV/PQ events); the nearest switched solution is
always the active set. With dU_c 1 and 2 % no machine ends in the middle
segment: bus 1 sits in the lower corner, buses 2, 3 and 6 in the upper
corner or at Q_max. Bus 2 needs 48.84 of 50 Mvar in the switched solution,
which is in the top 10 % of its band; the corner gives it 45.3 to 46.5 Mvar
at 0.7 to 1.1 % below U_set. For bus 2 a corner (9 Mvar over 1 or 2 %) is
flatter than the droop 0.5 % (90 Mvar over 1 %), so the droop stays
nearer. dU/dQ is positive at every bus with and without the
characteristic.

With dU_c 5 % all four machines end at Q_max at 0.59 to 0.72 pu, the
low-voltage solution of the droop with start `flat` (losses 51.8 MW):
dU/dQ negative at buses 1, 2 and 3, smallest eigenvalue -0.62 with and
without the characteristic, although the run starts at U_set. Whether this
characteristic has a high-voltage solution was not checked.

K-nband: with dU_c 1 % both machines are at 5.5 Mvar, the active set
solution. With 2 % Birkkamp_110, with 5 % both machines are in the upper
corner, 0.0008 and 0.0046 pu off. No run reaches the classic solution with
Westtal_110 at 1.02 pu and 6.14 Mvar, which is outside the characteristic
(`results/fig8_kataoka.png`). Smallest eigenvalue 0.0067 to 0.0070 without
and 0.0070 to 0.0079 with the characteristic, as at the switched active set
solution (0.0070); dU/dQ at least 0.64.

K-118: no strategy converges undamped (80 iterations). Damped, all three
reach one solution in 6 iterations, 0.0019 pu from the switched active set
solution; the droop 0.5 % reaches 0.0030 pu, the droop 1 % 0.0054 pu, both
in 49 damped iterations. 46 of the 53 machines are in the middle segment,
5 in the upper and 2 in the lower corner. 43 of the 46 hold U_set in the
switched active set solution as well; the other 3 are at a Q limit there,
and Soft-PV keeps them within 0.1 % of U_set. Every machine that holds
U_set in the switched solution is in the middle segment.
With the characteristic off dU/dQ is negative at all 53 buses (smallest
eigenvalue -0.011), with it on positive at all 53 (8.50), the same reading
as for the droop.

Iterations: Soft-PV against droop 0.5 % with the active set, K-zall 5 to 6
against 5 (13 on the low-voltage solution), K-nband 6 to 7 against 6,
K-118 6 against 49 (both damped; undamped both fail). The steep middle
segment costs no iterations.

H5 (the Soft-PV solution is nearer to the active set than every droop)
holds in K-118 only. In K-zall the droop 0.5 % is nearer, in K-nband the
droop 0.5 and 1 % and Soft-PV with dU_c 1 % all give the active set
solution. |U - U_set| < dU_in at a bus in the middle segment holds by the
definition of that segment and is not a result.

## Limits

- One version of Sparlectra: 0.60.0 from the public GitHub repository at
  commit a3cd5bc9 (not in the General registry yet). Switched runs: one
  start (classic), one tolerance.
- The narrow band of `sp_case60_narrow` is set by hand.
- Tap changers, phase shifters and the SVC stay at the positions of the
  case files; the interaction of the Q-limit strategies with an outer
  control loop is not part of this study.
- Q(U) droop: linear, two points. Soft-PV: linear, four points, not the
  hyperbolic or sigmoid curve of [3]. K-118 only with dU_in 0.1 % and
  dU_c 2 %; 118-all only at dU 0.5 and 1 %.
- The sp_case60 variants run on the file with the coupler contracted.
- `dudq_qu` and `qv_min_eig_qu` leave out P(U).
- Start values other than `uset` and `flat` were not run.
- The physical check covers eq. 3, 5, 6 and 7 of [1] and the sign of dU/dQ
  at the regulated buses at a limit. At a bus held at its set point dU/dQ
  is zero by definition and not tested; load buses enter only through
  `qv_min_eig`. Not run: a continuation power flow or loadability limit,
  which [1] uses as independent check, and the load increase test for the
  lower branch of the PV curve.

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
3. Y. Kataoka: "A smooth power flow model of electric power system with
   generator reactive power limits taken into consideration", IEEE
   International Symposium on Circuits and Systems (ISCAS), 2005,
   pp. 5286-5289. Cited from [1], not read for this study.
