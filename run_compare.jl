# run_compare.jl: one network, three Q-limit strategies, same start values and
# tolerance. Writes one CSV line per run (results/runs.csv) and the final
# solution of every run (results/solutions/<run>.csv), and the physical check
# of every final solution at the voltage-regulated buses
# (results/consistency.csv, admissibility.jl).
#
# usage: julia --project=. run_compare.jl

using Sparlectra
using Printf

include(joinpath(@__DIR__, "admissibility.jl"))

const ROOT = @__DIR__
const RESULTS = joinpath(ROOT, "results")
const CASES = joinpath(ROOT, "cases")
const STRATEGIES = ["active_set", "classic_simultaneous", "classic_one_at_a_time"]
const PKG_SCF = joinpath(pkgdir(Sparlectra), "data", "scf")
const PKG_MPOWER = joinpath(pkgdir(Sparlectra), "data", "mpower")

# narrow-band machines of sp_case60_narrow: the two 40 MW units with a
# voltage regulator, generators 159 (node 6) and 160 (node 60) of
# sp_case60.scf.json; the third regulated machine, 168 (120 MW at node 38),
# keeps its band. The 3 to 4 MW units of the case are PQ injections.
const NARROW_GENERATORS = [159, 160]
# the band of both machines, 4.0 .. 5.5 Mvar (0.015 pu at 100 MVA, below
# the 0.02 pu of the guard). Base Q in sp_case60 (active set): 7.5 Mvar at
# generator 159 and 4.9 Mvar at 160, so the upper limit binds at 159 and 160
# stays inside its band.
const NARROW_QMIN_MVAR = 4.0
const NARROW_QMAX_MVAR = 5.5

# --- cases -------------------------------------------------------------------

# the networks as SCF files in cases/, copied or converted from the
# Sparlectra package; no case configuration file travels along, so only
# config/base.yaml and the run settings apply
function prepare_cases()
  mkpath(CASES)
  cp(joinpath(PKG_SCF, "case14_zeng_p306_activeSet_A.scf.json"), joinpath(CASES, "case14_zeng.scf.json"); force = true)
  cp(joinpath(PKG_SCF, "sp_case14.scf.json"), joinpath(CASES, "sp_case14.scf.json"); force = true)
  cp(joinpath(PKG_SCF, "sp_case60.scf.json"), joinpath(CASES, "sp_case60.scf.json"); force = true)
  net118 = redirect_stdout(() -> createNetFromMatPowerFile(filename = joinpath(PKG_MPOWER, "sp_case118.m")), devnull)
  exportSCF(net118; file = joinpath(CASES, "sp_case118.scf.json"))
  return nothing
end

# --- one run -------------------------------------------------------------------

function run_config(strategy::AbstractString, guard::Bool)
  mkpath(joinpath(RESULTS, "configs"))
  file = joinpath(RESULTS, "configs", "$(strategy)_guard_$(guard ? "on" : "off").yaml")
  base = read(joinpath(ROOT, "config", "base.yaml"), String)
  base = replace(base, "    enforcement_mode: active_set" => "    enforcement_mode: $(strategy)\n    guard:\n      enabled: $(guard)")
  write(file, base)
  return file
end

function run_case(case::AbstractString, strategy::AbstractString; guard::Bool = true)
  cfg = load_sparlectra_config(run_config(strategy, guard))
  net = redirect_stdout(() -> importSCF(joinpath(CASES, case * ".scf.json")), devnull)
  types0 = [getNodeType(n) for n in net.nodeVec]
  vset = Sparlectra._bus_voltage_setpoints_from_prosumers(net)
  res = redirect_stdout(() -> run_sparlectra(net = net, config = cfg), devnull)
  d = res.diagnostics
  calcNetLosses!(net)
  ploss, _ = getTotalLosses(net = net)
  report = buildACPFlowReport(net)
  slack = [r for r in report.nodes if getNodeType(net.nodeVec[r.bus]) == Sparlectra.Slack]
  slack_p = isempty(slack) ? NaN : sum(r.p_gen_MW for r in slack)
  slack_q = isempty(slack) ? NaN : sum(r.q_gen_MVar for r in slack)
  # buses that started as PV and ended as PQ (Q limit active)
  types1 = [getNodeType(n) for n in net.nodeVec]
  pv_to_pq = count(i -> types0[i] == Sparlectra.PV && types1[i] == Sparlectra.PQ, eachindex(types0))
  row = (case = case, strategy = strategy, guard = guard, converged = res.final_converged, iterations = res.iterations,
    switching_rounds = get(d, :qlimit_active_set_changes, 0), pv_pq_events = get(d, :pv_pq_switching_events, 0),
    cycle = get(d, :oscillating_buses, 0) > 0 || res.reason === :max_switching_exceeded, oscillating_buses = get(d, :oscillating_buses, 0),
    guarded = get(d, :guarded_narrow_q_pv_buses, 0), pv_to_pq = pv_to_pq, slack_p_MW = slack_p, slack_q_MVar = slack_q, loss_MW = ploss, reason = res.reason)
  adm, qv_min_eig = admissibility(net, case, strategy, guard, "-", types0, vset, res.final_converged)
  v = res.final_converged ? violations(adm) : NO_VIOLATIONS
  row = merge(row, v, (qv_min_eig = qv_min_eig,))
  sol = [(bus = i, name = n.comp.cName, vn_kV = n.comp.cVN, type = string(types1[i]), vm_pu = something(n._vm_pu, NaN), va_deg = something(n._va_deg, NaN)) for (i, n) in enumerate(net.nodeVec)]
  return row, sol, adm
end

# --- sp_case60_narrow ----------------------------------------------------------

# sp_case60 with the voltage regulators of NARROW_GENERATORS on the narrow
# band; the base Q of each machine (active set) goes into the note file
function build_narrow_case()
  src = read(joinpath(CASES, "sp_case60.scf.json"), String)
  net = redirect_stdout(() -> importSCF(joinpath(CASES, "sp_case60.scf.json")), devnull)
  cfg = load_sparlectra_config(run_config("active_set", true))
  redirect_stdout(() -> run_sparlectra(net = net, config = cfg), devnull)
  report = buildACPFlowReport(net)
  out = src
  chosen = String[]
  for gid in NARROW_GENERATORS
    m = match(Regex("\"q_max\": ([-0-9.e+]+),\\s*\"q_min\": ([-0-9.e+]+),\\s*\"regulated_object\": $(gid),"), out)
    m === nothing && error("sp_case60.scf.json: no voltage regulator for generator $(gid)")
    node = parse(Int, match(Regex("\"id\": $(gid),\\s*\"node\": (\\d+)"), src).captures[1])
    # the SCF node id maps to the Sparlectra bus through extra.<id>.bus_index
    bus = parse(Int, match(Regex("\"$(node)\": \\{\\s*\"bus_index\": (\\d+)"), src).captures[1])
    row = only(r for r in report.nodes if r.bus == bus)
    out = replace(out, m.match => "\"q_max\": $(NARROW_QMAX_MVAR * 1e6),\n        \"q_min\": $(NARROW_QMIN_MVAR * 1e6),\n        \"regulated_object\": $(gid),")
    push!(chosen, @sprintf("generator %d at node %d (bus %s): base Q %.3f Mvar, band %.1f .. %.1f Mvar (was %.1f .. %.1f)", gid, node, row.bus_name, row.q_gen_MVar, NARROW_QMIN_MVAR, NARROW_QMAX_MVAR, parse(Float64, m.captures[2]) / 1e6, parse(Float64, m.captures[1]) / 1e6))
  end
  write(joinpath(CASES, "sp_case60_narrow.scf.json"), out)
  write(joinpath(RESULTS, "sp_case60_narrow.txt"), join(chosen, "\n") * "\n")
  return chosen
end

# --- output ----------------------------------------------------------------------

csvval(x::AbstractFloat) = @sprintf("%.9g", x)
csvval(x) = string(x)

function write_rows(file, rows)
  open(file, "w") do io
    println(io, join(string.(keys(first(rows))), ","))
    for r in rows
      println(io, join(csvval.(values(r)), ","))
    end
  end
end

function main()
  prepare_cases()
  mkpath(joinpath(RESULTS, "solutions"))
  rows = []
  adm = []
  # runs A: the three strategies with the default guard
  for case in ("case14_zeng", "sp_case14", "sp_case118")
    for s in STRATEGIES
      row, sol, a = run_case(case, s; guard = true)
      push!(rows, row)
      append!(adm, a)
      write_rows(joinpath(RESULTS, "solutions", "$(case)_$(s)_guard_on.csv"), sol)
    end
  end
  # runs B: sp_case60_narrow, every strategy with and without the guard
  build_narrow_case()
  for s in STRATEGIES, g in (true, false)
    row, sol, a = run_case("sp_case60_narrow", s; guard = g)
    push!(rows, row)
    append!(adm, a)
    write_rows(joinpath(RESULTS, "solutions", "sp_case60_narrow_$(s)_guard_$(g ? "on" : "off").csv"), sol)
  end
  write_rows(joinpath(RESULTS, "runs.csv"), rows)
  # check of runs B without the guard: the narrow-band buses run as PQ
  # through power_flow.qlimits.lock_pv_to_pq_buses (internal bus positions
  # of generators 159 and 160), at their scheduled Q clamped into the band
  lock_rows = []
  for buses in ([11], [25], [11, 25])
    f = run_config("active_set", false)
    write(f, replace(read(f, String), "    guard:\n      enabled: false" => "    guard:\n      enabled: false\n    lock_pv_to_pq_buses: [$(join(buses, ", "))]"))
    cfg = load_sparlectra_config(f)
    net = redirect_stdout(() -> importSCF(joinpath(CASES, "sp_case60_narrow.scf.json")), devnull)
    types0 = [getNodeType(n) for n in net.nodeVec]
    vset = Sparlectra._bus_voltage_setpoints_from_prosumers(net)
    res = redirect_stdout(() -> run_sparlectra(net = net, config = cfg), devnull)
    a, _ = admissibility(net, "sp_case60_narrow", "active_set", false, join(buses, " "), types0, vset, res.final_converged)
    append!(adm, a)
    v = res.final_converged ? violations(a) : NO_VIOLATIONS
    push!(lock_rows, merge((locked_buses = join(buses, " "), names = join([net.nodeVec[b].comp.cName for b in buses], " "), converged = res.final_converged, iterations = res.iterations), v))
  end
  rm(joinpath(RESULTS, "configs", "active_set_guard_off.yaml"))
  run_config("active_set", false)
  write_rows(joinpath(RESULTS, "narrow_lock.csv"), lock_rows)
  write_rows(joinpath(RESULTS, "consistency.csv"), adm)
  println("run_compare: ", length(rows), " runs, results/runs.csv")
end

if abspath(PROGRAM_FILE) == @__FILE__
  Base.invokelatest(main)
end
