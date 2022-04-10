# Make file to start and manage EKS cluster

# Parameters for cluster
NS=mbwx-namespace
CLUSTER_NAME=mbwx
EKS_CTX=mbwx
KC=kubectl
ISTIO_NS=istio-system
APP_NS=mbwx-namespace


NGROUP=worker-nodes
NTYPE=t3.medium
REGION=us-west-2
KVER=1.21

# App Version
APP_VER = v1
LOADER_VER = v1

# Keep all the logs out of main directory
LOG_DIR=logs

# Need to switch this PERSONAL INFO
CREG=ghcr.io
REGID=wla194-tommy

# Launch app
launch:
	make -f cluster.mak cluster-up
	make -f cluster.mak db
	make -f cluster.mak s1
	make -f cluster.mak s2
	make -f cluster.mak s3
	make -f cluster.mak gw
	make -f cluster.mak cri


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
cri: $(LOG_DIR)/s1.repo.log $(LOG_DIR)/s2.repo.log $(LOG_DIR)/s3.repo.log $(LOG_DIR)/db.repo.log

# --- BUILDS
# Build the s1 service
$(LOG_DIR)/s1.repo.log: s1/Dockerfile s1/app.py s1/requirements.txt
	make -f cluster.mak --no-print-directory registry-login
	docker build --platform x86_64 -t $(CREG)/$(REGID)/cmpt756s1:$(APP_VER) s1 | tee $(LOG_DIR)/s1.img.log
	docker push $(CREG)/$(REGID)/cmpt756s1:$(APP_VER) | tee $(LOG_DIR)/s1.repo.log

# Build the s2 service
$(LOG_DIR)/s2.repo.log: s2/Dockerfile s2/app.py s2/requirements.txt
	make -f cluster.mak  --no-print-directory registry-login
	docker build --platform x86_64 -t $(CREG)/$(REGID)/cmpt756s2:$(APP_VER) s2 | tee $(LOG_DIR)/s2.img.log
	docker push $(CREG)/$(REGID)/cmpt756s2:$(APP_VER) | tee $(LOG_DIR)/s2.repo.log

# Build the s3 service
$(LOG_DIR)/s3.repo.log: s3/Dockerfile s3/app.py s3/requirements.txt
	make -f cluster.mak  --no-print-directory registry-login
	docker build --platform x86_64 -t $(CREG)/$(REGID)/cmpt756s3:$(APP_VER) s3 | tee $(LOG_DIR)/s3.img.log
	docker push $(CREG)/$(REGID)/cmpt756s3:$(APP_VER) | tee $(LOG_DIR)/s3.repo.log

# Build the db service
$(LOG_DIR)/db.repo.log: db/Dockerfile db/app.py db/requirements.txt
	make -f cluster.mak --no-print-directory registry-login
	docker build --platform x86_64 -t $(CREG)/$(REGID)/cmpt756db:$(APP_VER) db | tee $(LOG_DIR)/db.img.log
	docker push $(CREG)/$(REGID)/cmpt756db:$(APP_VER) | tee $(LOG_DIR)/db.repo.log

# Build the loader
$(LOG_DIR)/loader.repo.log: loader/app.py loader/requirements.txt loader/Dockerfile registry-login
	docker build --platform x86_64 -t $(CREG)/$(REGID)/cmpt756loader:$(LOADER_VER) loader  | tee $(LOG_DIR)/loader.img.log
	docker push $(CREG)/$(REGID)/cmpt756loader:$(LOADER_VER) | tee $(LOG_DIR)/loader.repo.log

# --- UPDATES
# Update service gateway
gw: cluster/service-gateway.yaml
	kubectl -n $(NS) apply -f $< | tee $(LOG_DIR)/gw.log

# Update S1 and associated monitoring, rebuilding if necessary
s1: $(LOG_DIR)/s1.repo.log cluster/s1.yaml cluster/s1-sm.yaml cluster/s1-vs.yaml
	kubectl -n $(NS) apply -f cluster/s1.yaml | tee $(LOG_DIR)/s1.log
	kubectl -n $(NS) apply -f cluster/s1-sm.yaml | tee -a $(LOG_DIR)/s1.log
	kubectl -n $(NS) apply -f cluster/s1-vs.yaml | tee -a $(LOG_DIR)/s1.log

# Update S2 and associated monitoring, rebuilding if necessary
s2: rollout-s2 cluster/s2-svc.yaml cluster/s2-sm.yaml cluster/s2-vs.yaml
	kubectl -n $(NS) apply -f cluster/s2-svc.yaml | tee $(LOG_DIR)/s2.log
	kubectl -n $(NS) apply -f cluster/s2-sm.yaml | tee -a $(LOG_DIR)/s2.log
	kubectl -n $(NS) apply -f cluster/s2-vs.yaml | tee -a $(LOG_DIR)/s2.log

# Update S3 and associated monitoring, rebuilding if necessary
s3: rollout-s3 cluster/s3-svc.yaml cluster/s3-sm.yaml cluster/s3-vs.yaml
	kubectl -n $(NS) apply -f cluster/s3-svc.yaml | tee $(LOG_DIR)/s3.log
	kubectl -n $(NS) apply -f cluster/s3-sm.yaml | tee -a $(LOG_DIR)/s3.log
	kubectl -n $(NS) apply -f cluster/s3-vs.yaml | tee -a $(LOG_DIR)/s3.log

# Update DB and associated monitoring, rebuilding if necessary
db: $(LOG_DIR)/db.repo.log cluster/awscred.yaml cluster/dynamodb-service-entry.yaml cluster/db.yaml cluster/db-sm.yaml cluster/db-vs.yaml
	kubectl -n $(NS) apply -f cluster/awscred.yaml | tee $(LOG_DIR)/db.log
	kubectl -n $(NS) apply -f cluster/dynamodb-service-entry.yaml | tee -a $(LOG_DIR)/db.log
	kubectl -n $(NS) apply -f cluster/db.yaml | tee -a $(LOG_DIR)/db.log
	kubectl -n $(NS) apply -f cluster/db-sm.yaml | tee -a $(LOG_DIR)/db.log
	kubectl -n $(NS) apply -f cluster/db-vs.yaml | tee -a $(LOG_DIR)/db.log

# --- ROLLOUTS

# Rollout a new deployment of S1
rollout-s1: s1
	kubectl rollout -n $(NS) restart deployment/cmpt756s1

# Rollout a new deployment of S2
rollout-s2: $(LOG_DIR)/s2.repo.log  cluster/s2-dpl-v1.yaml
	kubectl -n $(NS) apply -f cluster/s2-dpl-v1.yaml | tee $(LOG_DIR)/rollout-s2.log
	kubectl rollout -n $(NS) restart deployment/cmpt756s2-v1 | tee -a $(LOG_DIR)/rollout-s2.log

# Rollout a new deployment of S3
rollout-s3: $(LOG_DIR)/s3.repo.log  cluster/s3-dpl-v1.yaml
	kubectl -n $(NS) apply -f cluster/s3-dpl-v1.yaml | tee $(LOG_DIR)/rollout-s3.log
	kubectl rollout -n $(NS) restart deployment/cmpt756s3-v1 | tee -a $(LOG_DIR)/rollout-s3.log

# Rollout a new deployment of DB
rollout-db: db
	kubectl rollout -n $(NS) restart deployment/cmpt756db

provision: istio prom deploy

deploy: appns gw s1 s2 db monitoring
	$(KC) -n $(APP_NS) get gw,vs,deploy,svc,pods

# --- grafana-url: Print the URL to browse Grafana in current cluster
grafana-url:
	@# Use back-tick for subshell so as not to confuse with make $() variable notation
	@/bin/sh -c 'echo http://`$(IP_GET_CMD) svc/grafana-ingress`:3000/'

prom:
	make -f obs.mak init-helm --no-print-directory
	make -f obs.mak install-prom --no-print-directory

monitoring: monvs
	$(KC) -n $(ISTIO_NS) get vs

# Update monitoring virtual service
monvs: cluster/monitoring-virtualservice.yaml
	$(KC) -n $(ISTIO_NS) apply -f $< > $(LOG_DIR)/monvs.log

appns:
	# Appended "|| true" so that make continues even when command fails
	# because namespace already exists
	$(KC) create ns $(APP_NS) || true
	$(KC) label namespace $(APP_NS) --overwrite=true istio-injection=enabled
