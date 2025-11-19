#!/bin/bash

# Docker helper script for PFlow-jl

set -e

show_help() {
    echo "PFlow-jl Docker Helper Script"
    echo ""
    echo "Usage: ./docker.sh [command]"
    echo ""
    echo "Commands:"
    echo "  start       Build and start the Jupyter notebook server"
    echo "  stop        Stop the running container"
    echo "  rebuild     Rebuild the Docker image from scratch"
    echo "  logs        Show container logs"
    echo "  clean       Remove all containers and images"
    echo "  help        Show this help message"
    echo ""
}

start_container() {
    echo "Starting PFlow-jl Jupyter notebook server..."
    docker-compose up
}

stop_container() {
    echo "Stopping PFlow-jl container..."
    docker-compose down
}

rebuild_container() {
    echo "Rebuilding PFlow-jl Docker image..."
    docker-compose down
    docker-compose build --no-cache
    echo "Rebuild complete. Run './docker.sh start' to start the container."
}

show_logs() {
    docker-compose logs -f
}

clean_all() {
    echo "Removing all PFlow-jl containers and images..."
    docker-compose down --rmi all --volumes
    echo "Cleanup complete."
}

case "${1:-help}" in
    start)
        start_container
        ;;
    stop)
        stop_container
        ;;
    rebuild)
        rebuild_container
        ;;
    logs)
        show_logs
        ;;
    clean)
        clean_all
        ;;
    help|*)
        show_help
        ;;
esac
