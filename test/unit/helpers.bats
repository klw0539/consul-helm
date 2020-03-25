#!/usr/bin/env bats
# This file tests the helpers in _helpers.tpl.

load _helpers

#--------------------------------------------------------------------
# consul.fullname
# These tests use test-runner.yaml to test the consul.fullname helper
# since we need an existing template that calls the consul.fullname helper.

@test "helper/consul.fullname: defaults to release-name-consul" {
  cd `chart_dir`
  local actual=$(helm template \
      -x templates/tests/test-runner.yaml \
      . | tee /dev/stderr |
      yq -r '.metadata.name' | tee /dev/stderr)
  [ "${actual}" = "release-name-consul-test" ]
}

@test "helper/consul.fullname: fullnameOverride overrides the name" {
  cd `chart_dir`
  local actual=$(helm template \
      -x templates/tests/test-runner.yaml \
      --set fullnameOverride=override \
      . | tee /dev/stderr |
      yq -r '.metadata.name' | tee /dev/stderr)
  [ "${actual}" = "override-test" ]
}

@test "helper/consul.fullname: fullnameOverride is truncated to 63 chars" {
  cd `chart_dir`
  local actual=$(helm template \
      -x templates/tests/test-runner.yaml \
      --set fullnameOverride=abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz \
      . | tee /dev/stderr |
      yq -r '.metadata.name' | tee /dev/stderr)
  [ "${actual}" = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijk-test" ]
}

@test "helper/consul.fullname: fullnameOverride has trailing '-' trimmed" {
  cd `chart_dir`
  local actual=$(helm template \
      -x templates/tests/test-runner.yaml \
      --set fullnameOverride=override- \
      . | tee /dev/stderr |
      yq -r '.metadata.name' | tee /dev/stderr)
  [ "${actual}" = "override-test" ]
}

@test "helper/consul.fullname: global.name overrides the name" {
  cd `chart_dir`
  local actual=$(helm template \
      -x templates/tests/test-runner.yaml \
      --set global.name=override \
      . | tee /dev/stderr |
      yq -r '.metadata.name' | tee /dev/stderr)
  [ "${actual}" = "override-test" ]
}

@test "helper/consul.fullname: global.name is truncated to 63 chars" {
  cd `chart_dir`
  local actual=$(helm template \
      -x templates/tests/test-runner.yaml \
      --set global.name=abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz \
      . | tee /dev/stderr |
      yq -r '.metadata.name' | tee /dev/stderr)
  [ "${actual}" = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijk-test" ]
}

@test "helper/consul.fullname: global.name has trailing '-' trimmed" {
  cd `chart_dir`
  local actual=$(helm template \
      -x templates/tests/test-runner.yaml \
      --set global.name=override- \
      . | tee /dev/stderr |
      yq -r '.metadata.name' | tee /dev/stderr)
  [ "${actual}" = "override-test" ]
}

@test "helper/consul.fullname: nameOverride is supported" {
  cd `chart_dir`
  local actual=$(helm template \
      -x templates/tests/test-runner.yaml \
      --set nameOverride=override \
      . | tee /dev/stderr |
      yq -r '.metadata.name' | tee /dev/stderr)
  [ "${actual}" = "release-name-override-test" ]
}

# This test ensures that we use {{ template "consul.fullname" }} everywhere instead of
# {{ .Release.Name }} because that's required in order to support the name
# override settings fullnameOverride and global.name. In some cases, we need to
# use .Release.Name. In those cases, add your exception to this list.
#
# If this test fails, you're likely using {{ .Release.Name }} where you should
# be using {{ template "consul.fullname" }}
@test "helper/consul.fullname: used everywhere" {
  cd `chart_dir`
  # Grep for uses of .Release.Name that aren't using it as a label.
  local actual=$(grep -r '{{ .Release.Name }}' templates/*.yaml | grep -v 'release: ' | tee /dev/stderr )
  [ "${actual}" = 'templates/server-acl-init-job.yaml:                -server-label-selector=component=server,app={{ template "consul.name" . }},release={{ .Release.Name }} \' ]
}


#--------------------------------------------------------------------
# consul.getAutoEncryptClientCA
# Similarly to consul.fullname tests, these tests use test-runner.yaml to test the
# consul.getAutoEncryptClientCA helper since we need an existing template that calls
# the consul.getAutoEncryptClientCA helper.

@test "helper/consul.getAutoEncryptClientCA: get-auto-encrypt-client-ca uses server's stateful set address by default" {
  cd `chart_dir`
  local command=$(helm template \
      -x templates/tests/test-runner.yaml  \
      --set 'global.tls.enabled=true' \
      --set 'global.tls.enableAutoEncrypt=true' \
      . | tee /dev/stderr |
      yq '.spec.initContainers[] | select(.name == "get-auto-encrypt-client-ca").command | join(" ")' | tee /dev/stderr)

  # check server address
  actual=$(echo $command | jq ' . | contains("-server-addr=release-name-consul-server")')
  [ "${actual}" = "true" ]

  # check server port
  actual=$(echo $command | jq ' . | contains("-server-port=8501")')
  [ "${actual}" = "true" ]

  # check server's CA cert
  actual=$(echo $command | jq ' . | contains("-ca-file=/consul/tls/ca/tls.crt")')
  [ "${actual}" = "true" ]
}

@test "helper/consul.getAutoEncryptClientCA: uses client.join string if externalServer.enabled is true but the address is not provided" {
  cd `chart_dir`
  local command=$(helm template \
      -x templates/tests/test-runner.yaml  \
      --set 'global.tls.enabled=true' \
      --set 'global.tls.enableAutoEncrypt=true' \
      --set 'externalServer.enabled=true' \
      --set 'client.join[0]=consul-server.com' \
      . | tee /dev/stderr |
      yq '.spec.initContainers[] | select(.name == "get-auto-encrypt-client-ca").command | join(" ")' | tee /dev/stderr)

  # check server address
  actual=$(echo $command | jq ' . | contains("-server-addr=\"consul-server.com\"")')
  [ "${actual}" = "true" ]

  # check the default server port is 443 if not provided
  actual=$(echo $command | jq ' . | contains("-server-port=443")')
  [ "${actual}" = "true" ]

  # check server's CA cert
  actual=$(echo $command | jq ' . | contains("-ca-file=/consul/tls/ca/tls.crt")')
  [ "${actual}" = "true" ]
}

@test "helper/consul.getAutoEncryptClientCA: can set the provided server address if externalServer.enabled is true" {
  cd `chart_dir`
  local command=$(helm template \
      -x templates/tests/test-runner.yaml  \
      --set 'global.tls.enabled=true' \
      --set 'global.tls.enableAutoEncrypt=true' \
      --set 'externalServer.enabled=true' \
      --set 'externalServer.https.address=consul.io' \
      . | tee /dev/stderr |
      yq '.spec.initContainers[] | select(.name == "get-auto-encrypt-client-ca").command | join(" ")' | tee /dev/stderr)

  # check server address
  actual=$(echo $command | jq ' . | contains("-server-addr=consul.io")')
  [ "${actual}" = "true" ]

  # check the default server port is 443 if not provided
  actual=$(echo $command | jq ' . | contains("-server-port=443")')
  [ "${actual}" = "true" ]

  # check server's CA cert
  actual=$(echo $command | jq ' . | contains("-ca-file=/consul/tls/ca/tls.crt")')
  [ "${actual}" = "true" ]
}

@test "helper/consul.getAutoEncryptClientCA: fails if externalServer.enabled is true but neither client.join nor externalServer.https.address are provided" {
  cd `chart_dir`
  run helm template \
      -x templates/tests/test-runner.yaml  \
      --set 'global.tls.enabled=true' \
      --set 'global.tls.enableAutoEncrypt=true' \
      --set 'externalServer.enabled=true' .
  [ "$status" -eq 1 ]
  [[ "$output" =~ "either client.join or externalServer.https.address must be set if externalServer.enabled is true" ]]
}

@test "helper/consul.getAutoEncryptClientCA: can set the provided port if externalServer.enabled is true" {
  cd `chart_dir`
  local command=$(helm template \
      -x templates/tests/test-runner.yaml  \
      --set 'global.tls.enabled=true' \
      --set 'global.tls.enableAutoEncrypt=true' \
      --set 'externalServer.enabled=true' \
      --set 'externalServer.https.address=consul.io' \
      --set 'externalServer.https.port=8501' \
      . | tee /dev/stderr |
      yq '.spec.initContainers[] | select(.name == "get-auto-encrypt-client-ca").command | join(" ")' | tee /dev/stderr)

  # check server address
  actual=$(echo $command | jq ' . | contains("-server-addr=consul.io")')
  [ "${actual}" = "true" ]

  # check the default server port is 443 if not provided
  actual=$(echo $command | jq ' . | contains("-server-port=8501")')
  [ "${actual}" = "true" ]

  # check server's CA cert
  actual=$(echo $command | jq ' . | contains("-ca-file=/consul/tls/ca/tls.crt")')
  [ "${actual}" = "true" ]
}

@test "helper/consul.getAutoEncryptClientCA: can set TLS server name if externalServer.enabled is true" {
  cd `chart_dir`
  local actual=$(helm template \
      -x templates/tests/test-runner.yaml  \
      --set 'global.tls.enabled=true' \
      --set 'global.tls.enableAutoEncrypt=true' \
      --set 'externalServer.enabled=true' \
      --set 'externalServer.https.address=consul.io' \
      --set 'externalServer.https.tlsServerName=custom-server-name' \
      . | tee /dev/stderr |
      yq '.spec.initContainers[] | select(.name == "get-auto-encrypt-client-ca").command | join(" ") | contains("-tls-server-name=custom-server-name")' | tee /dev/stderr)

  [ "${actual}" = "true" ]
}

@test "helper/consul.getAutoEncryptClientCA: doesn't provide the CA if externalServer.enabled is true and externalServer.useSystemRoots is true" {
  cd `chart_dir`
  local actual=$(helm template \
      -x templates/tests/test-runner.yaml  \
      --set 'global.tls.enabled=true' \
      --set 'global.tls.enableAutoEncrypt=true' \
      --set 'externalServer.enabled=true' \
      --set 'externalServer.https.address=consul.io' \
      --set 'externalServer.https.useSystemRoots=true' \
      . | tee /dev/stderr |
      yq '.spec.initContainers[] | select(.name == "get-auto-encrypt-client-ca").command | join(" ") | contains("-ca-file=/consul/tls/ca/tls.crt")' | tee /dev/stderr)

  [ "${actual}" = "false" ]
}

@test "helper/consul.getAutoEncryptClientCA: doesn't mount the consul-ca-cert volume if externalServer.enabled is true and externalServer.useSystemRoots is true" {
  cd `chart_dir`
  local actual=$(helm template \
      -x templates/tests/test-runner.yaml  \
      --set 'global.tls.enabled=true' \
      --set 'global.tls.enableAutoEncrypt=true' \
      --set 'externalServer.enabled=true' \
      --set 'externalServer.https.address=consul.io' \
      --set 'externalServer.https.useSystemRoots=true' \
      . | tee /dev/stderr |
      yq '.spec.initContainers[] | select(.name == "get-auto-encrypt-client-ca").volumeMounts[] | select(.name=="consul-ca-cert")' | tee /dev/stderr)

  [ "${actual}" = "" ]
}