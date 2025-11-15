# Docker Setup Testing Guide

This document provides guidance on testing the Docker setup for PFlow.jl.

## Manual Testing Steps

### 1. Test Docker Compose Configuration

Validate the docker-compose.yml syntax:
```bash
docker compose config --quiet
```

Expected: No errors, silent success

### 2. Build the Docker Image

Build the image (this may take 5-10 minutes):
```bash
docker compose build
```

Expected: Successful build with no errors

### 3. Start the Container

Start the Jupyter notebook server:
```bash
docker compose up
```

Expected output should include:
```
jupyter_1  | [I 2024-XX-XX XX:XX:XX.XXX NotebookApp] Serving notebooks from local directory: /workspace
jupyter_1  | [I 2024-XX-XX XX:XX:XX.XXX NotebookApp] Jupyter Notebook X.X.X is running at:
jupyter_1  | [I 2024-XX-XX XX:XX:XX.XXX NotebookApp] http://pflow-jupyter:8888/
```

### 4. Access Jupyter Notebook

1. Open browser to: http://localhost:8888
2. Verify the Jupyter interface loads
3. Navigate to `example.ipynb`
4. Click "Kernel" → "Change kernel" → Select "Julia 1.11.2"
5. Run the first cell to verify PFlow.jl imports correctly

Expected: No errors, model visualization appears

### 5. Test Julia REPL

In a separate terminal, test the Julia REPL:
```bash
docker compose exec jupyter julia --project=.
```

Then in the Julia REPL:
```julia
using pflow
m = Pflow()
place!(m, "test", initial=1, x=100, y=100)
println("✓ PFlow.jl loaded successfully")
exit()
```

Expected: No errors, success message displayed

### 6. Test Volume Mounting

1. Edit a file locally (e.g., add a comment to `src/pflow.jl`)
2. In the running container, verify the change:
   ```bash
   docker compose exec jupyter cat /workspace/src/pflow.jl | head -5
   ```

Expected: The local changes are visible in the container

### 7. Test Package Persistence

1. Stop the container:
   ```bash
   docker compose down
   ```

2. Restart the container:
   ```bash
   docker compose up
   ```

Expected: Container starts quickly without reinstalling packages

### 8. Test Makefile Targets

Test each Makefile target:

```bash
make docker-build    # Should build the image
make docker-up       # Should start the container
# Test in browser at http://localhost:8888
make docker-down     # Should stop the container
```

Expected: Each command works without errors

## Automated Testing

The GitHub Actions workflow (`.github/workflows/docker-test.yml`) automatically:
- Validates docker-compose.yml syntax
- Builds the Docker image
- Uses caching for faster builds

## Common Issues and Solutions

### Port Already in Use

**Symptom**: Error: "port is already allocated"

**Solution**: 
```bash
# Find process using port 8888
lsof -i :8888
# Kill the process or change port in docker-compose.yml
```

### Build Fails

**Symptom**: Docker build fails during Julia package installation

**Solution**:
```bash
# Clean and rebuild
docker compose down -v
docker compose build --no-cache
```

### Kernel Not Found

**Symptom**: Julia kernel not available in Jupyter

**Solution**:
```bash
# Rebuild the image
docker compose build --no-cache
docker compose up
```

## Performance Notes

- **First build**: 5-10 minutes (downloads Julia, installs packages)
- **Subsequent builds**: 1-2 minutes (uses cache)
- **Container startup**: 5-10 seconds
- **Jupyter ready**: 10-15 seconds after startup

## Success Criteria

The Docker setup is working correctly if:
- ✓ Docker compose config validates
- ✓ Image builds without errors
- ✓ Container starts and serves Jupyter on port 8888
- ✓ Julia kernel is available in Jupyter
- ✓ PFlow.jl loads without errors
- ✓ Example notebook runs successfully
- ✓ Local file changes are visible in container
- ✓ Julia packages persist between restarts
