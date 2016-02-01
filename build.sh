#!/usr/bin/env bash

#set -e
#set -u

check_missing_packages() {
  local check_packages=('curl' 'pkg-config' 'make' 'git' 'cmake' 'gcc' 'autoconf' 'automake' 'yasm' 'cvs' 'flex' 'bison' 'makeinfo' 'g++' 'ed' 'hg' 'pax' 'unzip' 'patch' 'wget' 'xz')
  check_packages+=(libtoolize)

  for package in "${check_packages[@]}"; do
    type -P "$package" >/dev/null || missing_packages=("$package" "${missing_packages[@]}")
  done

  if [[ -n "${missing_packages[@]}" ]]; then
    clear
    echo "Could not find the following execs : ${missing_packages[@]}"
    echo 'Install the missing packages before running this script.'
    echo "for ubuntu: $ sudo apt-get install curl texinfo g++ bison flex cvs yasm automake libtool autoconf gcc cmake git make pkg-config zlib1g-dev mercurial unzip pax -y" 
    exit 1
  fi

  local out=`cmake --version` # like cmake version 2.8.7
  local version_have=`echo "$out" | cut -d " " -f 3`

  function version { echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'; }

  if [[ $(version $version_have)  < $(version '2.8.10') ]]; then
    echo "your cmake version is too old $version_have wanted 2.8.10"
    exit 1
  fi

  out=`yasm --version`
  yasm_version=`echo "$out" | cut -d " " -f 2` # like 1.1.0.112
  if [[ $(version $yasm_version)  < $(version '1.2.0') ]]; then
    echo "your yasm version is too old $yasm_version wanted 1.2.0"
    exit 1
  fi
}

build_ffmpeg() {
  local postpend_configure_opts="--disable-decoders --disable-encoders --enable-encoder=png --enable-encoder=apng --enable-encoder=ljpeg --enable-encoder=jpeg2000 --enable-encoder=bmp --enable-encoder=libx264 --enable-encoder=rawvideo --enable-decoder=png --enable-decoder=apng --enable-decoder=jpeg2000 --enable-decoder=bmp --enable-decoder=aac --enable-avisynth --enable-decoder=pcm_s16le --enable-decoder=pcm_f64le --enable-decoder=rawvideo --enable-encoder=mjpeg --enable-decoder=mjpeg --extra-libs=-lstdc++ --extra-libs=-lpng --enable-libvidstab"
  postpend_configure_opts="--enable-static --disable-shared $postpend_configure_opts --prefix=${OUTPUT_DIR:-$TARGET_DIR}"

  do_git_checkout $ffmpeg_git ffmpeg

  cd ffmpeg
    apply_ffmpeg_patches
    config_options="--enable-gpl --enable-libpulse --enable-libx264 --enable-version3 --enable-libmp3lame --enable-zlib --enable-libopenjpeg --enable-gnutls --enable-libfreetype  --enable-bzlib"
    config_options="$config_options --pkg-config-flags=--static --extra-version=static --extra-cflags=-I${TARGET_DIR}/include --extra-ldflags=-L${TARGET_DIR}/lib --extra-libs=-ldl --extra-libs=-ljson --extra-libs=-lrt --extra-libs=-ljson-c --extra-cflags=--static --extra-cflags=-static --extra-ldflags=-static"
    config_options="$config_options --disable-debug --disable-ffplay --disable-ffserver --disable-doc"

    config_options="$config_options $postpend_configure_opts"
    do_configure "$config_options"

    if [[ $force_ffmpeg_rebuild = "y" ]]; then
      rm -f already_ran_make*
    fi

    do_make_and_make_install
  cd ..
}

apply_ffmpeg_patches() {
  if [ -d "$FFMPEG_PATCHES_DIR" ]; then
    for f in "$FFMPEG_PATCHES_DIR/*.patch"; do
      apply_patch $f
    done
  fi
}

apply_patch() {
 local patch_file=$1
 local patch_type=$2
 if [[ -z $patch_type ]]; then
   patch_type="-p0"
 fi
 local patch_name=$(basename $patch_file)
 local patch_done_name="$patch_name.done"
 if [[ ! -e $patch_done_name ]]; then
   if [[ -f $patch_name ]]; then
     rm $patch_name || exit 1 # remove old version in case it has been since updated
   fi
   curl -4 $url -O || exit 1
   echo "applying patch $patch_name"
   patch $patch_type < "$patch_file" || exit 1
   touch $patch_done_name || exit 1
   rm -f already_ran* # if it's a new patch, reset everything too, in case it's really really really new
 else
   echo "patch $patch_name already applied"
 fi
}

build_dependencies() {
  build_gmp
  build_libnettle
  build_vidstab
  build_gnutls
  build_openjpeg
  build_zlib
  build_bzlib2
  build_x264
  build_lame
  build_json_c
  build_sndfile
  build_pulseaudio
  build_freetype
}

build_freetype() {
  download_and_unpack_file http://download.savannah.gnu.org/releases/freetype/freetype-2.5.5.tar.gz freetype-2.5.5
  cd freetype-2.5.5
    generic_configure "--with-png=no"
    do_make_and_make_install
  cd ..
}

build_json_c() {
  do_git_checkout https://github.com/json-c/json-c json-c "97ef110" # 0.11
  cd json-c
    sh autogen.sh
    generic_configure
    do_make_and_make_install
  cd ..
}

build_sndfile() {
  download_and_unpack_file http://www.mega-nerd.com/libsndfile/files/libsndfile-1.0.26.tar.gz libsndfile-1.0.26
  cd libsndfile-1.0.26
    generic_configure
    do_make_and_make_install
  cd ..
}

build_pulseaudio() {
  download_and_unpack_file http://freedesktop.org/software/pulseaudio/releases/pulseaudio-8.0.tar.gz pulseaudio-8.0
  cd pulseaudio-8.0
    apply_patch $ENV_ROOT/padsp.c-no-obsolete-macros.patch
    generic_configure "--without-caps --disable-systemd-daemon --disable-udev"
    do_make_and_make_install "-lrt"
  cd ..
}

build_gmp() {
  download_and_unpack_file https://gmplib.org/download/gmp/gmp-6.0.0a.tar.xz gmp-6.0.0
  cd gmp-6.0.0
    generic_configure
    do_make_and_make_install
  cd ..
}

build_libnettle() {
  download_and_unpack_file http://www.lysator.liu.se/~nisse/archive/nettle-2.7.1.tar.gz nettle-2.7.1
  cd nettle-2.7.1
    generic_configure "--disable-openssl"
    do_make_and_make_install
  cd ..
}

build_vidstab() {
  do_git_checkout https://github.com/georgmartius/vid.stab.git vid.stab "430b4cffeb" # 0.9.8
  cd vid.stab
    sed -i.bak "s/SHARED/STATIC/g" CMakeLists.txt # static build-ify
    do_cmake_and_install
  cd ..
}

build_gnutls() {
  download_and_unpack_file ftp://ftp.gnutls.org/gcrypt/gnutls/v3.3/gnutls-3.3.19.tar.xz gnutls-3.3.19
  cd gnutls-3.3.19
    generic_configure "--disable-cxx --disable-doc --enable-local-libopts --disable-guile"
    do_make_and_make_install
  cd ..
}

build_openjpeg() {
  download_and_unpack_file http://sourceforge.net/projects/openjpeg.mirror/files/1.5.2/openjpeg-1.5.2.tar.gz/download openjpeg-1.5.2
  cd openjpeg-1.5.2
    export CFLAGS="$CFLAGS -DOPJ_STATIC" # see https://github.com/rdp/ffmpeg-windows-build-helpers/issues/37
    generic_configure_make_install
    export CFLAGS=$original_cflags # reset it
  cd ..
}

build_zlib() {
  download_and_unpack_file http://sourceforge.net/projects/libpng/files/zlib/1.2.8/zlib-1.2.8.tar.gz/download zlib-1.2.8
  cd zlib-1.2.8
    do_configure "--static --prefix=$TARGET_DIR"
    do_make_and_make_install
  cd ..
}

build_bzlib2() {
  download_and_unpack_file http://fossies.org/linux/misc/bzip2-1.0.6.tar.gz bzip2-1.0.6
  cd bzip2-1.0.6
    do_make
    do_make_install "" "PREFIX=$TARGET_DIR"
  cd ..
}

build_x264() {
  do_git_checkout "http://repo.or.cz/r/x264.git" "x264" "origin/stable"
  cd x264
    generic_configure "--enable-strip --disable-lavf --disable-opencl"
    do_make_and_make_install
  cd ..
}

build_lame() {
  generic_download_and_install http://downloads.sourceforge.net/project/lame/lame/3.99/lame-3.99.5.tar.gz lame-3.99.5
}


# Utility functions

update_to_desired_git_branch_or_revision() {
  local to_dir="$1"
  local desired_branch="$2" # or tag or whatever...
  if [ -n "$desired_branch" ]; then
   pushd $to_dir
      echo "git checkout'ing $desired_branch"
      git checkout "$desired_branch" || exit 1 # if this fails, nuke the directory first...
      git merge "$desired_branch" || exit 1 # this would be if they want to checkout a revision number, not a branch...
   popd # in case it's a cd to ., don't want to cd to .. here...since sometimes we call it with a '.'
  fi
}

do_git_checkout() {
  local repo_url="$1"
  local to_dir="$2"
  if [[ -z $to_dir ]]; then
    echo "got empty to dir for git checkout?"
    exit 1
  fi
  local desired_branch="$3"
  if [ ! -d $to_dir ]; then
    echo "Downloading (via git clone) $to_dir from $repo_url"
    rm -rf $to_dir.tmp # just in case it was interrupted previously...
    # prevent partial checkouts by renaming it only after success
    git clone $repo_url $to_dir.tmp || exit 1
    mv $to_dir.tmp $to_dir
    echo "done downloading $to_dir"
    update_to_desired_git_branch_or_revision $to_dir $desired_branch
  else
    cd $to_dir
    old_git_version=`git rev-parse HEAD`

    if [[ -z $desired_branch ]]; then
      if [[ $git_get_latest = "y" ]]; then
        echo "Updating to latest $to_dir git version [origin/master]..."
        git fetch
        git merge origin/master || exit 1
      else
        echo "not doing git get latest pull for latest code $to_dir"
      fi
    else
      if [[ $git_get_latest = "y" ]]; then
        echo "Doing git fetch $to_dir in case it affects the desired branch [$desired_branch]"
        git fetch
        git merge $desired_branch || exit 1
      else
        echo "not doing git fetch $to_dir to see if it affected desired branch [$desired_branch]"
      fi
    fi
    update_to_desired_git_branch_or_revision "." $desired_branch
    new_git_version=`git rev-parse HEAD`
    if [[ "$old_git_version" != "$new_git_version" ]]; then
     echo "got upstream changes, forcing re-configure."
     rm -f already*
    else
     echo "this pull got no new upstream changes, not forcing re-configure... (already at $new_git_version)"
    fi 
    cd ..
  fi
}

get_small_touchfile_name() { # have to call with assignment like a=$(get_small...)
  local beginning="$1"
  local extra_stuff="$2"
  local touch_name="${beginning}_$(echo -- $extra_stuff $CFLAGS | /usr/bin/env md5sum)" # make it smaller
  touch_name=$(echo "$touch_name" | sed "s/ //g") # md5sum introduces spaces, remove them
  echo "$touch_name" # bash cruddy return system LOL
} 

do_configure() {
  local configure_options="$1"
  local configure_name="$2"
  if [[ "$configure_name" = "" ]]; then
    configure_name="./configure"
  fi
  local cur_dir2=$(pwd)
  local english_name=$(basename $cur_dir2)
  local touch_name=$(get_small_touchfile_name already_configured "$configure_options $configure_name $LDFLAGS $CFLAGS")
  if [ ! -f "$touch_name" ]; then
    make clean # just in case useful...try and cleanup stuff...possibly not useful
    # make uninstall # does weird things when run under ffmpeg src so disabled
    if [ -f bootstrap ]; then
      ./bootstrap
    fi
    if [ -f bootstrap.sh ]; then
      ./bootstrap.sh
    fi
    if [[ ! -f $configure_name ]]; then
      autoreconf -fiv # a handful of them require this  to create ./configure :|
    fi
    rm -f already_* # reset
    echo "configuring $english_name ($PWD) as $ PATH=$path_addition:$original_path $configure_name $configure_options"
    nice "$configure_name" $configure_options || exit 1
    touch -- "$touch_name"
    make clean # just in case, but sometimes useful when files change, etc.
  else
    echo "already configured $(basename $cur_dir2)" 
  fi
}

do_make() {
  local extra_make_options="$1 -j $cpu_count"
  local cur_dir2=$(pwd)
  local touch_name=$(get_small_touchfile_name already_ran_make "$extra_make_options")

  if [ ! -f $touch_name ]; then
    echo
    echo "making $cur_dir2 as $ PATH=$path_addition:\$PATH make $extra_make_options"
    echo
    if [ ! -f configure ]; then
      make clean # just in case helpful if old junk left around and this is a 're make' and wasn't cleaned at reconfigure time
    fi
    nice make $extra_make_options || exit 1
    touch $touch_name || exit 1 # only touch if the build was OK
  else
    echo "already did make $(basename "$cur_dir2")"
  fi
}

download_and_unpack_file() {
  url="$1"
  output_name=$(basename $url)
  output_dir="$2"
  if [ ! -f "$output_dir/unpacked.successfully" ]; then
    echo "downloading $url"
    if [[ -f $output_name ]]; then
      rm $output_name || exit 1
    fi

    #  From man curl
    #  -4, --ipv4
    #  If curl is capable of resolving an address to multiple IP versions (which it is if it is  IPv6-capable),
    #  this option tells curl to resolve names to IPv4 addresses only.
    #  avoid a "network unreachable" error in certain [broken Ubuntu] configurations

    curl -4 "$url" -O -L || exit 1
    tar -xf "$output_name" || unzip "$output_name" || exit 1
    touch "$output_dir/unpacked.successfully" || exit 1
    rm "$output_name" || exit 1
  fi
}

generic_configure() {
  local extra_configure_options="$1"
  do_configure "--prefix=$TARGET_DIR --disable-shared --enable-static $extra_configure_options"
}

# needs 2 parameters currently [url, name it will be unpacked to]
generic_download_and_install() {
  local url="$1"
  local english_name="$2" 
  local extra_configure_options="$3"
  download_and_unpack_file $url $english_name
  cd $english_name || exit "needs 2 parameters"
  generic_configure "$extra_configure_options"
  do_make_and_make_install
  cd ..
}

generic_configure_make_install() {
  generic_configure # no parameters, force them to break it up :)
  do_make_and_make_install
}

do_make_and_make_install() {
  local extra_make_options="$1"
  do_make "$extra_make_options"
  do_make_install "$extra_make_options"
}

do_make_install() {
  local extra_make_install_options="$1"
  local override_make_install_options="$2" # startingly, some need/use something different than just 'make install'
  if [[ -z $override_make_install_options ]]; then
    local make_install_options="install $extra_make_options"
  else
    local make_install_options="$override_make_install_options"
  fi
  local touch_name=$(get_small_touchfile_name already_ran_make_install "$make_install_options")
  if [ ! -f $touch_name ]; then
    echo "make installing $(pwd) as $ PATH=$path_addition:\$PATH make $make_install_options"
    nice make $make_install_options || exit 1
    touch $touch_name || exit 1
  fi
}

do_cmake_and_install() {
  extra_args="$1" 
  local touch_name=$(get_small_touchfile_name already_ran_cmake "$extra_args")

  if [ ! -f $touch_name ]; then
    rm -f already_* # reset so that make will run again if option just changed
    local cur_dir2=$(pwd)
    echo doing cmake in $cur_dir2 with PATH=$path_addition:\$PATH with extra_args=$extra_args like this:
    cmake –G”Unix Makefiles” . -DENABLE_STATIC_RUNTIME=1 -DCMAKE_INSTALL_PREFIX=$TARGET_DIR || exit 1
    touch $touch_name || exit 1
  fi
  do_make_and_make_install
}



# Setting intial values
cpu_count="$(grep -c processor /proc/cpuinfo 2>/dev/null)" # linux cpu count
if [ -z "$cpu_count" ]; then
  cpu_count=`sysctl -n hw.ncpu | tr -d '\n'` # OS X
  if [ -z "$cpu_count" ]; then
    echo "warning, unable to determine cpu count, defaulting to 1"
    cpu_count=1 # else default to just 1, instead of blank, which means infinite 
  fi
fi

ffmpeg_git="https://github.com/FFmpeg/FFmpeg.git"
force_ffmpeg_rebuild=y


while true; do
  case $1 in
    -h | --help ) echo "available options [with defaults]:
      --ffmpeg-git=\"https://github.com/FFmpeg/FFmpeg.git\"
      --force-ffmpeg-rebuild=y"; exit 0 ;;
    --ffmpeg-git=* ) ffmpeg_git="${1#*=}"; shift ;;
    --force-ffmpeg-rebuild=* ) force_ffmpeg_rebuild="${1#*=}"; shift ;;
    -- ) shift; break ;;
    -* ) echo "Error, unknown option: '$1'."; exit 1 ;;
    * ) break ;;
  esac
done

check_missing_packages

cd `dirname $0`

# Setup environment
ENV_ROOT=`pwd`
export ENV_ROOT
BUILD_DIR="${BUILD_DIR:-$ENV_ROOT/build}"
TARGET_DIR="${TARGET_DIR:-$ENV_ROOT/target}"
FFMPEG_PATCHES_DIR="${FFMPEG_PATCHES_DIR:-$ENV_ROOT/ffmpeg_patches}"
export LDFLAGS="-L${TARGET_DIR}/lib"
export DYLD_LIBRARY_PATH="${TARGET_DIR}/lib"
export PKG_CONFIG_PATH="$TARGET_DIR/lib/pkgconfig"
export CFLAGS="-I${TARGET_DIR}/include $LDFLAGS"
export PATH="${TARGET_DIR}/bin:${PATH}"
export original_cflags=$CFLAGS # copy CFLAGS
export PKG_CONFIG_LIBDIR= # disable pkg-config from finding [and using] normal linux system installed libs [yikes]
# Force PATH cache clearing
hash -r



echo "Building ffmpeg..."
mkdir -p $BUILD_DIR
cd $BUILD_DIR
  build_dependencies
  build_ffmpeg
cd ..
