# Best Practice (In my opinion)

For using julia in a scientific context I personally recommend the following workflows.

## Quick analysis

If you want to quickly analyze data or prototype/plot something, just use the main julia environment. Add the packages you need with `Pkg.add("Package")` and you are good to go.
Either in a jupyter notebook or a script. Be sure you are using the correct environment, should be something like `v1.x`.

## Project and Publication

If you work on a project and think about publishing it at some point, I recommend the following workflow:

### Step 1 - Creating a new package

Create a new julia package using [PkgTemplates](https://github.com/JuliaRegistries/PkgTemplates.jl) this will include everything you need for a proper package, sometimes this might be overkill.
In this case just generate a new directory with a `Project.toml` and a `src/` directory with:

```julia
using Pkg
Pkg.generate("MyPackage")
```

This will create a new directory called `MyPackage` with a `Project.toml` and a `src/` directory.

#### Interlude - What is a Project.toml?

A `Project.toml` is a file that contains information about your project, such as the name, version, and dependencies. It is used by the package manager to install and manage dependencies.
This will make your project reproducible and allow you to track what packages you used and needed.

#### Interlude - What is a Manifest.toml?

A `Manifest.toml` is a file that contains information about the exact versions of the dependencies that were installed. This will be generated automatically, and should NOT be uploaded to a git repository. With this file the exact circumstances of your project can be replicated, so that reproduction of results is possible.
So this file should be only uploaded when you publish your code with a DOI, or in conjunction with a paper.

## Step 2 - Installing dependencies

To add new packages that you need always activate the environment first with:

```julia
using Pkg
Pkg.activate("MyPackage")
```

Then you can add new packages with:

```julia
Pkg.add("Package")
```

This will add the package to the `Project.toml` and the `Manifest.toml` once you actually run the code.

## Step 3 - Development

To work and develop stuff for your project always work in the specific project environment (Yes you will need a project environment for each small part). Then you can write functions/methods/workflows in the `src/` directory. And outside the `src/` directory you can write scripts that use the functions/methods/workflows you wrote in the `src/` directory. You can also use Jupyter notebooks with functions you created in the `src/` directory. Be sure your project environment is activated (especially in VSCode). You should see Julia:MyPackage somewhere in the bottom left.

You do not necessarily need to populate the `src/` directory and just work with notebooks scripts... directly, but it is recommended.

## Step 4 - Git

Please use git to track your changes. If you used PkgTemplates to create your package, it will already be a git repository.

## Step 5 - Publishing

Use zenodo, or at least git tags to mark specific points of your project that you used for a paper. Include the Manifest.toml only at this stage! Do not touch this code then anymore.

*Have Fun*
