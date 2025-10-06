# Install GDAL 3.4.3 (as done in gdal6.dockerfile) and
# then try to install topoflow36 using gdal_topoflow1.dockerfile:
# % docker build --no-cache . --file gdal_tf361.dockerfile --tag \
#        localbuild/gdtf4:latest 2>&1 | tee build5.log
# Build took around 246 seconds.

#---------------------------------------------------------------------
# Open a terminal into Docker image to check gdal stuff:
# % docker run -it --rm --entrypoint /bin/bash 'localbuild/gdtf4'
#
# Now topoflow and all Python packages needed by topoflow36 are in:
#    /ngen/.venv/lib64/python3.9/site-packages
# because the "pip install" target was:
#    /ngen/.venv/lib64/python3.9/site-packages
# Note:  /ngen/.venv/lib64 is a symbolic link to /ngen/.venv/lib.
#
# However, the Python packages "osgeo" and "osgeo_utils" that are
#    needed to import gdal, ogr, and osr were installed at the
#    sytem level in:   /usr/lib64/python3.9/site-package
#    when python3-gdal was installed.
# This path was added to the environment variable PYTHONPATH so
#    that is added to sys.path.
# It was also necessary to use "requirements_no_gdal.txt" which
#    has the GDAL line commented out.
#
# Note: "import cfunits" in a Python session gives message:
#    FileNotFoundError: cfunits requires UNIDATA UDUNITS-2.
#    Can't find the 'udunits2' library.
# but this may not be an issue in a full NGIAB install.
# Everything else seems to import fine now.
#---------------------------------------------------------------------

#=====================================================================
# Use the official Rocky Linux 9.1 base image
#----------------------------------------------
FROM rockylinux:9.1

ENV TOPOFLOW_REPO=peckhams/topoflow36
ENV TOPOFLOW_BRANCH=master
ENV NGEN_REPO=peckhams/ngen
ENV NGEN_BRANCH=ngiab

#-------------------------------------------------------------
# Install EPEL repository for extra packages, including GDAL
# Install python3, pip, etc.
# Note: which is helpful for "terminal troubleshooting"
#-------------------------------------------------------------
RUN dnf install -y epel-release && dnf clean all
RUN dnf install -y python3 python3-pip python3-devel git which

#----------------------------------------
# Install GDAL and its Python bindings
# 'gdal' is the core library
# 'python3-gdal' provides Python access
#---------------------------------------------------------------
# Tried leaving off python3-gdal to see if GDAL binaries
# get installed by "pip install" with topoflow36 requirements
# but that failed. 
# But using python3-gdal here means osgeo is not found in:
#    /ngen/.venv/lib64/python3.9/site-packages
# unless we add it PYTHONPATH as done here so it gets
# appended to Python's sys.path.
#---------------------------------------------------------------
RUN dnf install -y gdal python3-gdal && dnf clean all
ENV PYTHONPATH="/usr/lib64/python3.9/site-packages:${PYTHONPATH}"

#---------------------------------------------
# SDP. These are not needed to install GDAL.
#---------------------------------------------
## RUN dinf install -y gdal-devel proj-devel geos-devel

#---------------------------------------
# SDP. Create venv and add it to PATH.
#---------------------------------------
WORKDIR /ngen
RUN pip3 install uv && uv venv
ENV PATH="/ngen/.venv/bin:${PATH}"

#-------------------------------------------------------------
# SDP. Install topoflow36 requirements with "uv pip install"
#      This doesn't work, but just "pip install" works.
#-------------------------------------------------------------
## make sure clone isn't cached if repo is updated
ADD https://api.github.com/repos/${TOPOFLOW_REPO}/git/refs/heads/${TOPOFLOW_BRANCH} /tmp/version.json
# RUN uv pip install -r https://raw.githubusercontent.com/${TOPOFLOW_REPO}/refs/heads/${TOPOFLOW_BRANCH}/requirements.txt

#-----------------------------------------------------------
# SDP. Install topoflow36 requirements with "pip install"
#        and specify a target directory for "pip install".
#      Otherwise, they are installed in various places:
#     ./usr/lib/python3.9/site-packages
#     ./usr/lib64/python3.9/site-packages
#     ./usr/local/lib/python3.9/site-packages
#     ./usr/local/lib64/python3.9/site-packages
#     ./ngen/.venv/lib/python3.9/site-packages
#-----------------------------------------------------------
# Note that "dinf install" ignores any active venv, while
# "uv pip install" seems to activate and use it.
# But using "--target" here does what we want.
#----------------------------------------------------------- 
# Perhaps should remove "requirements" line in the
#   setup.py file for topoflow36.
#-----------------------------------------------------------
RUN pip install -r https://raw.githubusercontent.com/${TOPOFLOW_REPO}/refs/heads/${TOPOFLOW_BRANCH}/requirements_no_gdal.txt \
    --target "/ngen/.venv/lib64/python3.9/site-packages"

#------------------------------------------------------
# SDP. Install NextGen from with topoflow36 submodule
#------------------------------------------------------
## make sure clone isn't cached if repo is updated
ADD https://api.github.com/repos/${NGEN_REPO}/git/refs/heads/${NGEN_BRANCH} /tmp/version.json
RUN git clone --single-branch --branch ${NGEN_BRANCH} https://github.com/${NGEN_REPO}.git && \
    cd ngen && \
    git submodule update --init --recursive --depth 1

#-----------------------------------------
# SDP. Install topoflow36 Python package
#-----------------------------------------
RUN uv pip install --no-cache-dir /ngen/ngen/extern/topoflow36 \
    --target "/ngen/.venv/lib64/python3.9/site-packages"



