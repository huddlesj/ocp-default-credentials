
## Create User CA and send it to Openshift to be signed

```shell
# create user cert
openssl req -nodes -newkey rsa:4096 -keyout ./admin.key -subj "/O=custom-admins/CN=system:admin" -out ./admin.csr

# create cert request
cat << EOF | oc create -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: admin-access
spec:
  expirationSeconds: 31536000
  signerName: kubernetes.io/kube-apiserver-client
  groups:
  - system:authenticated
  request: $(cat ./admin.csr | base64 -w0)
  usages:
  - client auth
EOF

# approve cert request
oc adm certificate approve admin-access

### get approved cert
oc get csr admin-access -o jsonpath='{.status.certificate}' | base64 -d > ./admin.crt
```

### Setup kubeconfig

```shell
# get api cert 
export OPENSHIFT_API_SERVER_ENDPOINT=$(oc whoami --show-server | sed -e 's|https://||')
openssl s_client -showcerts -connect ${OPENSHIFT_API_SERVER_ENDPOINT} </dev/null 2>/dev/null|openssl x509 -outform PEM > ./ocp-apiserver-cert.crt

# generate kubeconfig 
oc --kubeconfig /tmp/t51-kubeconfig-admin.yaml config set-credentials system:admin --client-certificate=./admin.crt --client-key=./admin.key --embed-certs=true
oc --kubeconfig /tmp/t51-kubeconfig-admin.yaml config set-cluster openshift-cluster-dev --certificate-authority=./ocp-apiserver-cert.crt --embed-certs=true --server=https://${OPENSHIFT_API_SERVER_ENDPOINT}
oc --kubeconfig /tmp/t51-kubeconfig-admin.yaml config set-context openshift-dev --cluster=openshift-cluster-dev --namespace=default --user=system:admin
oc --kubeconfig /tmp/t51-kubeconfig-admin.yaml config use-context openshift-dev
```

# login as new admin user

```shell
oc --kubeconfig /tmp/t51-kubeconfig-admin.yaml login -u system:admin
oc get nodes 
```

```shell
# get api cert 
export OPENSHIFT_API_SERVER_ENDPOINT=$(oc whoami --show-server | sed -e 's|https://||')
openssl s_client -showcerts -connect ${OPENSHIFT_API_SERVER_ENDPOINT} </dev/null 2>/dev/null|openssl x509 -outform PEM > ./ocp-apiserver-cert.crt

# generate kubeconfig 
oc --kubeconfig /tmp/admin.kubeconfig config set-credentials system:admin --client-certificate=./system:admin.crt --client-key=./system:admin.key --embed-certs=true
oc --kubeconfig /tmp/admin.kubeconfig config set-cluster openshift-cluster-dev --certificate-authority=./ocp-apiserver-cert.crt --embed-certs=true --server=https://${OPENSHIFT_API_SERVER_ENDPOINT}
oc --kubeconfig /tmp/admin.kubeconfig config set-context openshift-dev --cluster=openshift-cluster-dev --namespace=default --user=admin
oc --kubeconfig /tmp/admin.kubeconfig config use-context openshift-dev

# Add new user to cluster admins role
oc adm policy add-cluster-role-to-group cluster-admin custom-admins

export CLUSTER_NAME=mycluster
export KUBE_API=$(oc whoami --show-server)  # e.g. https://api.t51.jk308.com:6443
```

# New

```shell
export OPENSHIFT_API_SERVER_ENDPOINT=$(oc whoami --show-server | sed -e 's|https://||')

openssl req -nodes -newkey rsa:4096 -keyout /tmp/john.key -subj "/O=custom-admins/CN=john" -out /tmp/john.csr

openssl x509 -extfile <(printf "extendedKeyUsage = clientAuth") -req -in /tmp/john.csr -CA /root/tmp/kubeadmin/custom-ca.crt -CAkey /root/tmp/kubeadmin/custom-ca.key -CAcreateserial -out /tmp/john.crt -days 365 -sha256

oc --kubeconfig /tmp/john config set-credentials john --client-certificate=/tmp/john.crt --client-key=/tmp/john.key --embed-certs=true
oc --kubeconfig /tmp/john config set-cluster openshift-cluster-dev --certificate-authority=/root/tmp/kubeadmin/ocp-apiserver-cert.crt --embed-certs=true --server=https://${OPENSHIFT_API_SERVER_ENDPOINT}
oc --kubeconfig /tmp/john config set-context openshift-dev --cluster=openshift-cluster-dev --namespace=default --user=john
oc --kubeconfig /tmp/john config use-context openshift-dev
```
