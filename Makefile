# Makefile for Coral Machine Volume Setup
# Provides convenient commands for common operations

.PHONY: help setup dev test shell clean logs status rebuild install-% prep

# Default target shows help
help:
	@echo "Coral Machine Development Environment"
	@echo "====================================="
	@echo ""
	@echo "Initial Setup:"
	@echo "  make setup          - Run full volume setup (30-45 min)"
	@echo "  make prep          - Prepare volumes directories"
	@echo ""
	@echo "Development:"
	@echo "  make dev           - Start development container"
	@echo "  make shell         - Open shell in running dev container"
	@echo "  make ssh           - SSH into dev container"
	@echo ""
	@echo "Testing:"
	@echo "  make test          - Test installation"
	@echo "  make status        - Show container and volume status"
	@echo "  make logs          - Show container logs"
	@echo ""
	@echo "Maintenance:"
	@echo "  make rebuild       - Rebuild Docker images"
	@echo "  make clean         - Remove volumes (WARNING: deletes data!)"
	@echo ""
	@echo "Individual Installers:"
	@echo "  make install-prep       - Setup build environment"
	@echo "  make install-compilers  - Install NVIDIA HPC SDK"
	@echo "  make install-headers    - Install build headers"
	@echo "  make install-libraries  - Build core libraries"
	@echo "  make install-viz        - Install visualization tools"

# Prepare volume directories
prep:
	@echo "Creating volume directory structure..."
	@mkdir -p volumes/workspace/deps volumes/workspace/source volumes/workspace/build volumes/workspace/output/vtk
	@echo "Volume directory structure created"

# Run full setup
setup: prep
	@echo "Starting full volume setup..."
	@echo "This will take 30-45 minutes"
	docker-compose --profile setup run --rm setup

# Start development container
dev:
	@echo "Starting development container..."
	docker-compose --profile dev up -d dev
	@echo ""
	@echo "Container started!"
	@echo "SSH: ssh coral-dev@localhost -p 2222"
	@echo "Or use: make shell"

# Open shell in running container
shell:
	docker-compose --profile dev exec dev /bin/zsh

# SSH into container
ssh:
	ssh coral-dev@localhost -p 2222

# Run tests
test:
	@echo "Running installation tests..."
	docker-compose --profile test run --rm test

# Show status
status:
	@echo "=== Containers ==="
	@docker-compose ps
	@echo ""
	@echo "=== Volumes ==="
	@docker volume ls | grep coral || echo "No coral volumes found"
	@echo ""
	@echo "=== Images ==="
	@docker images | grep volume-setup || echo "No volume-setup images found"

# Show logs
logs:
	docker-compose logs -f

# Rebuild Docker images
rebuild:
	@echo "Rebuilding Docker images..."
	docker-compose build --no-cache

# Individual installer targets
install-prep:
	docker-compose --profile installer run --rm installer ./installers/00-prep.sh

install-compilers:
	docker-compose --profile installer run --rm installer ./installers/01-compilers.sh

install-headers:
	docker-compose --profile installer run --rm installer ./installers/02-build-headers.sh

install-libraries:
	docker-compose --profile installer run --rm installer ./installers/03-core-libraries.sh

install-viz:
	docker-compose --profile installer run --rm installer ./installers/04-visualization.sh

# Generic installer pattern
install-%:
	docker-compose --profile installer run --rm installer ./installers/$*.sh

# Clean volumes (with confirmation)
clean:
	@echo "WARNING: This will delete all data in the volumes!"
	@read -p "Are you sure? Type 'yes' to continue: " confirm && \
	if [ "$$confirm" = "yes" ]; then \
		docker-compose --profile maintenance run --rm clean; \
		docker-compose down -v; \
		rm -rf volumes/; \
		echo "Volumes cleaned"; \
	else \
		echo "Cancelled"; \
	fi

# Stop all containers
stop:
	docker-compose down

# Remove containers but keep volumes
down:
	docker-compose down

# Start from scratch
reset: clean setup dev
	@echo "Full reset complete!"

# # Stop all containers
# stop:
# 	docker-compose down

# # Remove containers but keep volumes
# down:
# 	docker-compose down

# # Start from scratch
# reset: clean setup dev
# 	@echo "Full reset complete!"

# # Runtime image config
# IMAGE_NAME ?= gstvbrg/coral-machine-runtime
# TAG ?= latest
# RUNTIME_DOCKERFILE ?= docker/Dockerfile.runtime

# .PHONY: runtime-build runtime-push runtime-buildx-push runtime-login

# # Build runtime image (no cache)
# runtime-build:
# 	docker build --no-cache -f $(RUNTIME_DOCKERFILE) -t $(IMAGE_NAME):$(TAG) .

# # Push runtime image (assumes you're logged in)
# runtime-push:
# 	docker push $(IMAGE_NAME):$(TAG)

# # Build and push in one step using Buildx
# runtime-buildx-push:
# 	docker buildx build --no-cache -f $(RUNTIME_DOCKERFILE) -t $(IMAGE_NAME):$(TAG) --push .

# # Optional: quick login
# runtime-login:
# 	docker login -u $(DOCKER_USER)