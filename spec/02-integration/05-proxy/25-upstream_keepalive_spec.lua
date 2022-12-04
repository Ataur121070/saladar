local helpers = require "spec.helpers"
local ssl_fixtures = require "spec.fixtures.ssl"


local fixtures = {
  http_mock = {
    upstream_mtls = [[
      server {
          listen 16798 ssl;

          ssl_certificate        ../spec/fixtures/mtls_certs/example.com.crt;
          ssl_certificate_key    ../spec/fixtures/mtls_certs/example.com.key;
          ssl_client_certificate ../spec/fixtures/mtls_certs/ca.crt;
          ssl_verify_client      on;
          ssl_session_tickets    off;
          ssl_session_cache      off;
          keepalive_requests     10;

          location = / {
              echo '$ssl_client_fingerprint';
          }
      }
  ]]
  },
}


describe("#postgres upstream keepalive", function()
  local proxy_client

  local function start_kong(opts)
    local kopts = {
      log_level  = "debug",
      database   = "postgres",
      nginx_conf = "spec/fixtures/custom_nginx.template",
    }

    for k, v in pairs(opts or {}) do
      kopts[k] = v
    end

    helpers.clean_logfile()

    assert(helpers.start_kong(kopts, nil, nil, fixtures))

    proxy_client = helpers.proxy_client()
  end

  lazy_setup(function()
    local bp = helpers.get_db_utils("postgres", {
      "routes",
      "services",
      "certificates",
    })

    -- upstream TLS
    bp.routes:insert {
      hosts = { "one.com" },
      preserve_host = true,
      service = bp.services:insert {
        protocol = helpers.mock_upstream_ssl_protocol,
        host = helpers.mock_upstream_hostname,
        port = helpers.mock_upstream_ssl_port,
      },
    }

    bp.routes:insert {
      hosts = { "two.com" },
      preserve_host = true,
      service = bp.services:insert {
        protocol = helpers.mock_upstream_ssl_protocol,
        host = helpers.mock_upstream_hostname,
        port = helpers.mock_upstream_ssl_port,
      },
    }

    -- upstream mTLS
    bp.routes:insert {
      hosts = { "example.com", },
      service = bp.services:insert {
        url = "https://127.0.0.1:16798/",
        client_certificate = bp.certificates:insert {
          cert = ssl_fixtures.cert_client,
          key = ssl_fixtures.key_client,
        },
      },
    }

    bp.routes:insert {
      hosts = { "example2.com", },
      service = bp.services:insert {
        url = "https://127.0.0.1:16798/",
        client_certificate = bp.certificates:insert {
          cert = ssl_fixtures.cert_client2,
          key = ssl_fixtures.key_client2,
        },
      },
    }
  end)


  after_each(function()
    if proxy_client then
      proxy_client:close()
    end

    helpers.stop_kong(nil, true)
  end)


  it("pools by host|port|sni when upstream is https", function()
    start_kong()

    local res = assert(proxy_client:send {
      method = "GET",
      path = "/echo_sni",
      headers = {
        Host = "one.com",
      }
    })
    local body = assert.res_status(200, res)
    assert.equal("SNI=one.com", body)
    assert.errlog()
          .has
          .line([[enabled connection keepalive \(pool=[A-F0-9.:]+\|\d+\|one.com]])

    assert.errlog()
          .has.line([[keepalive get pool, name: [A-F0-9.:]+\|\d+\|one.com, cpool: [A-F0-9]+]])
    assert.errlog()
          .has.line([[keepalive create pool, name: [A-F0-9.:]+\|\d+\|one.com, size: [A-F0-9]+]])
    assert.errlog()
          .has.line([[keepalive no free connection, cpool: [A-F0-9]+]])
    assert.errlog()
          .has.line([[keepalive saving connection [A-F0-9]+, cpool: [A-F0-9]+]])

    local res = assert(proxy_client:send {
      method = "GET",
      path = "/echo_sni",
      headers = {
        Host = "two.com",
      }
    })
    local body = assert.res_status(200, res)
    assert.equal("SNI=two.com", body)
    assert.errlog()
          .has
          .line([[enabled connection keepalive \(pool=[A-F0-9.:]+\|\d+\|two.com]])

    assert.errlog()
          .has.line([[keepalive get pool, name: [A-F0-9.:]+\|\d+\|two.com, cpool: [A-F0-9]+]])
    assert.errlog()
          .has.line([[keepalive create pool, name: [A-F0-9.:]+\|\d+\|two.com, size: [A-F0-9]+]])
    assert.errlog()
          .has.line([[keepalive no free connection, cpool: [A-F0-9]+]])
    assert.errlog()
          .has.line([[keepalive saving connection [A-F0-9]+, cpool: [A-F0-9]+]])
  end)


  it("pools by host|port|sni|client_cert_id when upstream requires mTLS", function()
    start_kong()

    local res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        Host = "example.com",
      }
    })
    local fingerprint_1 = assert.res_status(200, res)
    assert.not_equal("", fingerprint_1)

    local res = assert(proxy_client:send {
      method = "GET",
      path = "/",
      headers = {
        Host = "example2.com",
      }
    })
    local fingerprint_2 = assert.res_status(200, res)
    assert.not_equal("", fingerprint_2)

    assert.not_equal(fingerprint_1, fingerprint_2)

    assert.errlog()
              .has
              .line([[enabled connection keepalive \(pool=[0-9.]+|\d+|[0-9.]+:\d+|[a-f0-9-]+]])

    assert.errlog()
          .has.line([[keepalive get pool, name: [0-9.]+|\d+|[0-9.]+:\d+|[a-f0-9-]+, cpool: [A-F0-9]+]])
    assert.errlog()
          .has.line([[keepalive create pool, name: [0-9.]+|\d+|[0-9.]+:\d+|[a-f0-9-]+, size: [A-F0-9]+]])
    assert.errlog()
          .has.line([[keepalive no free connection, cpool: [A-F0-9]+]])
    assert.errlog()
          .has.line([[keepalive saving connection [A-F0-9]+, cpool: [A-F0-9]+]])
  end)


  it("upstream_keepalive_pool_size = 0 disables connection pooling", function()
    start_kong({
      upstream_keepalive_pool_size = 0,
    })

    local res = assert(proxy_client:send {
      method = "GET",
      path = "/echo_sni",
      headers = {
        Host = "one.com",
      }
    })
    local body = assert.res_status(200, res)
    assert.equal("SNI=one.com", body)
    assert.errlog()
          .not_has
          .line("enabled connection keepalive", true)

    assert.errlog()
          .not_has.line([[keepalive get pool]], true)
    assert.errlog()
          .not_has.line([[keepalive create pool]], true)

    local res = assert(proxy_client:send {
      method = "GET",
      path = "/echo_sni",
      headers = {
        Host = "two.com",
      }
    })
    local body = assert.res_status(200, res)
    assert.equal("SNI=two.com", body)
    assert.errlog()
          .not_has
          .line("enabled connection keepalive", true)

    assert.errlog()
          .not_has.line([[keepalive get pool]], true)
    assert.errlog()
          .not_has.line([[keepalive create pool]], true)
  end)

end)
