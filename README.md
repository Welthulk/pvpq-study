# PV/PQ switching strategies in Sparlectra: same network, different solutions

Three Q-limit strategies of [Sparlectra.jl](https://github.com/Welthulk/Sparlectra.jl)
0.60.0 (`active_set`, `classic_simultaneous`, `classic_one_at_a_time`),
same networks, start and tolerance. The strategy decides which solution
the power flow ends on (Zhao et al. [1], Zeng et al. [2]). Every converged
solution is checked for admissibility. Details of every run, check and
file: [docs/details.md](docs/details.md).

## Reproduce

```
git clone https://github.com/Welthulk/pvpq-study.git
cd pvpq-study
julia --project=. -e "using Pkg; Pkg.instantiate()"
julia reproduce.jl
```

Julia 1.13.2, Sparlectra from GitHub at commit a3cd5bc9, installation in
[docs/install.md](docs/install.md). Two runs give byte-identical CSV files.
Rectangular Newton-Raphson, 1e-6 pu, at most 80 iterations per Newton
solve, classic start, all automatic aids and the outer control loop off.
A Q(U) run that does not converge is repeated with `autodamp`.

## 1. One network, three solutions

case14_zeng [2]:

| Strategy | Iterations | Buses PV to PQ | Slack Q Mvar | Losses MW | Admissible |
|---|---|---|---|---|---|
| active_set | 7 | 3 | 22.47 | 21.945 | yes |
| classic_simultaneous | 9 | 4 | 18.42 | 21.506 | no, 3 buses |
| classic_one_at_a_time | 11 | 2 | 22.26 | 21.939 | no, 1 bus |

![Voltage profile of the three solutions](results/fig5a_voltage_profile.png)

The voltages differ by up to 0.0118 pu. `classic_simultaneous` leaves buses
2, 3 and 6 at Q_max with the voltage above the set point (eq. 7 of [1]),
`classic_one_at_a_time` leaves bus 6 PV with 24.68 Mvar against 24 Mvar.
In sp_case14 and sp_case118 all strategies reach the same solution.

## 2. Machines with a narrow reactive band

sp_case60_narrow: two 40 MW machines (Birkkamp_110, Westtal_110) get a band
of 4.0 to 5.5 Mvar but would need 7.26 and 5.71 Mvar at their set points.
The active set ends with both at 5.5 Mvar below their set points. The
classic strategies keep Westtal_110 at 1.02 pu with 6.14 Mvar, inside
their Q hysteresis of 0.01 pu. With hysteresis 0 (`hyst0.jl`) both classic
strategies reach the active set solution (Westtal_110 at 5.5 Mvar and
0.98833 pu), and on case14_zeng `classic_one_at_a_time` ends in 14
iterations with bus 6 PQ at 24.000 Mvar and 1.06866 pu. At commit a3cd5bc9
`power_flow.qlimits.hysteresis_pu` does not take effect on an imported net
(fixed for the 0.60.0 release, not at this commit), so the script sets the values on the net.

## 3. Characteristics instead of switching

**Q(U) droop** from (U_set - dU, Q_max) to (U_set + dU, Q_min), dU 0.5 to
5 % of U_set. The steeper the droop, the nearer the solution to the
admissible switched one. Started from 1.0 pu, case14_zeng ends at 0.59 to
0.72 pu with all four machines at Q_max, an unstable solution (smallest
eigenvalue -0.62).

![Distance of the droop solution to the switched solutions, case14_zeng](results/fig6_zeng_softpv.png)

**Soft-PV after Kataoka [3].** The machine holds U_set within dU_in (0.05
or 0.1 %) while Q is inside 80 % of its band; the last 10 % on each side
are spread over dU_c (1, 2 or 5 %). Distance to the active set solution,
dU_in 0.1 %:

- sp_case118 (damped, undamped neither converges): Soft-PV with dU_c 2 %
  0.0019 pu in 6 iterations, droop 0.5 % 0.0030 pu in 49.
- case14_zeng: droop 0.5 % 0.0050 pu, Soft-PV with dU_c 1 % 0.0076 pu.
  With dU_c 5 % it ends on the unstable solution above.
- sp_case60_narrow: Soft-PV with dU_c 1 % hits the solution, 2 % is
  0.0008 pu off.

![Q(U) droop and Soft-PV, sp_case60_narrow](results/fig8_kataoka.png)

## Admissibility check

At Q_max the voltage must be at or below the set point, at Q_min at or
above it, and a PV bus must have Q inside its limits (eq. 5 to 7 of [1]).
dU/dQ is positive at every switched solution, also at the abnormal ones;
only the voltage test finds them.

## Limits

- One Sparlectra commit, one start per switched run, one tolerance.
- Taps, phase shifters and the SVC fixed.
- Characteristics are linear (two or four points), not the curve of [3].
- No continuation power flow, which [1] uses as the independent check.

## References

Software: Schmitz, Udo: Sparlectra.jl: A Power-Flow and State-Estimation
Framework in Julia, 2026. Used here: version 0.60.0, commit a3cd5bc9.
https://github.com/Welthulk/Sparlectra.jl (see Citing below).

1. Zhao, Chiang, Li, Ju: On PV-PQ bus type switching logic in power flow
   computation. 16th PSCC, Glasgow, 2008.
2. Zeng, Chiang, Neves, Alberto: On the accuracy of power flow and load
   margin calculation caused by incorrect logical PV/PQ switching. IJEPES
   147 (2023) 108905.
3. Kataoka: A smooth power flow model of electric power system with
   generator reactive power limits taken into consideration. ISCAS 2005.

## Citing

Please cite Sparlectra.jl, the package all runs use:

```bibtex
@software{sparlectra_jl,
  title  = {Sparlectra.jl: A Power-Flow and State-Estimation Framework in Julia},
  author = {Schmitz, Udo},
  year   = {2026},
  url    = {https://github.com/Welthulk/Sparlectra.jl}
}
```
