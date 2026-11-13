# csk-devops-final

Two Flask services behind an nginx reverse proxy on EKS. Everything is built and deployed by two GitHub Actions workflows that authenticate to AWS with OIDC, so no access keys are stored anywhere in GitHub.

## What's in here

| Path | What it is |
|---|---|
| `src/service-a`, `src/service-b` | Flask apps with Dockerfiles, port 8080 |
| `k8s/` | Namespace, deployments, nginx DaemonSet, NLB Service |
| `terraform/` | VPC, EKS cluster, node group, ECR repos, load balancer controller, and the GitHub Actions OIDC role |
| `.github/workflows/build-and-push.yml` | On push to `main` touching `src/**` or `k8s/**`: builds both images, pushes to ECR tagged with the commit SHA (plus `latest`), then deploys to the cluster with kubectl |
| `.github/workflows/terraform-apply.yml` | On push to `main` touching `terraform/**`: `terraform apply -auto-approve` against S3 remote state (lockfile locking) |
| `docs/oidc-debugging.md` | How the CI authentication was debugged: the `sub` format change, the bootstrap deadlock, the unpushed-commit revert loop, access entry imports |

Normal operation needs nothing from you: push to `main` and the right workflow runs. Both can also be triggered manually from the Actions tab.

State lives in S3 bucket `csepella-w10-362099375729-eu-west-3-an`, key `csepella-eks-reverse-proxy/terraform.tfstate`.

**Cost warning:** while this stack is up it runs roughly $120+/month (EKS control plane $73, three t3.small nodes, an NLB). Tear it down when you're not using it. That's what the next two sections are for.

## Tearing it down

Run from your laptop with your normal AWS credentials.

### 1. Delete the NLB through Kubernetes first

The load balancer is created by the load balancer controller from the `nginx-proxy` Service. Terraform has no idea it exists, so if you skip this step the NLB survives the cluster and keeps billing forever.

```sh
kubectl delete service nginx-proxy -n apps
```

Give it a minute, then check it's actually gone:

```sh
aws elbv2 describe-load-balancers --region eu-west-3 \
  --query 'LoadBalancers[].LoadBalancerName' --output text
```

If kubectl isn't working (see step 5 of bring-up), delete the NLB from the EC2 console instead. The cluster is going away anyway, so there's nothing left to get out of sync.

### 2. Destroy the stack

```sh
cd terraform
terraform destroy
```

Takes 10 to 15 minutes. One prerequisite: the helm release (load balancer controller) is uninstalled through the Kubernetes API during destroy, so your IAM user needs cluster access. If you did step 5 of bring-up on this cluster, you're set. Otherwise run those commands before destroying.

Note that this also deletes the GitHub Actions OIDC role. CI can no longer authenticate after this. That's expected; step 1 of bring-up fixes it.

### 3. Verify nothing is left

```sh
aws eks list-clusters --region eu-west-3
aws ec2 describe-instances --region eu-west-3 \
  --filters Name=instance-state-name,Values=running,stopped \
  --query 'Reservations[].Instances[].InstanceId'
```

Both should be empty.

What survives: the S3 state bucket (now holding empty state), the account-level GitHub OIDC provider (we only reference it via `data`), and the GitHub repo with its workflows, run history, and variables. None of that costs anything meaningful.

## Bringing it back up

The stack is rebuilt by CI, not locally. Only one small step happens on the laptop, then the workflows do the rest.

### 1. Bootstrap the CI role

The Terraform Apply workflow authenticates as `csepella-eks-reverse-proxy-gha`, and teardown deleted that role. Chicken and egg, so create it from the laptop first:

```sh
cd terraform
terraform apply -target=aws_iam_role.gha \
  -target=aws_iam_role_policy_attachment.gha_admin -auto-approve
```

Five seconds, two resources. The role comes back with the StringLike trust policy from the committed config, which matches GitHub's current `sub` format.

### 2. Run the Terraform Apply workflow

Actions → Terraform Apply → Run workflow. Around 15 to 20 minutes: VPC, EKS, node group, addons, ECR repos, load balancer controller.

### 3. Expect the first run to fail, then fix the access entry

The cluster is created with `bootstrap_cluster_creator_admin_permissions = true`, so AWS auto-creates an access entry for the CI role as part of cluster creation. Terraform then tries to create the same entry explicitly and dies on `EntityAlreadyExists`. Import both resources from the laptop and re-run:

```sh
cd terraform
terraform import aws_eks_access_entry.gha \
  "csepella-eks-task:arn:aws:iam::362099375729:role/csepella-eks-reverse-proxy-gha"
terraform import aws_eks_access_policy_association.gha \
  "csepella-eks-task#arn:aws:iam::362099375729:role/csepella-eks-reverse-proxy-gha#arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
```

The entry ID uses `:` separators, the association uses `#`. Yes, inconsistent. That's the provider.

Then Actions → the failed run → Re-run failed jobs. The plan is nearly empty at that point, so it goes green fast.

### 4. Run the Build and Push workflow

Actions → Build and Push → Run workflow. The ECR repos are fresh and empty, so use a new dispatch, not a re-run of some old failed run. This builds both images, pushes them, then the deploy job applies the manifests and rolls out the SHA-tagged images.

### 5. Give your laptop cluster access (optional but recommended)

The new cluster only knows the CI role. Your IAM user starts with no access, which blocks kubectl and the destroy step next time:

```sh
aws eks create-access-entry --cluster-name csepella-eks-task \
  --principal-arn arn:aws:iam::362099375729:user/hello@csepella.com \
  --region eu-west-3
aws eks associate-access-policy --cluster-name csepella-eks-task \
  --principal-arn arn:aws:iam::362099375729:user/hello@csepella.com \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster --region eu-west-3
aws eks update-kubeconfig --region eu-west-3 --name csepella-eks-task
```

### 6. Grab the new NLB hostname

It changes on every rebuild:

```sh
kubectl -n apps get svc nginx-proxy
curl http://<nlb-dns>/health
curl http://<nlb-dns>/api/sa
curl http://<nlb-dns>/api/sb
```

Anything that referenced the old hostname needs updating after a rebuild, including any submission you may have written it into.
