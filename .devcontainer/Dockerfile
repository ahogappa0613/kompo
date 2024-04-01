FROM mcr.microsoft.com/devcontainers/base:ubuntu
# Install the xz-utils package
RUN apt-get update && apt-get install -y clang
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:$PATH"
RUN git clone https://github.com/ahogappa0613/kompo-vfs.git && \
  cd kompo-vfs && \
  sudo /root/.cargo/bin/cargo build --release && \
  sudo cp target/release/kompo-cli /usr/local/bin && \
  sudo cp target/release/libkompo.a /usr/local/lib

