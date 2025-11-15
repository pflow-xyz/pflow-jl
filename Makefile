.PHONY: help install update test clean repl format

help: ## Show this help message
	@echo "PFlow.jl Makefile"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Install project dependencies
	julia --project=. -e 'using Pkg; Pkg.instantiate()'

update: ## Update project dependencies
	julia --project=. -e 'using Pkg; Pkg.update()'

resolve: ## Resolve project dependencies
	julia --project=. -e 'using Pkg; Pkg.resolve()'

test: ## Run tests
	julia --project=. -e 'using Pkg; Pkg.test()'

test-verbose: ## Run tests with verbose output
	julia --project=. -e 'using Pkg; Pkg.test(; test_args=["--verbose"])'

repl: ## Start Julia REPL with project
	julia --project=.

clean: ## Remove build artifacts and cache
	rm -rf Manifest.toml
	find . -type d -name ".ipynb_checkpoints" -exec rm -rf {} +

format: ## Format Julia code (requires JuliaFormatter.jl)
	julia --project=. -e 'using JuliaFormatter; format(".")'

check: ## Check project status
	julia --project=. -e 'using Pkg; Pkg.status()'

precompile: ## Precompile project
	julia --project=. -e 'using Pkg; Pkg.precompile()'

build: install resolve ## Install and resolve dependencies
	@echo "Project built successfully"

all: build test ## Build and test the project
