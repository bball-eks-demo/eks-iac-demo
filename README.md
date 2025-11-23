# Executive Summary
This project deploys a containerized application to Amazon EKS using Terraform, Docker, and Kubernetes. The original prompt referenced a WAF → NLB → EKS architecture; however, AWS WAF cannot be attached to Network Load Balancers, so the design cannot be implemented exactly as described. This repository delivers everything that is technically achievable with an NLB-based approach and documents the required architectural change, using an ALB, to enable WAF integration in a production-ready setup.

# Prerequisites
Install the following tools:
* Docker Desktop: https://www.docker.com/products/docker-desktop/
* AWS CLI
* kubectl
* Terraform
  ```console
  brew install awscli kubectl terraform
  ```

# AWS CLI Configuration
Before deploying, authenticate with AWS:
```console
aws configure
```
You will be prompted for:
* AWS Access Key
* AWS Secret Key
* Default region (us-east-1 or your favorite region)
* Output format (json)

([How to create an AWS Access Key](https://docs.aws.amazon.com/IAM/latest/UserGuide/access-key-self-managed.html#Using_CreateAccessKey))

# 1. Deploy Infrastructure
All infrastructure lives inside /infra.
```bash
cd infra
terraform init
terraform apply
```
Type **yes** when prompted.

Provisioning includes:
* VPC
* ECR repository
* EKS cluster
* Node group

This step typically takes **15–30 minutes**.

# 2. Build & Push the Docker Image

Still inside /infra, authenticate Docker to ECR:
```bash
aws ecr get-login-password --region $(terraform output -raw region) \
  | docker login \
      --username AWS \
      --password-stdin $(terraform output -raw ecr_repo_url | cut -d'/' -f1)
```

Build & push the app image:
```bash
docker buildx build \
  --platform linux/amd64 \
  -t $(terraform output -raw ecr_repo_url):latest \
  --push \
  ../app
```

(Optional local test, http://localhost:8080)
```bash
docker run -p 8080:8080 hello-app
```

# 3. Configure kubectl for the New Cluster
```bash
aws eks --region $(terraform output -raw region) update-kubeconfig \
    --name $(terraform output -raw cluster_name)
```

# 4. Deploy Kubernetes Resources
## Deployment
The deployment uses `envsubst` to insert the image tag produced by Terraform:
```bash
export IMAGE=$(terraform output -raw ecr_repo_url):latest
envsubst < ../manifests/deployment.yaml | kubectl apply -f -
```
## Service
```bash
kubectl apply -f ../manifests/service.yaml
```

The NLB typically takes **1–3 minutes** to finish provisioning.

# 5. Test the Application
Test via curl:
```bash
curl http://$(kubectl get svc hello-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

Or, get the NLB hostname and test in your browser:
```bash
echo "http://$(kubectl get svc hello-app-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```
# Tradeoffs & Design Notes
### ❌ AWS WAF cannot be placed in front of an NLB
The original prompt specified the architecture: WAF → NLB → EKS

AWS does not support attaching a WAF Web ACL to a Network Load Balancer.
Only the following AWS resources support WAF associations:
* Application Load Balancers
* CloudFront
* API Gateway
* AppSync

* Because of this platform limitation, the requested design cannot be implemented exactly as written.

### ✔️ What this project delivers
This deployment completes everything that can be built from the prompt:
* EKS cluster
* NLB-backed Kubernetes Service
* Dockerized application running on EKS
* Fully automated infra + manifests
* Clear build/deploy instructions

This provides a working end-to-end environment that matches the deliverable portion of the original request.

### How WAF Fits Into a Production-Ready Design
If WAF protection is required, the architecture needs to use an Application Load Balancer, since WAF cannot attach to an NLB. The supported pattern is: WAF → ALB → EKS.

An ALB (typically managed through the AWS Load Balancer Controller) enables WAF integration and provides routing flexibility. In a full production setup, you would also include HTTPS termination at the ALB, WAF logging, autoscaling, private cluster endpoints, and optionally CloudFront in front of WAF for global caching and additional security controls.

# Cleanup
To remove everything:
```bash
cd infra
terraform destroy
docker rmi hello-app:latest
```


