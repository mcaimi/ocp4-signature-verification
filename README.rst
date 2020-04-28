OPENSHIFT 4 IMAGE SIGNATURE VERIFICATION
========================================

With OpenShift 4, container image signatures can be verified at deploy time by configuring CRI-O to use GPG keys.
This repo contains a walkthrough/demo of this feature and a simple solution to signature storage. This demo will use:

- Openshift 4 as the container platform
- An external Sonatype Nexus instance to simulate a private docker registry
- GPG to sign/verify container images
- NGINX + LuaJIT as the application framework (OpenResty)

PREREQUISITES
-------------

1) Install Openshift 4.x

2) Generate a GPG Key that will be used to sign images

.. code:: bash

    # gpg --quick-gen-key demo@redhat.com
    # gpg -k
    [...]
    pub   rsa2048 2020-04-24 [SC] [expires: 2022-04-24]
      01164344435F9572F7B8B06D48790DBE02151245
    uid           [ultimate] demo@redhat.com
    sub   rsa2048 2020-04-24 [E]
    [...]

3) Export the public key to file

.. code:: bash

    # gpg --armor --export demo@redhat.com > nexus-key.gpg

4) Deploy an instance of Nexus

.. code:: bash

    # oc create -f components/nexus-deployment.yaml

5) On the nexus web interface, create a new Hosted Docker repository.

CONFIGURE OPENSHIFT NODES
-------------------------

This demo uses a local instance of Nexus as an external image repository. We want images coming from that repo to be signed and verified.
Worker (and masters optionally) nodes in an OCP cluster need to be made aware of a new repo that requires signature verification.

1) Configure a policy.json file with all repositories that need signature verification. Specify the public key path every repo section:

.. code:: json

    {
      "default": [
        {
          "type": "insecureAcceptAnything"
        }
      ],
      "transports": {
        "docker": {
          "registry.access.redhat.com": [
            {
              "type": "signedBy",
              "keyType": "GPGKeys",
              "keyPath": "/etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release"
            }
          ],
          "registry.redhat.io": [
            {
              "type": "signedBy",
              "keyType": "GPGKeys",
              "keyPath": "/etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release"
            }
          ],
          "nexus-registry.apps.ocp4.sandbox595.opentlc.com": [
            {
              "type": "signedBy",
              "keyType": "GPGKeys",
              "keyPath": "/etc/pki/rpm-gpg/nexus-key.gpg"
            }
          ]
        },
        "docker-daemon": {
          "": [
            {
              "type": "insecureAcceptAnything"
            }
          ]
        }
      }
    }

2) Create a configuration file for every repo and fill in the address of the HTTP server that will host the signatures:

.. code:: yaml

    docker:
        nexus-registry.apps.ocp4.sandbox595.opentlc.com:
            sigstore: https://signature.apps.ocp4.sandbox595.opentlc.com/sigstore

Create a file like this for all repositories mentioned in the policy.json file modified at step 1

3) Generate the MachineConfig manifests with the provided script (under machineconfig/)

.. code:: bash

  # ./gen-machineconfig.sh -k /path/to/nexus-key.gpg

This will create two MachineConfig manifest files under the ./rendered/ folder:

.. code:: bash

  # oc create -f 02-master-rh-registry-trust.yaml
  # oc create -f 02-worker-rh-registry-trust.yaml

After a while both configuration will be applied to the cluster.

.. code:: bash

  # oc get machineconfigpool
  NAME      CONFIG                                             UPDATED   UPDATING   DEGRADED   MACHINECOUNT   READYMACHINECOUNT   UPDATEDMACHINECOUNT   DEGRADEDMACHINECOUNT   AGE
  master    rendered-master-36f5d702f485cde72df754013e17937f   True      False      False      3              3                   3                     0                      4d5h
  worker    rendered-worker-ec7bab1743d5d2a88bed9cf1280ff9f1   True      False      False      3              3                   3                     0                      4d5h
