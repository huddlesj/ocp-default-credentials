# Kubeadmin

Start with cluster built with ACM showing the resulting kubeadmin creds

```shell
# oc get kubeadmin secret in kube-system
# inspect kubeconfig
# login as system:admin
oc whoami 
oc whoami --show-server
oc login -u system:admin https://api.t51.jk308.com:6443
```

## Show existing cert 

```shell
oc get secrets -n kube-system kubeadmin -o yaml | oc neat
oc get secret kubeadmin -n kube-system -o jsonpath='{.data.kubeadmin}' | base64 -d; echo
```

## Delete secret to remove kubeadmin login 

```shell
oc get secrets -n kube-system
oc delete secrets kubeadmin -n kube-system
```