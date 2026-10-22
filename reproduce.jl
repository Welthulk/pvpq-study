# reproduce.jl: everything under results/ from a fresh checkout.
#
# usage: julia reproduce.jl
#
# Installs the pinned environment of Project.toml and Manifest.toml
# (Sparlectra 0.60.0; until it is registered the manifest points at the
# development checkout), then runs the three steps
# in their own processes: measurement, comparison, figures.

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
