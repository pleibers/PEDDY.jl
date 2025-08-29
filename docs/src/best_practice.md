# Best Practice (In my opinion)

For using julia in a scientific context I personally recommend the following workflows.

## Quick analysis

If you want to quickly analyze data or prototype/plot something, just use the main julia environment. Add the packages you need with `Pkg.add("Package")` and you are good to go.
Either in a jupyter notebook or a script. Be sure you are using the correct environment, should be something like `v1.x`.