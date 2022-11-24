

#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function test() {
    /usr/local/openresty/bin/openresty -v 2>&1 | grep -q ${OPENRESTY_VERSION}
    ldd /usr/local/openresty/bin/openresty | grep -q '/usr/local/kong/lib/libssl.so*'
    ldd /usr/local/openresty/bin/openresty | grep -q '/usr/local/kong/lib/libcrypto.so*'
    /usr/local/openresty/bin/openresty -V 2>&1 | grep /tmp/pcre-${PCRE_VERSION}
    /usr/local/openresty/bin/resty -e 'print(jit.version)' | grep -q 'LuaJIT[[:space:]][[:digit:]]\+.[[:digit:]]\+.[[:digit:]]\+-[[:digit:]]\{8\}'

    ls -l /usr/local/openresty/lualib/resty/websocket/*.lua
    grep _VERSION /usr/local/openresty/lualib/resty/websocket/*.lua
    luarocks --version
}

test