# Kubeadmin

Start with cluster built with ACM showing the resulting kubeadmin creds

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