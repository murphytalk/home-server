# Use the slim version of Python as the base image
FROM python:3.13-slim

# Add non-root user with UID 1000 and GID 1000
ARG USERNAME=devuser
ARG USER_UID=1000
ARG USER_GID=1000

# Install psycopg2 dependencies, git, and vim in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 git openssh-client vim htop screen curl procps  &&  apt-get clean  && rm -rf /var/lib/apt/lists/*

# Create a new user and group with the specified UID and GID
RUN groupadd --gid $USER_GID $USERNAME && \
    useradd --uid $USER_UID --gid $USER_GID --create-home $USERNAME

# Switch to the non-root user
USER $USERNAME

# Set the default command to start bash
CMD ["/bin/bash"]

