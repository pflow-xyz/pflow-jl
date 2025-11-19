# Use the official Julia image with the latest version
FROM julia:latest

# Install system dependencies for Jupyter and plotting
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /workspace

# Copy project files
COPY Project.toml Manifest.toml ./

# Install Julia dependencies
RUN julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'

# Install Jupyter and IJulia
RUN julia --project=. -e 'using Pkg; Pkg.add("IJulia"); using IJulia; installkernel("Julia")'

# Copy source code
COPY src ./src
COPY test ./test

# Expose Jupyter notebook port
EXPOSE 8888

# Set up Jupyter to accept connections from any IP
ENV JUPYTER_ENABLE_LAB=yes

# Create notebooks directory if it doesn't exist
RUN mkdir -p /workspace/notebooks

# Start Jupyter notebook with Julia kernel
CMD ["julia", "--project=.", "-e", "using IJulia; IJulia.notebook(dir=\"/workspace/notebooks\", detached=false)"]
