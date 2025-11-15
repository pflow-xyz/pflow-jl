# Docker Setup for PFlow.jl

This document provides detailed instructions for running PFlow.jl with Jupyter Notebook using Docker.

## Prerequisites

- Docker installed on your system ([Get Docker](https://docs.docker.com/get-docker/))
- Docker Compose (usually included with Docker Desktop)

## Quick Start

1. **Clone the repository**:
   ```bash
   git clone https://github.com/pflow-xyz/pflow-jl.git
   cd pflow-jl
   ```

2. **Start the Jupyter notebook server**:
   ```bash
   docker compose up
   ```

3. **Access Jupyter Notebook**:
   - Open your browser and go to: `http://localhost:8888`
   - No password or token is required by default

4. **Open example notebook**:
   - Navigate to `example.ipynb` in the Jupyter interface
   - Run the cells to see PFlow.jl in action

## Docker Configuration

### Dockerfile

The `Dockerfile` sets up:
- Julia 1.11.2 base image
- System dependencies (build tools, git)
- PFlow.jl project dependencies
- IJulia kernel for Jupyter
- Additional packages (Plots, OrdinaryDiffEq)

### docker compose.yml

The `docker compose.yml` provides:
- Automatic port mapping (8888:8888)
- Volume mounting for live code editing
- Persistent Julia package storage
- Environment configuration

## Usage Examples

### Starting the Container

**Using docker compose (recommended)**:
```bash
docker compose up
```

**Run in detached mode (background)**:
```bash
docker compose up -d
```

**View logs**:
```bash
docker compose logs -f
```

### Stopping the Container

**Stop the container**:
```bash
docker compose down
```

**Stop and remove volumes**:
```bash
docker compose down -v
```

### Rebuilding After Changes

If you modify the Dockerfile or dependencies:
```bash
docker compose up --build
```

### Running Julia REPL Instead of Jupyter

To start an interactive Julia session instead of Jupyter:
```bash
docker compose run --rm jupyter julia --project=.
```

### Executing Julia Scripts

To run a Julia script:
```bash
docker compose run --rm jupyter julia --project=. /workspace/examples/traffic_light_colored.jl
```

## Advanced Configuration

### Custom Jupyter Settings

To add a password or token, modify the `docker compose.yml`:
```yaml
command: jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token='your-token-here'
```

### Using Different Julia Version

Modify the `Dockerfile` first line:
```dockerfile
FROM julia:1.12.1  # or any other version
```

### Port Configuration

To use a different port, modify `docker compose.yml`:
```yaml
ports:
  - "9999:8888"  # Maps host port 9999 to container port 8888
```

Then access at: `http://localhost:9999`

## Troubleshooting

### Port Already in Use

If port 8888 is already in use:
1. Stop the conflicting service, or
2. Change the port in `docker compose.yml` (see above)

### Permission Issues

If you encounter permission issues with mounted volumes:
```bash
docker compose run --rm jupyter chown -R $(id -u):$(id -g) /workspace
```

### Package Installation Issues

If Julia packages fail to install:
1. Remove the volume and rebuild:
   ```bash
   docker compose down -v
   docker compose up --build
   ```

### Container Won't Start

Check the logs:
```bash
docker compose logs jupyter
```

## Development Workflow

1. **Start the container**:
   ```bash
   docker compose up
   ```

2. **Edit files locally**: Changes are immediately reflected in the container due to volume mounting

3. **Restart Julia kernel**: In Jupyter, use Kernel → Restart to reload changes

4. **Run tests**:
   ```bash
   docker compose exec jupyter make test
   ```

## Volume Management

The container uses two volumes:
- `.:/workspace` - Your project files (live-mounted)
- `julia-packages:/root/.julia` - Julia packages (persisted)

To clean up volumes:
```bash
docker compose down -v
```

## Security Notes

The default configuration disables authentication for ease of local development. If exposing the container to a network:

1. Add authentication:
   ```yaml
   command: jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token='secure-token-here'
   ```

2. Or generate a password hash:
   ```bash
   jupyter notebook password
   ```

## Additional Resources

- [Docker Documentation](https://docs.docker.com/)
- [Jupyter Docker Stacks](https://jupyter-docker-stacks.readthedocs.io/)
- [IJulia Documentation](https://github.com/JuliaLang/IJulia.jl)
- [Julia Docker Images](https://hub.docker.com/_/julia)
