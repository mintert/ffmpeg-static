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
../fetchurl "http://downloads.sourceforge.net/project/libpng/libpng15/1.5.25/libpng-1.5.25.tar.gz"
../fetchurl "http://downloads.xiph.org/releases/ogg/libogg-1.3.2.tar.gz"
../fetchurl "http://downloads.xiph.org/releases/vorbis/libvorbis-1.3.5.tar.gz"
../fetchurl "http://downloads.xiph.org/releases/theora/libtheora-1.1.1.tar.bz2"
../fetchurl "http://storage.googleapis.com/downloads.webmproject.org/releases/webm/libvpx-1.5.0.tar.bz2"
../fetchurl "http://downloads.sourceforge.net/project/faac/faac-src/faac-1.28/faac-1.28.tar.bz2"
../fetchurl "ftp://ftp.videolan.org/pub/x264/snapshots/last_x264.tar.bz2"
../fetchurl "http://downloads.xvid.org/downloads/xvidcore-1.3.4.tar.gz"
../fetchurl "http://downloads.sourceforge.net/project/lame/lame/3.99/lame-3.99.5.tar.gz"
../fetchurl "http://downloads.xiph.org/releases/opus/opus-1.1.1.tar.gz"
../fetchurl "https://www.openssl.org/source/openssl-1.0.1q.tar.gz"
git clone git://git.ffmpeg.org/rtmpdump
git clone git://source.ffmpeg.org/ffmpeg.git

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

echo "*** Building librtmp ***"
cd $BUILD_DIR/rtmp*

# patch rtmpdump makefile to include -ldl
# reference :  http://pcloadletter.co.uk/2011/12/30/compiling-ffmpeg-0-9-with-librtmp/
sed -i.bak -e '/^LIB_OPENSSL\=/s/lcrypto/lcrypto \-ldl/' Makefile

make SYS=posix -j $jval SHARED= INC=-I$TARGET_DIR/include LDFLAGS=-L$TARGET_DIR/lib
make install prefix=$TARGET_DIR SHARED= 

echo "*** Building bzip2 ***"
cd $BUILD_DIR/bzip2*
make
make install PREFIX=$TARGET_DIR

echo "*** Building libpng ***"
cd $BUILD_DIR/libpng*
./configure --prefix=$TARGET_DIR --enable-static --disable-shared
make -j $jval
make install

# Ogg before vorbis
echo "*** Building libogg ***"
cd $BUILD_DIR/libogg*
./configure --prefix=$TARGET_DIR --enable-static --disable-shared
make -j $jval
make install

# Vorbis before theora
echo "*** Building libvorbis ***"
cd $BUILD_DIR/libvorbis*
./configure --prefix=$TARGET_DIR --enable-static --disable-shared
make -j $jval
make install

echo "*** Building libtheora ***"
cd $BUILD_DIR/libtheora*
./configure --prefix=$TARGET_DIR --enable-static --disable-shared
make -j $jval
make install

echo "*** Building livpx ***"
cd $BUILD_DIR/libvpx*
./configure --prefix=$TARGET_DIR --disable-shared
make -j $jval
make install

echo "*** Building faac ***"
cd $BUILD_DIR/faac*
./configure --prefix=$TARGET_DIR --enable-static --disable-shared
# FIXME: gcc incompatibility, does not work with log()

sed -i -e "s|^char \*strcasestr.*|//\0|" common/mp4v2/mpeg4ip.h
make -j $jval
make install

echo "*** Building x264 ***"
cd $BUILD_DIR/x264*
./configure --prefix=$TARGET_DIR --enable-static --disable-shared --disable-opencl
make -j $jval
make install

echo "*** Building xvidcore ***"
cd "$BUILD_DIR/xvidcore/build/generic"
./configure --prefix=$TARGET_DIR --enable-static --disable-shared
make -j $jval
make install
#rm $TARGET_DIR/lib/libxvidcore.so.*

echo "*** Building lame ***"
cd $BUILD_DIR/lame*
./configure --prefix=$TARGET_DIR --enable-static --disable-shared
make -j $jval
make install

echo "*** Building opus ***"
cd $BUILD_DIR/opus*
./configure --prefix=$TARGET_DIR --enable-static --disable-shared
make -j $jval
make install

# FIXME: only OS-specific
rm -f "$TARGET_DIR/lib/*.dylib"
rm -f "$TARGET_DIR/lib/*.so"

# FFMpeg
echo "*** Building FFmpeg ***"
cd $BUILD_DIR/ffmpeg*

# comment out the "require_pkg_config librtmp ..." line
# this line assumes you have installed librtmp to your /usr/lib64 
# but here i want a "static" build
# sed -i.bak '/enabled librtmp/s/^/# /' configure

CFLAGS="-I$TARGET_DIR/include" LDFLAGS="-L$TARGET_DIR/lib -lm" ./configure --prefix=${OUTPUT_DIR:-$TARGET_DIR} --extra-cflags="-I$TARGET_DIR/include -static" --extra-ldflags="-L$TARGET_DIR/lib -lm -static" --extra-version=static --disable-debug --disable-shared --enable-static --extra-cflags=--static --disable-ffplay --disable-ffserver --disable-doc --enable-gpl --enable-pthreads --enable-postproc --enable-gray --enable-runtime-cpudetect --enable-libfaac --enable-libmp3lame --enable-libopus --enable-libtheora --enable-libvorbis --enable-libx264 --enable-libxvid --enable-bzlib --enable-zlib --enable-nonfree --enable-version3 --enable-libvpx --disable-devices --enable-librtmp  --extra-libs="-ldl"
make -j $jval && make install
