# Note: The following error message seems to occur intermittently:
#          "all mirrors were already tried without success"
#       and can be resolved by just trying to build the image again.
#-----------------------------------------------------------------------
FROM rockylinux:9.1 AS base
ENV TROUTE_REPO=CIROH-UA/t-route
ENV TROUTE_BRANCH=ngiab
ENV TOPOFLOW_REPO=peckhams/topoflow36
ENV TOPOFLOW_BRANCH=master
ENV NGEN_REPO=peckhams/ngen
ENV NGEN_BRANCH=ngiab

#-------
# SDP
#-------
RUN dnf clean packages

# Install final dependencies to make sure ngen is build and deployed with matching versions
# Needed here for build caching
RUN echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf
RUN dnf update -y && \
    dnf install -y epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf install -y \
    vim libgfortran sqlite \
    bzip2 expat udunits2 zlib \
    mpich hdf5 netcdf netcdf-fortran netcdf-cxx netcdf-cxx4-mpich

FROM base AS build_base
# no dnf update to keep devel packages consistent with versions installed in base
RUN echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf

RUN dnf install -y epel-release && \
    dnf config-manager --set-enabled crb && \
    dnf install -y \
    sudo gcc gcc-c++ make cmake ninja-build tar git gcc-gfortran libgfortran sqlite sqlite-devel \
    python3 python3-devel python3-pip \
    expat-devel flex bison udunits2-devel zlib-devel \
    wget mpich-devel hdf5-devel netcdf-devel \
    netcdf-fortran-devel netcdf-cxx-devel lld 


FROM build_base AS boost_build
RUN wget https://archives.boost.io/release/1.79.0/source/boost_1_79_0.tar.gz
RUN tar -xzf boost_1_79_0.tar.gz
WORKDIR /boost_1_79_0
RUN ./bootstrap.sh && ./b2 && ./b2 headers
ENV BOOST_ROOT=/boost_1_79_0


FROM boost_build AS troute_prebuild
WORKDIR /ngen
# troute looks for netcdf.mod in the wrong place unless we set this
ENV FC=gfortran NETCDF=/usr/lib64/gfortran/modules/
# it also tries to use python instead of python3
RUN ln -s /usr/bin/python3 /usr/bin/python

# SDP. Note "/ngen/" or "/ngen" is okay here.
WORKDIR /ngen/
RUN pip3 install uv && uv venv
ENV PATH="/ngen/.venv/bin:${PATH}"
## make sure clone isn't cached if repo is updated
ADD https://api.github.com/repos/${TROUTE_REPO}/git/refs/heads/${TROUTE_BRANCH} /tmp/version.json
# install requirements like this so the troute clone can run in parallel with ngen download and build
RUN uv pip install -r https://raw.githubusercontent.com/${TROUTE_REPO}/refs/heads/${TROUTE_BRANCH}/requirements.txt
# this installs numpy 1.26.4 but the produced wheels install a non pinned version
#----------------------------------------------------------------------------
# SDP.  Try adding topoflow36 requirements right after t-route requirements
#       instead of in a separate build stage (see below).
#       Had to create new requirements.txt from recent package versions.
#       Can't install topoflow36 package yet, because it is a submodule
#       of the NGEN_REPO, which hasn't been installed yet.
#----------------------------------------------------------------------------
###############################################################
# TRY INSTALLING gdal-devel, etc. HERE IN troute_prebuild
# IT WILL THEN BE INCLUDED IN ngen_clone DUE TO LINE BELOW:
# FROM troute_prebuild AS ngen_clone
###############################################################
#----------------------------------------
# Install GDAL and its Python bindings
# 'gdal' is the core library
# 'python3-gdal' provides Python access
#----------------------------------------
# Note: Next 2 lines are in gdal6.dockerfile, but were done above.
#       The 3rd line installed GDAL 3.4.3 for Python 3.9
## RUN dnf install -y epel-release && dnf clean all
## RUN dnf install -y python3 python3-pip python3-devel
RUN dnf install -y gdal python3-gdal && dnf clean all
#-------------------------------------------------------------
# SDP.  Need to add this since the GDAL files are installed
#       at the system level and not in uv's venv.
#       Otherwise, "import osgeo" doesn't work.
#       Do this in the final build stage, though.
#-------------------------------------------------------------
## ENV PYTHONPATH="/usr/lib64/python3.9/site-packages:${PYTHONPATH}"

#-----------------------------------------------------
# Install system-level files needed by matplotlib
# Matplotlib can't find  "pyparsing" in final image.
# Try installing it explicitly here.
#-----------------------------------------------------
RUN dnf install -y --enablerepo=crb python3-matplotlib
RUN uv pip uninstall pyparsing
RUN uv pip install pyparsing==2.4.7

WORKDIR /tf36
### RUN pip3 install uv && uv venv
RUN uv venv .venv
ENV PATH="/tf36/.venv/bin:${PATH}"

#-------------------------------------------------------------------
# SDP.  Specify target for "pip install" & topoflow36 requirements
#       Otherwise, they are installed in various places.
#       Notice use of "requirements_ngiab2.txt" here.
#       "pip install" works but "uv pip install" fails.
#-------------------------------------------------------------------
## make sure clone isn't cached if repo is updated
ADD https://api.github.com/repos/${TOPOFLOW_REPO}/git/refs/heads/${TOPOFLOW_BRANCH} /tmp/version.json
# install requirements like this so the troute clone can run in parallel with ngen download and build
RUN pip install -r https://raw.githubusercontent.com/${TOPOFLOW_REPO}/refs/heads/${TOPOFLOW_BRANCH}/requirements_ngiab2.txt \
    --target "/tf36/.venv/lib64/python3.9/site-packages"
## --upgrade

#-----------------------------------------------------------
# RUN uv pip install -r https://raw.githubusercontent.com/${TOPOFLOW_REPO}/refs/heads/${TOPOFLOW_BRANCH}/requirements_ngiab2.txt \
#     --target "/tf36/.venv/lib64/python3.9/site-packages"

FROM troute_prebuild AS troute_build
WORKDIR /ngen/t-route
RUN git clone --depth 1 --single-branch --branch ${TROUTE_BRANCH} https://github.com/${TROUTE_REPO}.git .
# build and save a link to the repo used
RUN echo $(git remote get-url origin | sed 's/\.git$//' | awk '{print $0 "/tree/" }' | tr -d '\n' && git rev-parse HEAD) >> /tmp/troute_url
RUN git submodule update --init --depth 1
RUN uv pip install build wheel

# disable everything except the kernel builds
RUN sed -i 's/build_[a-z]*=/#&/' compiler.sh

RUN ./compiler.sh no-e

# install / build using UV because it's so much faster
# no build isolation needed because of cython namespace issues
RUN uv pip install --config-setting='--build-option=--use-cython' src/troute-network/
RUN uv build --wheel --config-setting='--build-option=--use-cython' src/troute-network/
RUN uv pip install --no-build-isolation --config-setting='--build-option=--use-cython' src/troute-routing/
RUN uv build --wheel --no-build-isolation --config-setting='--build-option=--use-cython' src/troute-routing/
RUN uv build --wheel --no-build-isolation src/troute-config/
RUN uv build --wheel --no-build-isolation src/troute-nwm/

FROM troute_prebuild AS ngen_clone
WORKDIR /ngen
## make sure clone isn't cached if repo is updated
ADD https://api.github.com/repos/${NGEN_REPO}/git/refs/heads/${NGEN_BRANCH} /tmp/version.json
RUN git clone --single-branch --branch ${NGEN_BRANCH} https://github.com/${NGEN_REPO}.git && \
    cd ngen && \
    git submodule update --init --recursive --depth 1


FROM ngen_clone AS ngen_build
ENV PATH=${PATH}:/usr/lib64/mpich/bin

WORKDIR /ngen/ngen
RUN echo $(git remote get-url origin | sed 's/\.git$//' | awk '{print $0 "/tree/" }' | tr -d '\n' && git rev-parse HEAD) >> /tmp/ngen_url

# Define common build arguments
ARG COMMON_BUILD_ARGS="-DNGEN_WITH_EXTERN_ALL=ON \
    -DNGEN_WITH_NETCDF:BOOL=ON \
    -DNGEN_WITH_BMI_C:BOOL=ON \
    -DNGEN_WITH_BMI_FORTRAN:BOOL=ON \
    -DNGEN_WITH_PYTHON:BOOL=ON \
    -DNGEN_WITH_ROUTING:BOOL=ON \
    -DNGEN_WITH_SQLITE:BOOL=ON \
    -DNGEN_WITH_UDUNITS:BOOL=ON \
    -DUDUNITS_QUIET:BOOL=ON \
    -DNGEN_WITH_TESTS:BOOL=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=. \
    -DCMAKE_CXX_FLAGS='-fuse-ld=lld'"
# lld is the linker, it's faster than the default


# Build Ngen serial
RUN cmake -G Ninja -B cmake_build_serial -S . ${COMMON_BUILD_ARGS} -DNGEN_WITH_MPI:BOOL=OFF && \
    cmake --build cmake_build_serial --target all -- -j $(nproc)

ARG MPI_BUILD_ARGS="-DNGEN_WITH_MPI:BOOL=ON \
    -DNetCDF_ROOT=/usr/lib64/mpich \
    -DCMAKE_PREFIX_PATH=/usr/lib64/mpich \
    -DCMAKE_LIBRARY_PATH=/usr/lib64/mpich/lib"
# the two in the command below can't be here because the $() isn't evaluated properly


# Install the mpi enabled netcdf library and build Ngen parallel with it
RUN dnf install -y netcdf-cxx4-mpich-devel
RUN cmake -G Ninja -B cmake_build_parallel -S . ${COMMON_BUILD_ARGS} ${MPI_BUILD_ARGS} \
    -DNetCDF_CXX_INCLUDE_DIR=/usr/include/mpich-$(arch) \
    -DNetCDF_INCLUDE_DIR=/usr/include/mpich-$(arch) && \
    cmake --build cmake_build_parallel --target all -- -j $(nproc)


FROM ngen_build AS restructure_files
# Setup final directories and permissions
RUN mkdir -p /dmod/datasets /dmod/datasets/static /dmod/shared_libs /dmod/bin /dmod/utils/ && \
    shopt -s globstar && \
    cp -a ./extern/**/cmake_build/*.so* /dmod/shared_libs/. || true && \
    cp -a ./extern/noah-owp-modular/**/*.TBL /dmod/datasets/static && \
    cp -a ./cmake_build_parallel/ngen /dmod/bin/ngen-parallel || true && \
    cp -a ./cmake_build_serial/ngen /dmod/bin/ngen-serial || true && \
    cp -a ./cmake_build_parallel/partitionGenerator /dmod/bin/partitionGenerator || true && \
    cp -ar ./utilities/* /dmod/utils/ && \
    cd /dmod/bin && \
    (stat ngen-parallel && ln -s ngen-parallel ngen) || (stat ngen-serial && ln -s ngen-serial ngen)


FROM restructure_files AS dev

COPY  HelloNGEN.sh /ngen/HelloNGEN.sh
# Set up library path
RUN echo "/dmod/shared_libs/" >> /etc/ld.so.conf.d/ngen.conf && ldconfig -v
# Add mpirun to path
ENV PATH=${PATH}:/usr/lib64/mpich/bin
# Set permissions
RUN chmod a+x /dmod/bin/* /ngen/HelloNGEN.sh
RUN mv /ngen/ngen /ngen/ngen_src
WORKDIR /ngen
ENTRYPOINT ["./HelloNGEN.sh"]

FROM build_base AS lstm_weights
RUN git clone --depth=1 --branch example_weights https://github.com/ciroh-ua/lstm.git /lstm_weights
# replace the relative path with the absolute path in the model config files
RUN shopt -s globstar
RUN sed -i 's|\.\.|/ngen/ngen/extern/lstm|g' /lstm_weights/trained_neuralhydrology_models/**/config.yml

#-----------------------------------------------------------
# SDP. New "build stage" to install TopoFlow requirements?
# See ngiab2.dockerfile
#-----------------------------------------------------------
# FROM ngen_clone AS topoflow_build


#--------------------------------------
# SDP.  This is the final build stage
#--------------------------------------
FROM base AS final

WORKDIR /ngen

# Copy necessary files from build stages
COPY  HelloNGEN.sh /ngen/HelloNGEN.sh
COPY --from=restructure_files /dmod /dmod
COPY --from=troute_build /ngen/t-route/src/troute-*/dist/*.whl /tmp/

RUN ln -s /dmod/bin/ngen /usr/local/bin/ngen

ENV UV_INSTALL_DIR=/root/.cargo/bin
ENV UV_COMPILE_BYTECODE=1

RUN curl -LsSf https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:${PATH}"
RUN uv self update && uv venv && \
    uv pip install --no-cache-dir /tmp/*.whl netCDF4==1.6.3
# Clean up some stuff, this doesn't make the image any smaller
RUN rm -rf /tmp/*.whl
# DONT ADD THE VENV TO THE PATH YET

# Set up library path
RUN echo "/dmod/shared_libs/" >> /etc/ld.so.conf.d/ngen.conf && ldconfig -v

# Add mpirun to path
ENV PATH=${PATH}:/usr/lib64/mpich/bin
RUN chmod a+x /dmod/bin/* /ngen/HelloNGEN.sh

# Only here after everything else is done will the ngen binary work and provide --info
#                                                             This mess is parsing the version number
# RUN uv pip install numpy==$(/dmod/bin/ngen --info | grep -e 'NumPy Version: ' | cut -d ':' -f 2 | uniq | xargs)
#--------------------------------------------------------------------
# SDP.  Previous line seems to install python 1.26.4 (config/build)
#       that was installed with t-route, which conflicts with the
#       "runtime" version 1.23.5 (GDAL).
#       So try installing version 1.23.5 here instead.
#       Try:  ngen --info in terminal to docker image 
#--------------------------------------------------------------------
RUN uv pip install numpy==1.23.5
## RUN uv pip install numpy==1.26.4


# now that the only version of numpy is the one that NGen expects,
# we can add the venv to the path so ngen can find it
# Moved this further down. ################################
## ENV PATH="/ngen/.venv/bin:${PATH}"

# Install lstm - the extra index url installs cpu-only pytorch which is ~6gb smaller
COPY --from=ngen_clone /ngen/ngen/extern/lstm/lstm /ngen/ngen/extern/lstm
RUN uv pip install --no-cache-dir /ngen/ngen/extern/lstm --extra-index-url https://download.pytorch.org/whl/cpu


#---------------------------------------------------------
# SDP.  Copy everything needed by GDAL from ngen_clone
#---------------------------------------------------------
## COPY --from=ngen_clone /usr/lib/libgdal* /usr/lib/
#------------------------------------------------------------
# The next 4 COPY commands aren't getting everything,
# but the 5th & 6th COPY commands may be getting too much.
#------------------------------------------------------------
# Some GDAL binaries in /usr/bin don't match gdal* or ogr*:
# 8211createfromxml, 8211dump, 8211view (for 8211 rasters)
# gnmanalyse, gnmmanage, nearblack, s57dump
#------------------------------------------------------------
#COPY --from=ngen_clone /usr/lib64/libgdal* /usr/lib64/
#COPY --from=ngen_clone /usr/lib64/python3.9/site-packages/osgeo \
#    /usr/lib64/python3.9/site-packages/osgeo
#COPY --from=ngen_clone /usr/lib64/python3.9/site-packages/osgeo_utils \
#   /usr/lib64/python3.9/site-packages/osgeo_utils
#COPY --from=ngen_clone /usr/lib64/ogdi /usr/lib64/ogdi

COPY --from=ngen_clone /usr/lib64 /usr/lib64
COPY --from=ngen_clone /usr/bin /usr/bin
## COPY --from=ngen_clone /usr/bin/gdal* /usr/bin
## COPY --from=ngen_clone /usr/bin/ogr* /usr/bin
COPY --from=ngen_clone /usr/share/gdal /usr/share/gdal
COPY --from=ngen_clone /usr/share/proj /usr/share/proj
##### COPY --from=ngen_clone /usr/include/udunits2 /usr/include/udunits2

#------------------------------------------------------------
# SDP. These may be needed to find pyparsing for matplotlib
#------------------------------------------------------------
# COPY --from=ngen_clone /usr/local/lib /usr/local/lib
# COPY --from=ngen_clone /usr/local/lib64 /usr/local/lib64

#--------------------------------------------------------------
# SDP.  Next line generates this error message: 
# failed to compute cache key: "/usr/include/gdal" not found
# The preceding lines seemed to work, though.
#--------------------------------------------------------------
## COPY --from=ngen_clone /usr/include/gdal /usr/include/gdal

#-----------------------------------------------------------
# SDP.  Install topoflow36 package here.
#       Emulate COPY & RUN commands above to install LSTM.
#       Install after venv added to PATH.
#-----------------------------------------------------------
COPY --from=ngen_clone /ngen/ngen/extern/topoflow36 /ngen/ngen/extern/topoflow36
RUN uv pip install --no-cache-dir /ngen/ngen/extern/topoflow36 \
    --target "/tf36/.venv/lib64/python3.9/site-packages"
## --upgrade

#-------------------------------------------------------------
# SDP.  Need to add to PYTHONPATH since the GDAL files are
#       installed at the system level and not in uv's venv.
#       Otherwise, "import osgeo" doesn't work.
#       Do this in the final build stage, though.
#-------------------------------------------------------------
ENV PATH="/ngen/.venv/bin:${PATH}"
ENV PATH="/tf36/.venv/bin:${PATH}"
ENV PYTHONPATH="/tf36/.venv/lib64/python3.9/site-packages:${PYTHONPATH}"
ENV PYTHONPATH="/usr/lib64/python3.9/site-packages:${PYTHONPATH}"
ENV MPLBACKEND=Agg

# Replace the noaa-owp example weights with jmframes
RUN rm -rf /ngen/ngen/extern/lstm/trained_neuralhydrology_models
COPY --from=lstm_weights /lstm_weights/trained_neuralhydrology_models /ngen/ngen/extern/lstm/trained_neuralhydrology_models

## add some metadata to the image
COPY --from=troute_build /tmp/troute_url /ngen/troute_url
COPY --from=ngen_build /tmp/ngen_url /ngen/ngen_url

RUN echo "export PS1='\u\[\033[01;32m\]@ngiab_dev\[\033[00m\]:\[\033[01;35m\]\W\[\033[00m\]\$ '" >> ~/.bashrc

ENTRYPOINT ["./HelloNGEN.sh"]
