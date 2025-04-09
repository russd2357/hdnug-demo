#!/bin/bash

suffix="$(
    tr -dc a-z0-9 </dev/urandom | head -c 6
    echo | tr '[:upper:]' '[:lower:]')"

local_name="houdemo"
tags="owner=houdemo"
location="westus3"
resource_group_name="rg-${local_name}-${suffix}"
node_count=3
app_ns="houdemo"

# Create a resource group
az group create \
--name $resource_group_name \
--location $location

if [ $? -ne 0 ]; then
    echo "Failed to create resource group"
    exit 1
fi
echo "Resource group $resource_group_name created successfully"

# Create an Azure Container Registry
acr_name="acr${local_name}${suffix}"
acr_id=$(az acr create \
--resource-group $resource_group_name \
--name  $acr_name \
--sku Basic \
--query "id" \
--output tsv)

if [ $? -ne 0 ]; then
    echo "Failed to create ACR"
    exit 1
fi
echo "ACR $acr_name created successfully"

# Create a user-assigned managed identity
uami_json=$(az identity create \
--resource-group $resource_group_name \
--name "uami-${local_name}-$suffix" \
--output json)

if [ $? -ne 0 ]; then
    echo "Failed to create user-assigned managed identity"
    exit 1
fi
echo "User-assigned managed identity created successfully"

uami_resource_id=$(echo $uami_json | jq -r '.id')
uami_object_id=$(echo $uami_json | jq -r '.principalId')
uami_client_id=$(echo $uami_json | jq -r '.clientId')

# Assign the AcrPull role to the managed identity
az role assignment create \
--assignee-object-id $uami_object_id \
--assignee-principal-type ServicePrincipal \
--role AcrPull \
--scope $acr_id
--output none

if [ $? -ne 0 ]; then
    echo "Failed to assign AcrPull role to the managed identity"
    exit 1
fi
echo "AcrPull role assigned to the managed identity successfully"

# Get the latest Kubernetes version
k8sversion=$(az aks get-versions \
--location $location \
--query "values[0].{version: version}" \
--output tsv)

# Create an AKS cluster
aks_name="aks-${local_name}-${suffix}"
az aks create \
--name "$aks_name" \
--tags "$tag" \
--resource-group "$resource_group_name" \
--generate-ssh-keys \
--node-resource-group "MC_${aks_name}_$(date '+%Y%m%d%H%M%S')" \
--enable-keda \
--enable-managed-identity \
--enable-workload-identity \
--assign-identity ${uami_resource_id} \
--node-provisioning-mode Auto \
--network-plugin azure \
--network-plugin-mode overlay \
--network-dataplane cilium \
--node-count "${node_count}" \
--nodepool-name systempool \
--enable-oidc-issuer \
--attach-acr ${acr_name} \
--enable-addons monitoring \
--kubernetes-version "$k8sversion" \

if [ $? -ne 0 ]; then
    echo "Failed to create AKS cluster"
    exit 1
fi
echo "AKS cluster $aks_name being provisioned"

while true; do
    echo -e -n "Waiting for AKS cluster to be provisioned..."
    provisionState=$(az aks show \
    --resource-group ${resource_group_name} \
    --name ${aks_name} \
    --only-show-errors \
    --query 'provisioningState' \
    -o tsv | tr -d '\r')
    if [ "$provisionState" == "Succeeded" ]; then
        break
    fi
    sleep 2
done
echo -e "AKS ${aks_name} cluster provisioned successfully."

# Update the node pool to add a taint to prevent workloads 
# from being scheduled on the system node pool
az aks nodepool update \
--resource-group $resource_group_name \
--cluster-name $aks_name \
--name systempool \
--node-taints CriticalAddonsOnly=true:NoSchedule

if [ $? -ne 0 ]; then
    echo "Failed to update node pool with taint"
    exit 1
fi
echo "Node pool successfully updated with taint"

# Get the AKS credentials
az aks get-credentials \
--resource-group $resource_group_name \
--name $aks_name \
--overwrite-existing 
if [ $? -ne 0 ]; then
    echo "Failed to get AKS credentials"
    exit 1
fi
echo "AKS credentials retrieved successfully"

# Create a Karpenter node pool
defaultNodePoolApiVersion=$(kubectl get nodepools -o=jsonpath='{.items[?(@.metadata.name=="default")].apiVersion}')
if [ -z  $defaultNodePoolApiVersion]; then
echo -e "Creating default node pool..." 

# Now create the app [Karpenter] node pool
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  annotations:
    karpenter.sh/nodepool-hash: "12393960163388511505"
    karpenter.sh/nodepool-hash-version: v2
    kubernetes.io/description: General purpose NodePool for generic workloads
    meta.helm.sh/release-name: aks-managed-karpenter-overlay
    meta.helm.sh/release-namespace: kube-system
  creationTimestamp: "2024-10-07T19:36:54Z"
  generation: 1
  labels:
    app.kubernetes.io/managed-by: Helm
    helm.toolkit.fluxcd.io/name: karpenter-overlay-main-adapter-helmrelease
    helm.toolkit.fluxcd.io/namespace: 6704378c3385a600011c675e
  name: default
  resourceVersion: "1832"
  uid: 59d68c8a-5cff-47a5-a378-5e425e8ddbe8
spec:
  disruption:
    budgets:
    - nodes: 100%
    consolidationPolicy: WhenUnderutilized
    expireAfter: Never
  template:
    spec:
      nodeClassRef:
        name: default
      requirements:
      - key: kubernetes.io/arch
        operator: In
        values:
        - amd64
      - key: kubernetes.io/os
        operator: In
        values:
        - linux
      - key: karpenter.sh/capacity-type
        operator: In
        values:
        - on-demand
      - key: karpenter.azure.com/sku-family
        operator: In
        values:
        - D
EOF
else
    echo -e "Default node pool already exists." 
fi

if [ $? -ne 0 ]; then
    echo "Failed to create Karpenter node pool"
    exit 1
fi
echo "Karpenter node pool created successfully"

# Create a namespace for the application
kubectl create namespace $app_ns
if [ $? -ne 0 ]; then
    echo "Failed to create namespace $app_ns"
    exit 1
fi
echo "Namespace $app_ns created successfully"

# Create a workload identity
workload_identity_name="uami-workload-identity-${local_name}-${suffix}"
workload_identity_json=$(az aks workload identity create \
--name $workload_identity_name \
--resource-group $resource_group_name \
--output json)

if [ $? -ne 0 ]; then
    echo "Failed to create workload identity"
    exit 1
fi
echo "Workload identity created successfully"
workload_identity_resource_id=$(echo $workload_identity_json | jq -r '.id')
workload_identity_client_id=$(echo $workload_identity_json | jq -r '.clientId')
workload_identity_object_id=$(echo $workload_identity_json | jq -r '.principalId')

# Create a service account for the workload identity
kubectl create serviceaccount demo-app-service-account \
--namespace $app_ns \

if [ $? -ne 0 ]; then
    echo "Failed to create service account"
    exit 1
fi
echo "Service account created successfully"

# Annotate the service account to associate it with the workload identity
kubectl annotate serviceaccount \
--namespace $app_ns \
demo-app-service-account \
"azure.workload.identity/client-id=${workload_identity_client_id}" \

if [ $? -ne 0 ]; then
    echo "Failed to annotate service account"
    exit 1
fi
echo "Service account annotated successfully"

# Retrive the OIDC issurer URL
oidc_issuer_url=$(az aks show --name ${aks_name} \
--resource-group "${resource_group_name}" \
--query "oidcIssuerProfile.issuerUrl" \
-o tsv)

# Create a Federated Identity Credential
fic_name="fic-${local_name}-${suffix}"

az identity federated-credential create \
--name $fic_name \
--identity-name $workload_identity_name \
--resource-group $resource_group_name \
--issuer $oidc_issuer_url \
--subject "system:serviceaccount:${app_ns}:demo-app-service-account"

if [ $? -ne 0 ]; then
    echo "Failed to create Federated Identity Credential"
    exit 1
fi
echo "Federated Identity Credential created successfully"

# Create a second Federated Identity Credential for the KEDA service account
keda_fic_name="fic-keda-${local_name}-${suffix}"
az identity federated-credential create \
--name ${keda_fic_name} \
--identity-name ${workload_identity_name} \
--resource-group "${resource_group_name}" \
--issuer ${oidc_issuer_url} \
--subject system:serviceaccount:kube-system:keda-operator

if [ $? -ne 0 ]; then
    echo "Failed to create Federated Identity Credential for KEDA"
    exit 1
fi
echo "Federated Identity Credential for KEDA created successfully"

echo "Deployment script completed successfully"

exit 0
# End of script

