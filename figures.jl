# figures.jl: the figures of the study, PNG 1200 x 627 px.
#   5a voltage profile of the three final solutions of the case with the
#      largest deviation (results/fig5a_voltage_profile.png), when the
#      decision rule selects it
#   5b iterations and switching rounds with and without the guard for
#      sp_case60_narrow (results/fig5b_narrow_guard.png)
#   6  case14_zeng with Q(U) droop: distance to the switched solutions
#      (results/fig6_zeng_softpv.png)
#   7  sp_case60_narrow with Q(U) droop: characteristics and solved points
#      (results/fig7_narrow_softpv.png)
#   8  sp_case60_narrow, Q(U) droop 1 % and Soft-PV after Kataoka side by
#      side (results/fig8_kataoka.png)
#
# usage: julia --project=. figures.jl   (after compare.jl and compare_softpv.jl)

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

# 6: case14_zeng with Q(U) droop, distance of the Q(U) solution (active set,
# start uset) to each switched solution over the half width dU of the
# characteristic (results/pairs_softpv.csv)
function fig6()
  pairs = read_csv(joinpath(RESULTS, "pairs_softpv.csv"))
  p = plot(size = (1200, 628), dpi = 100, xscale = :log10, xticks = ([0.5, 1, 2, 5], ["0.5", "1", "2", "5"]), xlabel = "half width dU of the Q(U) droop (% of U_set)", ylabel = "max |dU| to the switched solution (pu)",
    title = "case14_zeng: Q(U) droop instead of PV/PQ switching", legend = :topleft, framestyle = :box, left_margin = 12Plots.mm, bottom_margin = 10Plots.mm, ylims = (0, :auto))
  for (variant, ls, lab) in (("Z-all", :solid, "droop at all four PV machines"), ("Z-one", :dash, "droop at buses 2 and 6"))
    for (s, m) in zip(STRATEGIES, (:circle, :rect, :utriangle))
      sel = [x for x in pairs if x["variant"] == variant && x["control"] == "qu" && x["start"] == "uset" && x["strategy"] == "active_set" && x["damped"] == "false" && x["ref_strategy"] == s]
      isempty(sel) && continue
      ok = sel[1]["ref_inconsistent_buses"] == "0" ? "admissible" : "not admissible"
      plot!(p, parse.(Float64, getindex.(sel, "du_pct")), parse.(Float64, getindex.(sel, "max_dU_pu")), label = "$(lab), against $(s) ($(ok))", linestyle = ls, marker = m, markersize = 5)
    end
  end
  save_1200x627(p, joinpath(RESULTS, "fig6_zeng_softpv.png"))
end

# 7: sp_case60_narrow, the Q(U) characteristic of both narrow-band machines
# per dU with the solved point, and the switched solutions
# (results/stability_softpv.csv, results/consistency.csv)
function fig7()
  stab = [x for x in read_csv(joinpath(RESULTS, "stability_softpv.csv")) if x["variant"] == "N-band" && x["strategy"] == "active_set" && x["damped"] == "false"]
  cons = [x for x in read_csv(joinpath(RESULTS, "consistency.csv")) if x["case"] == "sp_case60_narrow" && x["guard"] == "true" && x["lock"] == "-"]
  panels = []
  for name in ("Birkkamp_110", "Westtal_110")
    rs = [x for x in stab if x["name"] == name]
    p = plot(xlabel = "U (pu)", ylabel = "Q (Mvar)", title = name, legend = :bottomleft, framestyle = :box)
    for r in rs
      us, du, qmin, qmax = parse(Float64, r["uset_pu"]), parse(Float64, r["du_pct"]), parse(Float64, r["qmin_MVar"]), parse(Float64, r["qmax_MVar"])
      d = us * du / 100
      plot!(p, [0.95, us - d, us + d, 1.06], [qmax, qmax, qmin, qmin], label = "droop, dU $(r["du_pct"]) %")
      scatter!(p, [parse(Float64, r["u_pu"])], [parse(Float64, r["q_MVar"])], label = "", color = :black, markersize = 4)
    end
    for (s, m) in zip(STRATEGIES, (:star5, :diamond, :xcross))
      c = only(x for x in cons if x["name"] == name && x["strategy"] == s)
      scatter!(p, [parse(Float64, c["u_pu"])], [parse(Float64, c["q_MVar"])], label = "switched, $(s)", marker = m, markersize = 8)
    end
    vline!(p, [parse(Float64, rs[1]["uset_pu"])], label = "U_set", color = :gray, linestyle = :dot)
    push!(panels, p)
  end
  p = plot(panels..., layout = (1, 2), size = (1200, 628), dpi = 100, plot_title = "sp_case60_narrow: band 4.0 to 5.5 Mvar as Q(U) droop, dots: solved points", left_margin = 10Plots.mm, bottom_margin = 10Plots.mm)
  save_1200x627(p, joinpath(RESULTS, "fig7_narrow_softpv.png"))
end

# characteristic of a row of stability_softpv.csv as (U, Q) points, with
# flat ends from `ulo` to `uhi` (softpv.jl, characteristic_points)
function char_line(r, ulo, uhi)
  us, qmin, qmax = parse(Float64, r["uset_pu"]), parse(Float64, r["qmin_MVar"]), parse(Float64, r["qmax_MVar"])
  if r["shape"] == "droop"
    d = us * parse(Float64, r["du_pct"]) / 100
    return [ulo, us - d, us + d, uhi], [qmax, qmax, qmin, qmin]
  end
  din, dc = us * parse(Float64, r["du_in_pct"]) / 100, us * parse(Float64, r["du_c_pct"]) / 100
  delta = (qmax - qmin) * parse(Float64, r["delta_pct"]) / 100
  return [ulo, us - din - dc, us - din, us + din, us + din + dc, uhi], [qmax, qmax, qmax - delta, qmin + delta, qmin, qmin]
end

# 8: sp_case60_narrow, Q(U) droop 1 % and Soft-PV after Kataoka (dU_in
# 0.1 %, dU_c 2 %) side by side, both machines with the solved points and
# the switched solutions (results/stability_softpv.csv, results/consistency.csv)
function fig8()
  stab = [x for x in read_csv(joinpath(RESULTS, "stability_softpv.csv")) if x["strategy"] == "active_set" && x["damped"] == "false" && x["start"] == "uset"]
  cons = [x for x in read_csv(joinpath(RESULTS, "consistency.csv")) if x["case"] == "sp_case60_narrow" && x["guard"] == "true" && x["lock"] == "-"]
  panels = []
  # uhi above U_set + dU_in + dU_c of Westtal_110 (1.0404 pu), so the Q_min
  # end of its Soft-PV characteristic is visible
  ulo, uhi = 0.97, 1.045
  for (title, sel) in (("Q(U) droop, dU 1 %", x -> x["variant"] == "N-band" && x["du_pct"] == "1"),
    ("Soft-PV (Kataoka), dU_in 0.1 %, dU_c 2 %", x -> x["variant"] == "K-nband" && x["du_in_pct"] == "0.1" && x["du_c_pct"] == "2"))
    p = plot(xlabel = "U (pu)", ylabel = "Q (Mvar)", title = title, legend = :bottomleft, framestyle = :box, xlims = (ulo, uhi), ylims = (3.8, 6.4))
    for (name, col) in (("Birkkamp_110", :steelblue), ("Westtal_110", :darkorange))
      r = only(x for x in stab if sel(x) && x["name"] == name)
      us, uq = char_line(r, ulo, uhi)
      plot!(p, us, uq, label = "$(name) characteristic", color = col, linewidth = 2)
      scatter!(p, [parse(Float64, r["u_pu"])], [parse(Float64, r["q_MVar"])], label = "$(name) solved", color = col, markersize = 7)
      for (s, m) in zip(STRATEGIES, (:star5, :diamond, :xcross))
        c = only(x for x in cons if x["name"] == name && x["strategy"] == s)
        scatter!(p, [parse(Float64, c["u_pu"])], [parse(Float64, c["q_MVar"])], label = name == "Birkkamp_110" ? "switched, $(s)" : "", marker = m, markersize = 8, color = col, markerstrokecolor = :black)
      end
    end
    push!(panels, p)
  end
  p = plot(panels..., layout = (1, 2), size = (1200, 628), dpi = 100, plot_title = "sp_case60_narrow: band 4.0 to 5.5 Mvar, droop against Soft-PV", left_margin = 10Plots.mm, bottom_margin = 10Plots.mm)
  save_1200x627(p, joinpath(RESULTS, "fig8_kataoka.png"))
end

function main()
  d = read(joinpath(RESULTS, "decision.txt"), String)
  case = match(r"figure 5a case: (\S+)", d).captures[1]
  occursin("main figure: 5a", d) && case != "-" && fig5a(case)
  fig5b()
  isfile(joinpath(RESULTS, "pairs_softpv.csv")) && fig6()
  isfile(joinpath(RESULTS, "stability_softpv.csv")) && fig7()
  isfile(joinpath(RESULTS, "stability_softpv.csv")) && fig8()
  println("figures written to results/")
end

if abspath(PROGRAM_FILE) == @__FILE__
  Base.invokelatest(main)
end
