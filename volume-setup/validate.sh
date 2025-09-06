#!/bin/bash
# Validation script to check Docker setup is working correctly

set -e

echo "====================================="
echo "Coral Machine Docker Setup Validation"
echo "====================================="
echo ""

# Check Docker is installed
echo "Checking Docker..."
if command -v docker &> /dev/null; then
    echo "✅ Docker: $(docker --version)"
else
    echo "❌ Docker not found. Please install Docker."
    exit 1
fi

# Check Docker Compose
echo "Checking Docker Compose..."
if command -v docker-compose &> /dev/null; then
    echo "✅ Docker Compose: $(docker-compose --version)"
else
    echo "❌ Docker Compose not found. Please install Docker Compose."
    exit 1
fi

# Check Make
echo "Checking Make..."
if command -v make &> /dev/null; then
    echo "✅ Make: $(make --version | head -1)"
else
    echo "⚠️  Make not found. You can still use docker-compose directly."
fi

# Check if Docker daemon is running
echo "Checking Docker daemon..."
if docker info &> /dev/null; then
    echo "✅ Docker daemon is running"
else
    echo "❌ Docker daemon is not running. Please start Docker."
    exit 1
fi

# Check for NVIDIA Docker support (optional)
echo "Checking GPU support..."
if docker run --rm --gpus all nvidia/cuda:12.5.0-base-ubuntu22.04 nvidia-smi &> /dev/null; then
    echo "✅ NVIDIA GPU support detected"
else
    echo "⚠️  No GPU support (CPU-only mode)"
fi

# Check if volumes directory exists
echo "Checking volume directories..."
if [ -d "volumes" ]; then
    echo "⚠️  Volume directories exist. Use 'make clean' to reset."
else
    echo "✅ Ready for fresh installation"
fi

# Check if .env exists
echo "Checking configuration..."
if [ -f ".env" ]; then
    echo "✅ .env file exists"
else
    echo "⚠️  No .env file. Creating from template..."
    cp .env.example .env
    echo "✅ Created .env from template"
fi

# Check port availability
echo "Checking ports..."
for port in 2222 11111; do
    if ! lsof -i:$port &> /dev/null && ! netstat -an | grep -q ":$port "; then
        echo "✅ Port $port is available"
    else
        echo "⚠️  Port $port may be in use"
    fi
done

echo ""
echo "====================================="
echo "Validation complete!"
echo ""
echo "Next steps:"
echo "1. Review and edit .env if needed"
echo "2. Run 'make setup' to build volumes (30-45 min)"
echo "3. Run 'make dev' to start development environment"
echo "4. Connect with 'make ssh' or 'make shell'"
echo "====================================="