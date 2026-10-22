# admissibility.jl: physical check of a solved power flow at every
# voltage-regulated bus, included by run_compare.jl.
#
# Criteria of Zhao, Chiang, Li, Ju, "On PV-PQ bus type switching logic in
# power flow computation": a generator is either at its voltage set point or
# at one of its Q limits (eq. 3); a bus held at its voltage keeps Q inside
# the limits (eq. 5); a bus with U < U_set is at Q_max (eq. 6), a bus with
# U > U_set is at Q_min (eq. 7), so a bus at Q_max has U <= U_set and a bus
# at Q_min has U >= U_set; dU/dQ > 0 at the bus (V-Q sensitivity after
# Kundur, ref. 12 of the paper).
#
# Q limits and voltage set points come from Sparlectra: the aggregated
# per-bus limits (getQLimits_pu; on a bus with a regulating or reference
# unit the sum of the limits of those units plus the fixed Q of the other
# generator units of the bus) and the set points the solver holds
# (_bus_voltage_setpoints_from_prosumers, taken before the solve). Q of a
# bus is its total generator Q, from the solved voltages and the Sparlectra
# Ybus; the Q of the report (q_gen_MVar, the sum of the units of a bus) is
# written next to it.

using LinearAlgebra

# Tolerances, chosen here (the paper gives none). A bus is "on the set
# point" when |U - U_set| <= TOL_U; this is also the margin on U in check
# (a). A bus is "at a limit" when Q is within TOL_Q_MVAR of that limit; this
# is also the margin on Q in check (b). The solver tolerance is 1e-6 pu.
const TOL_U = 1e-6        # pu
const TOL_Q_MVAR = 1e-3   # Mvar
# perturbation of the reactive injection for dU/dQ
const DQ = 1e-3         # pu, 0.1 Mvar at 100 MVA

# buses with a voltage-regulating or reference unit, in bus order
function regulated_buses(net)
  b = Int[]
  for ps in net.prosumpsVec
    Sparlectra.isGenerator(ps) || continue
    (Sparlectra.isRegulating(ps) || Sparlectra.isSlack(ps)) && push!(b, Sparlectra.getPosumerBusIndex(ps))
  end
  return sort(unique(b))
end

# Jacobian blocks dS/dtheta and dS/d|U| of S = U conj(Y U) (polar form)
function dS_dU(Y, U)
  I = Y * U
  dU = Diagonal(U)
  dS_dth = im * dU * conj(Diagonal(I) - Y * dU)
  dS_dvm = dU * conj(Y * Diagonal(U ./ abs.(U))) + conj(Diagonal(I)) * Diagonal(U ./ abs.(U))
  return dS_dth, dS_dvm
end

# Power flow of the solved state with every bus type held fixed: `ref`
# holds U and theta, `pv` holds P and |U|, all other buses hold P and Q.
# Specified injections are those of the solved state plus `dS`. Newton in
# polar form from the solved state; returns the new voltages.
function resolve_fixed_types(Y, U0, ref, pv, dS)
  n = length(U0)
  Sspec = U0 .* conj.(Y * U0) .+ dS
  pq = [i for i = 1:n if !(i in ref) && !(i in pv)]
  pvpq = [i for i = 1:n if !(i in ref)]
  th = angle.(U0)
  vm = abs.(U0)
  for _ = 1:30
    U = vm .* cis.(th)
    mis = U .* conj.(Y * U) .- Sspec
    F = [real(mis[pvpq]); imag(mis[pq])]
    maximum(abs, F) < 1e-12 && return U
    dS_dth, dS_dvm = dS_dU(Y, U)
    J = [real(dS_dth[pvpq, pvpq]) real(dS_dvm[pvpq, pq]); imag(dS_dth[pq, pvpq]) imag(dS_dvm[pq, pq])]
    dx = -(J \ F)
    th[pvpq] .+= dx[1:length(pvpq)]
    vm[pq] .+= dx[(length(pvpq)+1):end]
  end
  error("resolve_fixed_types: no convergence after 30 iterations")
end

# reduced Jacobian J_R = J_QV - J_Qth J_Pth^-1 J_PV at the solved state; its
# inverse holds dU_i/dQ_j for the PQ buses (Kundur, V-Q sensitivity)
function reduced_jacobian(Y, U, ref, pv)
  n = length(U)
  pq = [i for i = 1:n if !(i in ref) && !(i in pv)]
  pvpq = [i for i = 1:n if !(i in ref)]
  dS_dth, dS_dvm = dS_dU(Y, U)
  J11 = real(dS_dth[pvpq, pvpq])
  J12 = real(dS_dvm[pvpq, pq])
  J21 = imag(dS_dth[pq, pvpq])
  J22 = imag(dS_dvm[pq, pq])
  return J22 - J21 * (J11 \ J12), pq
end

"""
    admissibility(net, case, strategy, guard, lock, types0, vset, converged)

Rows of results/consistency.csv for one solved run, one per voltage-regulated
bus, plus the minimum real eigenvalue of the reduced Jacobian. `lock` names
the buses of `lock_pv_to_pq_buses` ("-" for none), `types0` are the bus
types before the solve, `vset` the voltage set points.
"""
function admissibility(net, case, strategy, guard, lock, types0, vset, converged)
  base = net.baseMVA
  buses = regulated_buses(net)
  report = buildACPFlowReport(net)
  rep = Dict(r.bus => r for r in report.nodes)
  qmin, qmax = getQLimits_pu(net)
  tolq = TOL_Q_MVAR / base
  # generator units per bus; with one unit the bus limits are the limits of
  # that machine
  units = Dict{Int,Int}()
  for ps in net.prosumpsVec
    Sparlectra.isGenerator(ps) || continue
    k = Sparlectra.getPosumerBusIndex(ps)
    units[k] = get(units, k, 0) + 1
  end

  # Q of each regulated bus from the solved voltages, on the solver's
  # working net: closed links (bus couplers) contracted onto one
  # representative bus, as the solver does. Generator Q of a bus is its
  # injection plus its load; other units of the same cluster are taken from
  # the report. The report value is kept for comparison (q_report_MVar).
  wnet, reps, _ = Sparlectra._merged_pf_net(net)
  active = [i for i in eachindex(wnet.nodeVec) if !(i in wnet.isoNodes)]
  pos = Dict(b => k for (k, b) in enumerate(active))
  members = Dict(k => Int[] for k in eachindex(active))
  for b in eachindex(net.nodeVec)
    haskey(pos, reps[b]) && push!(members[pos[reps[b]]], b)
  end
  Y = Matrix(createYBUS(net = wnet))
  size(Y, 1) == length(active) || error("$(case): Ybus size does not match the active buses")
  U0 = [wnet.nodeVec[b]._vm_pu * cis(deg2rad(wnet.nodeVec[b]._va_deg)) for b in active]
  Sinj = U0 .* conj.(Y * U0) .* base
  qgen = Dict{Int,Float64}()
  for b in buses
    k = pos[reps[b]]
    qgen[b] = imag(Sinj[k]) + sum(rep[m].q_load_MVar for m in members[k]) - sum((rep[m].q_gen_MVar for m in members[k] if m != b); init = 0.0)
  end

  # state of each regulated bus, from U, U_set, Q and the limits
  state = Dict{Int,String}()
  for b in buses
    q = qgen[b] / base
    state[b] = if getNodeType(net.nodeVec[b]) == Sparlectra.Slack || abs(rep[b].vm_pu - vset[b]) <= TOL_U
      "vset"
    elseif abs(q - qmax[b]) <= tolq
      "qmax"
    elseif abs(q - qmin[b]) <= tolq
      "qmin"
    else
      "none"
    end
  end

  # dU/dQ at every regulated bus not held at its set point
  sens = Dict{Int,Float64}()
  sens_jac = Dict{Int,Float64}()
  qv_min_eig = NaN
  if converged
    ref = sort(unique([pos[reps[b]] for b in eachindex(net.nodeVec) if getNodeType(net.nodeVec[b]) == Sparlectra.Slack]))
    pv = sort(unique([pos[reps[b]] for b in buses if state[b] == "vset" && !(pos[reps[b]] in ref)]))
    # the Ybus must reproduce the solved state: P of every non-reference
    # cluster and Q of every cluster without a regulated bus equal the
    # generation minus load of the report
    gencl = Set(pos[reps[b]] for b in buses)
    for k in eachindex(active)
      k in ref && continue
      p = sum(rep[m].p_gen_MW - rep[m].p_load_MW for m in members[k])
      abs(real(Sinj[k]) - p) < 1e-3 || error("$(case) $(strategy): Ybus does not reproduce the solved state at bus $(active[k]) (P)")
      k in gencl && continue
      q = sum(rep[m].q_gen_MVar - rep[m].q_load_MVar for m in members[k])
      abs(imag(Sinj[k]) - q) < 1e-3 || error("$(case) $(strategy): Ybus does not reproduce the solved state at bus $(active[k]) (Q)")
    end
    JR, pq = reduced_jacobian(Y, U0, ref, pv)
    qv_min_eig = minimum(real, eigvals(JR))
    JRinv = inv(JR)
    for b in buses
      k = pos[reps[b]]
      (k in pv || k in ref) && continue
      dS = zeros(ComplexF64, length(active))
      dS[k] = im * DQ
      U1 = resolve_fixed_types(Y, U0, ref, pv, dS)
      sens[b] = (abs(U1[k]) - abs(U0[k])) / DQ
      j = findfirst(==(k), pq)
      sens_jac[b] = JRinv[j, j]
    end
  end

  pf(x) = x ? "pass" : "fail"
  rows = []
  for b in buses
    r = rep[b]
    s = state[b]
    u, us = r.vm_pu, vset[b]
    q = qgen[b] / base
    ev = get(net.qLimitEvents, b, nothing)
    # (a) complementarity at a limit: at Q_max U <= U_set (eq. 7), at Q_min
    # U >= U_set (eq. 6); a bus neither at U_set nor at a limit fails eq. 3
    a = s == "qmax" ? pf(u <= us + TOL_U) : s == "qmin" ? pf(u >= us - TOL_U) : s == "none" ? "fail" : "n/a"
    # (b) a bus held at its set point keeps Q inside its limits
    b_ = s == "vset" ? pf(qmin[b] - tolq <= q <= qmax[b] + tolq) : "n/a"
    # (c) dU/dQ > 0 at a bus that is not held at its set point
    c = haskey(sens, b) ? pf(sens[b] > 0) : "n/a"
    # a run that did not converge leaves an iterate, not a result: its bus
    # type, Q and U are not written
    push!(rows, (case = case, strategy = strategy, guard = guard, lock = lock, bus = b, name = r.bus_name,
      gen_units = get(units, b, 0), start_type = string(types0[b]), end_type = converged ? string(getNodeType(net.nodeVec[b])) : "-", state = converged ? s : "-",
      qlimit_event = ev === nothing ? "-" : string(ev),
      q_MVar = converged ? qgen[b] : NaN, q_report_MVar = converged ? r.q_gen_MVar : NaN, qmin_MVar = qmin[b] * base, qmax_MVar = qmax[b] * base,
      u_pu = converged ? u : NaN, uset_pu = us,
      check_a = converged ? a : "not_solved", check_b = converged ? b_ : "not_solved", check_c = converged ? c : "not_solved",
      dudq = get(sens, b, NaN), dudq_jacobian = get(sens_jac, b, NaN)))
  end
  return rows, qv_min_eig
end

# violating buses per check of one run, and buses that fail any of them
violations(rows) = (viol_a = count(r -> r.check_a == "fail", rows), viol_b = count(r -> r.check_b == "fail", rows), viol_c = count(r -> r.check_c == "fail", rows),
  inconsistent_buses = count(r -> "fail" in (r.check_a, r.check_b, r.check_c), rows))
# placeholder of a run that did not converge
const NO_VIOLATIONS = (viol_a = "-", viol_b = "-", viol_c = "-", inconsistent_buses = "-")
