FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY ai_core/ ./ai_core/
COPY shared/ ./shared/
COPY configs/ ./configs/

# Create logs directory
RUN mkdir -p logs/trials

# Set environment variables
ENV PYTHONPATH=/app

# Expose port for communication with Godot
EXPOSE 8080

# Run the AI agent
CMD ["python", "ai_core/run_agent.py"] 