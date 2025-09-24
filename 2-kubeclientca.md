# Generate and replace client CA
 
### Show details about the existing cert

```shell
# Show system:admin kubeconfig details
cat /root/kubeconfig-t51.yaml | less -S

# Original kube ca
oc -n openshift-config get cm admin-kubeconfig-client-ca -o yaml | oc neat

# login as oauth user
oc whoami
oc login -u huddlesj https://api.t51.jk308.com:6443
```

### Generate new CA

```shell
export NAME="custom"
export CA_SUBJ="/OU=openshift/CN=admin-kubeconfig-signer-custom"

# set the CA validity to 10 years
 export VALIDITY=3650

# generate the CA private key
 openssl genrsa -out ${NAME}-ca.key 4096

# Create the CA certificate
openssl req -x509 -new -nodes -key ${NAME}-ca.key -sha256 -days $VALIDITY -out ${NAME}-ca.crt -subj "${CA_SUBJ}"
```


Create temp client-ca ConfigMap

*This step is only needed for testing*

```shell
# create the client-ca ConfigMap"
oc create configmap client-ca-custom -n openshift-config --from-file=ca-bundle.crt=${NAME}-ca.crt

# patch the APIServer
oc patch apiserver cluster --type=merge -p '{"spec": {"clientCA": {"name": "client-ca-custom"}}}'
```


### Replace old CA with new one

```shell
oc create configmap admin-kubeconfig-client-ca -n openshift-config --from-file=ca-bundle.crt=${NAME}-ca.crt \
  --dry-run -o yaml | oc replace -f -
```
