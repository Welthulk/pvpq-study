# compare_softpv.jl: every converged Q(U) solution (Q(U) droop and Soft-PV
# after Kataoka) against every converged switched solution of the same
# network (results/pairs_softpv.csv), and the tables for the question which
# switched solution a characteristic comes closest to, with the strategies
# against each other (results/h2_softpv.txt).
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
# Kataoka variant => droop variant on the same network and the droop half
# width (%) its iterations are compared with
const K_DROOP = Dict("K-zall" => ("Z-all", "0.5"), "K-nband" => ("N-band", "0.5"), "K-118" => ("118-all", "1"))

function read_csv(file)
  L = readlines(file)
  h = split(L[1], ",")
  return [Dict(String(h[k]) => String(v) for (k, v) in enumerate(split(l, ","))) for l in L[2:end]]
end

f(r, k) = parse(Float64, r[k])

soft_file(r) = joinpath(SOL, "softpv", r["file"] * "_" * r["strategy"] * (r["start"] == "flat" ? "_flat" : "") * (r["damped"] == "true" ? "_damped" : "") * ".csv")

# the switched reference runs of a Q(U) row: (strategy, run row, solution file)
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

# label of the characteristic of a row
chlabel(r) = r["shape"] == "kataoka" ? "in $(r["du_in_pct"]) c $(r["du_c_pct"])" : "dU $(r["du_pct"])"

# the run of a variant and characteristic used in the tables: given
# strategy, start uset, undamped when it converged, else damped
function pick(rows, sel, strategy)
  c = [r for r in rows if sel(r) && r["strategy"] == strategy && r["start"] == "uset" && r["control"] != "switched"]
  isempty(c) && return nothing
  u = [r for r in c if r["damped"] == "false"]
  return !isempty(u) && u[1]["converged"] == "true" ? u[1] : (length(c) > 1 ? only(r for r in c if r["damped"] == "true") : u[1])
end

itlabel(r) = r === nothing ? "-" : r["converged"] == "true" ? r["iterations"] * (r["damped"] == "true" ? " damped" : "") : "no (" * r["iterations"] * ")"

function compare_softpv_main()
  runs = read_csv(joinpath(RESULTS, "runs.csv"))
  soft_runs = read_csv(joinpath(RESULTS, "runs_softpv.csv"))
  stab = read_csv(joinpath(RESULTS, "stability_softpv.csv"))
  pairs = []
  for r in soft_runs
    r["converged"] == "true" || continue
    # the contracted narrow case with switching: against the same strategy
    # on the original file
    if r["control"] == "switched"
      r["variant"] == "N-band" || continue
      ref = only(x for x in runs if x["case"] == "sp_case60_narrow" && x["strategy"] == r["strategy"] && x["guard"] == "true")
      du, dth, iso = distance(joinpath(SOL, "softpv", "$(r["file"])_$(r["strategy"]).csv"), joinpath(SOL, "sp_case60_narrow_$(r["strategy"])_guard_on.csv"))
      push!(pairs, (variant = r["variant"], band = r["band"], control = r["control"], start = r["start"], shape = r["shape"], du_pct = r["du_pct"], du_in_pct = r["du_in_pct"], du_c_pct = r["du_c_pct"],
        strategy = r["strategy"], damped = r["damped"], ref_strategy = r["strategy"], ref_inconsistent_buses = ref["inconsistent_buses"], max_dU_pu = du, max_dtheta_deg = dth, isolated_buses_skipped = iso,
        dloss_MW = f(r, "loss_MW") - f(ref, "loss_MW"), dslack_q_MVar = f(r, "slack_q_MVar") - f(ref, "slack_q_MVar")))
      continue
    end
    for (s, ref, file) in references(r, runs, soft_runs)
      ref["converged"] == "true" || continue
      du, dth, iso = distance(soft_file(r), file)
      push!(pairs, (variant = r["variant"], band = r["band"], control = r["control"], start = r["start"], shape = r["shape"], du_pct = r["du_pct"], du_in_pct = r["du_in_pct"], du_c_pct = r["du_c_pct"],
        strategy = r["strategy"], damped = r["damped"], ref_strategy = s, ref_inconsistent_buses = ref["inconsistent_buses"], max_dU_pu = du, max_dtheta_deg = dth, isolated_buses_skipped = iso,
        dloss_MW = f(r, "loss_MW") - f(ref, "loss_MW"), dslack_q_MVar = f(r, "slack_q_MVar") - f(ref, "slack_q_MVar")))
    end
  end
  open(joinpath(RESULTS, "pairs_softpv.csv"), "w") do io
    println(io, join(string.(keys(first(pairs))), ","))
    for p in pairs
      println(io, join(g.(values(p)), ","))
    end
  end

  # H1: the strategies against each other, per variant, characteristic and start
  h1 = String[]
  for r in soft_runs
    (r["converged"] == "true" && r["control"] != "switched" && r["strategy"] == "active_set") || continue
    others = [x for x in soft_runs if x["file"] == r["file"] && x["start"] == r["start"] && x["damped"] == r["damped"] && x["converged"] == "true" && x["strategy"] != "active_set"]
    isempty(others) && continue
    d = maximum(first(distance(soft_file(r), soft_file(x))) for x in others)
    push!(h1, @sprintf("%-8s %-9s %-11s start %-5s%s: max |dU| active_set to %s = %.3g pu", r["variant"], r["band"], chlabel(r), r["start"], r["damped"] == "true" ? " damped" : "", join([x["strategy"] for x in others], ", "), d))
  end

  # pair of a run against one switched strategy
  pairof(r, s) = only(p for p in pairs if p.variant == r["variant"] && p.control == r["control"] && p.start == r["start"] && p.du_pct == r["du_pct"] && p.du_in_pct == r["du_in_pct"] &&
    p.du_c_pct == r["du_c_pct"] && p.strategy == r["strategy"] && p.damped == r["damped"] && p.band == r["band"] && p.ref_strategy == s)

  # H2: per network and dU, the Q(U) droop solution (active set, start uset,
  # undamped if it converged) against each switched solution; the switched
  # solution with 0 inconsistent buses fulfils eq. 5 to 7 of Zhao et al.
  open(joinpath(RESULTS, "h2_softpv.txt"), "w") do io
    println(io, "H1: Q(U) solutions of the three strategies (same file, start and damping)")
    foreach(l -> println(io, l), h1)
    println(io)
    println(io, "H2: max |dU| in pu of the Q(U) droop solution (active_set, start uset) to each switched solution;")
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

    # Soft-PV after Kataoka: distance to the three switched solutions, the
    # nearest droop of the same network, iterations against the droop, and
    # position and |U - U_set| of every Soft-PV bus
    println(io)
    println(io, "Kataoka: Soft-PV (four points: PV inside the band, corners with 10 % of the band over dU_c).")
    println(io, "Run: active_set, start uset, damped only where the undamped run did not converge.")
    println(io, "H5: the Soft-PV solution is nearer to active_set than every Q(U) droop of the same network,")
    println(io, "and |U - U_set| < dU_in at every bus in the middle segment. \"equal\": both distances below 1e-6 pu, the solver tolerance.")
    for kv in ("K-zall", "K-nband", "K-118")
      dv, d0 = K_DROOP[kv]
      kr = [r for r in soft_runs if r["variant"] == kv]
      chars = unique([(r["du_in_pct"], r["du_c_pct"]) for r in kr])
      dsel = unique([r["du_pct"] for r in soft_runs if r["variant"] == dv && r["control"] != "switched"])
      dpairs = [(du, pairof(pick(soft_runs, x -> x["variant"] == dv && x["du_pct"] == du, "active_set"), "active_set")) for du in dsel if pick(soft_runs, x -> x["variant"] == dv && x["du_pct"] == du, "active_set")["converged"] == "true"]
      best = dpairs[argmin([p.max_dU_pu for (_, p) in dpairs])]
      d0run = pick(soft_runs, x -> x["variant"] == dv && x["du_pct"] == d0, "active_set")
      refs = [(x["strategy"], x["inconsistent_buses"]) for x in runs if x["case"] == kr[1]["case"] && x["guard"] == "true"]
      println(io)
      println(io, kv, " (", kr[1]["case"], "), nearest droop to active_set: dU ", best[1], " % with ", @sprintf("%.6f", best[2].max_dU_pu), " pu",
        best[2].damped == "true" ? " damped" : "", "; droop dU ", d0, " %: ", itlabel(d0run), " iterations")
      println(io, rpad("in % c %", 12), join([rpad("$(s) ($(n))", 28) for (s, n) in refs]), rpad("nearest", 22), rpad("H5", 6), rpad("iterations " * join(["as", "cs", "co"], "/"), 34), "PV/PQ events")
      for (din, dc) in chars
        sel = x -> x["variant"] == kv && x["du_in_pct"] == din && x["du_c_pct"] == dc
        r = pick(soft_runs, sel, "active_set")
        its = join([itlabel(pick(soft_runs, sel, s)) for s in STRATEGIES], "/")
        ev = sum(parse(Int, x["pv_pq_events"]) for x in soft_runs if sel(x))
        if r["converged"] != "true"
          println(io, rpad("$(din) $(dc)", 12), rpad("not converged, also damped", 28 * length(refs) + 27), rpad(its, 34), ev)
          continue
        end
        row = [pairof(r, s) for (s, _) in refs]
        near = row[argmin([p.max_dU_pu for p in row])]
        mid = [x for x in stab if x["variant"] == kv && x["du_in_pct"] == din && x["du_c_pct"] == dc && x["strategy"] == "active_set" && x["damped"] == r["damped"] && x["position"] == "mid"]
        mid_ok = all(f(x, "abs_du_pu") < f(x, "uset_pu") * f(x, "du_in_pct") / 100 for x in mid)
        dk = pairof(r, "active_set").max_dU_pu
        h5 = !mid_ok || near.ref_strategy != "active_set" ? "no" : max(dk, best[2].max_dU_pu) < 1e-6 ? "equal" : dk < best[2].max_dU_pu ? "yes" : "no"
        println(io, rpad("$(din) $(dc)", 12), join([rpad(@sprintf("%.6f", p.max_dU_pu) * (p.damped == "true" ? " damped" : ""), 28) for p in row]), rpad(near.ref_strategy, 22), rpad(h5, 6), rpad(its, 34), ev)
      end
      println(io, "per bus (active_set): bus name position |U - U_set| pu, dU_in pu, Q Mvar, dU/dQ off/on")
      for (din, dc) in chars
        r = pick(soft_runs, x -> x["variant"] == kv && x["du_in_pct"] == din && x["du_c_pct"] == dc, "active_set")
        r["converged"] == "true" || continue
        rows = [x for x in stab if x["variant"] == kv && x["du_in_pct"] == din && x["du_c_pct"] == dc && x["strategy"] == "active_set" && x["damped"] == r["damped"]]
        println(io, "  in $(din) c $(dc)", r["damped"] == "true" ? " damped" : "", ":")
        for x in rows
          println(io, @sprintf("    %4s %-14s %-10s %.6f  %.6f  %9.3f  %8.3f / %8.3f", x["bus"], x["name"], x["position"], f(x, "abs_du_pu"), f(x, "uset_pu") * f(x, "du_in_pct") / 100, f(x, "q_MVar"), f(x, "dudq"), f(x, "dudq_qu")))
        end
      end
    end
  end
  print(read(joinpath(RESULTS, "h2_softpv.txt"), String))
end

if abspath(PROGRAM_FILE) == @__FILE__
  Base.invokelatest(compare_softpv_main)
end
