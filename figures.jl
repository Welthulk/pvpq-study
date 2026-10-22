# figures.jl: the two figures of the study, PNG 1200 x 627 px.
#   5a voltage profile of the three final solutions of the case with the
#      largest deviation (results/fig5a_voltage_profile.png), when the
#      decision rule selects it
#   5b iterations and switching rounds with and without the guard for
#      sp_case60_narrow (results/fig5b_narrow_guard.png)
#
# usage: julia --project=. figures.jl   (after compare.jl)

# GR draws offscreen. Without this, on a desktop session (Wayland, X11) GR
# tries to open a Qt window first; when that fails ("GKS: Open failed") the
# PNG still gets written, but with another layout (title cut off in 5b).
ENV["GKSwstype"] = "100"

using Plots
using PNGFiles
gr()

const ROOT = @__DIR__
const RESULTS = joinpath(ROOT, "results")
const STRATEGIES = ["active_set", "classic_simultaneous", "classic_one_at_a_time"]

function read_csv(file)
  L = readlines(file)
  h = split(L[1], ",")
  return [Dict(String(h[k]) => String(v) for (k, v) in enumerate(split(l, ","))) for l in L[2:end]]
end

# GR writes even pixel heights only (627 gives 626); the figures are drawn
# 628 high and the last pixel row is cut off, which gives 1200 x 627
function save_1200x627(p, file)
  savefig(p, file)
  img = PNGFiles.load(file)
  PNGFiles.save(file, img[1:627, 1:1200])
end

function fig5a(case)
  p = plot(size = (1200, 628), dpi = 100, xlabel = "bus", ylabel = "voltage magnitude (pu)", title = "$(case): final voltage per strategy", legend = :bottomright, framestyle = :box, left_margin = 12Plots.mm, bottom_margin = 10Plots.mm)
  for (s, m) in zip(STRATEGIES, (:circle, :rect, :utriangle))
    sol = read_csv(joinpath(RESULTS, "solutions", "$(case)_$(s)_guard_on.csv"))
    buses = parse.(Int, getindex.(sol, "bus"))
    plot!(p, buses, parse.(Float64, getindex.(sol, "vm_pu")), label = s, marker = m, markersize = 5, linewidth = 1, xticks = buses)
  end
  save_1200x627(p, joinpath(RESULTS, "fig5a_voltage_profile.png"))
end

function fig5b()
  runs = [r for r in read_csv(joinpath(RESULTS, "runs.csv")) if r["case"] == "sp_case60_narrow"]
  labels = String[]
  iters = Float64[]
  rounds = Float64[]
  for s in STRATEGIES, g in ("true", "false")
    r = only(x for x in runs if x["strategy"] == s && x["guard"] == g)
    push!(labels, "$(s)\nguard $(g == "true" ? "on" : "off")" * (r["converged"] == "true" ? "" : "\n(not converged)"))
    push!(iters, parse(Float64, r["iterations"]))
    push!(rounds, parse(Float64, r["switching_rounds"]) + parse(Float64, r["pv_pq_events"]))
  end
  x = collect(1:length(labels))
  # headroom above the highest bar for the legend; without it the y axis
  # ends at the tallest bar and the legend covers it
  ymax = 1.3 * maximum(vcat(iters, rounds))
  p = bar(x .- 0.2, iters, bar_width = 0.4, label = "Newton iterations", size = (1200, 628), dpi = 100, xticks = (x, labels), ylabel = "count", ylims = (0, ymax), title = "sp_case60_narrow: two machines with a Q band of 0.015 pu", framestyle = :box, legend = :topright, left_margin = 12Plots.mm, bottom_margin = 16Plots.mm)
  bar!(p, x .+ 0.2, rounds, bar_width = 0.4, label = "active-set changes + PV/PQ switching events")
  save_1200x627(p, joinpath(RESULTS, "fig5b_narrow_guard.png"))
end

function main()
  d = read(joinpath(RESULTS, "decision.txt"), String)
  case = match(r"figure 5a case: (\S+)", d).captures[1]
  occursin("main figure: 5a", d) && case != "-" && fig5a(case)
  fig5b()
  println("figures written to results/")
end

if abspath(PROGRAM_FILE) == @__FILE__
  Base.invokelatest(main)
end
