<!-- private: docs/dev, never public -->
# LinkedIn draft: PV/PQ switching strategies (not published)

Computed with Sparlectra 0.60.0 (development checkout 02b3d62b, Julia
1.13.2). Figures in this folder, 1200 x 627 px. Numbers from `runs.csv`,
`pairs.csv`, `narrow_lock.csv`.

---

**Same network, same start, three Q-limit strategies: two solutions.**

When a generator hits its reactive limit, the power flow turns its bus from
PV to PQ. In which order and how often that happens is a choice of the
solver, and it can decide which solution you get. Zeng and Chiang showed
this in 2023 on a modified IEEE 14-bus case. I recomputed their case with
the three Q-limit strategies of Sparlectra.jl 0.60.0: the active set, the
classic simultaneous switching (all violating machines at once, MATPOWER
style) and the classic one-at-a-time switching. Same start values, same
tolerance (1e-6 pu), all automatic aids off.

All three converge. The active set and the one-at-a-time switching end on
the same operating point (largest voltage difference 0.0013 pu). The
simultaneous switching ends on another one: four machines at their limit
instead of three, voltages up to 0.0118 pu apart, losses 0.44 MW lower. Both
points satisfy the power-flow equations. On sp_case14 and on the 118-bus
case the three strategies agree to 2e-7 degrees.

![Final voltage per bus of the three strategies, case of Zeng and Chiang](fig5a_voltage_profile.png)

Second case: two 40 MW machines in a 60-bus network get a reactive band of
only 1.5 Mvar (0.015 pu). Sparlectra has a guard for such narrow bands, so
the solver does not switch a machine back and forth. Up to version 0.50.0
the guard ran such a machine as PQ at the middle of its band from the
start. Here that stopped the active set from converging (80 iterations);
one of the two machines holds the voltage of a weak 110 kV area and sits
inside its band. Since 0.60.0 the guard keeps a machine PV while its Q lies
inside the band and locks it only at the limit it reaches. All three
strategies now converge with and without the guard, the active set in 5
iterations, on the same solution.

![Newton iterations and switching events with and without the guard, narrow band case](fig5b_narrow_guard.png)

The scripts recompute every number and both figures from a fresh checkout
with one command: [link].

References: Zeng, Chiang, IJEPES 2023; Sundaresh, Rao, Sadhana 2015.
