# Debugging the OIDC authentication

How CI authenticates: each GitHub Actions job requests a short-lived OIDC token from GitHub and exchanges it with AWS STS for credentials of the role `csepella-eks-reverse-proxy-gha`. No access keys live anywhere in GitHub. When this chain breaks, AWS answers with a single unhelpful AccessDenied, so the interesting work is figuring out *which* link failed.

This repo hit four separate causes of that same error in two days (November 2026). These notes record each one, how it was found, and what to check next time. For the tear-down / bring-up runbook, see the [README](../README.md).

## 1. GitHub changed the token's `sub` format

Symptom: the "Configure AWS credentials" step fails with `Not authorized to perform: sts:AssumeRoleWithWebIdentity`.

The trust policy matched the classic sub format:

```
repo:elspecal/csk-devops-final:ref:refs/heads/main
```

But newer GitHub repos emit owner and repo IDs in the claim:

```
repo:elspecal@66340758/csk-devops-final@1454008211:ref:refs/heads/main
```

Format: `repo:<owner>@<owner-id>/<repo>@<repo-id>:ref:<ref>`. A `StringEquals` condition can only match one of the two. The fix in `terraform/github-oidc.tf` is `StringLike` accepting both patterns, still scoped to this repo and `main`:

```hcl
condition {
  test     = "StringLike"
  variable = "token.actions.githubusercontent.com:sub"
  values = [
    "repo:elspecal/csk-devops-final:ref:refs/heads/main",
    "repo:elspecal@*/csk-devops-final@*:ref:refs/heads/main",
  ]
}
```

Keeping both patterns costs nothing and survives either token format.

## 2. The error message lies

`Not authorized` covers at least two unrelated causes:

- the role doesn't exist at all (it was destroyed along with the stack)
- the role exists but the trust policy doesn't match the token

AWS reports a missing role with the *same* Not authorized message as a trust mismatch. Tell them apart with:

```sh
aws iam get-role --role-name csepella-eks-reverse-proxy-gha
# NoSuchEntity → the role is gone, no point debugging trust policies

aws iam get-role --role-name csepella-eks-reverse-proxy-gha \
  --query 'Role.AssumeRolePolicyDocument.Statement[0].Condition'
# compare what's live in AWS against what the committed config says
```

## 3. The bootstrap deadlock

The OIDC role is created by Terraform, but the Terraform workflow needs that role to authenticate. After a `terraform destroy` neither side can start: CI can't assume a role that no longer exists, and the laptop can't reasonably rebuild 52 resources by hand.

The escape hatch is a targeted apply that creates only the role and its policy attachment:

```sh
cd terraform
terraform apply -target=aws_iam_role.gha \
  -target=aws_iam_role_policy_attachment.gha_admin -auto-approve
```

Five seconds, two resources. Everything else stays CI's job. This is step 1 of bring-up in the README, and it's load-bearing: without it, every dispatch after a destroy fails at "Configure AWS credentials" with the same error as a broken trust policy.

## 4. The unpushed commit whack-a-mole

The nastiest one, because everything looked right and kept breaking anyway. The trust-policy fix existed as a local commit (`6940597`) but was never pushed; `origin/main` still pointed at the pre-fix commit (`50685ec`). The sequence that followed:

1. A laptop apply fixed the live policy, so authentication worked again
2. A CI run checked out `50685ec` (old config) and its `terraform apply` pushed the broken `StringEquals` policy back to AWS
3. The next CI authentication attempt failed against the freshly reverted policy
4. Repeat, with no obvious cause

The tells were the live policy flipping back to `StringEquals` while the local file showed the fix, and `git ls-remote origin main` showing the old head. Two lessons came out of it:

- **Re-running a failed job replays that run's original commit**, not the current `main`. After pushing a fix, dispatch a *fresh* run instead of re-running the old one.
- When local and CI disagree about infrastructure, run `git ls-remote origin main` and compare against the local head before debugging anything else.

## 5. The access entry that already existed

After CI rebuilt the cluster from scratch, the apply died near the end while creating `aws_eks_access_entry.gha` with `EntityAlreadyExists`. The cluster is created with `bootstrap_cluster_creator_admin_permissions = true`, so AWS auto-creates an access entry for the cluster creator. In a CI run the creator *is* the CI role, which Terraform then tries to register explicitly.

CloudTrail confirmed it: no `CreateAccessEntry` call anywhere in the log, yet the entry existed. The create happened server-side as part of `CreateCluster`.

The fix is importing both resources into state, then re-running the failed jobs:

```sh
terraform import aws_eks_access_entry.gha \
  "csepella-eks-task:arn:aws:iam::362099375729:role/csepella-eks-reverse-proxy-gha"
terraform import aws_eks_access_policy_association.gha \
  "csepella-eks-task#arn:aws:iam::362099375729:role/csepella-eks-reverse-proxy-gha#arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
```

The access entry ID uses `:` separators; the association uses `#`. Inconsistent, undocumented in error messages, and guaranteed to cost you an attempt if you guess.

## Tools that carried the debugging

**CloudTrail sees the token even when STS denies it.** The `AssumeRoleWithWebIdentity` event records the token's `sub` in the `principalId` field, denied or not. One command turns "Not authorized" into an exact diagnosis:

```sh
aws cloudtrail lookup-events --region eu-west-3 \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --start-time "2026-11-12T10:00:00Z" --max-results 20 --output json \
  | python3 -c "
import json, sys
for e in sorted(json.load(sys.stdin)['Events'], key=lambda x: x['EventTime']):
    d = json.loads(e['CloudTrailEvent'])
    pid = (d.get('userIdentity') or {}).get('principalId', '')
    print(e['EventTime'], '|', d.get('errorCode', 'SUCCESS'), '|', pid)
"
```

This was the command that cracked problem 1 (the new sub format appeared right there in a denied event) and problem 5 (the absence of `CreateAccessEntry` proved the entry came from cluster bootstrap).

**GitHub's API is readable unauthenticated, with care.** Run, job, and step statuses need no token, but the limit is 60 requests per hour. Polling with `If-None-Match`/ETag headers turns unchanged responses into 304s that don't count against the limit. Job logs, though, require authentication even for public repos, so AWS-side evidence (CloudTrail, live resource state) fills that gap.

**A local `terraform plan` lies when the laptop can't see the cluster.** Without an access entry for the local identity, plans showed a phantom "will be created" for the helm release that was in fact already installed, because the plan couldn't read the cluster's state. Treat local plan output for cluster-scoped resources as unreliable unless laptop access is set up; CI's plan sees the truth.

## Checklist for the next AccessDenied

1. CloudTrail: what `sub` did the token carry, and what was the error code?
2. `aws iam get-role`: does the role exist?
3. Live trust policy vs the committed one: did something overwrite it?
4. `git ls-remote origin main` vs the local head: is the fix actually pushed?
5. Re-run or fresh dispatch? Re-runs replay the original commit.
6. If the apply dies on the access entry, it's the bootstrap collision; import and re-run.
