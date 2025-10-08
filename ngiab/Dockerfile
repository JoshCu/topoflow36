FROM awiciroh/ciroh-ngen-image AS tf36_build
# ENV TOPOFLOW_REPO=peckhams/topoflow36
# ENV TOPOFLOW_BRANCH=master
#==================================================================================
RUN dnf install -y gdal gdal-devel g++ python3-devel

# Get code from local files
COPY . /ngen/ngen/extern/topoflow36

# Or clone code
# ADD https://api.github.com/repos/${TOPOFLOW_REPO}/git/refs/heads/${TOPOFLOW_BRANCH} /tmp/version.json
# RUN git clone --single-branch --branch ${TOPOFLOW_BRANCH} https://github.com/${TOPOFLOW_REPO}.git

# Or get code from ngen clone
# COPY --from=ngen_clone /ngen/ngen/extern/topoflow36 /ngen/ngen/extern/topoflow36

RUN uv pip install --no-cache-dir /ngen/ngen/extern/topoflow36
