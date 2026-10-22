# PV/PQ switching strategies in Sparlectra: same network, different solutions

Three Q-limit strategies of [Sparlectra.jl](https://github.com/Welthulk/Sparlectra.jl)
0.60.0 (`active_set`, `classic_simultaneous`, `classic_one_at_a_time`), same
networks, same start, same tolerance. The strategy decides which solution
the power flow ends on (Zhao et al. [1], Zeng et al. [2]). Every converged
solution is checked for whether it is an admissible operating point.

Details of every run, check and file: [docs/details.md](docs/details.md).

## Reproduce

```
git clone https://github.com/Welthulk/pvpq-study.git
cd pvpq-study
julia --project=. -e "using Pkg; Pkg.instantiate()"
julia reproduce.jl
```

Julia 1.13.2, Sparlectra from GitHub at commit a3cd5bc9 (`[sources]` in
`Project.toml`). Two runs give byte-identical CSV files. Installation:
[docs/install.md](docs/install.md). Settings: rectangular Newton-Raphson,
1e-6 pu, at most 80 iterations, classic start, all automatic aids and the
outer control loop off.

## 1. One network, three solutions

case14_zeng (the case of Zeng and Chiang as shipped with Sparlectra):

| Strategy | Iterations | Buses PV to PQ | Slack Q Mvar | Losses MW | Admissible |
|---|---|---|---|---|---|
| active_set | 7 | 3 | 22.47 | 21.945 | yes |
| classic_simultaneous | 9 | 4 | 18.42 | 21.506 | no, 3 buses |
| classic_one_at_a_time | 11 | 2 | 22.26 | 21.939 | no, 1 bus |

![Voltage profile of the three solutions](results/fig5a_voltage_profile.png)

All three converge; the voltages differ by up to 0.0118 pu. Only the active
set solution is admissible. `classic_simultaneous` leaves buses 2, 3 and 6
at Q_max with the voltage above the set point (eq. 7 of [1]),
`classic_one_at_a_time` leaves bus 6 PV with 24.68 Mvar against a limit of
24 Mvar. In sp_case14 and sp_case118 all strategies reach the same solution.

## 2. Machines with a narrow reactive band

sp_case60_narrow: two 40 MW machines (Birkkamp_110, Westtal_110) get a band
of 4.0 to 5.5 Mvar; at their set points they would need 7.26 and 5.71 Mvar.
The active set ends with both at 5.5 Mvar below their set points
(admissible, smallest eigenvalue of the reduced Jacobian 0.007). The classic
strategies keep Westtal_110 at 1.02 pu with 6.14 Mvar, 0.64 Mvar above its
limit and inside their Q hysteresis of 0.01 pu. The narrow band guard
changes nothing.

![Q(U) droop and solved points, sp_case60_narrow](results/fig7_narrow_softpv.png)

## 3. Characteristics instead of switching

**Q(U) droop.** The voltage regulator is replaced by a line from
(U_set - dU, Q_max) to (U_set + dU, Q_min), dU 0.5 to 5 % of U_set. No bus
switches type.

![Distance of the droop solution to the switched solutions, case14_zeng](results/fig6_zeng_softpv.png)

- The steeper the droop, the nearer the solution to the admissible switched
  solution (case14_zeng, sp_case60_narrow, sp_case60 band `qbase_m1`). The
  classic solution with 6.14 Mvar is not on any droop.
- From 1.0 pu instead of the set points case14_zeng ends on an unstable
  low-voltage solution (0.59 to 0.72 pu). Converged is not stable, the
  objection of [1] against smooth characteristics.

**Soft-PV after Kataoka [4].** The machine stays PV inside its band (within
0.1 or 0.05 % of U_set) and runs into its limits along a soft corner that
holds the last 10 % of the band over 1 to 5 % of voltage. In sp_case118 46
of 53 machines stay within 0.1 % of their set point and the solution comes
to 0.0019 pu of the active set solution, against 0.0054 pu for the droop;
both converge only damped. In case14_zeng the machines need Q near their
limits and sit in the flat corners, so the 0.5 % droop is nearer (0.0050
against 0.0073 pu), and with 5 % corners the run ends on the unstable
low-voltage solution.

![Q(U) droop and Soft-PV, sp_case60_narrow](results/fig8_kataoka.png)

## Admissibility check

At Q_max the voltage must be at or below the set point, at Q_min at or
above it, a PV bus must have Q inside its limits (eq. 5 to 7 of [1]), and
dU/dQ must be positive. The sign of dU/dQ passes at every switched
solution, also the abnormal ones; only the voltage test finds them.

## Limits

- One Sparlectra commit, one start per switched run, one tolerance.
- Taps, phase shifters and the SVC stay at the case positions.
- Characteristics are linear (two or four points), not the curve of [4].
- No continuation power flow, which [1] uses as the independent check.

## References

1. Zhao, Chiang, Li, Ju: On PV-PQ bus type switching logic in power flow
   computation. 16th PSCC, Glasgow, 2008.
2. Zeng, Chiang, Neves, Alberto: On the accuracy of power flow and load
   margin calculation caused by incorrect logical PV/PQ switching. IJEPES
   147 (2023) 108905.
3. Sundaresh, Rao: Sadhana 2015.
4. Kataoka: A smooth power flow model of electric power system with
   generator reactive power limits taken into consideration. ISCAS 2005.
