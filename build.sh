#!/bin/sh

set -e
set -u

jflag=
jval=2

while getopts 'j:' OPTION
do
  case $OPTION in
  j)	jflag=1
        	jval="$OPTARG"
	        ;;
  ?)	printf "Usage: %s: [-j concurrency_level] (hint: your cores + 20%%)\n" $(basename $0) >&2
		exit 2
		;;
  esac
done
shift $(($OPTIND - 1))

if [ "$jflag" ]
then
  if [ "$jval" ]
  then
    printf "Option -j specified (%d)\n" $jval
  fi
fi

cd `dirname $0`
ENV_ROOT=`pwd`
. ./env.source

rm -rf "$BUILD_DIR" "$TARGET_DIR"
mkdir -p "$BUILD_DIR" "$TARGET_DIR"

# NOTE: this is a fetchurl parameter, nothing to do with the current script
#export TARGET_DIR_DIR="$BUILD_DIR"

echo "#### FFmpeg static build, by STVS SA ####"
cd $BUILD_DIR
../fetchurl "http://www.tortall.net/projects/yasm/releases/yasm-1.3.0.tar.gz"
../fetchurl "http://zlib.net/zlib-1.2.8.tar.gz"
../fetchurl "http://www.bzip.org/1.0.6/bzip2-1.0.6.tar.gz"
../fetchurl "ftp://ftp.videolan.org/pub/x264/snapshots/last_x264.tar.bz2"
../fetchurl "http://downloads.sourceforge.net/project/lame/lame/3.99/lame-3.99.5.tar.gz"
../fetchurl "https://www.openssl.org/source/openssl-1.0.1q.tar.gz"
git clone git://git.ffmpeg.org/rtmpdump
git clone https://github.com/mintert/FFmpeg.git
../fetchurl "http://www.lysator.liu.se/~nisse/archive/nettle-2.7.1.tar.gz"
wget "ftp://ftp.gnutls.org/gcrypt/gnutls/v3.3/gnutls-3.3.19.tar.xz"
tar xf gnutls-3.3.19.tar.xz
rm -f gnutls-3.3.19.tar.xz
../fetchurl "http://downloads.sourceforge.net/project/openjpeg.mirror/1.5.2/openjpeg-1.5.2.tar.gz"
../fetchurl "https://github.com/georgmartius/vid.stab/archive/release-0.98.tar.gz"
../fetchurl "http://downloads.sourceforge.net/project/opencore-amr/vo-aacenc/vo-aacenc-0.1.3.tar.gz"


echo "*** Building vidstab ***"
cd $BUILD_DIR/vid.stab*
sed -i.bak "s/SHARED/STATIC/g" CMakeLists.txt
cmake –G”Unix Makefiles” . -DENABLE_STATIC_RUNTIME=1 -DCMAKE_INSTALL_PREFIX=$TARGET_DIR || exit 1
make -j $jval
make install


echo "*** Building vo_aacenc ***"
cd $BUILD_DIR/vo-aacenc*
./configure --prefix=$TARGET_DIR --disable-shared --enable-static
make -j $jval
make install


echo "*** Building libopenjpeg ***"
cd $BUILD_DIR/openjpeg*
export CFLAGS="$CFLAGS -DOPJ_STATIC"
./bootstrap.sh
./configure --prefix=$TARGET_DIR --disable-shared --enable-static
make -j $jval
make install
export CFLAGS=""


echo "*** Building libnettle ***"
cd $BUILD_DIR/nettle*
./configure --disable-openssl
make -j $jval
make install

echo "*** Building gnutls ***"
cd $BUILD_DIR/gnutls*
./configure --prefix=$TARGET_DIR --disable-cxx --disable-doc --enable-local-libopts --disable-guile --enable-static --disable-shared
make -j $jval
make install

echo "*** Building yasm ***"
cd $BUILD_DIR/yasm*
./configure --prefix=$TARGET_DIR
make -j $jval
make install

echo "*** Building zlib ***"
cd $BUILD_DIR/zlib*
./configure --prefix=$TARGET_DIR
make -j $jval
make install

echo "*** Building openssl ***"
cd $BUILD_DIR/openssl*
./config --prefix=$TARGET_DIR no-shared
make
make install

echo "*** Building bzip2 ***"
cd $BUILD_DIR/bzip2*
make
make install PREFIX=$TARGET_DIR

echo "*** Building x264 ***"
cd $BUILD_DIR/x264*
./configure --prefix=$TARGET_DIR --enable-static --disable-shared --disable-opencl
make -j $jval
make install

echo "*** Building lame ***"
cd $BUILD_DIR/lame*
./configure --prefix=$TARGET_DIR --enable-static --disable-shared
make -j $jval
make install

# FFMpeg
echo "*** Building FFmpeg ***"
cd $BUILD_DIR/FFmpeg*

postpend_configure_opts="--disable-decoders --disable-encoders --enable-encoder=png --enable-encoder=apng --enable-enco$
postpend_configureOpts="--enable-static --disable-shared $postpend_configure_opts"

CFLAGS="-I$TARGET_DIR/include" \
LDFLAGS="-L$TARGET_DIR/lib -lm" \
./configure \
  --extra-cflags="-I$TARGET_DIR/include -static" \
  --extra-ldflags="-L$TARGET_DIR/lib -lm -static" \
  --pkg-config-flags=--static \
  --extra-version=static \
  --disable-debug \
  --extra-cflags=--static \
  --disable-ffplay \
  --disable-ffserver \
  --disable-doc \
  --enable-gpl \
  --enable-libx264 \
  --enable-version3 \
  --enable-libmp3lame \
  --enable-zlib \
  --enable-libopenjpeg \
  --enable-gnutls \
  --enable-libfreetype \
  --enable-zlib \
  --enable-bzlib \
  --enable-gray \
  --enable-runtime-cpudetect \
  --extra-libs="-ldl" \
  $postpend_configure_opts \
  --prefix=${OUTPUT_DIR:-$TARGET_DIR}
make -j $jval && make install
