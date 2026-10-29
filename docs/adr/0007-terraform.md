# 0007. Terraform and HCP Terraform for the Cognito, reports and parser infrastructure

Status: accepted (Lab 7) · Date: 2026-10-30

## Context

Labs 4-6 described three parts of the system in CloudFormation: Cognito (`cognito.yaml`), the
weekly report (`reports.yaml`) and the agenda parser (`ai.yml`). They work, but:

- each is deployed from a laptop by a shell script that also copies stack outputs into `.env`;
- there is one environment and no plan step a reviewer can read before a change lands;
- the project already reaches outside one AWS account (the Google OAuth client, GitHub), and a
  second environment is the next obvious need.

Two of the resources hold data that cannot be re-created: the Cognito user pool (every account
that signed up) and the reports bucket (every report). The migration must not delete them.

## Decision

- **Terraform (HCL), state in an HCP Terraform workspace** (`peach-dev`), one root module in
  `infra/`: `auth.tf`, `reports.tf`, `ai.tf`, `variables.tf`, `outputs.tf`.
- **Adopt, do not re-create.** CloudFormation stacks were updated with
  `DeletionPolicy: Retain`, deleted, and the 38 retained resources were handed to Terraform with
  `import` blocks. `prevent_destroy` is set on the user pool and the reports bucket.
- **Who can change infrastructure:** anyone through a pull request. A pull request gets a
  speculative plan as a check; a merge to `main` runs plan and apply in HCP Terraform with
  short-lived AWS credentials from OIDC (role `hcp-terraform-<org>`). No terraform apply target
  exists in the Makefile.
- **Application code stays on its own road.** The Lambda functions that run the backend image use
  `lifecycle { ignore_changes = [image_uri] }`; `make deploy-ai` / `deploy-reports` push an image
  and call `update-function-code`. Terraform owns the shape of a function, the pipeline owns which
  build runs, so the two never fight.
- `backend.yaml`, `frontend.yaml` and `github-oidc.yaml` stay on CloudFormation (they are not part
  of this migration). Terraform reads the backend Lambda's `DATABASE_URL` and `COGNITO_JWKS` with
  a data source instead of keeping a second copy.

## Alternatives considered

| Alternative | Why it lost |
| --- | --- |
| Stay on CloudFormation | AWS-only: it cannot also manage the Google OAuth client or GitHub. No readable plan by default (change sets are optional). Fine for one account, but no second environment without copying templates. |
| AWS CDK | Needs a build step and a language runtime for infrastructure, and still compiles to CloudFormation, so the plan and import story stays CloudFormation's. |
| OpenTofu | Accepts the same files and would work. HCP Terraform integrates with Terraform directly (OIDC dynamic credentials, VCS runs), and the course tooling is built around it. Switching later is a small change. |
| Delete the stacks and apply the Terraform | Deletes the user pool (all accounts) and the reports bucket (all reports). |

## Consequences

- **Secrets.** `google_client_secret` is a sensitive workspace variable, never in a file. It is
  still stored in the state (`sensitive = true` hides it in plan output, not in the state), as is
  the database URL read from the backend Lambda. Access to the workspace is access to those
  values, so membership of the HCP Terraform organization must be small.
- **State.** One central, locked state with history in HCP Terraform. If it were lost, Terraform
  would no longer know the resources are its own and would try to create them again; the
  `import` blocks can be restored from Git history and used again.
- **If HCP Terraform is down.** The running system is unaffected (Lambda, Cognito, S3 keep
  running); only changes to the infrastructure wait. In an emergency a person with AWS access
  can fix the resource by hand and must put the same change into the code afterwards, or the next
  apply puts it back (drift).
- **No automatic rollback.** A failed apply stops halfway. The fix is a new commit, and the plan
  shows what is left to do.
- **Bootstrap.** The IAM OIDC provider and role that HCP Terraform assumes are created once with
  a local state (`infra/bootstrap/`), because HCP Terraform needs them before it can do anything.
  The role has AdministratorAccess for the class project; a real team narrows it.
- **Lambda code.** The report mailer's code lived inline in the CloudFormation template. It is
  now `infra/lambda/mailer/index.py`, zipped by Terraform.
