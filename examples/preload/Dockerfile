FROM erlang:27

# Install Python, pip, and build tools (cmake needed for erlang_python NIF)
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    cmake \
    && rm -rf /var/lib/apt/lists/*

# Create venv and install Python dependencies
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install fastembed (lighter than sentence-transformers for demo)
RUN pip install --no-cache-dir fastembed

WORKDIR /app

# Copy the project
COPY . .

# Copy example module to src for compilation
RUN cp examples/preload/preload_example.erl src/

# Build the project
RUN rebar3 compile

# Set the venv path for barrel_embed
ENV BARREL_EMBED_VENV=/opt/venv

CMD ["rebar3", "shell"]
