# reproduce.jl: everything under results/ from a fresh checkout.
#
# usage: julia reproduce.jl
#
# Installs the pinned environment of Project.toml and Manifest.toml, then
# runs the steps in their own processes: measurement with the physical check
# of every solution, the runs with Q hysteresis 0, comparison, the Q(U) runs
# (droop and Soft-PV after Kataoka) with their comparison, figures.
# Sparlectra 0.60.0 comes from the public GitHub repository at commit
# a3cd5bc9 ([sources] in Project.toml); no registry entry is needed.

const ROOT = @__DIR__

function main()
  jl = Base.julia_cmd()
  run(`$(jl) --project=$(ROOT) -e "using Pkg; Pkg.instantiate()"`)
  rm(joinpath(ROOT, "results"); force = true, recursive = true)
  for step in ("run_compare.jl", "hyst0.jl", "compare.jl", "softpv.jl", "compare_softpv.jl", "figures.jl")
    println("== ", step)
    flush(stdout)
    run(`$(jl) --project=$(ROOT) $(joinpath(ROOT, step))`)
  end
end

Base.invokelatest(main)
