# Docker Setup for PFlow-jl

This guide explains how to run PFlow-jl with Jupyter notebook in a Docker container.

## Prerequisites

- Docker installed on your system
- Docker Compose (optional, but recommended)

## Quick Start

### Using Docker Compose (Recommended)

1. Build and start the container:
```bash
docker-compose up
```

2. Open your browser and navigate to the URL displayed in the terminal (typically `http://127.0.0.1:8888/?token=...`)

3. The `./notebooks` directory is automatically mounted, so any changes you make in Jupyter will be reflected in your local filesystem.

### Using Docker CLI

1. Build the image:
```bash
docker build -t pflow-jl .
```

2. Run the container:
```bash
docker run -p 8888:8888 -v $(pwd)/notebooks:/workspace/notebooks pflow-jl
```

3. Open your browser and navigate to the URL displayed in the terminal.

## Features

- **Latest Julia**: The container uses the latest official Julia image
- **Jupyter Notebook**: Pre-configured with IJulia kernel
- **Volume Mount**: The `./notebooks` directory is mounted to persist your work
- **Pre-installed Dependencies**: All PFlow-jl dependencies are pre-installed and precompiled

## Stopping the Container

- If using Docker Compose: Press `Ctrl+C` in the terminal, then run `docker-compose down`
- If using Docker CLI: Press `Ctrl+C` in the terminal

## Rebuilding After Changes

If you modify the `Project.toml` or source code:

```bash
docker-compose down
docker-compose build --no-cache
docker-compose up
```

## Troubleshooting

### Port Already in Use

If port 8888 is already in use, modify the port mapping in `docker-compose.yml`:
```yaml
ports:
  - "8889:8888"  # Use port 8889 on your host
```

### Permission Issues with Notebooks

If you encounter permission issues with the mounted notebooks directory, you may need to adjust the ownership:
```bash
sudo chown -R $USER:$USER ./notebooks
```

## Example Notebooks

The repository includes example notebooks in the `./notebooks` directory:
- `knapsack.ipynb`: Example Petri net model for solving a knapsack problem

## Additional Resources

- [PFlow-jl README](README.md)
- [Julia Documentation](https://docs.julialang.org/)
- [IJulia Documentation](https://github.com/JuliaLang/IJulia.jl)
