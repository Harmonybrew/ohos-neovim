#!/bin/sh
set -e

# 如果存在旧的目录和文件，就清理掉
# 仅清理工作目录，不清理系统目录，因为默认用户每次使用新的容器进行构建（仓库中的构建指南是这么指导的）
rm -rf *.tar.gz \
    neovim-0.11.4 \
    gettext-0.22 \
    libiconv-1.17 \
    ncurses-6.5 \
    neovim-0.11.4-ohos-arm64

# 准备一些杂项的命令行工具
curl -L -O https://github.com/Harmonybrew/ohos-coreutils/releases/download/9.9/coreutils-9.9-ohos-arm64.tar.gz
curl -L -O https://github.com/Harmonybrew/ohos-grep/releases/download/3.12/grep-3.12-ohos-arm64.tar.gz
curl -L -O https://github.com/Harmonybrew/ohos-gawk/releases/download/5.3.2/gawk-5.3.2-ohos-arm64.tar.gz
tar -zxf coreutils-9.9-ohos-arm64.tar.gz -C /opt
tar -zxf grep-3.12-ohos-arm64.tar.gz -C /opt
tar -zxf gawk-5.3.2-ohos-arm64.tar.gz -C /opt

# 准备鸿蒙版的 llvm、make、cmake、ninja
curl -L -O https://github.com/Harmonybrew/ohos-llvm/releases/download/20251121/llvm-21.1.5-ohos-arm64.tar.gz
curl -L -O https://github.com/Harmonybrew/ohos-make/releases/download/4.4.1/make-4.4.1-ohos-arm64.tar.gz
curl -L -O https://github.com/Harmonybrew/ohos-cmake/releases/download/4.1.2/cmake-4.1.2-ohos-arm64.tar.gz
curl -L -O https://github.com/Harmonybrew/ohos-ninja/releases/download/1.13.1/ninja-1.13.1-ohos-arm64.tar.gz
tar -zxf llvm-21.1.5-ohos-arm64.tar.gz -C /opt
tar -zxf make-4.4.1-ohos-arm64.tar.gz -C /opt
tar -zxf cmake-4.1.2-ohos-arm64.tar.gz -C /opt
tar -zxf ninja-1.13.1-ohos-arm64.tar.gz -C /opt

# 设置环境变量
export PATH=/opt/coreutils-9.9-ohos-arm64/bin:$PATH
export PATH=/opt/grep-3.12-ohos-arm64/bin:$PATH
export PATH=/opt/gawk-5.3.2-ohos-arm64/bin:$PATH
export PATH=/opt/llvm-21.1.5-ohos-arm64/bin:$PATH
export PATH=/opt/make-4.4.1-ohos-arm64/bin:$PATH
export PATH=/opt/cmake-4.1.2-ohos-arm64/bin:$PATH
export PATH=/opt/ninja-1.13.1-ohos-arm64/bin:$PATH

# 编 gettext、conv、ncurses 需要这几个变量
export CC=clang
export CXX=clang++
export AR=llvm-ar
export LD=ld.lld

# 编译 gettext。要有这个库才能正常编出 neovim。
curl -L -O http://mirrors.ustc.edu.cn/gnu/gettext/gettext-0.22.tar.gz
tar -zxf gettext-0.22.tar.gz
cd gettext-0.22
./configure --prefix=/opt/gettext-0.22-ohos-arm64 --host=aarch64-linux --disable-shared 
make -j$(nproc)
make install
cd ..

# 编译 libiconv。要有这个库才能正常编出 neovim。
curl -L -O http://mirrors.ustc.edu.cn/gnu/libiconv/libiconv-1.17.tar.gz
tar -zxf libiconv-1.17.tar.gz
cd libiconv-1.17
./configure --prefix=/opt/libiconv-1.17-ohos-arm64 --host=aarch64-linux  --disable-shared
make -j$(nproc)
make install
cd ..

# 准备 neovim 源码
curl -L https://github.com/neovim/neovim/archive/refs/tags/v0.11.4.tar.gz -o neovim-0.11.4.tar.gz
tar -zxf neovim-0.11.4.tar.gz
cd neovim-0.11.4

# 将 neovim 依赖的 libuv 版本改成最新版（1.50.0 改成 1.51.0）
# libuv 1.51.0 做了鸿蒙适配，解决了 pthread_getaffinity_np 接口不存在的编译报错
sed -i 's|https://github.com/libuv/libuv/archive/v1.50.0.tar.gz|https://github.com/libuv/libuv/archive/v1.51.0.tar.gz|g' cmake.deps/deps.txt
sed -i 's|b1ec56444ee3f1e10c8bd3eed16ba47016ed0b94fe42137435aaf2e0bd574579|27e55cf7083913bfb6826ca78cde9de7647cded648d35f24163f2d31bb9f51cd|g' cmake.deps/deps.txt

# 把 ar 命令创建出来，避免编到 luajit 的时候报错
ln -s llvm-ar /opt/llvm-21.1.5-ohos-arm64/bin/ar

# 编译 neovim 的捆绑依赖项
cmake -S cmake.deps -B .deps -G Ninja \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_C_COMPILER=clang \
    -D CMAKE_AR=llvm-ar \
    -D CMAKE_LINKER=ld.lld \
    -D CMAKE_SYSTEM_NAME=Linux \
    -D CMAKE_SYSTEM_PROCESSOR=aarch64
ninja -C .deps

# 编译 neovim 本体
cmake -B build -G Ninja \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_C_COMPILER=clang \
    -D CMAKE_AR=llvm-ar \
    -D CMAKE_LINKER=ld.lld \
    -D CMAKE_SYSTEM_NAME=Linux \
    -D CMAKE_SYSTEM_PROCESSOR=aarch64 \
    -D LIBINTL_INCLUDE_DIR=/opt/gettext-0.22-ohos-arm64/include \
    -D LIBINTL_LIBRARY=/opt/gettext-0.22-ohos-arm64/lib/libintl.a \
    -D ICONV_INCLUDE_DIR=/opt/libiconv-1.17-ohos-arm64/include \
    -D ICONV_LIBRARY=/opt/libiconv-1.17-ohos-arm64/lib/libiconv.a \
    -D BUILD_SHARED_LIBS=OFF \
    -D CMAKE_INSTALL_PREFIX=/opt/neovim-0.11.4-ohos-arm64
ninja -C build install
cd ..

# 编译 ncurses，生成 terminfo 数据库，并把 terminfo 数据库复制到 neovim 的安装目录中
# 并不是所有 OpenHarmony 环境上都有 terminfo 数据库，为了让 neovim 在尽可能多的环境中可用，这里需要放一份 terminfo 数据库到 neovim 的安装目录中，随 neovim 一同发布
curl -L -O https://mirrors.ustc.edu.cn/gnu/ncurses/ncurses-6.5.tar.gz
tar -zxf ncurses-6.5.tar.gz
cd ncurses-6.5
./configure \
    --host=aarch64-linux \
    --prefix=/opt/ncurses-6.5-ohos-arm64 \
    --enable-database \
    --with-strip-program=llvm-strip
make -j$(nproc)
make install
cd ..
cp -r /opt/ncurses-6.5-ohos-arm64/share/terminfo /opt/neovim-0.11.4-ohos-arm64/share/terminfo

# 履行开源义务，把使用的开源软件的 license 全部聚合起来放到制品中
neovim_license=$(cat neovim-0.11.4/LICENSE.txt; echo)
gettext_license=$(cat gettext-0.22/COPYING; echo)
gettext_authors=$(cat gettext-0.22/AUTHORS; echo)
libiconv_license=$(cat libiconv-1.17/COPYING; echo)
libiconv_authors=$(cat libiconv-1.17/AUTHORS; echo)
ncurses_license=$(cat ncurses-6.5/COPYING; echo)
ncurses_authors=$(cat ncurses-6.5/AUTHORS; echo)
printf '%s\n' "$(cat <<EOF
This document describes the licenses of all software distributed with the
bundled application.
==========================================================================

neovim
=============
$neovim_license

gettext
=============
==license==
$gettext_license
==authors==
$gettext_authors

libiconv
=============
==license==
$libiconv_license
==authors==
$libiconv_authors

ncurses
=============
==license==
$ncurses_license
==authors==
$ncurses_authors
EOF
)" > /opt/neovim-0.11.4-ohos-arm64/licenses.txt

# 打包最终产物
cp -r /opt/neovim-0.11.4-ohos-arm64 ./
tar -zcf neovim-0.11.4-ohos-arm64.tar.gz neovim-0.11.4-ohos-arm64

# 这一步是针对手动构建场景做优化。
# 在 docker run --rm -it 的用法下，有可能文件还没落盘，容器就已经退出并被删除，从而导致压缩文件损坏。
# 使用 sync 命令强制让文件落盘，可以避免那种情况的发生。
sync
