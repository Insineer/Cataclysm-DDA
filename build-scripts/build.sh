#!/bin/bash

# Build script intended for use in Travis CI

set -ex

function run_tests
{
    $WINE "$@" -d yes --rng-seed time $EXTRA_TEST_OPTS
}

date +%s > build-start-time

export CCACHE_MAXSIZE=1G
if [ -n "$TEST_STAGE" ]
then
    build-scripts/lint-json.sh
    make -j 5 style-json
elif [ -n "$JUST_JSON" ]
then
    exit 0
fi

ccache --zero-stats
if [ -n "$CMAKE" ]
then
    bin_path="./"
    if [ "$RELEASE" = "1" ]
    then
        build_type=MinSizeRel
        bin_path="build/tests/"
    else
        build_type=Debug
    fi

    mkdir build
    cd build
    cmake \
        -DBACKTRACE=ON \
        -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
        -DCMAKE_BUILD_TYPE="$build_type" \
        -DTILES=${TILES:-0} \
        -DSOUND=${SOUND:-0} \
        ..
    if [ -n "$CATA_CLANG_TIDY" ]
    then
        # Run clang-tidy analysis instead of regular build & test
        # We could use CMake to create compile_commands.json, but that's super
        # slow, so use compiledb <https://github.com/nickdiego/compiledb>
        # instead.
        compiledb -n make

        cd ..
        ln -s build/compile_commands.json
        grep '"file": "' build/compile_commands.json | \
            sed "s+.*$PWD/++;s+\"$++" | shuf | \
            xargs -P 3 -n 1 ./build-scripts/clang-tidy-wrapper.sh
    else
        # Regular build
        make -j3
        cd ..
        # Run regular tests
        [ -f "${bin_path}cata_test" ] && run_tests "${bin_path}cata_test"
        [ -f "${bin_path}cata_test-tiles" ] && run_tests "${bin_path}cata_test-tiles"
    fi
else
    make -j3 RELEASE=1 CCACHE=1 BACKTRACE=1 CROSS="$CROSS_COMPILATION" LINTJSON=0
    run_tests ./tests/cata_test
    if [ -n "$MODS" ]
    then
        run_tests ./tests/cata_test $MODS
    fi
fi
ccache --show-stats
