#!/usr/bin/env bash
EXCLUDES=$(awk '{ printf "--exclude %s ", $0 }' lcovreport.exclude)
bun run test:coverage:all-libs --report lcov
genhtml lcov.info --branch-coverage --output-dir coverage \
    --prefix "$(pwd)" \
    --ignore-errors corrupt,inconsistent \
    $EXCLUDES \
    --rc derive_function_end_line=0
