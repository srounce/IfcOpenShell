###############################################################################
#                                                                             #
# This file is part of IfcOpenShell.                                          #
#                                                                             #
# IfcOpenShell is free software: you can redistribute it and/or modify        #
# it under the terms of the Lesser GNU General Public License as published by #
# the Free Software Foundation, either version 3.0 of the License, or         #
# (at your option) any later version.                                         #
#                                                                             #
# IfcOpenShell is distributed in the hope that it will be useful,             #
# but WITHOUT ANY WARRANTY; without even the implied warranty of              #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the                #
# Lesser GNU General Public License for more details.                         #
#                                                                             #
# You should have received a copy of the Lesser GNU General Public License    #
# along with this program. If not, see <http://www.gnu.org/licenses/>.        #
#                                                                             #
###############################################################################

###############################################################################
#                                                                             #
# This script builds IfcOpenShell and its dependencies                        #
#                                                                             #
# Prerequisites for this script to function correctly:                        #
#     * git * bzip2 * tar * c(++) compilers * yacc * autoconf                 #
#     on debian 7.8 these can be obtained with:                               #
#          $ apt-get install git bzip2 bizon autoconf gcc g++                 #
#                                                                             #
###############################################################################

set -e

readlink() {
    if hash greadlink 2>/dev/null; then
        greadlink "$@"
    else
        readlink "$@"
    fi
}

strip() {
    if hash gstrip 2>/dev/null; then
        gstrip "$@"
    else
        strip "$@"
    fi
}

PROJECT_NAME=IfcOpenShell
OCE_VERSION=0.16
PYTHON_VERSIONS=(2.7.9 3.3.6 3.4.2)
BOOST_VERSION=1.55.0
PCRE_VERSION=8.38
LIBXML_VERSION=2.9.3
CMAKE_VERSION=3.4.3
ICU_VERSION=56.1

# Helper function for coloured printing

BLACK_ON_WHITE="\033[0;30;107m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
MAGENTA="\033[35m"
function cecho {
    printf "$1$2\033[0m\n"
}

# Set defaults for missing empty environment variables

if [ -z "$IFCOS_NUM_BUILD_PROCS" ]; then
IFCOS_NUM_BUILD_PROCS=$(expr $(sysctl -n hw.ncpu 2> /dev/null || cat /proc/cpuinfo | grep processor | wc -l) + 1)
fi

if [ -z "$TARGET_ARCH" ]; then
TARGET_ARCH="$(uname -m)"
fi

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
CMAKE_DIR="$SCRIPT_DIR/../cmake/"

if [ -z "$DEPS_DIR" ]; then
DEPS_DIR="$SCRIPT_DIR/../build/$(uname)/"
[ -d $DEPS_DIR ] || mkdir -p $DEPS_DIR
DEPS_DIR=`readlink -f $DEPS_DIR`
fi

if [ -z "$BUILD_CFG" ]; then
BUILD_CFG="RelWithDebInfo"
fi

if [ -z "$BUILD_TYPE" ]; then
BUILD_TYPE=Build
fi

# Print build configuration information

cecho $BLACK_ON_WHITE "This script fetches and builds $PROJECT_NAME and its dependencies"
echo ""
cecho $GREEN "Script configuration:"

cecho $MAGENTA "* Target Architecture    = $TARGET_ARCH"
echo  " - Whether 32-bit (i686) or 64-bit (x86_64) will be built."
cecho $MAGENTA "* Dependency Directory   = $DEPS_DIR"
echo  " - The directory where $PROJECT_NAME dependencies are installed."
cecho $MAGENTA "* Build Config Type      = $BUILD_CFG"
echo  " - The used build configuration type for the dependencies."
echo  "   Defaults to RelWithDebInfo if not specified."

if [ "$BUILD_CFG" = "MinSizeRel" ]; then
cecho $RED "     WARNING: MinSizeRel build can suffer from a significant performance loss."
fi

cecho $MAGENTA "* IFCOS_NUM_BUILD_PROCS  = $IFCOS_NUM_BUILD_PROCS"
echo  " - How many compiler processes may be run in parallel."

echo ""

# Check that required tools are in PATH

for cmd in git bunzip2 tar cc c++ autoconf yacc
do
    which $cmd > /dev/null || { cecho $RED "Required tool '$cmd' not installed or not added to PATH" ; exit 1 ; }
done

which curl > /dev/null && DOWNLOAD="curl -sLO"
which wget > /dev/null && DOWNLOAD="wget -q --no-check-certificate"

if [ -z "$DOWNLOAD" ]; then
    cecho $RED "No download application found, tried: curl, wget"
    exit 1
fi

# Create log directory and file

mkdir -p $DEPS_DIR/logs
LOG_FILE=$DEPS_DIR/logs/`date +"%Y%m%d"`.log

BOOST_VERSION_UNDERSCORE=${BOOST_VERSION//./_}
ICU_VERSION_UNDERSCORE=${ICU_VERSION//./_}
CMAKE_VERSION_2=${CMAKE_VERSION:0:3}

OCE_LOCATION=https://github.com/tpaviot/oce/archive/OCE-$OCE_VERSION.tar.gz
BOOST_LOCATION=http://downloads.sourceforge.net/project/boost/boost/$BOOST_VERSION/boost_$BOOST_VERSION_UNDERSCORE.tar.bz2
OPENCOLLADA_LOCATION=https://github.com/KhronosGroup/OpenCOLLADA.git
OPENCOLLADA_COMMIT=f99d59e73e565a41715eaebc00c7664e1ee5e628

# Helper functions 

function download {
    [ -f $2 ] || $DOWNLOAD $1$2
}

function run_autoconf  {
    if [ ! -f ../configure ]; then 
        pushd . >>$LOG_FILE 2>&1
        cd ..
        ./autogen.sh >>$LOG_FILE 2>&1
        popd >>$LOG_FILE 2>&1
    fi
    ../configure $2 --prefix=$DEPS_DIR/install/$1 >>$LOG_FILE 2>&1
}

function run_cmake {
    if [ -z "$3" ]; then
        P=..
    else
        P=$3
    fi
    $DEPS_DIR/install/cmake-$CMAKE_VERSION/bin/cmake $P $2 -DCMAKE_BUILD_TYPE=$BUILD_TYPE >>$LOG_FILE 2>&1
}

function run_icu {
    PLATFORM=`uname -s`
    if [ $PLATFORM == "Darwin" ]; then
        PLATFORM=MacOSX
    fi
    ../source/runConfigureICU $PLATFORM $2 --prefix=$DEPS_DIR/install/$1 >>$LOG_FILE 2>&1
}

function git_clone {
    [ -d $2 ] || git clone --depth 1 $1 $2 >>$LOG_FILE 2>&1
    if [ ! -z "$3" ]; then
        cd $2
        if ! git fetch origin $3 && git checkout $3; then
          git fetch -v --unshallow
          git fetch origin $3
          git checkout $3
        fi
        cd ..
    fi
}

function build_dependency {
    if [ -e $DEPS_DIR/install/$1 ]; then
        echo "Found existing $1"
        return
    fi
    mkdir -p $DEPS_DIR/build/
    cd $DEPS_DIR/build/
    printf "\rFetching $1...   "
    $6 $4 $5 $7
    if [ -d $5 ]; then
        DEP_NAME=$5
    else
        DEP_NAME=`tar --exclude="*/*" -tf $5`
        [ -z $DEP_NAME ] && DEP_NAME=`tar -tf $5 2> /dev/null | head -n 1 | cut -f1 -d /`
        [ -d $DEP_NAME ] || tar -xf $5
    fi
    cd $DEP_NAME
    if [ "$2" != "bjam" ]; then
        [ -d build ] && rm -rfv build
        mkdir build
        cd build
        printf "\rConfiguring $1..."
        run_$2 $1 "$3"
        printf "\rBuilding $1...   "
        make -j$IFCOS_NUM_BUILD_PROCS >>$LOG_FILE 2>&1
        printf "\rInstalling $1... "
        make install >>$LOG_FILE 2>&1
        printf "\rInstalled $1     \n"
    else
        printf "\rConfiguring $1..."
        ./bootstrap.sh >>$LOG_FILE 2>&1
        printf "\rBuilding $1...   "
        ./b2 $3 >>$LOG_FILE 2>&1
        printf "\rInstalling $1... "
        cp -R boost $DEPS_DIR/install/boost-$BOOST_VERSION/ >>$LOG_FILE 2>&1
        printf "\rInstalled $1     \n"
    fi
}

cecho $GREEN "Collecting dependencies:"

# Set compiler flags for 32bit builds on 64bit system

if [ "$TARGET_ARCH" == "i686" ] && [ "$(uname -m)" == "x86_64" ]; then
ADDITIONAL_ARGS="-m32 -arch i386"
fi

#if [ "$(uname)" == "Darwin" ]; then
#ADDITIONAL_ARGS="-macosx_version_min 10.6 $ADDITIONAL_ARGS"
#fi

# If the linker supports GC sections, set it up to reduce binary file size
# -fPIC is required for the shared libraries to work

if man ld 2> /dev/null | grep gc-sections &> /dev/null; then
export CXXFLAGS="$CXXFLAGS -fPIC -fdata-sections -ffunction-sections -fvisibility=hidden -fvisibility-inlines-hidden $ADDITIONAL_ARGS"
export   CFLAGS="$CFLAGS   -fPIC -fdata-sections -ffunction-sections -fvisibility=hidden $ADDITIONAL_ARGS"
export  LDFLAGS="$LDFLAGS  -Wl,--gc-sections $ADDITIONAL_ARGS"
export CXXFLAGS_MINIMAL="$CXXFLAGS_MINIMAL -fPIC $ADDITIONAL_ARGS"
export   CFLAGS_MINIMAL="$CFLAGS_MINIMAL   -fPIC $ADDITIONAL_ARGS"
else
export CXXFLAGS="$CXXFLAGS -fPIC -fvisibility=hidden -fvisibility-inlines-hidden $ADDITIONAL_ARGS"
export   CFLAGS="$CFLAGS   -fPIC -fvisibility=hidden -fvisibility-inlines-hidden $ADDITIONAL_ARGS"
export  LDFLAGS="$LDFLAGS  -s -death_code $ADDITIONAL_ARGS"
export CXXFLAGS_MINIMAL="$CXXFLAGS_MINIMAL -fPIC $ADDITIONAL_ARGS"
export   CFLAGS_MINIMAL="$CFLAGS_MINIMAL   -fPIC $ADDITIONAL_ARGS"
fi

# Some dependencies need a more recent CMake version than most distros provide
build_dependency cmake-$CMAKE_VERSION autoconf "" https://cmake.org/files/v$CMAKE_VERSION_2/ cmake-$CMAKE_VERSION.tar.gz download

# Extract compiler flags from CMake to harmonize settings with other autoconf dependencies
CMAKE_FLAG_EXTRACT_DIR=ifcopenshell_cmake_test_`cat /dev/urandom | env LC_CTYPE=C tr -dc 'a-zA-Z0-9' | head -c 32`
[ -e $CMAKE_FLAG_EXTRACT_DIR ] && rm -rfv $CMAKE_FLAG_EXTRACT_DIR
mkdir $CMAKE_FLAG_EXTRACT_DIR
cd $CMAKE_FLAG_EXTRACT_DIR
BUILD_CFG_UPPER=${BUILD_CFG^^}
for FL in C CXX LD; do
    echo "
    message(\"\${CMAKE_${FL}_FLAGS_${BUILD_CFG_UPPER}}\")
    " > CMakeLists.txt
    declare ${FL}FLAGS="`$DEPS_DIR/install/cmake-$CMAKE_VERSION/bin/cmake . 2>&1 >/dev/null`"
    declare ${FL}FLAGS_MINIMAL="`$DEPS_DIR/install/cmake-$CMAKE_VERSION/bin/cmake . 2>&1 >/dev/null`"
done
cd ..
rm -rfv $CMAKE_FLAG_EXTRACT_DIR

build_dependency pcre-$PCRE_VERSION autoconf "--disable-shared" ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/ pcre-$PCRE_VERSION.tar.bz2 download

# An issue exists with swig-1.3 and python >= 3.2
# Therefore, build a recent copy from source
build_dependency swig autoconf "--with-pcre-prefix=$DEPS_DIR/install/pcre-$PCRE_VERSION" https://github.com/swig/swig.git swig git_clone rel-3.0.8

build_dependency oce-$OCE_VERSION cmake "-DOCE_DISABLE_TKSERVICE_FONT=ON -DOCE_TESTING=OFF -DOCE_BUILD_SHARED_LIB=OFF -DOCE_DISABLE_X11=ON -DOCE_VISUALISATION=OFF -DOCE_OCAF=OFF -DOCE_INSTALL_PREFIX=$DEPS_DIR/install/oce-$OCE_VERSION/" https://github.com/tpaviot/oce/archive/ OCE-$OCE_VERSION.tar.gz download
build_dependency libxml2-$LIBXML_VERSION autoconf "--without-python --disable-shared" ftp://xmlsoft.org/libxml2/ libxml2-$LIBXML_VERSION.tar.gz download
#build_dependency OpenCOLLADA cmake "
#-DLIBXML2_INCLUDE_DIR=$DEPS_DIR/install/libxml2-$LIBXML_VERSION/include/libxml2
#-DLIBXML2_LIBRARIES=$DEPS_DIR/install/libxml2-$LIBXML_VERSION/lib/libxml2.a
#-DPCRE_INCLUDE_DIR=$DEPS_DIR/install/pcre-$PCRE_VERSION/include
#-DPCRE_PCREPOSIX_LIBRARY=$DEPS_DIR/install/pcre-$PCRE_VERSION/lib/libpcreposix.a
#-DPCRE_PCRE_LIBRARY=$DEPS_DIR/install/pcre-$PCRE_VERSION/lib/libpcre.a
#-DCMAKE_INSTALL_PREFIX=$DEPS_DIR/install/OpenCOLLADA/" $OPENCOLLADA_LOCATION OpenCOLLADA git_clone $OPENCOLLADA_COMMIT

# Python should not be built with -fvisibility=hidden, from experience that introduces segfaults

OLD_CXX_FLAGS=$CXXFLAGS
OLD_C_FLAGS=$CFLAGS
OLD_LD_FLAGS=$LDFLAGS
export CXXFLAGS=$CXXFLAGS_MINIMAL
export CFLAGS=$CFLAGS_MINIMAL
export LDFLAGS=$LDFLAGS_MINIMAL
  
for PYTHON_VERSION in "${PYTHON_VERSIONS[@]}"; do
    build_dependency python-$PYTHON_VERSION autoconf "" http://www.python.org/ftp/python/$PYTHON_VERSION/ Python-$PYTHON_VERSION.tgz download
done

export CXXFLAGS=$OLD_CXX_FLAGS
export CFLAGS=$OLD_C_FLAGS
export LDFLAGS=$OLD_LD_FLAGS

if [ "$(uname)" == "Darwin" ] && [ "$1" == "32" ]; then
BOOST_ADDRESS_MODEL="toolset=darwin architecture=x86 target-os=darwin address-model=32"
fi
build_dependency boost-$BOOST_VERSION bjam "--stagedir=$DEPS_DIR/install/boost-$BOOST_VERSION --with-program_options link=static $BOOST_ADDRESS_MODEL stage" http://downloads.sourceforge.net/project/boost/boost/$BOOST_VERSION/ boost_$BOOST_VERSION_UNDERSCORE.tar.bz2 download

build_dependency icu-$ICU_VERSION icu "--enable-static --disable-shared" http://download.icu-project.org/files/icu4c/$ICU_VERSION/ icu4c-${ICU_VERSION_UNDERSCORE}-src.tgz download

cecho $GREEN "Building IfcOpenShell:"

IFCOS_DIR=$DEPS_DIR/build/ifcopenshell
[ -d $IFCOS_DIR ] && rm -rfv $IFCOS_DIR
mkdir -p $IFCOS_DIR
cd $IFCOS_DIR

mkdir -p executables
cd executables

printf "\rConfiguring executables..."

run_cmake "" "
-DCOLLADA_SUPPORT=OFF
-DBOOST_ROOT=$DEPS_DIR/install/boost-$BOOST_VERSION                        
-DOCC_INCLUDE_DIR=$DEPS_DIR/install/oce-$OCE_VERSION/include/oce           
-DOCC_LIBRARY_DIR=$DEPS_DIR/install/oce-$OCE_VERSION/lib                   
-DOPENCOLLADA_INCLUDE_DIR=$DEPS_DIR/install/OpenCOLLADA/include/opencollada
-DOPENCOLLADA_LIBRARY_DIR=$DEPS_DIR/install/OpenCOLLADA/lib/opencollada    
-DICU_INCLUDE_DIR=$DEPS_DIR/install/icu-$ICU_VERSION/include
-DICU_LIBRARY_DIR=$DEPS_DIR/install/icu-$ICU_VERSION/lib
-DPCRE_LIBRARY_DIR=$DEPS_DIR/install/pcre-$PCRE_VERSION/lib
-DBUILD_IFCPYTHON=OFF
" $CMAKE_DIR

make help
echo ""
printf "\rBuilding executables...   "

make VERBOSE=1 ifcopenshelljs npmpkg -j$IFCOS_NUM_BUILD_PROCS >>$LOG_FILE 2>&1

#strip -s IfcConvert IfcGeomServer

cd ..

#for PYTHON_VERSION in "${PYTHON_VERSIONS[@]}"; do
    
    #printf "\rConfiguring python $PYTHON_VERSION wrapper..."
    
    #mkdir -p python-$PYTHON_VERSION
    #cd python-$PYTHON_VERSION

    #PYTHON_LIBRARY=`ls    $DEPS_DIR/install/python-$PYTHON_VERSION/lib/libpython*.a`
    #PYTHON_INCLUDE=`ls -d $DEPS_DIR/install/python-$PYTHON_VERSION/include/python*`
    #PYTHON_EXECUTABLE=$DEPS_DIR/install/python-$PYTHON_VERSION/bin/python
    #export PYTHON_LIBRARY_BASENAME=`basename $PYTHON_LIBRARY`
    
    #run_cmake "" "
    #-DCOLLADA_SUPPORT=OFF
    #-DBOOST_ROOT=$DEPS_DIR/install/boost-$BOOST_VERSION                        
    #-DOCC_INCLUDE_DIR=$DEPS_DIR/install/oce-$OCE_VERSION/include/oce           
    #-DOCC_LIBRARY_DIR=$DEPS_DIR/install/oce-$OCE_VERSION/lib                   
    #-DOPENCOLLADA_INCLUDE_DIR=$DEPS_DIR/install/OpenCOLLADA/include/opencollada
    #-DOPENCOLLADA_LIBRARY_DIR=$DEPS_DIR/install/OpenCOLLADA/lib/opencollada    
    #-DICU_INCLUDE_DIR=$DEPS_DIR/install/icu-$ICU_VERSION/include
    #-DICU_LIBRARY_DIR=$DEPS_DIR/install/icu-$ICU_VERSION/lib
    #-DPYTHON_LIBRARY=$PYTHON_LIBRARY
    #-DPYTHON_EXECUTABLE=$PYTHON_EXECUTABLE
    #-DPYTHON_INCLUDE_DIR=$PYTHON_INCLUDE
    #-DSWIG_EXECUTABLE=$DEPS_DIR/install/swig/bin/swig
    #" $CMAKE_DIR
    
    ## This still needs to be tested
    ## test "$(uname)" == "Darwin" && sed -i~ "s/-o/-flat_namespace -undefined suppress -o/" ifcwrap/CMakeFiles/_ifcopenshell_wrapper.dir/link.txt
    
    #printf "\rBuilding python $PYTHON_VERSION wrapper...   "
    
    #make -j$IFCOS_NUM_BUILD_PROCS _ifcopenshell_wrapper >>$LOG_FILE 2>&1
    
    #strip -s \
        #-K PyInit__ifcopenshell_wrapper \
        #ifcwrap/_ifcopenshell_wrapper.so
        
#done

printf "\rBuilt IfcOpenShell...                        \n\n"

