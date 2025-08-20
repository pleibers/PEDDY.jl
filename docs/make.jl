using Documenter

import Pkg
if get(ENV, "DOCS_USE_ROOT_ENV", "0") == "1"
    # Use the root project environment, assuming it's already instantiated
    Pkg.activate(joinpath(@__DIR__, ".."))
else
    # Default: build using the docs environment and develop the local package
    Pkg.activate(@__DIR__)
    Pkg.develop(path=joinpath(@__DIR__, ".."))
    Pkg.instantiate()
end

using PEDDY

DocMeta.setdocmeta!(PEDDY, :DocTestSetup, :(using PEDDY); recursive=true)

makedocs(;
         modules=[PEDDY],
         authors="Patrick Leibersperger <patrick.leibersperger@slf.ch>, Patricia Asemann <patriciia.asemann@slf.ch>, Rainette Engbers <rainette.engbers@slf.ch>",
         sitename="PEDDY.jl",
         format=Documenter.HTML(;
                                edit_link="main",
                                assets=String[],),
         repo="",
         remotes=nothing,
         checkdocs=:none,
         pages=["Home" => "index.md"],)
