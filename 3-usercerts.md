
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

### login as new admin user

```shell
oc --kubeconfig /tmp/t51-kubeconfig-admin.yaml get nodes

# Add new user to cluster admins role
oc adm policy add-cluster-role-to-group cluster-admin custom-admins
oc --kubeconfig /tmp/t51-kubeconfig-admin.yaml get nodes
```

###

```shell
oc get csr admin-access -o jsonpath='{.status.certificate}'| base64 -d | openssl x509 -noout -dates
```


## Locally signed user certificate

```shell
export OPENSHIFT_API_SERVER_ENDPOINT=$(oc whoami --show-server | sed -e 's|https://||')

openssl req -nodes -newkey rsa:4096 -keyout /tmp/localsigned-admin.key -subj "/O=custom-admins/CN=localsigned-admin" -out /tmp/localsigned-admin.csr

openssl x509 -extfile <(printf "extendedKeyUsage = clientAuth") -req -in /tmp/localsigned-admin.csr -CA /tmp/custom-ca.crt -CAkey /tmp/custom-ca.key -CAcreateserial -out /tmp/localsigned-admin.crt -days 365 -sha256

oc --kubeconfig /tmp/localsigned-admin config set-credentials localsigned-admin --client-certificate=/tmp/localsigned-admin.crt --client-key=/tmp/localsigned-admin.key --embed-certs=true
oc --kubeconfig /tmp/localsigned-admin config set-cluster openshift-cluster-dev --certificate-authority=/tmp/ocp-apiserver-cert.crt --embed-certs=true --server=https://${OPENSHIFT_API_SERVER_ENDPOINT}
oc --kubeconfig /tmp/localsigned-admin config set-context openshift-dev --cluster=openshift-cluster-dev --namespace=default --user=localsigned-admin
oc --kubeconfig /tmp/localsigned-admin config use-context openshift-dev
```

## Test it out

```shell
oc --kubeconfig /tmp/localsigned-admin get nodes
```
