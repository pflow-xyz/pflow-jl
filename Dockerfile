# Dockerfile for PFlow.jl with Jupyter Notebook support
FROM julia:1.12.1

# Set working directory
WORKDIR /workspace

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    wget \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy project files
COPY Project.toml Manifest.toml ./
COPY src/ ./src/
COPY test/ ./test/
COPY examples/ ./examples/

# Install Julia dependencies with robust error handling
RUN julia --project=. -e ' \
    using Pkg; \
    println("Resolving dependencies..."); \
    try \
        Pkg.resolve(); \
    catch e \
        println("Warning: Pkg.resolve() failed: ", e); \
        println("Continuing with instantiate..."); \
    end; \
    println("Installing dependencies..."); \
    Pkg.instantiate(); \
    println("Dependency status:"); \
    Pkg.status(); \
    ' && \
    # Apply workaround for Petri.jl SteadyStateDiffEq compatibility issue with Julia 1.12 \
    PETRI_PATH=$(julia --project=. -e 'using Pkg; println(joinpath(dirname(Base.find_package("Petri")), "..", "..", "Petri"))' 2>/dev/null | tail -1) && \
    if [ -n "$PETRI_PATH" ] && [ -f "$PETRI_PATH/src/Petri.jl" ]; then \
        echo "Applying Petri.jl workaround for Julia 1.12..."; \
        chmod u+w "$PETRI_PATH/src/Petri.jl" && \
        sed -i 's/include("solvers.jl")/# include("solvers.jl")  # Commented out to avoid SteadyStateDiffEq precompilation error/' "$PETRI_PATH/src/Petri.jl" && \
        rm -rf /root/.julia/compiled/v1.12/Petri /root/.julia/compiled/v1.12/SteadyStateDiffEq /root/.julia/compiled/v1.12/pflow; \
    fi && \
    # Precompile packages with error diagnostics \
    julia --project=. -e ' \
    using Pkg; \
    println("Precompiling packages..."); \
    try \
        Pkg.precompile(); \
        println("Precompilation successful!"); \
    catch e \
        println("ERROR: Precompilation failed!"); \
        println("Error details: ", e); \
        println("\nCurrent package status:"); \
        Pkg.status(); \
        rethrow(e); \
    end \
    '

# Install IJulia for Jupyter notebook support
RUN julia -e 'using Pkg; Pkg.add("IJulia"); using IJulia; IJulia.installkernel("Julia", "--project=@.")'

# Install additional plotting and ODE packages needed for notebooks
RUN julia --project=. -e 'using Pkg; Pkg.add(["Plots", "OrdinaryDiffEq"]); Pkg.precompile()'

# Expose Jupyter notebook port
EXPOSE 8888

# Set the default command to start Jupyter notebook
CMD ["jupyter", "notebook", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", "--NotebookApp.token=''", "--NotebookApp.password=''"]
