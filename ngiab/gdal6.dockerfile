# This works to install GDAL 3.4.3 and also installs python3.
# It only takes 97 seconds to create the Docker image.
# Resulting Docker image size is 1.3 GB (in Docker Desktop)
# Added this line to install python3:
#    RUN dnf install -y python3 python3-pip python3-devel 
# Am now able to start python3 and then import osgeo
# Notice that these are not used: gdal-devel, proj-devel
#-------------------------------------------------------------------
# Moved this line:
#    RUN dnf install -y python3 python3-pip python3-devel
# before this one
     RUN dnf install -y gdal python3-gdal && dnf clean all
# and still worked but image build time was reduced to 82 seconds.
#-------------------------------------------------------------------
# Open a terminal into Docker image to check gdal stuff:
# % docker run -it --rm --entrypoint /bin/bash 'localbuild/gdal6'
#
# [root@7ddab08130c1 lib]# gdalinfo --version
# GDAL 3.4.3, released 2022/04/22
#
# [root@7ddab08130c1 lib]# cd /usr/bin
# [root@7ddab08130c1 bin]# ls gdal*
#   gdal_contour   gdal_create   gdal_grid    gdal_rasterize   gdal_translate
#   gdal_viewshed   gdaladdo   gdalbuildvrt   gdaldem   gdalenhance
#   gdalinfo   gdallocationinfo   gdalmanage   gdalmdiminfo   gdalmdimtranslate
#   gdalsrsinfo   gdaltindex   gdaltransform   gdalwarp           
#            
# [root@7ddab08130c1 bin]# ls ogr*
#   ogr2ogr   ogrinfo   ogrlineref   ogrmerge.py   ogrtindex 
#
# [root@7ddab08130c1 bin]# cd /usr/share/gdal
# [root@7ddab08130c1 gdal]# ls
#   -> Lots of files (.gfs, .json, .csv, etc etc)
#
# [root@7ddab08130c1 gdal]# cd /usr/lib
# [root@7ddab08130c1 lib]# ls
#   -> Has python3.9 subdir, with site-packages
#   -> site-packages has osgeo and osgeo_utils
#
# [root@7ddab08130c1 lib]# cd /usr/lib64
# [root@7ddab08130c1 lib64]# ls *gdal*
# libgdal.so.30  libgdal.so.30.0.3
# gdalplugins: (empty directory)
#
# [root@7ddab08130c1 lib64]# cd /usr/include
# [root@7ddab08130c1 include]# ls
#   numpy  python3.9
#
# [root@7ddab08130c1 lib64]# cd /
# [root@7ddab08130c1 /]# find . -name *gdal*
#  -> shows man pages in:  /usr/share/man/man1/gdal*
#  -> shows bash completions in: /usr/share/bash-completion/completions/gdal*
#
# Note:  The "which" command is not installed so far,
#        so next line gives:
# [root@7ddab08130c1 /]# which python
# bash: which: command not found
#
# [root@7ddab08130c1 /] python3
# Python 3.9.21 (main, Aug 19 2025, 00:00:00) 
# [GCC 11.5.0 20240719 (Red Hat 11.5.0-5)] on linux
# >>> import osgeo   # (works)
# >>> from osgeo import gdal, ogr, osr  # works
#
# Note: ogr uses proj internally.
# >>> print(f"PROJ Major Version: {osr.GetPROJVersionMajor()}")
#  PROJ Major Version: 8
#
# GDAL also uses numpy:
# >>> import numpy
# >>> numpy.__version__
#  '1.23.5'
# >>> import pip   # (works)
# >>> pip.__version__
#  '21.3.1'
#
#=====================================================================
# Use the official Rocky Linux 9.1 base image
#----------------------------------------------
FROM rockylinux:9.1

#-------------------------------------------------------------
# Install EPEL repository for extra packages, including GDAL
# Install python3, pip, etc.
#-------------------------------------------------------------
RUN dnf install -y epel-release && dnf clean all
RUN dnf install -y python3 python3-pip python3-devel

#----------------------------------------
# Install GDAL and its Python bindings
# 'gdal' is the core library
# 'python3-gdal' provides Python access
#----------------------------------------
RUN dnf install -y gdal python3-gdal && dnf clean all

#----------------------------------
# SDP. Install python3, pip, etc.
#----------------------------------
## RUN dnf install -y python3 python3-pip python3-devel

#-----------------------------------------------------
# SDP. These apparently aren't need to install GDAL.
#-----------------------------------------------------
## RUN dinf install -y gcc gcc-c++ make \
##    gdal-devel proj-devel geos-devel

#-----------------------------
# Set up a working directory
#-----------------------------
WORKDIR /app

# (Optional) Example command to run a GDAL utility to confirm installation
# CMD ["gdalinfo", "--version"]

