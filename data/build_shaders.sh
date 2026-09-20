#!/usr/bin/env bash
set -euxo pipefail
cd "$(dirname "$0")"

slangc sprite.slang -target metal -entry vertexMain   -stage vertex   -o sprite.vs.metal
slangc sprite.slang -target metal -entry fragmentMain -stage fragment -o sprite.ps.metal
slangc sprite.slang -target wgsl  -entry vertexMain   -stage vertex \
                                  -entry fragmentMain -stage fragment -o sprite.wgsl