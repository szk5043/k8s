#!/bin/bash

ETCD_NAME=${1:-"etcd01"}
ETCD_IP=${2:-"127.0.0.1"}
ETCD_CLUSTER=${3:-"etcd01=http://127.0.0.1:2379"}

cat <<EOF >/opt/kubernetes/cfg/etcd
#[Member]
ETCD_NAME="${ETCD_NAME}"
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="https://${ETCD_IP}:2380"
ETCD_LISTEN_CLIENT_URLS="https://${ETCD_IP}:2379"

#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://${ETCD_IP}:2380"
ETCD_ADVERTISE_CLIENT_URLS="https://${ETCD_IP}:2379"
ETCD_INITIAL_CLUSTER="${ETCD_CLUSTER}"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF

cat <<EOF >/lib/systemd/system/flanneld.service
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
EnvironmentFile=-/opt/kubernetes/cfg/etcd
ExecStart=/opt/kubernetes/bin/etcd \\
--name=\${ETCD_NAME} \\
--data-dir=\${ETCD_DATA_DIR} \\
--listen-peer-urls=\${ETCD_LISTEN_PEER_URLS} \\
--listen-client-urls=\${ETCD_LISTEN_CLIENT_URLS},http://127.0.0.1:2379 \\
--advertise-client-urls=${ETCD_ADVERTISE_CLIENT_URLS} \\
--initial-advertise-peer-urls=\${ETCD_INITIAL_ADVERTISE_PEER_URLS} \\
--initial-cluster=\${ETCD_INITIAL_CLUSTER} \\
--initial-cluster-token=\${ETCD_INITIAL_CLUSTER_TOKEN} \\
--initial-cluster-state=new \\
--cert-file=/opt/kubernetes/ssl/server.pem \\
--key-file=/opt/kubernetes/ssl/server-key.pem \\
--peer-cert-file=/opt/kubernetes/ssl/server.pem \\
--peer-key-file=/opt/kubernetes/ssl/server-key.pem \\
--trusted-ca-file=/opt/kubernetes/ssl/ca.pem \\
--peer-trusted-ca-file=/opt/kubernetes/ssl/ca.pem
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable etcd
systemctl restart etcd