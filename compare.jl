# compare.jl: pairwise comparison of the final solutions of results/runs.csv
# (results/pairs.csv) and the decision rule of the task (results/decision.txt).
#
# usage: julia --project=. compare.jl   (after run_compare.jl)

using Printf

const ROOT = @__DIR__
const RESULTS = joinpath(ROOT, "results")

function read_csv(file)
  L = readlines(file)
  h = split(L[1], ",")
  return [Dict(String(h[k]) => String(v) for (k, v) in enumerate(split(l, ","))) for l in L[2:end]]
end

solution(case, strategy, guard) = read_csv(joinpath(RESULTS, "solutions", "$(case)_$(strategy)_guard_$(guard == "true" ? "on" : "off").csv"))

function pair_row(a, b)
  sa = solution(a["case"], a["strategy"], a["guard"])
  sb = solution(b["case"], b["strategy"], b["guard"])
  du = maximum(abs(parse(Float64, x["vm_pu"]) - parse(Float64, y["vm_pu"])) for (x, y) in zip(sa, sb))
  dth = maximum(abs(parse(Float64, x["va_deg"]) - parse(Float64, y["va_deg"])) for (x, y) in zip(sa, sb))
  dtype = count(x["type"] != y["type"] for (x, y) in zip(sa, sb))
  f(r, k) = parse(Float64, r[k])
  return (case = a["case"], a = "$(a["strategy"])/guard_$(a["guard"])", b = "$(b["strategy"])/guard_$(b["guard"])",
    max_dU_pu = du, max_dtheta_deg = dth, buses_other_type = dtype,
    dloss_MW = f(b, "loss_MW") - f(a, "loss_MW"), dslack_p_MW = f(b, "slack_p_MW") - f(a, "slack_p_MW"), dslack_q_MVar = f(b, "slack_q_MVar") - f(a, "slack_q_MVar"))
end

function main()
  runs = read_csv(joinpath(RESULTS, "runs.csv"))
  ok = [r for r in runs if r["converged"] == "true"]
  pairs = []
  for i in eachindex(ok), j in (i + 1):length(ok)
    a, b = ok[i], ok[j]
    a["case"] == b["case"] || continue
    # strategies against each other at one guard setting, and each strategy
    # with against without the guard
    (a["guard"] == b["guard"] || a["strategy"] == b["strategy"]) || continue
    push!(pairs, pair_row(a, b))
  end
  open(joinpath(RESULTS, "pairs.csv"), "w") do io
    println(io, join(string.(keys(first(pairs))), ","))
    for p in pairs
      println(io, join([v isa AbstractFloat ? @sprintf("%.9g", v) : string(v) for v in values(p)], ","))
    end
  end
  # decision rule: runs A are the three cases with the guard on
  runs_a = [p for p in pairs if p.case in ("case14_zeng", "sp_case14", "sp_case118")]
  worst = isempty(runs_a) ? nothing : runs_a[argmax([p.max_dU_pu for p in runs_a])]
  main_a = any(p -> p.max_dU_pu > 0.005 || p.buses_other_type > 0, runs_a)
  open(joinpath(RESULTS, "decision.txt"), "w") do io
    println(io, "runs A: largest max |dU| ", worst === nothing ? "-" : @sprintf("%.6f pu (%s, %s against %s)", worst.max_dU_pu, worst.case, worst.a, worst.b))
    println(io, "runs A: pairs with another bus type: ", count(p -> p.buses_other_type > 0, runs_a))
    println(io, "rule: max |dU| > 0.005 pu or a bus type differs -> figure 5a is the main figure, else 5b")
    println(io, "main figure: ", main_a ? "5a" : "5b")
    println(io, "figure 5a case: ", worst === nothing ? "-" : worst.case)
  end
  print(read(joinpath(RESULTS, "decision.txt"), String))
end

if abspath(PROGRAM_FILE) == @__FILE__
  Base.invokelatest(main)
end
