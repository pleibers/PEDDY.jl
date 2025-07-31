using PEDDY
using Documenter

DocMeta.setdocmeta!(PEDDY, :DocTestSetup, :(using PEDDY); recursive=true)

makedocs(;
    modules=[PEDDY],
    authors="Patrick Leibersperger <patrick.leibersperger@slf.ch>, Patricia Asemann <patriciia.asemann@slf.ch>, Rainette Engbers <rainette.engbers@slf.ch>",
    sitename="PEDDY.jl",
    format=Documenter.HTML(;
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)
