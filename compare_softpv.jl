# compare_softpv.jl: every converged Soft-PV solution against every converged
# switched solution of the same network (results/pairs_softpv.csv), and the
# table for the question which switched solution a steep characteristic
# comes closest to, with the strategies against each other
# (results/h2_softpv.txt).
#
# Switched solutions: results/solutions/ (runs.csv, guard on) for
# case14_zeng, sp_case60_narrow and sp_case118; results/solutions/softpv/ for
# the two bands of sp_case60 (control "switched" in runs_softpv.csv).
# Buses of type Isolated are left out: in the sp_case60 variants the coupler
# is contracted and Neubach_110b is an isolated bus (softpv.jl).
#
# usage: julia --project=. compare_softpv.jl   (after softpv.jl)

using Printf

const ROOT = @__DIR__
const RESULTS = joinpath(ROOT, "results")
const SOL = joinpath(RESULTS, "solutions")
const STRATEGIES = ["active_set", "classic_simultaneous", "classic_one_at_a_time"]

function read_csv(file)
  L = readlines(file)
  h = split(L[1], ",")
  return [Dict(String(h[k]) => String(v) for (k, v) in enumerate(split(l, ","))) for l in L[2:end]]
end

f(r, k) = parse(Float64, r[k])

soft_file(r) = joinpath(SOL, "softpv", r["file"] * "_" * r["strategy"] * (r["start"] == "flat" ? "_flat" : "") * (r["damped"] == "true" ? "_damped" : "") * ".csv")

# the switched reference runs of a Soft-PV row: (strategy, run row, solution file)
function references(r, runs, soft_runs)
  if r["case"] in ("case14_zeng", "sp_case118") || (r["case"] == "sp_case60_narrow")
    rows = [x for x in runs if x["case"] == r["case"] && x["guard"] == "true"]
    return [(x["strategy"], x, joinpath(SOL, "$(x["case"])_$(x["strategy"])_guard_on.csv")) for x in rows]
  end
  rows = [x for x in soft_runs if x["variant"] == "N-fail" && x["control"] == "switched" && x["band"] == r["band"]]
  return [(x["strategy"], x, joinpath(SOL, "softpv", "$(x["file"])_$(x["strategy"]).csv")) for x in rows]
end

function distance(fa, fb)
  sa, sb = read_csv(fa), read_csv(fb)
  length(sa) == length(sb) || error("$(fa) and $(fb) have different bus counts")
  keep = [k for k in eachindex(sa) if sa[k]["type"] != "Isolated" && sb[k]["type"] != "Isolated"]
  du = maximum(abs(f(sa[k], "vm_pu") - f(sb[k], "vm_pu")) for k in keep)
  dth = maximum(abs(f(sa[k], "va_deg") - f(sb[k], "va_deg")) for k in keep)
  return du, dth, length(sa) - length(keep)
end

g(x) = x isa AbstractFloat ? @sprintf("%.9g", x) : string(x)

function compare_softpv_main()
  runs = read_csv(joinpath(RESULTS, "runs.csv"))
  soft_runs = read_csv(joinpath(RESULTS, "runs_softpv.csv"))
  pairs = []
  for r in soft_runs
    r["converged"] == "true" || continue
    # the contracted narrow case with switching: against the same strategy
    # on the original file
    if r["control"] == "switched"
      r["variant"] == "N-band" || continue
      ref = only(x for x in runs if x["case"] == "sp_case60_narrow" && x["strategy"] == r["strategy"] && x["guard"] == "true")
      du, dth, iso = distance(joinpath(SOL, "softpv", "$(r["file"])_$(r["strategy"]).csv"), joinpath(SOL, "sp_case60_narrow_$(r["strategy"])_guard_on.csv"))
      push!(pairs, (variant = r["variant"], band = r["band"], control = r["control"], start = r["start"], du_pct = r["du_pct"], strategy = r["strategy"], damped = r["damped"],
        ref_strategy = r["strategy"], ref_inconsistent_buses = ref["inconsistent_buses"], max_dU_pu = du, max_dtheta_deg = dth, isolated_buses_skipped = iso,
        dloss_MW = f(r, "loss_MW") - f(ref, "loss_MW"), dslack_q_MVar = f(r, "slack_q_MVar") - f(ref, "slack_q_MVar")))
      continue
    end
    for (s, ref, file) in references(r, runs, soft_runs)
      ref["converged"] == "true" || continue
      du, dth, iso = distance(soft_file(r), file)
      push!(pairs, (variant = r["variant"], band = r["band"], control = r["control"], start = r["start"], du_pct = r["du_pct"], strategy = r["strategy"], damped = r["damped"],
        ref_strategy = s, ref_inconsistent_buses = ref["inconsistent_buses"], max_dU_pu = du, max_dtheta_deg = dth, isolated_buses_skipped = iso,
        dloss_MW = f(r, "loss_MW") - f(ref, "loss_MW"), dslack_q_MVar = f(r, "slack_q_MVar") - f(ref, "slack_q_MVar")))
    end
  end
  open(joinpath(RESULTS, "pairs_softpv.csv"), "w") do io
    println(io, join(string.(keys(first(pairs))), ","))
    for p in pairs
      println(io, join(g.(values(p)), ","))
    end
  end

  # H1: the strategies against each other, per variant, dU and start
  h1 = String[]
  for r in soft_runs
    (r["converged"] == "true" && r["control"] != "switched" && r["strategy"] == "active_set") || continue
    others = [x for x in soft_runs if x["file"] == r["file"] && x["start"] == r["start"] && x["damped"] == r["damped"] && x["converged"] == "true" && x["strategy"] != "active_set"]
    isempty(others) && continue
    d = maximum(first(distance(soft_file(r), soft_file(x))) for x in others)
    push!(h1, @sprintf("%-8s %-9s dU %-4s start %-5s%s: max |dU| active_set to %s = %.3g pu", r["variant"], r["band"], r["du_pct"], r["start"], r["damped"] == "true" ? " damped" : "", join([x["strategy"] for x in others], ", "), d))
  end

  # H2: per network and dU, the Soft-PV solution (active set, start uset,
  # undamped if it converged) against each switched solution; the switched
  # solution with 0 inconsistent buses fulfils eq. 5 to 7 of Zhao et al.
  open(joinpath(RESULTS, "h2_softpv.txt"), "w") do io
    println(io, "H1: Soft-PV solutions of the three strategies (same file, start and damping)")
    foreach(l -> println(io, l), h1)
    println(io)
    println(io, "H2: max |dU| in pu of the Soft-PV solution (active_set, start uset) to each switched solution;")
    println(io, "in brackets the inconsistent buses of the switched solution (0 = fulfils eq. 5 to 7)")
    for (variant, band) in (("Z-all", "-"), ("Z-one", "-"), ("N-band", "-"), ("N-fail", "qbase_m1"))
      sel = [p for p in pairs if p.variant == variant && p.band == band && p.control == "qu" && p.start == "uset" && p.strategy == "active_set"]
      isempty(sel) && continue
      refs = unique([(p.ref_strategy, p.ref_inconsistent_buses) for p in sel])
      println(io)
      println(io, variant, band == "-" ? "" : " band $(band)", ":")
      println(io, rpad("dU %", 8), join([rpad("$(s) ($(n))", 30) for (s, n) in refs]), "nearest")
      for du in unique([p.du_pct for p in sel])
        row = [only(p for p in sel if p.du_pct == du && p.ref_strategy == s && p.damped == minimum(q.damped for q in sel if q.du_pct == du)) for (s, _) in refs]
        near = row[argmin([p.max_dU_pu for p in row])]
        println(io, rpad(du, 8), join([rpad(@sprintf("%.6f", p.max_dU_pu) * (p.damped == "true" ? " damped" : ""), 30) for p in row]), near.ref_strategy)
      end
    end
  end
  print(read(joinpath(RESULTS, "h2_softpv.txt"), String))
end

if abspath(PROGRAM_FILE) == @__FILE__
  Base.invokelatest(compare_softpv_main)
end
