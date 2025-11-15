# Dockerfile for PFlow.jl with Jupyter Notebook support
FROM julia:1.11.2

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
COPY tools/ ./tools/

# Install Julia dependencies with robust error handling
RUN julia --project=. -e 'using Pkg; println("Resolving dependencies..."); try Pkg.resolve(); catch e; println("Warning: Pkg.resolve() failed: ", e); println("Continuing with instantiate..."); end; println("Instantiating..."); Pkg.instantiate();' \
 && chmod +x /workspace/tools/patch_petri.sh \
 && /workspace/tools/patch_petri.sh \
 && julia --project=. -e 'using Pkg; try Pkg.precompile(); println("Precompilation successful!"); catch e; println("ERROR: Precompilation failed!"); println("Error details: ", e); println("\nCurrent package status:"); Pkg.status(); exit(1); end'

# Install IJulia for Jupyter notebook support
RUN julia -e 'using Pkg; Pkg.add("IJulia"); using IJulia; IJulia.installkernel("Julia", "--project=@.")'

# Install additional plotting and ODE packages needed for notebooks
RUN julia --project=. -e 'using Pkg; Pkg.add(["Plots", "OrdinaryDiffEq"]); Pkg.precompile()'

# Expose Jupyter notebook port
EXPOSE 8888

# Set the default command to start Jupyter notebook
CMD ["jupyter", "notebook", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", "--NotebookApp.token=''", "--NotebookApp.password=''"]
