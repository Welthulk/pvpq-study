# softpv.jl: Soft-PV. The voltage regulator of chosen generators is switched
# off and replaced by a Q(U) characteristic (QUController), optionally with a
# P(U) characteristic (PUController). The bus is PQ for the solver, its Q
# follows |U|; there is no PV/PQ switching at that bus.
#
# Characteristic of each machine: linear from (U_set - dU, Q_max) to
# (U_set + dU, Q_min), clamped outside, so at U = U_set Q is in the middle of
# the band. dU in percent of U_set. P(U): P_base up to U_set + dU, then linear
# to 0.8 P_base at U_set + 2 dU, clamped above.
#
# Every variant is written as SCF file to cases/softpv/ (SCF carries the
# characteristics in extra.<machine>.qu_control / pu_control) and solved from
# that file. Writes results/runs_softpv.csv, the final solutions to
# results/solutions/softpv/ and the perturbation check dU/dQ at every Soft-PV
# bus to results/stability_softpv.csv; results/frozen_softpv.txt holds the
# switched active set solutions with every machine frozen at its solved Q.
#
# usage: julia --project=. softpv.jl   (after run_compare.jl)

using Sparlectra
using Printf
using LinearAlgebra

include(joinpath(@__DIR__, "run_compare.jl"))

const SOFT_CASES = joinpath(CASES, "softpv")
const SOFT_SOLUTIONS = joinpath(RESULTS, "solutions", "softpv")
const DU_PCT = [0.5, 1.0, 2.0, 5.0]
const DU_PU_PCT = [1.0, 2.0]
const SBASE_MVA = 100.0
# Z-one: the two buses of case14_zeng at which the strategies end on another
# bus type or state (pairs.csv, consistency.csv)
const ZONE_BUSES = [2, 6]
# N-fail: two bands of generators 159 and 160 of sp_case60, each 1.5 Mvar
# wide like the narrow band: -1.0 .. 0.5 Mvar, and an upper limit 1 Mvar
# below the base Q of the machine (active set, results/sp_case60_narrow.txt)
const BAND_WIDTH_MVAR = 1.5

# --- network helpers -----------------------------------------------------------

# Sparlectra bus index of SCF generator `gid`: node of the generator, then
# extra.<node>.bus_index
function scf_gen_bus(file, gid)
  src = read(file, String)
  node = parse(Int, match(Regex("\"id\": $(gid),\\s*\"node\": (\\d+)"), src).captures[1])
  return parse(Int, match(Regex("\"$(node)\": \\{\\s*\"bus_index\": (\\d+)"), src).captures[1])
end

load_net(file) = redirect_stdout(() -> importSCF(file), devnull)

# the regulating, non-reference generator of bus `b`
function regulating_gen(net, b)
  g = [ps for ps in net.prosumpsVec if Sparlectra.isGenerator(ps) && Sparlectra.getPosumerBusIndex(ps) == b && Sparlectra.isRegulating(ps) && !Sparlectra.isSlack(ps)]
  length(g) == 1 || error("bus $(b): expected one regulating generator, found $(length(g))")
  return only(g)
end

pv_generator_buses(net) = sort([Sparlectra.getPosumerBusIndex(ps) for ps in net.prosumpsVec if Sparlectra.isGenerator(ps) && Sparlectra.isRegulating(ps) && !Sparlectra.isSlack(ps)])

# set the Q band of the regulating generator of each bus (Mvar)
function set_bands!(net, bands)
  for (b, (qmin, qmax)) in bands
    ps = regulating_gen(net, b)
    ps.minQ = qmin
    ps.maxQ = qmax
  end
  Sparlectra._buildQLimits!(net)
  return net
end

# replace the voltage regulator of the generators at `buses` by Q(U) and,
# with `pu`, P(U); returns per bus (U_set, dU, Q_min, Q_max, P_base)
function make_softpv!(net, buses, du_pct, pu)
  net.baseMVA == SBASE_MVA || error("baseMVA $(net.baseMVA), expected $(SBASE_MVA)")
  data = Dict{Int,NamedTuple}()
  for b in buses
    ps = regulating_gen(net, b)
    vn = net.nodeVec[b].comp.cVN
    us = ps.vm_pu
    du = us * du_pct / 100
    qmin, qmax = ps.minQ, ps.maxQ
    (isfinite(qmin) && isfinite(qmax) && qmax > qmin) || error("bus $(b): band $(qmin) .. $(qmax) Mvar cannot carry a characteristic")
    ch = make_characteristic([((us - du) * vn, qmax), ((us + du) * vn, qmin)]; voltage_unit = :kV, value_unit = :MVAr, vn_kV = vn, sbase_MVA = SBASE_MVA, interpolation = :linear)
    ps.quController = QUController(ch; qmin_MVAr = qmin, qmax_MVAr = qmax, sbase_MVA = SBASE_MVA)
    p0 = something(ps.pVal, 0.0)
    if pu
      chp = make_characteristic([((us + du) * vn, p0), ((us + 2du) * vn, 0.8 * p0)]; voltage_unit = :kV, value_unit = :MW, vn_kV = vn, sbase_MVA = SBASE_MVA, interpolation = :linear)
      ps.puController = PUController(chp; sbase_MVA = SBASE_MVA)
    end
    # no voltage regulator: the bus becomes PQ, the set point only defines
    # the characteristic
    ps.isRegulated = false
    ps.vm_pu = nothing
    data[b] = (uset = us, du = du, qmin = qmin, qmax = qmax, p0 = p0)
  end
  refreshBusTypesFromProsumers!(net)
  Sparlectra._buildQLimits!(net)
  return data
end

# The pinned Sparlectra does not solve P(U)/Q(U) on a net with a closed bus
# coupler (runpf! stops with "not supported with active-link merge
# handling"). sp_case60 has one, link 135 between Neubach_110 (node 22) and
# Neubach_110b (node 23); the only other element of node 23 is line 89. The
# Soft-PV variants of sp_case60 therefore carry the contraction the solver
# does itself for the switched runs: line 89 starts at node 22, the coupler is
# open, node 23 stays as isolated bus. The switched runs of this file are in
# runs_softpv.csv (control "switched") and compared with runs.csv.
function contract_coupler(src_file, dst_file)
  src = read(src_file, String)
  m1 = match(r"\"from_node\": 23,(\s*\"from_status\": 1,\s*\"i_n\": [-0-9.e+]+,\s*\"id\": 89,)", src)
  m1 === nothing && error("$(src_file): line 89 at node 23 not found")
  out = replace(src, m1.match => "\"from_node\": 22," * m1.captures[1])
  m2 = match(r"\"from_node\": 22,\s*\"from_status\": 1,\s*\"id\": 135,\s*\"to_node\": 23,\s*\"to_status\": 1", out)
  m2 === nothing && error("$(src_file): closed link 135 between node 22 and 23 not found")
  out = replace(out, m2.match => "\"from_node\": 22,\n        \"from_status\": 0,\n        \"id\": 135,\n        \"to_node\": 23,\n        \"to_status\": 0")
  write(dst_file, out)
  return dst_file
end

# the Soft-PV generator of bus `b` after import
function soft_gen(net, b)
  g = [ps for ps in net.prosumpsVec if Sparlectra.isGenerator(ps) && Sparlectra.getPosumerBusIndex(ps) == b && Sparlectra.has_qu_controller(ps)]
  length(g) == 1 || error("bus $(b): expected one Q(U) generator, found $(length(g))")
  return only(g)
end

# --- configurations ------------------------------------------------------------

# the study settings with automatic damping on, for the separately marked
# rerun of a Soft-PV run that did not converge
function damped_config(strategy)
  f = run_config(strategy, true)
  out = joinpath(RESULTS, "configs", "$(strategy)_guard_on_damped.yaml")
  write(out, replace(read(f, String), "  autodamp: false" => "  autodamp: true"))
  return out
end

# --- perturbation check --------------------------------------------------------

"""
    softpv_stability(net, soft) -> rows, (qv_min_eig, qv_min_eig_qu)

dU/dQ at every Soft-PV bus of a solved net. All bus types are held: the
reference, the regulated buses on their set point as PV, every other bus
(the Soft-PV buses included) as PQ with the Q of the solved state; the
characteristic is off for the perturbation. Q of the bus is raised by DQ and
the network solved again (resolve_fixed_types of admissibility.jl). Each row
also holds the Q of the bus from the solved voltages and the Ybus; `qv_min_eig`
is the smallest real eigenvalue of the reduced Jacobian; `dudq_qu` and
`qv_min_eig_qu` are the same quantities with the characteristics on.
"""
function softpv_stability(net, soft)
  base = net.baseMVA
  report = buildACPFlowReport(net)
  rep = Dict(r.bus => r for r in report.nodes)
  vset = Sparlectra._bus_voltage_setpoints_from_prosumers(net)
  wnet, reps, _ = Sparlectra._merged_pf_net(net)
  active = [i for i in eachindex(wnet.nodeVec) if !(i in wnet.isoNodes)]
  pos = Dict(b => k for (k, b) in enumerate(active))
  members = Dict(k => Int[] for k in eachindex(active))
  for b in eachindex(net.nodeVec)
    haskey(pos, reps[b]) && push!(members[pos[reps[b]]], b)
  end
  Y = Matrix(createYBUS(net = wnet))
  U0 = [wnet.nodeVec[b]._vm_pu * cis(deg2rad(wnet.nodeVec[b]._va_deg)) for b in active]
  Sinj = U0 .* conj.(Y * U0) .* base
  ref = sort(unique([pos[reps[b]] for b in eachindex(net.nodeVec) if getNodeType(net.nodeVec[b]) == Sparlectra.Slack]))
  held = [b for b in regulated_buses(net) if abs(rep[b].vm_pu - vset[b]) <= TOL_U]
  pv = sort(unique([pos[reps[b]] for b in held if !(pos[reps[b]] in ref)]))
  JR, pq = reduced_jacobian(Y, U0, ref, pv)
  qv_min_eig = minimum(real, eigvals(JR))
  JRinv = inv(JR)
  # the same matrix with the characteristics on: the Q equation of a Soft-PV
  # bus is Q(U) - f(U) = 0, so its diagonal entry loses df/dU (pu/pu, zero
  # where the characteristic is clamped). P(U) is not included.
  JC = copy(JR)
  for b in soft
    j = findfirst(==(pos[reps[b]]), pq)
    JC[j, j] -= last(Sparlectra.evaluate_controller(soft_gen(net, b).quController, abs(U0[pos[reps[b]]])))
  end
  qv_min_eig_qu = minimum(real, eigvals(JC))
  JCinv = inv(JC)
  rows = Dict{Int,NamedTuple}()
  for b in soft
    k = pos[reps[b]]
    q_ybus = imag(Sinj[k]) + sum(rep[m].q_load_MVar for m in members[k]) - sum((rep[m].q_gen_MVar for m in members[k] if m != b); init = 0.0)
    dS = zeros(ComplexF64, length(active))
    dS[k] = im * DQ
    U1 = resolve_fixed_types(Y, U0, ref, pv, dS)
    j = findfirst(==(k), pq)
    rows[b] = (q_ybus = q_ybus, dudq = (abs(U1[k]) - abs(U0[k])) / DQ, dudq_jacobian = JRinv[j, j], dudq_qu = JCinv[j, j])
  end
  return rows, (qv_min_eig, qv_min_eig_qu)
end

# Smallest real eigenvalue of the reduced Jacobian of a solved net with every
# machine frozen at its solved Q: only the slack is reference, every other bus
# is PQ. This is what the check with the characteristic off sees at a Soft-PV
# bus, applied to all regulated buses at once, so a switched solution can be
# judged the same way.
function frozen_min_eig(net)
  wnet, reps, _ = Sparlectra._merged_pf_net(net)
  active = [i for i in eachindex(wnet.nodeVec) if !(i in wnet.isoNodes)]
  pos = Dict(b => k for (k, b) in enumerate(active))
  Y = Matrix(createYBUS(net = wnet))
  U0 = [wnet.nodeVec[b]._vm_pu * cis(deg2rad(wnet.nodeVec[b]._va_deg)) for b in active]
  ref = sort(unique([pos[reps[b]] for b in eachindex(net.nodeVec) if getNodeType(net.nodeVec[b]) == Sparlectra.Slack]))
  JR, _ = reduced_jacobian(Y, U0, ref, Int[])
  return minimum(real, eigvals(JR))
end

# --- one run ------------------------------------------------------------------

# Start values. The classic start begins from the voltages stored in the
# file; exportSCF writes 1.0 pu and 0 degrees at the PQ buses, and a Soft-PV
# bus is PQ. With start "uset" the Soft-PV buses start on their former set
# point, with start "flat" on 1.0 pu.
function soft_run(v, file, strategy; damped = false, start = "uset")
  cfgfile = damped ? damped_config(strategy) : run_config(strategy, true)
  prepare(net) = start == "uset" ? foreach(b -> (net.nodeVec[b]._vm_pu = v.data[b].uset), keys(v.data)) : nothing
  row, sol, _, net = run_case("softpv/" * file, strategy; guard = true, cfgfile = cfgfile, prepare = prepare)
  conv = row.converged
  soft = sort(collect(keys(v.data)))
  base = net.baseMVA
  vals = Dict{Int,NamedTuple}()
  stab, (qv_eig, qv_eig_qu) = conv ? softpv_stability(net, soft) : (Dict{Int,NamedTuple}(), (NaN, NaN))
  for b in soft
    d = v.data[b]
    ps = soft_gen(net, b)
    u = conv ? net.nodeVec[b]._vm_pu : NaN
    q = conv ? first(Sparlectra.evaluate_controller(ps.quController, u)) * base : NaN
    p = conv ? (Sparlectra.has_pu_controller(ps) ? first(Sparlectra.evaluate_controller(ps.puController, u)) * base : something(ps.pVal, 0.0)) : NaN
    region = !conv ? "-" : u < d.uset - d.du ? "qmax" : u > d.uset + d.du ? "qmin" : "slope"
    if conv
      # Q of the characteristic against Q from the solved voltages
      abs(q - stab[b].q_ybus) < TOL_Q_MVAR || error("$(file) $(strategy): Q(U) of bus $(b) is $(q) Mvar, the voltages give $(stab[b].q_ybus) Mvar")
    end
    vals[b] = (u = u, q = q, p = p, du = u - d.uset, region = region)
  end
  j(f) = join([f(vals[b]) for b in soft], ";")
  out = merge(row, (case = v.case, variant = v.variant, file = file, band = v.band, control = v.control, start = start, du_pct = v.du_pct, pu_enabled = v.pu, damped = damped,
    softpv_buses = join(soft, ";"), softpv_u_pu = j(x -> csvval(x.u)), softpv_q_MVar = j(x -> csvval(x.q)), softpv_p_MW = j(x -> csvval(x.p)),
    softpv_du_pu = j(x -> csvval(x.du)), softpv_region = j(x -> x.region)))
  st = [(variant = v.variant, case = v.case, band = v.band, du_pct = v.du_pct, pu_enabled = v.pu, strategy = strategy, start = start, damped = damped,
    bus = b, name = net.nodeVec[b].comp.cName, region = vals[b].region, u_pu = vals[b].u, uset_pu = v.data[b].uset, q_MVar = vals[b].q,
    q_ybus_MVar = stab[b].q_ybus, qmin_MVar = v.data[b].qmin, qmax_MVar = v.data[b].qmax, dudq = stab[b].dudq, dudq_jacobian = stab[b].dudq_jacobian,
    check = stab[b].dudq > 0 ? "pass" : "fail", qv_min_eig = qv_eig, dudq_qu = stab[b].dudq_qu, qv_min_eig_qu = qv_eig_qu) for b in soft if conv]
  tag = (start == "flat" ? "_flat" : "") * (damped ? "_damped" : "")
  # a run that did not converge leaves an iterate, not a solution
  conv && write_rows(joinpath(SOFT_SOLUTIONS, "$(file)_$(strategy)$(tag).csv"), sol)
  return out, st
end

# --- variants -----------------------------------------------------------------

dutag(x) = replace(@sprintf("%.1f", x), "." => "p")

function variant(variant, case, srcfile, buses, du_pct, pu, band, bands)
  net = load_net(srcfile)
  isempty(bands) || set_bands!(net, bands)
  data = make_softpv!(net, buses, du_pct, pu)
  file = lowercase(replace(variant, "-" => "")) * (band == "-" ? "" : "_" * band) * "_du" * dutag(du_pct)
  exportSCF(net; file = joinpath(SOFT_CASES, file * ".scf.json"))
  # the file must give back the same machines: PQ bus with a characteristic
  chk = load_net(joinpath(SOFT_CASES, file * ".scf.json"))
  for b in buses
    getNodeType(chk.nodeVec[b]) == Sparlectra.PQ || error("$(file): bus $(b) is not PQ after the SCF round trip")
    soft_gen(chk, b)
  end
  return (variant = variant, case = case, band = band, control = pu ? "qu_pu" : "qu", du_pct = du_pct, pu = pu, data = data), file
end

function softpv_main()
  rm(SOFT_CASES; force = true, recursive = true)
  rm(SOFT_SOLUTIONS; force = true, recursive = true)
  mkpath(SOFT_CASES)
  mkpath(SOFT_SOLUTIONS)
  rows = []
  stab = []
  # every run that does not converge is repeated with damping, marked damped
  function runall(v, file, strategies; starts = ["uset"])
    for start in starts, s in strategies
      r, st = soft_run(v, file, s; start = start)
      push!(rows, r)
      append!(stab, st)
      if !r.converged
        r, st = soft_run(v, file, s; damped = true, start = start)
        push!(rows, r)
        append!(stab, st)
      end
    end
  end
  zeng = joinpath(CASES, "case14_zeng.scf.json")
  zeng_pv = pv_generator_buses(load_net(zeng))
  narrow = contract_coupler(joinpath(CASES, "sp_case60_narrow.scf.json"), joinpath(SOFT_CASES, "sp_case60_narrow_contracted.scf.json"))
  c60 = contract_coupler(joinpath(CASES, "sp_case60.scf.json"), joinpath(SOFT_CASES, "sp_case60_contracted.scf.json"))
  nbuses = [scf_gen_bus(c60, g) for g in NARROW_GENERATORS]
  # a run with PV/PQ switching on a file of cases/softpv
  function switched(case, variant, file, band, s)
    row, sol, _, _ = run_case("softpv/" * file, s; guard = true)
    row.converged && write_rows(joinpath(SOFT_SOLUTIONS, "$(file)_$(s).csv"), sol)
    return merge(row, (case = case, variant = variant, file = file, band = band, control = "switched", start = "classic", du_pct = NaN, pu_enabled = false, damped = false,
      softpv_buses = "-", softpv_u_pu = "-", softpv_q_MVar = "-", softpv_p_MW = "-", softpv_du_pu = "-", softpv_region = "-"))
  end
  # the contracted narrow case with switching, against runs.csv
  for s in STRATEGIES
    push!(rows, switched("sp_case60_narrow", "N-band", "sp_case60_narrow_contracted", "-", s))
  end

  for du in DU_PCT
    runall(variant("Z-all", "case14_zeng", zeng, zeng_pv, du, false, "-", Dict())..., STRATEGIES; starts = ["uset", "flat"])
  end
  for du in DU_PCT
    runall(variant("Z-one", "case14_zeng", zeng, ZONE_BUSES, du, false, "-", Dict())..., STRATEGIES; starts = ["uset", "flat"])
  end
  for du in DU_PCT
    runall(variant("N-band", "sp_case60_narrow", narrow, nbuses, du, false, "-", Dict())..., STRATEGIES)
  end

  # N-fail: base Q of both machines with their own bands (active set), then
  # the two bands; first switched with the three strategies, then Q(U)
  _, _, _, bnet = run_case("sp_case60", "active_set"; guard = true)
  brep = Dict(r.bus => r for r in buildACPFlowReport(bnet).nodes)
  bands = [("m1p0_0p5", Dict(b => (-1.0, 0.5) for b in nbuses)),
    ("qbase_m1", Dict(b => (brep[b].q_gen_MVar - 1.0 - BAND_WIDTH_MVAR, brep[b].q_gen_MVar - 1.0) for b in nbuses))]
  notes = String[]
  for (bl, bd) in bands
    net = load_net(c60)
    set_bands!(net, bd)
    file = "nfail_" * bl * "_switched"
    exportSCF(net; file = joinpath(SOFT_CASES, file * ".scf.json"))
    for b in nbuses
      push!(notes, @sprintf("band %s: bus %d %s, base Q %.3f Mvar, band %.3f .. %.3f Mvar", bl, b, bnet.nodeVec[b].comp.cName, brep[b].q_gen_MVar, bd[b][1], bd[b][2]))
    end
    for s in STRATEGIES
      push!(rows, switched("sp_case60", "N-fail", file, bl, s))
    end
    for du in DU_PCT
      runall(variant("N-fail", "sp_case60", c60, nbuses, du, false, bl, bd)..., ["active_set"])
    end
    for du in DU_PU_PCT
      runall(variant("N-pu", "sp_case60", c60, nbuses, du, true, bl, bd)..., ["active_set"])
    end
  end
  write(joinpath(RESULTS, "softpv_bands.txt"), join(notes, "\n") * "\n")

  for du in DU_PU_PCT
    runall(variant("Z-pu", "case14_zeng", zeng, zeng_pv, du, true, "-", Dict())..., ["active_set"])
  end
  c118 = joinpath(CASES, "sp_case118.scf.json")
  runall(variant("118-all", "sp_case118", c118, pv_generator_buses(load_net(c118)), 1.0, false, "-", Dict())..., STRATEGIES)
  # the switched active set solutions with every machine frozen at its solved
  # Q, the reading of qv_min_eig at the Soft-PV buses (characteristic off)
  frozen = String[]
  for case in ("case14_zeng", "sp_case118")
    r, _, _, fnet = run_case(case, "active_set"; guard = true)
    r.converged || error("$(case): switched active set run did not converge")
    push!(frozen, @sprintf("%s switched active_set: qv_min_eig with PV held %.4f, with every machine frozen at its solved Q %.4f", case, r.qv_min_eig, frozen_min_eig(fnet)))
  end
  write(joinpath(RESULTS, "frozen_softpv.txt"), join(frozen, "\n") * "\n")

  # same column order in every row
  cols = keys(first(rows))
  write_rows(joinpath(RESULTS, "runs_softpv.csv"), [NamedTuple{cols}(r) for r in rows])
  write_rows(joinpath(RESULTS, "stability_softpv.csv"), stab)
  println("softpv: ", length(rows), " runs, results/runs_softpv.csv")
end

if abspath(PROGRAM_FILE) == @__FILE__
  Base.invokelatest(softpv_main)
end
