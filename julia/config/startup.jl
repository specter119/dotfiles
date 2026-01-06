#!/usr/bin/env julia
ENV["JULIA_PKG_SERVER"] = "https://mirrors.sjtug.sjtu.edu.cn/julia"

# conda.jl
ENV["CONDA_JL_HOME"] = ENV["MAMBA_ROOT_PREFIX"] # * "\\envs\\jupyverse"
ENV["CONDA_JL_CONDA_EXE"] = ENV["MAMBA_EXE"]

# IJulia
ENV["JUPYTER"] = "jupyter"

## PyCall.jl
# ENV["PYTHON"] = ENV["MAMBA_ROOT_PREFIX"] # * "\\envs\\jupyverse\\bin\\python"
