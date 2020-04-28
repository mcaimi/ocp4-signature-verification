#!/bin/bash

function usage() { 
  echo "Syntax: $0 [-k <pubkey_filename>]"
  exit 1
}

[[ ! -d rendered ]] && mkdir rendered
[[ $# -gt 0 ]] || usage
while getopts ":k:" options; do
    case "${options}" in
      k)
        keyfile=${OPTARG}
        if [[ ! -f "${keyfile}" ]]; then
          echo "Specified keyfile does not exist (${keyfile})"
          exit 1
        else
          echo "Using Keyfile: ${keyfile}"
        fi
        ;;
      :)
        echo "Option -$OPTARG requires an argument."
        usage
        ;;
      *)
        usage
        ;;
    esac
done
shift $((OPTIND-1))

export ARC_REG=$( cat registry.access.redhat.com.yaml | base64 -w0 )
export RIO_REG=$( cat registry.redhat.io.yaml | base64 -w0 )
export NEXUS_REG=$( cat nexus-registry.apps.ocp4.sandbox595.opentlc.com.yaml | base64 -w0 )
export GPG_PUB_KEY=$( cat ${keyfile} | base64 -w0 )
export POLICY_CONFIG=$( cat policy.json | base64 -w0 )

# Worker MachineConfig manifest
echo "Rendering rendered/02-worker-rh-registry-trust.yaml..."
cat > rendered/02-worker-rh-registry-trust.yaml <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 02-worker-registry-signature-trust-settings
spec:
  config:
    ignition:
      config: {}
      security:
        tls: {}
      timeouts: {}
      version: 2.2.0
    networkd: {}
    passwd: {}
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,${ARC_REG}
          verification: {}
        filesystem: root
        mode: 420
        path: /etc/containers/registries.d/registry.access.redhat.com.yaml
      - contents:
          source: data:text/plain;charset=utf-8;base64,${RIO_REG}
          verification: {}
        filesystem: root
        mode: 420
        path: /etc/containers/registries.d/registry.redhat.io.yaml
      - contents:
          source: data:text/plain;charset=utf-8;base64,${NEXUS_REG}
          verification: {}
        filesystem: root
        mode: 420
        path: /etc/containers/registries.d/nexus-registry.apps.ocp4.sandbox595.opentlc.com.yaml
      - contents:
          source: data:text/plain;charset=utf-8;base64,${GPG_PUB_KEY}
          verification: {}
        filesystem: root
        mode: 0644
        path: /etc/pki/rpm-gpg/nexus-key.gpg
      - contents:
          source: data:text/plain;charset=utf-8;base64,${POLICY_CONFIG}
          verification: {}
        filesystem: root
        mode: 420
        path: /etc/containers/policy.json
  osImageURL: ""
EOF

# Master MachineConfig manifest
echo "Rendering rendered/02-master-rh-registry-trust.yaml..."
cat > rendered/02-master-rh-registry-trust.yaml <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: 02-master-registry-signature-trust-settings
spec:
  config:
    ignition:
      config: {}
      security:
        tls: {}
      timeouts: {}
      version: 2.2.0
    networkd: {}
    passwd: {}
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,${ARC_REG}
          verification: {}
        filesystem: root
        mode: 420
        path: /etc/containers/registries.d/registry.access.redhat.com.yaml
      - contents:
          source: data:text/plain;charset=utf-8;base64,${RIO_REG}
          verification: {}
        filesystem: root
        mode: 420
        path: /etc/containers/registries.d/registry.redhat.io.yaml
      - contents:
          source: data:text/plain;charset=utf-8;base64,${NEXUS_REG}
          verification: {}
        filesystem: root
        mode: 420
        path: /etc/containers/registries.d/nexus-registry.apps.ocp4.sandbox595.opentlc.com.yaml
      - contents:
          source: data:text/plain;charset=utf-8;base64,${GPG_PUB_KEY}
          verification: {}
        filesystem: root
        mode: 0644
        path: /etc/pki/rpm-gpg/nexus-key.gpg
      - contents:
          source: data:text/plain;charset=utf-8;base64,${POLICY_CONFIG}
          verification: {}
        filesystem: root
        mode: 420
        path: /etc/containers/policy.json
  osImageURL: ""
EOF

#