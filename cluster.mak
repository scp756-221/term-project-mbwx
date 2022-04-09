# Make file to start and manage EKS cluster

# Parameters for cluster
NS=mbwx-namespace
CLUSTER_NAME=mbwx
EKS_CTX=mbwx


NGROUP=worker-nodes
NTYPE=t3.medium
REGION=us-west-2
KVER=1.21

# Keep all the logs out of main directory
LOG_DIR=logs

# Need to switch this PERSONAL INFO
CREG=docker.io
REGID=meganhfowler


# Create and control the cluster
cluster-up:
	make -f cluster.mak start
	make -f cluster.mak name
	make -f cluster.mak istio
	make -f cluster.mak showcontext
	make -f cluster.mak describe
	make -f cluster.mak lsa

# Start and stop cluster
start: showcontext
	eksctl create cluster --name $(CLUSTER_NAME) --version $(KVER) --region $(REGION) --nodegroup-name $(NGROUP) --node-type $(NTYPE) --nodes 2 --nodes-min 2 --nodes-max 2 --managed | tee $(LOG_DIR)/eks-start.log
	# Use back-ticks for subshell because $(...) notation is used by make
	kubectl config rename-context `kubectl config current-context` $(EKS_CTX) | tee -a $(LOG_DIR)/eks-start.log

stop:
	eksctl delete cluster --name $(CLUSTER_NAME) --region $(REGION) | tee $(LOG_DIR)/eks-stop.log
	kubectl config delete-context $(EKS_CTX) | tee -a $(LOG_DIR)/eks-stop.log


# create and delete an EKS cluster's nodegroup
up:
	eksctl create nodegroup --cluster $(CLUSTER_NAME) --region $(REGION) --name $(NGROUP) --node-type $(NTYPE) --nodes 2 --nodes-min 2 --nodes-min 2 --managed | tee $(LOG_DIR)/eks-up.log

down:
	eksctl delete nodegroup --cluster=$(CLUSTER_NAME) --region $(REGION) --name=$(NGROUP) | tee $(LOG_DIR)/eks-down.log


# Create namespace for cluster
name: showcontext
	kubectl config use-context $(EKS_CTX)
	kubectl create ns $(NS)
	kubectl config set-context $(CLUSTER_NAME) --namespace=$(NS)

# Use istio
istio:
	kubectl config use-context $(EKS_CTX)
	istioctl install -y --set profile=demo --set hub=gcr.io/istio-release
	kubectl label namespace $(NS) istio-injection=enabled

delistio:
	kubectl label namespace $(NS) istio-injection-

get-ingressgateway:
	kubectl -n istio-system get service istio-ingressgateway


# Various ways to check on the status of the cluster/nodegroups

showcontext:
	kubectl config get-contexts


status: showcontext
	eksctl get cluster --region $(REGION) | tee $(LOG_DIR)/eks-status.log
	eksctl get nodegroup --cluster $(CLUSTER_NAME) --region $(REGION) | tee -a $(LOG_DIR)/eks-status.log

describe:
	aws --output json ec2 describe-instances | jq -r '.Reservations[].Instances[]| .InstanceId + " " + .InstanceType + " " + .ImageId + " " + .Architecture + " " + .State.Name + " " + .PublicIpAddress'

lsa: showcontext
	kubectl get svc --all-namespaces




# DEPLOYMENT
# --- registry-login: Login to the container registry
#
registry-login:
	@/bin/sh -c 'cat cluster/${CREG}-token.txt | docker login $(CREG) -u $(REGID) --password-stdin'


# Build and push images to the CR
cri: $(LOG_DIR)/s2-v1.repo.log

# Build the s2 service
$(LOG_DIR)/s2-v1.repo.log: s2/v1/Dockerfile s2/v1/app.py s2/v1/requirements.txt
	make -f cluster.mak  --no-print-directory registry-login
	docker build --platform x86_64 -t $(CREG)/$(REGID)/cmpt756s2:v1 s2/v1 | sudo tee $(LOG_DIR)/s2-v1.img.log
	docker push $(CREG)/$(REGID)/cmpt756s2:v1 | sudo tee $(LOG_DIR)/s2-v1.repo.log

# Update S2 and associated monitoring, rebuilding if necessary
s2: rollout-s2 cluster/s2-svc.yaml cluster/s2-sm.yaml cluster/s2-vs.yaml
	kubectl -n $(NS) apply -f cluster/s2-svc.yaml | sudo tee $(LOG_DIR)/s2.log
	kubectl -n $(NS) apply -f cluster/s2-sm.yaml | sudo tee -a $(LOG_DIR)/s2.log
	kubectl -n $(NS) apply -f cluster/s2-vs.yaml | sudo tee -a $(LOG_DIR)/s2.log

# --- rollout-s2: Rollout a new deployment of S2
rollout-s2: $(LOG_DIR)/s2-v1.repo.log  cluster/s2-dpl-v1.yaml
	kubectl -n $(NS) apply -f cluster/s2-dpl-v1.yaml | sudo tee $(LOG_DIR)/rollout-s2.log
	kubectl rollout -n $(NS) restart deployment/cmpt756s2-v1 | sudo tee -a $(LOG_DIR)/rollout-s2.log


