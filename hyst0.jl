# hyst0.jl: case14_zeng and sp_case60_narrow with Q hysteresis 0, the three
# strategies with the guard as in run_compare.jl. Writes one CSV line per run
# (results/runs_hyst0.csv, columns of runs.csv) and the physical check of
# every final solution (results/consistency_hyst0.csv, admissibility.jl).
#
# usage: julia --project=. hyst0.jl   (after run_compare.jl, which builds
# cases/sp_case60_narrow.scf.json)

include(joinpath(@__DIR__, "run_compare.jl"))

# The classic outer loop and the final Q check of the solver read the
# hysteresis from the net (net.q_hyst_pu, net.final_q_accept_pu). At the
# pinned Sparlectra commit power_flow.qlimits.hysteresis_pu and
# final_q_accept_pu in the config do not reach an imported net, which keeps
# the import values 0.01 and 0.02 pu. Both are therefore set on the net
# before the solve.
function zero_hysteresis!(net)
  net.q_hyst_pu = 0.0
  net.final_q_accept_pu = 0.0
  return net
end

function main_hyst0()
  rows = []
  adm = []
  for case in ("case14_zeng", "sp_case60_narrow"), s in STRATEGIES
    row, _, a = run_case(case, s; guard = true, prepare = zero_hysteresis!)
    push!(rows, row)
    append!(adm, a)
  end
  write_rows(joinpath(RESULTS, "runs_hyst0.csv"), rows)
  write_rows(joinpath(RESULTS, "consistency_hyst0.csv"), adm)
  println("hyst0: ", length(rows), " runs, results/runs_hyst0.csv")
end

if abspath(PROGRAM_FILE) == @__FILE__
  Base.invokelatest(main_hyst0)
end
