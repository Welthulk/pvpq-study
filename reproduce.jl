# reproduce.jl: everything under results/ from a fresh checkout.
#
# usage: julia reproduce.jl
#
# Installs the pinned environment of Project.toml and Manifest.toml, then
# runs the three steps in their own processes: measurement, comparison,
# figures. Sparlectra comes from the public GitHub repository at commit
# a3cd5bc9 ([sources] in Project.toml), the development state of the
# upcoming 0.60; no registry entry is needed.

const ROOT = @__DIR__

function main()
  jl = Base.julia_cmd()
  run(`$(jl) --project=$(ROOT) -e "using Pkg; Pkg.instantiate()"`)
  rm(joinpath(ROOT, "results"); force = true, recursive = true)
  for step in ("run_compare.jl", "compare.jl", "figures.jl")
    println("== ", step)
    run(`$(jl) --project=$(ROOT) $(joinpath(ROOT, step))`)
  end
end

Base.invokelatest(main)
