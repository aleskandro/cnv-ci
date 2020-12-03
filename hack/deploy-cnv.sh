#!/usr/bin/env bash

set -e

echo "creating brew catalog source"
oc create -f - << EOF
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: brew-catalog-source
  namespace: openshift-marketplace
spec:
  sourceType: grpc
  image: $INDEX_IMAGE
  displayName: Brew Catalog Source
  publisher: grpc
EOF

oc wait pods -n "openshift-marketplace" -l olm.catalogSource="brew-catalog-source" --for condition=Ready --timeout=60s

oc create ns "${TARGET_NAMESPACE}"

echo "creating subscription"
oc create -f - << EOF
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kubevirt-hyperconverged
  namespace: "${TARGET_NAMESPACE}"
  labels:
    operators.coreos.com/kubevirt-hyperconverged.openshift-cnv: ''
spec:
  channel: stable
  installPlanApproval: Automatic
  name: kubevirt-hyperconverged
  source: brew-catalog-source
  sourceNamespace: openshift-marketplace
  startingCSV: kubevirt-hyperconverged-operator.$BUNDLE_VERSION
EOF

echo "creating operator group"
oc create -f - << EOF
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: "openshift-cnv-group"
  namespace: "${TARGET_NAMESPACE}"
spec:
  targetNamespaces:
  - "${TARGET_NAMESPACE}"
EOF

echo "waiting for operator pods to be created"
while [ "$( oc get pods -n "${TARGET_NAMESPACE}" --no-headers | wc -l )" -lt 5 ]; do
    sleep 5
done

counter=3
for i in $(seq 1 $counter); do
    echo "waiting for operator pods to be ready (try $i)"
    oc wait pods -n "${TARGET_NAMESPACE}" --all --for condition=Ready --timeout=10m && break
    sleep 5
done

echo "waiting for HyperConverged operator crd to be created"
while [ "$( oc get crd -n "${TARGET_NAMESPACE}" hyperconvergeds.hco.kubevirt.io --no-headers | wc -l )" -eq 0 ]; do
    sleep 5
done

echo "creating HyperConverged operator custom resource"
oc create -f - << EOF
apiVersion: hco.kubevirt.io/v1beta1
kind: HyperConverged
metadata:
  name: kubevirt-hyperconverged
  namespace: "${TARGET_NAMESPACE}"
spec:
  BareMetalPlatform: true
EOF

echo "waiting for HyperConverged operator to be available"
oc wait -n "${TARGET_NAMESPACE}" HyperConverged kubevirt-hyperconverged --for condition=Available --timeout=20m
